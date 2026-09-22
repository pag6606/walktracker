import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El cableado del composition root que ningún test del store ve.
@MainActor
@Suite("CompositionRoot · cableado del store")
struct CompositionRootTests {

    @Test("El store recibe el almacenamiento y el umbral de huérfana de formulas.json: una sesión de hace 1 h se restaura activa")
    func storeGetsStorageAndOrphanThreshold() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let startedAt = now.addingTimeInterval(-60 * 60)
        let storage = StorageStub(snapshot: ActiveSessionSnapshot(
            startedAt: startedAt, stepsMeasured: 4000, stepsEstimated: 0, totalPausesS: 0, paused: false,
            pausedAt: nil, strideM: 0.655, systemDistanceM: nil, savedAt: now, lastSampleAt: now,
            segmentStart: startedAt, segmentSteps: 4000, distanceBaseM: 0
        ))
        let root = CompositionRoot(
            clock: ClockStub(now: now), motion: MotionStub(status: .granted), storage: storage,
            location: LocationStub(status: .denied), weather: WeatherStub()
        )

        await root.sessionStore.restoreOnLaunch()

        let session = try #require(root.sessionStore.session)
        #expect(storage.loadCount == 1)
        #expect(session.status == .active)
        #expect(!session.recovered)
        #expect(session.stepsMeasured == 4000)
    }

    @Test("El store recibe el tope de gap estimable de formulas.json: un gap de 25 min no estima y uno de 20 sí")
    func storeGetsMaxEstimableGap() async throws {
        // Comportamental: si el cableado cogiera otra constante (p. ej. las 6 h del umbral de
        // huérfana), el gap de 25 min cabría y estimaría.
        let clock = ClockStub(now: Date(timeIntervalSince1970: 1_800_000_000))
        let motion = MotionStub(status: .granted)
        let root = CompositionRoot(
            clock: clock, motion: motion, storage: StorageStub(),
            location: LocationStub(status: .denied), weather: WeatherStub()
        )
        let store = root.sessionStore
        #expect(store.maxEstimableGapS == root.formulas.maxEstimableGapS)

        await store.start()
        motion.emit(steps: 800)
        await waitUntil { store.session?.stepsMeasured == 800 }
        clock.advance(by: 600)
        store.appDidEnterBackground()
        clock.advance(by: 25 * 60)
        motion.setQueryResponse(.none)
        await store.appDidBecomeActive()
        #expect(store.session?.stepsEstimated == 0, "25 min pasan del tope de 20 de formulas.json")

        // Y con un gap de justo 20 min, la misma degradación sí estima: 800 pasos en 35 min de
        // sesión son 22,9 spm (la cadencia se redondea a un decimal) × 20 min.
        store.appDidEnterBackground()
        clock.advance(by: 20 * 60)
        await store.appDidBecomeActive()
        #expect(store.session?.stepsEstimated == 458)
    }

    @Test("El store recibe la ubicación y el clima del composition root: al iniciar, el clima del WeatherPort llega a la sesión")
    func storeGetsLocationAndWeather() async throws {
        let location = LocationStub(status: .granted)
        let weather = WeatherStub()
        let root = CompositionRoot(
            clock: ClockStub(now: Date(timeIntervalSince1970: 1_800_000_000)), motion: MotionStub(status: .granted),
            storage: StorageStub(), location: location, weather: weather
        )

        await root.sessionStore.start()
        await waitUntil { root.sessionStore.session?.weather != nil }

        #expect(location.readCount == 1)
        #expect(weather.requested.count == 1)
        #expect(root.sessionStore.session?.weather?.wmoCode == 61)
        #expect(root.sessionStore.weatherStepTimeoutS == 3, "el tope de AR-12, en cada paso")
    }

    @Test("El store recibe el banco del bundle, el azar y el dueño de los ajustes: al iniciar, la frase llega a la sesión y a la ventana")
    func storeGetsQuotesRandomAndSettings() async throws {
        // Comportamental, como los tres de arriba: el banco, el `RandomPort` y el
        // `SettingsStore` tienen valor por omisión en el `init` del store, así que dejar de
        // cablear cualquiera de los tres COMPILA. Lo único que lo delata es una caminata real
        // del root que acabe con frase, con `quoteId` y con la ventana escrita.
        let random = RandomStub(.fixed(0))
        let storage = StorageStub()
        let root = CompositionRoot(
            clock: ClockStub(now: Date(timeIntervalSince1970: 1_800_000_000)), motion: MotionStub(status: .granted),
            storage: storage, location: LocationStub(status: .denied), weather: WeatherStub(), random: random
        )
        #expect(root.quotes.quotes.count == 100, "el banco leído del bundle son las 100 congeladas")

        await root.sessionStore.start()

        let quote = try #require(root.sessionStore.quote, "sin el banco cableado la app no enseñaría ni una frase")
        #expect(root.quotes.quote(id: quote.id) == quote, "y es una del banco del root, no de otro")
        #expect(root.sessionStore.session?.quoteId == quote.id)
        #expect(random.counts == [100], "el azar del root es el que elige, sobre el banco entero")
        #expect(root.settingsStore.recentQuoteIds == [quote.id], "el dueño de los ajustes cableado es el que la registra")
        #expect(storage.settingsSaved.last?.recentQuoteIds == [quote.id], "y escribe por el mismo almacenamiento")
    }

    // MARK: - El anillo de meta (3.1)

    @Test("El store de ajustes recibe el RELOJ del root: el anillo mide la semana de ese reloj")
    func settingsStoreGetsTheRootClock() throws {
        // Comportamental, y hace falta porque `clock` tiene valor por omisión en el `init` de
        // `SettingsStore`: dejar de cablearlo COMPILA y el anillo pasaría a medir contra
        // `SystemClock`, es decir, contra el día en que se ejecute. La caminata del fixture cae en
        // la semana del `ClockStub` (lunes 6 de julio de 2026) y en ninguna otra.
        let now = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!
        let record = try SessionRecord(
            id: UUID(), startedAt: ISO8601DateFormatter().date(from: "2026-07-06T10:00:00Z")!,
            endedAt: ISO8601DateFormatter().date(from: "2026-07-06T11:00:00Z")!,
            stepsMeasured: 0, stepsEstimated: 0, strideM: 0.655, distanceM: 7500,
            durationS: 3600, pausesS: 0, paceSecPerKm: nil, cadenceSpm: 0
        )
        let root = CompositionRoot(
            clock: ClockStub(now: now), motion: MotionStub(status: .granted),
            storage: StorageStub(sessions: [record]), location: LocationStub(status: .denied), weather: WeatherStub()
        )

        let progress = try #require(root.settingsStore.weeklyProgress)
        #expect(progress.completedKm == 7.5, "con el reloj del sistema esta caminata estaría fuera de la semana")
        #expect(progress.goalKm == 10)
        #expect(GoalEngine.weekKey(for: now, calendar: root.clock.calendar) == "2026-W28")
    }

    @Test("El store de ajustes recibe LA MISMA instancia del historial: el anillo se mueve al guardar")
    func settingsStoreSharesTheHistoryOwner() throws {
        // `history` también tenía valor por omisión mientras se escribía la 3.1, y dejarlo sin
        // cablear COMPILA: `SettingsStore` se construiría su propio `HistoryStore` sobre el mismo
        // fichero y habría **dos lectores** de `sessions.json`. Dos consecuencias, las dos mudas:
        // el anillo no se movería tras una caminata, y con el historial ilegible el primer lector
        // apartaría el fichero y el segundo leería "ausente" — el anillo diría 0 km / 0 % en vez
        // de "no se pudo leer".
        let now = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!
        let root = CompositionRoot(
            clock: ClockStub(now: now), motion: MotionStub(status: .granted),
            storage: StorageStub(), location: LocationStub(status: .denied), weather: WeatherStub()
        )
        #expect(root.settingsStore.weeklyProgress?.completedKm == 0)

        let record = try SessionRecord(
            id: UUID(), startedAt: ISO8601DateFormatter().date(from: "2026-07-07T10:00:00Z")!,
            endedAt: ISO8601DateFormatter().date(from: "2026-07-07T11:00:00Z")!,
            stepsMeasured: 0, stepsEstimated: 0, strideM: 0.655, distanceM: 4000,
            durationS: 3600, pausesS: 0, paceSecPerKm: nil, cadenceSpm: 0
        )
        #expect(root.historyStore.append(record))

        #expect(root.settingsStore.weeklyProgress?.completedKm == 4, "el anillo lee el historial del root, no otro")
    }

    @Test("El store de sesión recibe LA MISMA instancia de los logros y el catálogo del bundle")
    func sessionStoreSharesTheAchievementsOwnerAndTheCatalog() throws {
        // Mismo argumento que con el historial, un fichero más adentro: dejar `achievements` sin
        // cablear **compilaría** si tuviera valor por omisión, y habría dos dueños de
        // `achievements.json`. El de la sesión escribiría un desbloqueo que el del anillo no
        // vería, y `unlockWeeklyGoal(at:)` dejaría de ser idempotente contra lo ya escrito.
        let root = CompositionRoot(
            clock: ClockStub(now: ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!),
            motion: MotionStub(status: .granted), storage: StorageStub(),
            location: LocationStub(status: .denied), weather: WeatherStub()
        )

        #expect(root.sessionStore.achievements === root.achievementsStore)
        #expect(root.settingsStore.achievements === root.achievementsStore)
        // Y el catálogo es el que la app carga del bundle, no uno inventado: la evaluación es
        // Swift, pero qué se evalúa es dato (AD-5).
        #expect(root.sessionStore.achievementCatalog == root.achievementCatalog)
        #expect(root.sessionStore.achievementCatalog.achievements.map(\.key) == AchievementCatalog.requiredKeys)
    }

    @Test("Con el historial ilegible el anillo dice 'no se sabe', no 0 %")
    func anUnreadableHistoryReachesTheRing() {
        // La otra mitad del cableado anterior: con dos lectores, el primero aparta el fichero y
        // el segundo encuentra "no hay fichero", así que `readOutcome` dejaría de ser
        // `unreadable` y el anillo pintaría un 0 % que nadie sabe.
        let storage = StorageStub()
        storage.failLoadSessions(with: .malformed("bytes"))
        let root = CompositionRoot(
            clock: ClockStub(now: ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!),
            motion: MotionStub(status: .granted), storage: storage,
            location: LocationStub(status: .denied), weather: WeatherStub()
        )

        #expect(root.historyStore.showsUnreadableNotice)
        #expect(root.settingsStore.weeklyProgress == nil)
    }
}
