import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El canal de feedback cableado a los sucesos reales (4.1, CAP-12).
///
/// El puerto, sus cuatro eventos y el adapter existen desde la 8.6 y **nadie los disparaba**: el
/// único consumidor era la pantalla de diagnóstico de DEBUG. Aquí se comprueba que tres de los
/// cuatro disparos —inicio, kilómetro y logro— ocurren donde deben y **una sola vez por suceso**;
/// el cuarto, la meta semanal, vive en `SettingsStoreGoalTests` porque lo decide el anillo.
///
/// Lo que **no** se comprueba aquí es la háptica: qué intensidad, qué nitidez y qué sonido tiene
/// cada evento lo fija `FeedbackAdapterTests` desde la 8.6, y esta historia no toca el adapter.
/// Lo que se comprueba es el **cableado**: qué evento, cuántas veces y con qué `soundEnabled`.
@MainActor
@Suite("SessionStore · el canal de feedback")
struct SessionStoreFeedbackTests: SessionStoreSuite {

    private typealias Fixture = SessionStoreFixture

    /// Lleva la distancia de la sesión hasta `meters` con una muestra del stream **en vivo**.
    /// Los pasos solo tienen que crecer: la distancia la fija el sistema, que es lo que mide el
    /// cruce de kilómetro.
    ///
    /// La muestra del podómetro trae la distancia **del tramo**, no la de la sesión, así que se
    /// le resta la base: en una sesión restaurada ese tramo empieza con los kilómetros del
    /// snapshot ya andados, y emitir la distancia total la duplicaría.
    private static func walkLive(_ fixture: Fixture, steps: Int, toMeters meters: Double) async {
        fixture.motion.emit(steps: steps, distance: meters - fixture.store.distanceBaseM)
        await waitUntil { fixture.store.metrics?.distanceM == meters }
    }

    /// 4 100 pasos con la zancada por omisión son 2 685,5 m: desbloquea `first_km` y
    /// `first_session`, y **dos** logros de una vez es justo lo que D3 quiere ver vibrar una vez.
    private static func walkAndFinish(_ fixture: Fixture, steps: Int = 4_100) async {
        await fixture.startWalking(steps: steps)
        fixture.clock.advance(by: 1_800)
        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
    }

    // MARK: - Inicio de sesión

    @Test("Abrir una sesión dispara exactamente un .sessionStart, y sin sonido")
    func openingASessionFiresSessionStart() async {
        let fixture = Fixture()

        await fixture.store.start()

        #expect(fixture.feedback.fired == [.init(event: .sessionStart, soundEnabled: false)])
    }

    /// `openSession()` es el punto único, y los **dos** entrantes pasan por él. Sin este caso, el
    /// camino de la pre-pantalla podría abrir una sesión muda y nadie se enteraría.
    @Test("La sesión que nace tras conceder el permiso también vibra, y una sola vez")
    func theSessionBornAfterThePermissionFiresToo() async {
        let fixture = Fixture(motion: MotionStub(status: .notDetermined, requestAnswer: .granted))

        await fixture.store.start()
        #expect(fixture.feedback.events.isEmpty, "la pre-pantalla no es una sesión")

        await fixture.store.confirmMotionPermission()

        #expect(fixture.feedback.events == [.sessionStart])
    }

    @Test("Sin permiso no hay sesión y no se dispara nada")
    func aBlockedStartFiresNothing() async {
        let fixture = Fixture(motion: MotionStub(status: .denied))

        await fixture.store.start()

        #expect(fixture.store.session == nil)
        #expect(fixture.feedback.events.isEmpty)
    }

