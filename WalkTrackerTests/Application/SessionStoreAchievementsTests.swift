import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El enganche de la 3.2: al cerrar una caminata se evalúan los logros, **después** de un guardado
/// con éxito (decisión D1), en un único punto (AD-17) y escribiendo por el dueño de
/// `achievements.json` (AD-16).
///
/// La conducta del motor —qué logro se desbloquea con qué— la fijan los 65 vectores de AD-6 y
/// `AchievementEngineTests`. Aquí se comprueba el **cableado**: el orden entre las dos escrituras,
/// que los dos caminos de persistencia evalúan, que una huérfana no premia y que nada se
/// re-dispara.
///
/// "Relanzar" es construir otro `SessionStoreFixture` sobre el mismo `StorageStub`: el snapshot,
/// el historial y los logros vuelven con él, como los ficheros del sandbox.
@MainActor
@Suite("SessionStore · los logros del cierre")
struct SessionStoreAchievementsTests: SessionStoreSuite {

    private typealias Fixture = SessionStoreFixture

    private nonisolated static var orphanThresholdS: TimeInterval { SessionStoreFixture.orphanThresholdS }

    /// 4 100 pasos con la zancada por omisión son 2 685,5 m: `first_km` sí, `first_5km` no. Y el
    /// reloj del montaje arranca a las 08:00 UTC, que es **justo fuera** de `early_bird`.
    private static func walkAndFinish(_ fixture: Fixture, steps: Int = 4_100, durationS: TimeInterval = 1_800) async {
        await fixture.startWalking(steps: steps)
        fixture.clock.advance(by: durationS)
        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
    }

    private static func keys(_ unlocks: [AchievementUnlock]?) -> [String] {
        (unlocks ?? []).filter(\.isUnlocked).map(\.key).sorted()
    }

    // MARK: - El cierre desbloquea y lo escribe

    @Test("Al cerrar la primera caminata se desbloquean sus logros y quedan escritos")
    func finishingUnlocksAndPersists() async throws {
        let fixture = Fixture()

        await Self.walkAndFinish(fixture)

        #expect(Self.keys(fixture.storage.achievements) == ["first_km", "first_session"])
        #expect(fixture.store.unlockedAchievements.map(\.key).sorted() == ["first_km", "first_session"])
        #expect(fixture.storage.achievementsSaved.count == 1, "una sola escritura para los dos logros")
    }

    /// La señal lleva la **definición** del catálogo, no solo la clave: la celebración (3.4) y el
    /// resumen (3.5) necesitan el nombre y el emoji, que son dato congelado (AD-5).
    @Test("La señal trae nombre y emoji del catálogo, para quien celebre")
    func theSignalCarriesTheCatalogDefinition() async throws {
        let fixture = Fixture()

        await Self.walkAndFinish(fixture)

        let firstKm = try #require(fixture.store.unlockedAchievements.first { $0.key == "first_km" })
        let definition = try #require(AchievementCatalogFixture.bundled.definition(for: "first_km"))
        #expect(firstKm == definition)
        #expect(!firstKm.icon.isEmpty)
    }

    @Test("La señal es de ESTE cierre: salir del resumen la limpia y el desbloqueo se queda en disco")
    func theSignalIsClearedOnLeavingTheSummary() async throws {
        let fixture = Fixture()
        await Self.walkAndFinish(fixture)
        try #require(!fixture.store.unlockedAchievements.isEmpty)

        fixture.store.leaveSummary()

        #expect(fixture.store.unlockedAchievements.isEmpty)
        #expect(Self.keys(fixture.storage.achievements) == ["first_km", "first_session"], "el desbloqueo es de por vida")
    }

