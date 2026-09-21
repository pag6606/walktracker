import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El ciclo completo de `settings.json`: un fichero de verdad en un directorio de verdad, el
/// store montado encima, algo que escriba, y los **bytes crudos** releídos después (B-1).
///
/// **Es la costura que faltaba** (hallazgo V1 de la retro del Epic 2). `StorageStub` guarda un
/// `AppSettings?`, no bytes, así que un "fichero del futuro" no se podía expresar en los tests
/// del store; y los del adapter nunca montaban un `SettingsStore`. Entre las dos mitades cabía
/// D1: cada lado hacía lo suyo bien y el conjunto borraba la configuración de Paul en la
/// primera caminata. Aquí se prueban las dos a la vez.
///
/// **El fallo de lectura se monta quitándole al fichero el permiso de lectura**, no
/// corrompiéndolo: los bytes siguen enteros, que es justo lo que hay que proteger, y el
/// directorio sigue siendo escribible —o sea, la escritura destructiva es posible y lo único
/// que la evita es el store—.
@MainActor
@Suite("SettingsStore · el ciclo completo sobre settings.json")
struct SettingsStorePersistenceTests {

    /// Un directorio temporal propio, que se borra al terminar.
    private static func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SettingsStorePersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: Self.settingsURL(in: directory).path(percentEncoded: false)
            )
            try? FileManager.default.removeItem(at: directory)
        }
        try await body(directory)
    }

    private static func settingsURL(in directory: URL) -> URL {
        directory.appending(path: SettingsFileAdapter.fileName, directoryHint: .notDirectory)
    }

    /// El fallo de lectura: el fichero sigue entero, pero no se puede abrir.
    private static func denyReading(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// El fallo se pasa: la lectura vuelve a funcionar, como un error transitorio de verdad.
    private static func allowReading(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Nombres de los ajustes apartados (`settings.corrupt.<marca>.json`).
    private static func setAsideNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter {
            $0.hasPrefix(SettingsFileAdapter.setAsideFilePrefix) && $0.hasSuffix(SettingsFileAdapter.setAsideFileExtension)
        }
    }

    /// Unos ajustes escritos por la app: la ventana de la 2.2 y la zancada de la 2.3.
    ///
    /// - Parameter window: los ids de la ventana. Un test que deje escribir de verdad pasa ids
    ///   **fuera del banco** de frases, para que la que se elija se añada y no reordene.
    private static func writePreviousSettings(to storage: FileStorageAdapter, window: [Int] = [1, 2, 3]) throws -> Data {
        var previous = AppSettings(recentQuoteIds: window)
        try previous.setStrideM(0.72)
        try storage.saveSettings(previous)
        return try Data(contentsOf: Self.settingsURL(in: storage.settings.directory))
    }

    /// Un `SessionStore` de verdad sobre el almacenamiento de ficheros: es quien dispara la
    /// escritura de la primera caminata, vía `openSession()` → `attachQuoteForNewSession()`.
    private static func sessionStore(storage: FileStorageAdapter, settings: SettingsStore) -> SessionStore {
        SessionStore(
            clock: ClockStub(now: SessionStoreFixture.t0),
            motion: MotionStub(status: .granted),
            storage: storage,
            defaultStrideM: 0.655,
            reconciliationTimeoutS: 5,
            orphanSessionThresholdS: SessionStoreFixture.orphanThresholdS,
            maxEstimableGapS: SessionStoreFixture.maxEstimableGapS,
            location: LocationStub(status: .denied),
            weather: WeatherStub(),
            settings: settings,
            history: HistoryStore(storage: storage),
            quotes: SessionStoreFixture.bank(5),
            random: RandomStub(.fixed(0)),
            weatherStepTimeoutS: 5,
            measure: { _ in }
        )
    }

    // MARK: - Fallo de lectura: el fichero sobrevive a la caminata

    @Test("La primera caminata con la lectura fallida NO borra la zancada ni la ventana")
    func firstWalkKeepsTheUnreadableFile() async throws {
        // El caso que la retro reprodujo: un error de unos cientos de bytes al arrancar y, al
        // pulsar "Iniciar caminata", `recordShownQuote` escribía los valores por omisión encima
        // de la recalibración de la 2.3 y de la ventana de la 2.2, para siempre.
        try await Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            let bytes = try Self.writePreviousSettings(to: storage)
            let url = Self.settingsURL(in: directory)
            try Self.denyReading(url)

            let settings = SettingsStore(storage: storage)
            #expect(settings.settings == .defaults, "sin lectura se parte de los valores por omisión")
            let store = Self.sessionStore(storage: storage, settings: settings)
            await store.start()

            #expect(store.hasSession, "la caminata arranca igual: los ajustes no la bloquean")
            #expect(store.quote != nil, "y su frase se muestra")

            try Self.allowReading(url)
            #expect(try Data(contentsOf: url) == bytes, "los bytes de settings.json no han cambiado")
            let onDisk = try #require(try storage.loadSettings())
            #expect(onDisk.strideM == 0.72, "la zancada recalibrada de la 2.3 sigue ahí")
            #expect(onDisk.recentQuoteIds == [1, 2, 3], "y la ventana de la 2.2 también")
            #expect(try Self.setAsideNames(in: directory).isEmpty, "no se aparta lo que solo no se pudo leer")
        }
    }

    @Test("Una sesión entera de frases con la lectura fallida: la ventana vive en memoria y el fichero no cambia")
    func wholeSessionWithoutReadingLeavesTheFileAlone() async throws {
        try await Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            let bytes = try Self.writePreviousSettings(to: storage)
            let url = Self.settingsURL(in: directory)
            try Self.denyReading(url)
            let settings = SettingsStore(storage: storage)

            for id in 7...9 {
                settings.recordShownQuote(id: id)
            }

            #expect(settings.recentQuoteIds == [7, 8, 9], "dentro de esta ejecución no se repiten frases")
            try Self.allowReading(url)
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Guardar la zancada con la lectura fallida no persiste, y la pantalla lo dice")
    func savingStrideWithoutReadingIsReported() async throws {
        try await Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            let bytes = try Self.writePreviousSettings(to: storage)
            let url = Self.settingsURL(in: directory)
            try Self.denyReading(url)
            let settings = SettingsStore(storage: storage)

            settings.saveStride(fromText: "0,80")

            #expect(settings.strideOutcome == .notPersisted, "el resultado que ya existía desde la 2.3")
            #expect(settings.strideOutcome?.isSaved == false)
            #expect(settings.strideM == 0.80, "esta ejecución sí lo usa")
            try Self.allowReading(url)
            #expect(try Data(contentsOf: url) == bytes, "y el fichero se queda como estaba")
        }
    }

    // MARK: - Fallo transitorio, recuperado

    @Test("Recuperada la lectura, la zancada se guarda SIN perder la ventana que había en disco")
    func recoveredReadSavesOnTopOfTheDisk() async throws {
        try await Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            _ = try Self.writePreviousSettings(to: storage)
            let url = Self.settingsURL(in: directory)
            try Self.denyReading(url)
            let settings = SettingsStore(storage: storage)
            #expect(settings.recentQuoteIds.isEmpty, "al arrancar no se pudo leer nada")

            try Self.allowReading(url)
            settings.saveStride(fromText: "0,80")

            #expect(settings.strideOutcome == .saved)
            let onDisk = try #require(try storage.loadSettings())
            #expect(onDisk.strideM == 0.80, "el cambio se escribe")
            #expect(
                onDisk.recentQuoteIds == [1, 2, 3],
                "sobre lo leído del disco, no sobre los valores por omisión que el store arrastraba"
            )
        }
    }

    @Test("Recuperada la lectura, la caminata añade su frase a la ventana que había en disco")
    func recoveredReadAppendsToTheDiskWindow() async throws {
        try await Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            // Ventana fuera del banco (1…5): la frase que se elija se añade al final y no
            // reordena nada, así que la afirmación puede ser exacta.
            _ = try Self.writePreviousSettings(to: storage, window: [11, 12, 13])
            let url = Self.settingsURL(in: directory)
            try Self.denyReading(url)
            let settings = SettingsStore(storage: storage)
            let store = Self.sessionStore(storage: storage, settings: settings)

            try Self.allowReading(url)
            await store.start()

            let shown = try #require(store.quote?.id)
            let onDisk = try #require(try storage.loadSettings())
            #expect(onDisk.recentQuoteIds == [11, 12, 13] + [shown], "la ventana del disco no se pierde")
            #expect(onDisk.strideM == 0.72, "y la zancada recalibrada no se pierde")
        }
    }

    // MARK: - Esquema del futuro

    @Test("Un fichero de un esquema mayor no cambia NI UN BYTE tras una caminata")
    func futureSchemaSurvivesAWalk() async throws {
        // Alguien instaló un build anterior. El adapter lo deja intacto a propósito; hasta B-1,
        // esa preservación duraba hasta que Paul andaba.
        try await Self.withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = Self.settingsURL(in: directory)
            let future = Data(#"{ "schemaVersion": 2, "recentQuoteIds": [4, 5, 6], "strideM": 0.72 }"#.utf8)
            try future.write(to: url)
            let storage = FileStorageAdapter(directory: directory)

            let settings = SettingsStore(storage: storage)
            let store = Self.sessionStore(storage: storage, settings: settings)
            await store.start()

            #expect(store.hasSession)
            #expect(try Data(contentsOf: url) == future, "ni un byte")
            #expect(try Self.setAsideNames(in: directory).isEmpty, "del futuro no es corrupto: no se aparta")
        }
    }

    @Test("Y el reintento no lo desprotege: escriba quien escriba, el fichero del futuro sigue igual")
    func futureSchemaSurvivesEveryRetry() async throws {
        try await Self.withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = Self.settingsURL(in: directory)
            let future = Data(#"{ "schemaVersion": 9, "recentQuoteIds": [4, 5, 6] }"#.utf8)
            try future.write(to: url)
            let settings = SettingsStore(storage: FileStorageAdapter(directory: directory))

            settings.recordShownQuote(id: 7)
            settings.saveStride(fromText: "0,80")
            settings.recordShownQuote(id: 8)

            #expect(settings.strideOutcome == .notPersisted, "el reintento vuelve a fallar, por definición")
            #expect(try Data(contentsOf: url) == future)
        }
    }

    // MARK: - Primera instalación

    @Test("Sin fichero SÍ se escribe: la primera caminata lo crea con su ventana")
    func firstInstallCreatesTheFile() async throws {
        // "No hay nada que perder" no puede quedar bloqueado, o no se guardaría nunca nada.
        try await Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            let settings = SettingsStore(storage: storage)
            let store = Self.sessionStore(storage: storage, settings: settings)

            await store.start()

            let shown = try #require(store.quote?.id)
            let onDisk = try #require(try storage.loadSettings())
            #expect(onDisk.recentQuoteIds == [shown])
            #expect(FileManager.default.fileExists(atPath: Self.settingsURL(in: directory).path(percentEncoded: false)))
        }
    }

    @Test("Un ilegible se aparta y el fichero nuevo se crea: lo apartado no se pierde")
    func unreadableFileIsSetAsideAndReplaced() async throws {
        try await Self.withDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = Self.settingsURL(in: directory)
            let broken = Data(#"{ "schemaVersion": 1, "recentQuoteIds": "ay" }"#.utf8)
            try broken.write(to: url)
            let storage = FileStorageAdapter(directory: directory)

            let settings = SettingsStore(storage: storage)
            settings.recordShownQuote(id: 7)

            #expect(try storage.loadSettings()?.recentQuoteIds == [7], "tras apartarlo no queda nada que perder")
            let names = try Self.setAsideNames(in: directory)
            #expect(names.count == 1)
            let apartado = directory.appending(path: names[0], directoryHint: .notDirectory)
            #expect(try Data(contentsOf: apartado) == broken, "y el contenido original se conserva entero")
        }
    }

    // MARK: - Fallo de escritura (como hasta ahora)

    @Test("Con la lectura buena y la escritura imposible: en memoria sí, en disco no")
    func writeFailureIsStillReported() async throws {
        try await Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            _ = try Self.writePreviousSettings(to: storage)
            let settings = SettingsStore(storage: storage)
            // Sin permiso de escritura en el directorio no hay temporal que renombrar.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: directory.path(percentEncoded: false)
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: directory.path(percentEncoded: false)
                )
            }

            settings.saveStride(fromText: "0,80")

            #expect(settings.strideOutcome == .notPersisted)
            #expect(settings.strideM == 0.80, "la siguiente caminata de esta ejecución ya la usa")
            #expect(try storage.loadSettings()?.strideM == 0.72, "en disco sigue lo anterior")
        }
    }
}
