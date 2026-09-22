import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El ciclo completo de `sessions.json`: un fichero de verdad en un directorio de verdad, los
/// stores montados encima, una caminata que se cierra, y los **bytes crudos** releídos después.
///
/// Es la misma costura que B-1 abrió para los ajustes (hallazgo V1 de la retro del Epic 2), y por
/// la misma razón: `StorageStub` guarda registros, no bytes, así que ni el fichero del futuro ni
/// "el registro sigue ahí tras relanzar" se pueden expresar solo con el doble. Aquí se prueban
/// las dos mitades a la vez.
@MainActor
@Suite("HistoryStore · el ciclo completo sobre sessions.json")
struct HistoryStorePersistenceTests {

    private static func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "HistoryStorePersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private static func sessionsURL(in directory: URL) -> URL {
        directory.appending(path: SessionHistoryFileAdapter.fileName, directoryHint: .notDirectory)
    }

    private static func setAsideNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter {
            $0.hasPrefix(SessionHistoryFileAdapter.setAsideFilePrefix)
                && $0.hasSuffix(SessionHistoryFileAdapter.setAsideFileExtension)
        }
    }

    /// Los stores de una "ejecución" de la app sobre el mismo directorio. Montar otra es
    /// relanzar: los ficheros son los mismos y los stores se releen.
    private struct Launch {
        let storage: FileStorageAdapter
        let clock: ClockStub
        let motion: MotionStub
        let settings: SettingsStore
        let history: HistoryStore
        let store: SessionStore
    }

    @MainActor
    private static func launch(in directory: URL, at instant: Date = SessionStoreFixture.t0, defaultStrideM: Double = 0.655) -> Launch {
        let storage = FileStorageAdapter(directory: directory)
        let clock = ClockStub(now: instant)
        let motion = MotionStub(status: .granted)
        // El historial primero, y cableado al store de ajustes: dos instancias del dueño de
        // `sessions.json` son dos lectores, y el primero que lea uno ilegible lo **aparta**, así
        // que el segundo encontraría "no hay fichero" y el aviso de la 5.1 no saldría. Con las
        // dos líneas al revés, el test de historial ilegible de este mismo fichero se cae.
        let history = HistoryStore(storage: storage)
        // Y los logros, una vez y compartidos, por la misma razón (AD-16).
        let achievements = AchievementsStore(storage: storage)
        let feedback = FeedbackSpy()
        let settings = SettingsStore(
            storage: storage,
            history: history,
            achievements: achievements,
            feedback: feedback,
            clock: clock
        )
        let store = SessionStore(
            clock: clock,
            motion: motion,
            storage: storage,
            defaultStrideM: defaultStrideM,
            reconciliationTimeoutS: 5,
            orphanSessionThresholdS: SessionStoreFixture.orphanThresholdS,
            maxEstimableGapS: SessionStoreFixture.maxEstimableGapS,
            location: LocationStub(status: .denied),
            weather: WeatherStub(),
            settings: settings,
            history: history,
            achievements: achievements,
            achievementCatalog: AchievementCatalogFixture.bundled,
            feedback: feedback,
            quotes: .empty,
            random: RandomStub(),
            weatherStepTimeoutS: 5,
            measure: { _ in }
        )
        return Launch(storage: storage, clock: clock, motion: motion, settings: settings, history: history, store: store)
    }

    /// Camina `steps` pasos durante `durationS` segundos y cierra la caminata como la UI.
    private static func walkAndFinish(_ launch: Launch, steps: Int, durationS: TimeInterval = 1_800) async {
        await launch.store.start()
        launch.motion.emit(steps: steps)
        await waitUntil { launch.store.session?.stepsMeasured == steps }
        launch.clock.advance(by: durationS)
        launch.store.requestFinish()
        await launch.store.confirmFinish()
    }

    // MARK: - El criterio de aceptación

    @Test("Se camina, se termina, se cierra la app y se reabre: el registro sigue ahí")
    func theWalkSurvivesClosingTheApp() async throws {
        try await Self.withDirectory { directory in
            let primera = Self.launch(in: directory)
            await Self.walkAndFinish(primera, steps: 4_100)
            primera.store.leaveSummary()

            // Cerrar la app del todo: los stores mueren y solo quedan los ficheros.
            let bytes = try Data(contentsOf: Self.sessionsURL(in: directory))
            #expect(!bytes.isEmpty)

            let segunda = Self.launch(in: directory, at: SessionStoreFixture.t0.addingTimeInterval(86_400))

            #expect(segunda.history.records.count == 1)
            let record = try #require(segunda.history.records.first)
            #expect(record.startedAt == SessionStoreFixture.t0)
            #expect(record.stepsMeasured == 4_100)
            #expect(record.strideM == 0.655)
            #expect(record.durationS == 1_800)
            #expect(!segunda.store.hasSession, "y no vuelve como sesión viva")
            #expect(!FileManager.default.fileExists(atPath: directory.appending(path: ActiveSessionFileAdapter.fileName, directoryHint: .notDirectory).path(percentEncoded: false)))
        }
    }

    /// **La deuda concreta que la 2.3 dejó para esta historia**: no era demostrable sin sesiones
    /// cerradas contra las que probarlo. Cerrar con 0,655, recalibrar a 0,670 y comprobar que la
    /// fila guardada sigue en 0,655.
    @Test("Recalibrar la zancada NO reescribe el historial: la caminata cerrada sigue en 0,655")
    func recalibratingTheStrideNeverRewritesHistory() async throws {
        try await Self.withDirectory { directory in
            let primera = Self.launch(in: directory)
            await Self.walkAndFinish(primera, steps: 1_000)
            primera.store.leaveSummary()
            let antes = try Data(contentsOf: Self.sessionsURL(in: directory))
            try #require(primera.history.records.first?.strideM == 0.655)

            primera.settings.saveStride(fromText: "0,670")
            #expect(primera.settings.strideOutcome?.isSaved == true, "la recalibración sí se guarda… en settings.json")

            // Los bytes del historial no se han tocado.
            #expect(try Data(contentsOf: Self.sessionsURL(in: directory)) == antes)
            #expect(primera.history.records.first?.strideM == 0.655)

            // Y al relanzar tampoco: la zancada viaja DENTRO del registro, no se resuelve al leer.
            let segunda = Self.launch(in: directory, at: SessionStoreFixture.t0.addingTimeInterval(86_400))
            #expect(segunda.settings.strideM == 0.670, "la zancada nueva es la de los ajustes")
            #expect(segunda.history.records.first?.strideM == 0.655, "y la del registro sigue siendo la de aquella caminata")

            // La caminata SIGUIENTE sí usa la nueva, que es lo que la recalibración promete.
            await Self.walkAndFinish(segunda, steps: 1_000)
            #expect(segunda.history.records.count == 2)
            #expect(segunda.history.records.last?.strideM == 0.670)
            #expect(segunda.history.records.first?.strideM == 0.655)
        }
    }

    @Test("Varias caminatas se acumulan en el mismo fichero, sin pisarse")
    func severalWalksAccumulate() async throws {
        try await Self.withDirectory { directory in
            var launch = Self.launch(in: directory)
            for i in 0..<3 {
                await Self.walkAndFinish(launch, steps: 100 * (i + 1))
                launch.store.leaveSummary()
                launch = Self.launch(in: directory, at: SessionStoreFixture.t0.addingTimeInterval(TimeInterval(86_400 * (i + 1))))
            }

            #expect(launch.history.records.count == 3)
            #expect(launch.history.records.map(\.stepsMeasured) == [100, 200, 300])
            #expect(Set(launch.history.records.map(\.id)).count == 3, "cada registro con su identidad")
        }
    }

    // MARK: - Historial ilegible

    /// El criterio de aceptación: se aparta, la app funciona con historial vacío, y Paul se
    /// entera. Sobre bytes de verdad, porque lo que hay que comprobar es que **no se destruyen**.
    @Test("Un sessions.json ilegible se aparta, la app sigue y se avisa")
    func anUnreadableHistoryIsSetAsideAndAnnounced() async throws {
        try await Self.withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data("esto no es json".utf8)
            try bytes.write(to: Self.sessionsURL(in: directory))

            let launch = Self.launch(in: directory)

            #expect(launch.history.records.isEmpty)
            #expect(launch.history.showsUnreadableNotice, "Paul se entera")
            let apartados = try Self.setAsideNames(in: directory)
            #expect(apartados.count == 1, "y no se ha destruido")
            let apartado = directory.appending(path: try #require(apartados.first), directoryHint: .notDirectory)
            #expect(try Data(contentsOf: apartado) == bytes)

            // La app funciona: se puede caminar y la caminata nueva se guarda, porque lo que
            // había ya no está en `sessions.json` (está apartado) y no hay nada que sobrescribir.
            await Self.walkAndFinish(launch, steps: 500)
            #expect(launch.history.records.count == 1)
        }
    }

    /// **La mutación obligatoria**: escribir encima de un historial del futuro. Sin la guarda,
    /// la primera caminata se lleva por delante meses de datos que otra versión sí entiende.
    @Test("Un sessions.json del futuro se deja intacto, se avisa, y la caminata nueva NO lo pisa")
    func aFutureHistoryIsNeverOverwritten() async throws {
        try await Self.withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data(#"{ "schemaVersion": 99, "sessions": [{ "loQueSea": true }] }"#.utf8)
            try bytes.write(to: Self.sessionsURL(in: directory))

            let launch = Self.launch(in: directory)
            #expect(launch.history.showsUnreadableNotice)

            await Self.walkAndFinish(launch, steps: 500)

            #expect(try Data(contentsOf: Self.sessionsURL(in: directory)) == bytes, "los bytes del futuro no han cambiado")
            #expect(try Self.setAsideNames(in: directory).isEmpty, "y tampoco se ha apartado")
            #expect(launch.store.finishedWalkNotPersisted, "la caminata no se guardó, y el resumen lo dice")
            let snapshot = try launch.storage.loadActiveSession()
            #expect(snapshot != nil, "pero su snapshot sigue: no se ha perdido")
        }
    }
}