    @Test("El desbloqueo se fecha en el CIERRE de la caminata, no cuando se pulsa un botón")
    func theUnlockIsDatedAtTheEndOfTheWalk() async throws {
        let fixture = Fixture()
        // El disco falla al cerrar, así que la evaluación no ocurre; se recupera 10 min después.
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))
        await Self.walkAndFinish(fixture)
        let endedAt = try #require(fixture.store.session?.endedAt)
        fixture.clock.advance(by: 600)
        fixture.storage.failSaveSessions(with: nil)

        fixture.store.leaveSummary()

        let unlock = try #require(fixture.storage.achievements?.first { $0.key == "first_km" })
        #expect(unlock.unlockedAt == endedAt, "es cuando Paul se lo ganó, no cuando salió del resumen")
        #expect(endedAt != fixture.clock.now, "y los dos instantes son distintos, o el test no probaría nada")
    }

    // MARK: - El orden: sesión primero, logros después (D1)

    /// **La mutación obligatoria de esta historia**: evaluar antes del `append`. Con el orden
    /// invertido, este test se cae: los logros se escribirían de una caminata que no está en el
    /// historial, y eso es un logro fantasma **irrevocable** (AD-17, CAP-15).
    @Test("Si la caminata no se pudo guardar, NO se evalúa ningún logro")
    func aFailedSaveEvaluatesNothing() async throws {
        let fixture = Fixture()
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))

        await Self.walkAndFinish(fixture)

        #expect(fixture.store.finishedWalkNotPersisted)
        #expect(fixture.storage.achievementsSaved.isEmpty, "primero la caminata; sin ella no hay logro que premiar")
        #expect(fixture.store.unlockedAchievements.isEmpty)
    }

    /// D1b: con sesión primero, si el `append` falló la evaluación **no ocurrió**, así que el
    /// reintento de `leaveSummary()` también tiene que evaluar — y lo hace llamando al mismo sitio.
    @Test("El reintento del resumen guarda la caminata Y evalúa sus logros")
    func theRetryAlsoEvaluates() async throws {
        let fixture = Fixture()
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))
        await Self.walkAndFinish(fixture)
        try #require(fixture.storage.achievementsSaved.isEmpty)

        fixture.storage.failSaveSessions(with: nil)
        fixture.store.leaveSummary()

        #expect(fixture.storage.sessions?.count == 1)
        #expect(Self.keys(fixture.storage.achievements) == ["first_km", "first_session"])
    }

    /// La otra mitad del reintento, y es una **decisión escrita**, no un olvido: `leaveSummary()`
    /// reintenta y acto seguido resetea, así que la señal de ese camino no llega a nadie. Se deja
    /// morir porque el resumen ya no está en pantalla; el desbloqueo, que es lo irrevocable, sí
    /// queda escrito. Sin este test, la 3.4 se cablearía a la señal creyendo que el reintento
    /// celebra.
    @Test("El reintento escribe los logros pero NO los anuncia")
    func theRetryWritesButDoesNotAnnounce() async throws {
        let fixture = Fixture()
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))
        await Self.walkAndFinish(fixture)
        fixture.storage.failSaveSessions(with: nil)

        fixture.store.leaveSummary()

        #expect(Self.keys(fixture.storage.achievements) == ["first_km", "first_session"], "escritos")
        #expect(fixture.store.unlockedAchievements.isEmpty, "y sin anunciar: el resumen ya no está")
    }

    /// El otro lado del mismo orden: los cuatro logros acumulados **se curan solos** en el cierre
    /// siguiente, porque el historial ya trae la caminata anterior y la evaluación es determinista.
    /// Es la consecuencia que D1 acepta a sabiendas.
    @Test("Un logro perdido por un corte se cura solo en el cierre siguiente")
    func accumulatedAchievementsHealThemselves() async throws {
        // Primer cierre: la caminata entra en el historial y los logros NO se escriben.
        let fixture = Fixture()
        fixture.storage.failSaveAchievements(with: .failed(operation: "write"))
        await Self.walkAndFinish(fixture)
        try #require(fixture.storage.sessions?.count == 1)
        try #require(fixture.storage.achievements == nil, "el corte: la caminata está, el logro no")
        fixture.store.leaveSummary()

        // Segundo cierre, con el disco sano: `first_session` vuelve a salir porque nunca se escribió.
        fixture.storage.failSaveAchievements(with: nil)
        let relanzado = Fixture(storage: fixture.storage, at: Self.t0.addingTimeInterval(86_400))
        await Self.walkAndFinish(relanzado)

        #expect(Self.keys(relanzado.storage.achievements) == ["first_km", "first_session"])
    }

    // MARK: - Nada se re-dispara, nada se revoca

    @Test("Un logro ya desbloqueado no se re-dispara al cerrar la caminata siguiente")
    func anUnlockedAchievementIsNotRetriggered() async throws {
        let fixture = Fixture()
        await Self.walkAndFinish(fixture)
        let primero = try #require(fixture.storage.achievements?.first { $0.key == "first_session" })
        let escrituras = fixture.storage.achievementsSaved.count
        fixture.store.leaveSummary()

        let relanzado = Fixture(storage: fixture.storage, at: Self.t0.addingTimeInterval(86_400))
        await Self.walkAndFinish(relanzado)

        let despues = try #require(relanzado.storage.achievements?.first { $0.key == "first_session" })
        #expect(despues.unlockedAt == primero.unlockedAt, "AD-17: su instante no se mueve")
        #expect(relanzado.store.unlockedAchievements.isEmpty, "y no se vuelve a anunciar")
        #expect(relanzado.storage.achievementsSaved.count == escrituras, "ni se reescribe el fichero por nada")
    }

    // MARK: - La huérfana (AD-18)

    @Test("Una huérfana entra en el historial y NO desbloquea ningún logro")
    func anOrphanUnlocksNothing() async throws {
        let startedAt = Self.t0.addingTimeInterval(-(Self.orphanThresholdS + 3_600))
        let snapshot = ActiveSessionSnapshot(
            startedAt: startedAt,
            stepsMeasured: 20_000,
            stepsEstimated: 0,
            totalPausesS: 0,
            paused: false,
            pausedAt: nil,
            strideM: 0.655,
            systemDistanceM: nil,
            savedAt: startedAt.addingTimeInterval(1_800),
            lastSampleAt: startedAt.addingTimeInterval(1_800),
            segmentStart: startedAt,
            segmentSteps: 20_000,
            distanceBaseM: 0
        )
        let fixture = Fixture(storage: StorageStub(snapshot: snapshot))

        await fixture.store.restoreOnLaunch()

        let record = try #require(fixture.storage.sessions?.first)
        try #require(record.recovered)
        try #require(record.distanceM >= 10_000, "de sobra para first_10km, si se premiara")
        #expect(fixture.storage.achievementsSaved.isEmpty, "AD-18: una sesión que nadie finalizó no se premia")
        #expect(fixture.store.unlockedAchievements.isEmpty)
    }

    // MARK: - `weekly_goal`, la excepción declarada (AD-25)

    @Test("Con la meta de la semana cumplida, el cierre NO desbloquea weekly_goal")
    func theWeeklyGoalIsNeverUnlockedByTheFinish() async throws {
        // 10 km ya caminados en la misma semana ISO local que el reloj del montaje.
        let previa = try SessionRecord(
            id: UUID(),
            startedAt: Self.t0.addingTimeInterval(-86_400),
            endedAt: Self.t0.addingTimeInterval(-86_400 + 3_600),
            stepsMeasured: 0, stepsEstimated: 0, strideM: 0.655, distanceM: 10_000,
            durationS: 3_600, pausesS: 0, paceSecPerKm: nil, cadenceSpm: 0
        )
        let fixture = Fixture(storage: StorageStub(sessions: [previa]))
        try #require(fixture.settings.weeklyProgress?.isComplete == true, "la semana está cumplida")

        await Self.walkAndFinish(fixture)

        #expect(!Self.keys(fixture.storage.achievements).contains(AchievementsStore.weeklyGoalKey))
        #expect(!fixture.store.unlockedAchievements.contains { $0.key == AchievementsStore.weeklyGoalKey })
    }

    // MARK: - La hora es LOCAL en la costura donde se cablea el calendario

    /// **El hueco que ningún vector tapaba.** Los 65 vectores llaman al motor **directamente**,
    /// con la zona que declaran; por la costura donde el calendario se cablea de verdad
    /// —`SessionStore+History.swift`, `calendar: clock.calendar`— no pasaba ninguno, y el reloj de
    /// los tests estaba clavado en UTC. Sustituir ese `clock.calendar` por un `Calendar` en UTC,
    /// que es lo que hace `motivation.js` y lo que AD-19 prohíbe, dejaba los 834 tests, los 65
    /// vectores y los cuatro gates **en verde**. Y en Ecuador (UTC−5) `early_bird` no se
    /// desbloquearía nunca: las 06:30 locales son las 11:30 UTC.
    @Test("early_bird se decide en hora LOCAL: 11:30 UTC son las 06:30 en Guayaquil")
    func theStartHourIsLocalAtTheWiringSeam() async throws {
        // 2027-01-15T11:30:00Z = 06:30 del 15 de enero en `America/Guayaquil`.
        let seisTreintaLocal = Date(timeIntervalSince1970: 1_800_012_600)
        let fixture = Fixture(at: seisTreintaLocal, timeZone: "America/Guayaquil")
        try #require(fixture.clock.calendar.component(.hour, from: seisTreintaLocal) == 6)

        await Self.walkAndFinish(fixture)

        #expect(
            Self.keys(fixture.storage.achievements).contains("early_bird"),
            "con un calendario en UTC la hora sería 11 y este logro no se desbloquearía nunca en Ecuador"
        )
    }

    // MARK: - El fichero de logros ilegible

    /// B-1: sin una lectura buena no se escribe encima. Y lo que no llegó al disco **no se
    /// anuncia**: un logro celebrado que no está guardado volvería a desbloquearse en el cierre
    /// siguiente, y Paul lo vería dos veces.
    @Test("Con achievements.json ilegible no se escribe encima, no se anuncia nada y la caminata SÍ se guarda")
    func anUnreadableAchievementsFileCostsNoWalk() async throws {
        let storage = StorageStub()
        storage.failLoadAchievements(with: .unsupportedSchemaVersion(99))
        let fixture = Fixture(storage: storage)

        await Self.walkAndFinish(fixture)

        #expect(storage.achievementsSaved.isEmpty)
        #expect(fixture.store.unlockedAchievements.isEmpty)
        #expect(storage.sessions?.count == 1, "la caminata no se pierde por un logro")
        #expect(!fixture.store.finishedWalkNotPersisted)
    }

    /// **No se evalúa contra un estado que no se pudo leer.** Con `readOutcome == .unreadable` los
    /// `unlocks` en memoria están vacíos —no porque no haya logros, sino porque no se leyeron—, y
    /// el motor daría por **nuevos los catorce**. El caso peor es el fallo **transitorio**: el
    /// fichero sigue entero en disco, así que la relectura de `save(applying:)` sí va a funcionar
    /// y la escritura no está bloqueada por nada.
    @Test("Con el estado de los logros sin leer NO se evalúa, aunque el disco se recupere después")
    func nothingIsEvaluatedAgainstAnUnreadableState() async throws {
        let yaConseguido = try AchievementUnlock(key: "first_session", unlockedAt: Self.t0, progress: 1)
        let storage = StorageStub(achievements: [yaConseguido])
        storage.failLoadAchievements(with: .failed(operation: "read"))
        let fixture = Fixture(storage: storage)
        try #require(fixture.achievements.readOutcome.isUnreadable)
        try #require(fixture.achievements.unlocks.isEmpty)
        storage.failLoadAchievements(with: nil)

        await Self.walkAndFinish(fixture)

        #expect(storage.achievementsSaved.isEmpty, "ni siquiera `first_km`, que sí sería nuevo")
        #expect(fixture.store.unlockedAchievements.isEmpty)
        #expect(storage.achievements == [yaConseguido], "y lo que había sigue intacto")
        #expect(storage.sessions?.count == 1, "la caminata se guarda igual")
    }

    // MARK: - El único punto (AD-17)

    /// Abrir el historial, montar los stores y relanzar la app **no** evalúan nada. Solo el
    /// cierre. Sin esto, un logro se dispararía cada vez que la app arranca.
    @Test("Montar los stores y relanzar no evalúan nada: solo el cierre")
    func nothingIsEvaluatedOutsideTheFinish() async throws {
        let fixture = Fixture()
        await Self.walkAndFinish(fixture)
        fixture.store.leaveSummary()
        let escrituras = fixture.storage.achievementsSaved.count
        try #require(escrituras == 1)

        // Relanzar: se leen el historial y los logros, y no se escribe nada.
        let relanzado = Fixture(storage: fixture.storage, at: Self.t0.addingTimeInterval(7_200))
        await relanzado.store.restoreOnLaunch()

        #expect(relanzado.storage.achievementsSaved.count == escrituras)
        #expect(relanzado.store.unlockedAchievements.isEmpty)
    }
}