    /// **Restaurar no es empezar.** La sesión que vuelve tras un force-quit no pasa por
    /// `openSession()`, así que relanzar la app no confirma una caminata que empezó hace una hora.
    @Test("Restaurar una sesión al relanzar NO dispara .sessionStart")
    func restoringASessionDoesNotFireSessionStart() async {
        let fixture = Fixture(storage: StorageStub(snapshot: Self.snapshot(distanceM: 5_000)))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.store.session?.status == .active)
        #expect(fixture.feedback.events.isEmpty)
    }

    // MARK: - El cruce de kilómetro, en vivo

    @Test("El primer kilómetro: de 980 a 1.020 m dispara un .kilometer, sin sonido")
    func crossingTheFirstKilometerFiresOnce() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.feedback.clear()

        await Self.walkLive(fixture, steps: 1_400, toMeters: 980)
        #expect(fixture.feedback.count(of: .kilometer) == 0, "980 m no es un kilómetro")

        await Self.walkLive(fixture, steps: 1_500, toMeters: 1_020)

        #expect(fixture.feedback.fired == [.init(event: .kilometer, soundEnabled: false)])
    }

    @Test("Dentro del mismo kilómetro no se dispara nada: de 1.100 a 1.900 m")
    func notCrossingFiresNothing() async {
        let fixture = Fixture()
        await fixture.store.start()
        await Self.walkLive(fixture, steps: 1_600, toMeters: 1_100)
        fixture.feedback.clear()

        await Self.walkLive(fixture, steps: 2_800, toMeters: 1_900)

        #expect(fixture.feedback.events.isEmpty)
    }

    /// D3 en la costura, no solo en el dominio: saltar de 800 a 4.200 m cruza **tres** múltiplos
    /// y tiene que vibrar **una** vez. Una vibración por kilómetro convertiría una confirmación
    /// discreta en una ráfaga.
    @Test("Varios kilómetros en una muestra son UNA vibración: de 800 a 4.200 m")
    func severalKilometersAtOnceFireOnce() async {
        let fixture = Fixture()
        await fixture.store.start()
        await Self.walkLive(fixture, steps: 1_200, toMeters: 800)
        fixture.feedback.clear()

        await Self.walkLive(fixture, steps: 6_000, toMeters: 4_200)

        #expect(fixture.feedback.count(of: .kilometer) == 1, "tres múltiplos, un evento")
        #expect(fixture.feedback.events == [.kilometer])
    }

    @Test("Justo en el múltiplo: de 999 a 1.000 m exactos SÍ vibra")
    func theExactMultipleFires() async {
        let fixture = Fixture()
        await fixture.store.start()
        await Self.walkLive(fixture, steps: 1_500, toMeters: 999)
        fixture.feedback.clear()

        await Self.walkLive(fixture, steps: 1_520, toMeters: 1_000)

        #expect(fixture.feedback.count(of: .kilometer) == 1)
    }

    /// La **primera** muestra de una sesión no tiene con qué compararse: siembra la marca y no
    /// dispara. Con un cero inicial en vez de `nil`, una sesión restaurada con 5 km vibraría en
    /// cuanto llegara su primera muestra en vivo.
    @Test("La primera muestra de la sesión siembra la marca y no vibra")
    func theFirstSampleOnlySeedsTheMark() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.feedback.clear()

        await Self.walkLive(fixture, steps: 3_000, toMeters: 2_100)

        #expect(fixture.feedback.events.isEmpty)
    }

    // MARK: - Ni reconciliación ni recuperación (D2)

    /// **La reconstrucción de un hueco de background no es una travesía.** Vibrar aquí sería un
    /// buzz al desbloquear el móvil por kilómetros andados hace media hora.
    @Test("La reconciliación suma 3 km y no dispara ningún evento")
    func theReconciliationFiresNothing() async {
        let fixture = Fixture()
        await fixture.store.start()
        await Self.walkLive(fixture, steps: 1_000, toMeters: 500)
        fixture.feedback.clear()

        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 6_000, distance: 3_500))
        await fixture.store.appDidBecomeActive()

        #expect(fixture.store.metrics?.distanceM == 3_500, "la distancia sí avanzó: tres kilómetros")
        #expect(fixture.feedback.events.isEmpty)
    }

    /// La otra mitad, y la que de verdad cuesta: **la consulta mueve la marca aunque no dispare**.
    /// Sin eso, la primera muestra en vivo después del hueco compararía con la distancia de antes
    /// y vibraría por los kilómetros que la reconciliación acaba de reconstruir — el mismo buzz,
    /// un instante más tarde.
    @Test("Y la primera muestra en vivo tras el hueco tampoco vibra por lo reconstruido")
    func theFirstLiveSampleAfterTheGapDoesNotFireEither() async {
        let fixture = Fixture()
        await fixture.store.start()
        await Self.walkLive(fixture, steps: 1_000, toMeters: 500)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 6_000, distance: 3_500))
        await fixture.store.appDidBecomeActive()
        fixture.feedback.clear()

        await Self.walkLive(fixture, steps: 6_100, toMeters: 3_560)

        #expect(fixture.feedback.events.isEmpty)
    }

    /// Restaurar una sesión entera con 5 km andados no celebra ninguno de ellos. Y el canal
    /// **sigue vivo**: el kilómetro que Paul cruce a partir de ahí sí suena.
    @Test("Recuperar una sesión con 5 km no vibra, y el kilómetro SIGUIENTE sí")
    func recoveringASessionFiresNothingButTheNextKilometerDoes() async {
        let fixture = Fixture(storage: StorageStub(snapshot: Self.snapshot(distanceM: 5_000)))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.feedback.events.isEmpty, "cinco kilómetros de hace una hora no se celebran")

        // El tramo restaurado lleva su base: la muestra suma sobre los 5 000 m del snapshot.
        await Self.walkLive(fixture, steps: 7_700, toMeters: 5_100)
        #expect(fixture.feedback.events.isEmpty, "5 100 m sigue dentro del sexto kilómetro")

        await Self.walkLive(fixture, steps: 9_200, toMeters: 6_000)

        #expect(fixture.feedback.count(of: .kilometer) == 1)
    }

    // MARK: - La marca nunca baja

    /// **El hueco que la suite entera dejaba pasar**: sustituir el `max` por una asignación
    /// directa dejaba los 900 tests en verde, así que nada fijaba la monotonía de la marca.
    ///
    /// La conducta que protege es real y es fea. `Session.metrics(at:)` devuelve `distanceM: 0`
    /// con `degraded: true` cuando un cálculo no cuadra (B-3), y ese `catch` **no es
    /// inalcanzable**: `MetricsScenarios` lo alcanza, y darlo por imposible ya costó un crash en
    /// cada caminata. Si la marca siguiera esa caída a cero, el cálculo bueno siguiente volvería
    /// a cruzar los 1.000 y los 2.000 ya cruzados y vibraría **una vez por cada uno**: la ráfaga
    /// que D3 existe para impedir, y encima en el momento en que algo ya ha ido mal.
    @Test("Una distancia que CAE no reinicia la marca: un kilómetro ya cruzado no se re-cruza")
    func aFallingDistanceDoesNotResetTheMark() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        // La primera muestra siembra la marca; la segunda cruza los 1.000 y los 2.000.
        await Self.walkLive(fixture, steps: 300, toMeters: 200)
        await Self.walkLive(fixture, steps: 3_600, toMeters: 2_500)
        try #require(fixture.feedback.count(of: .kilometer) == 1, "dos múltiplos, un evento (D3)")
        fixture.feedback.clear()

        // El cero **de una métrica degradada de verdad**, no un literal elegido a mano: así lo
        // que entra aquí es exactamente lo que `record(...)` le pasaría al paso interno.
        let degradada = try Self.degradedMetrics()
        try #require(degradada.degraded && degradada.distanceM == 0)
        fixture.store.noteKilometerCrossing(upTo: degradada.distanceM, live: true)

        // Y el cálculo siguiente vuelve a pasar por esos mismos 1.000 y 2.000 m.
        fixture.store.noteKilometerCrossing(upTo: 2_600, live: true)

        #expect(fixture.feedback.events.isEmpty, "sin el tope esto son DOS vibraciones por kilómetros ya celebrados")

        // Y el canal sigue vivo: el tercer kilómetro, que nunca se cruzó, sí suena.
        fixture.store.noteKilometerCrossing(upTo: 3_100, live: true)
        #expect(fixture.feedback.count(of: .kilometer) == 1)
    }

    // MARK: - La marca es de esta caminata

    /// **Sin limpiar la marca en `resetSessionState()`, el primer kilómetro de la caminata
    /// siguiente no suena**: la distancia arranca de cero contra los 1 200 m de la anterior, así
    /// que nunca vuelve a "avanzar" hasta pasarla.
    @Test("La caminata siguiente vuelve a sonar en su primer kilómetro")
    func theNextWalkFiresItsOwnFirstKilometer() async {
        let fixture = Fixture()
        await fixture.store.start()
        await Self.walkLive(fixture, steps: 1_200, toMeters: 800)
        await Self.walkLive(fixture, steps: 1_800, toMeters: 1_200)
        #expect(fixture.feedback.count(of: .kilometer) == 1)
        fixture.clock.advance(by: 1_800)
        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        fixture.feedback.clear()

        await fixture.store.start()
        await Self.walkLive(fixture, steps: 1_200, toMeters: 800)
        await Self.walkLive(fixture, steps: 1_800, toMeters: 1_200)

        #expect(fixture.feedback.count(of: .kilometer) == 1, "la marca de la caminata anterior no se hereda")
        #expect(fixture.feedback.events == [.sessionStart, .kilometer])
    }

    // MARK: - Logros

    /// Una primera caminata de 2,6 km desbloquea `first_session` y `first_km` **a la vez**: dos
    /// logros, **una** vibración (D3).
    @Test("Un cierre que desbloquea dos logros vibra una sola vez")
    func aFinishUnlockingTwoAchievementsFiresOnce() async throws {
        let fixture = Fixture()

        await Self.walkAndFinish(fixture)

        try #require(fixture.store.unlockedAchievements.count == 2, "dos logros en el mismo cierre")
        #expect(fixture.feedback.count(of: .achievement) == 1)
        #expect(fixture.feedback.fired.last == .init(event: .achievement, soundEnabled: false))
    }

    /// **No se celebra lo que no se guardó.** Con `achievements.json` ilegible no se evalúa nada
    /// (B-1), así que tampoco se vibra: un logro celebrado que no llegó al disco volvería a
    /// desbloquearse en el cierre siguiente y Paul lo sentiría dos veces.
    @Test("Con achievements.json ilegible no se dispara ningún .achievement")
    func anUnreadableAchievementsFileFiresNothing() async {
        let storage = StorageStub()
        storage.failLoadAchievements(with: .unsupportedSchemaVersion(99))
        let fixture = Fixture(storage: storage)

        await Self.walkAndFinish(fixture)

        #expect(storage.achievementsSaved.isEmpty)
        #expect(fixture.feedback.count(of: .achievement) == 0)
        #expect(storage.sessions?.count == 1, "y la caminata se guarda igual: el feedback no falla hacia fuera")
    }

    @Test("Un cierre que no desbloquea nada no vibra")
    func aFinishUnlockingNothingFiresNothing() async {
        let fixture = Fixture()
        await Self.walkAndFinish(fixture)
        fixture.store.leaveSummary()
        fixture.feedback.clear()

        // Segunda caminata, corta: `first_session` y `first_km` ya están conseguidos.
        await Self.walkAndFinish(fixture, steps: 500)

        #expect(fixture.store.unlockedAchievements.isEmpty)
        #expect(fixture.feedback.count(of: .achievement) == 0)
        #expect(fixture.feedback.events == [.sessionStart], "solo el inicio de esa segunda caminata")
    }

    /// AD-18: una huérfana no premia, así que tampoco vibra. Y el archivado al arrancar no es una
    /// sesión que empiece: no dispara `.sessionStart`.
    @Test("Archivar una huérfana al arrancar no dispara nada")
    func closingAnOrphanFiresNothing() async {
        let startedAt = Self.t0.addingTimeInterval(-12 * 60 * 60)
        let snapshot = ActiveSessionSnapshot(
            startedAt: startedAt, stepsMeasured: 20_000, stepsEstimated: 0, totalPausesS: 0, paused: false,
            pausedAt: nil, strideM: 0.655, systemDistanceM: nil, savedAt: startedAt.addingTimeInterval(1_800),
            lastSampleAt: startedAt.addingTimeInterval(1_800), segmentStart: startedAt, segmentSteps: 20_000,
            distanceBaseM: 0
        )
        let fixture = Fixture(storage: StorageStub(snapshot: snapshot))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.storage.sessions?.first?.recovered == true)
        #expect(fixture.feedback.events.isEmpty)
    }

    // MARK: - Soporte

    /// Unas métricas **degradadas de verdad**, con la receta de `MetricsScenarios` ("metrics(at:)
    /// ante un cálculo imposible DEGRADA"): la suma `systemDistanceM + estimados` desborda aunque
    /// los dos sumandos sean finitos y la zancada quepa. De aquí sale el `distanceM: 0` que ve
    /// `record(...)` cuando el cálculo no cuadra, y no de un literal escrito a mano.
    private static func degradedMetrics() throws -> SessionMetrics {
        let session = try Session.restore(
            startedAt: Self.t0,
            stepsMeasured: 4_980,
            stepsEstimated: .max,
            totalPausesS: 0,
            paused: false,
            pausedAt: nil,
            strideM: MetricsCalculator.maxRepresentableStrideM,
            systemDistanceM: .greatestFiniteMagnitude
        )
        return session.metrics(at: Self.t0.addingTimeInterval(3_720))
    }

    /// Una sesión viva de hace una hora, con `distanceM` metros ya andados: lo que hay en el
    /// snapshot al relanzar la app.
    private static func snapshot(distanceM: Double) -> ActiveSessionSnapshot {
        let startedAt = Self.t0.addingTimeInterval(-60 * 60)
        return ActiveSessionSnapshot(
            startedAt: startedAt,
            stepsMeasured: 7_600,
            stepsEstimated: 0,
            totalPausesS: 0,
            paused: false,
            pausedAt: nil,
            strideM: 0.655,
            systemDistanceM: distanceM,
            savedAt: Self.t0,
            lastSampleAt: Self.t0,
            segmentStart: startedAt,
            segmentSteps: 7_600,
            distanceBaseM: distanceM
        )
    }
}
