import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 1.1 sobre `SessionStore`, con el reloj en un `ClockStub` y el permiso
/// ya concedido en un `MotionStub`.
@MainActor
@Suite("SessionStore · iniciar y cronómetro")
struct SessionStoreTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func store(clock: ClockStub, strideM: Double = 0.655) -> SessionStore {
        SessionStore(clock: clock, motion: MotionStub(status: .granted), strideM: strideM)
    }

    @Test("Iniciar: sesión active con los valores iniciales en el instante del reloj")
    func startCreatesActiveSession() async throws {
        let clock = ClockStub(now: Self.t0)
        let store = Self.store(clock: clock)
        #expect(store.session == nil)
        #expect(!store.hasSession)
        #expect(store.elapsedS == 0)

        await store.start()

        let session = try #require(store.session)
        #expect(store.hasSession)
        #expect(session.status == .active)
        #expect(session.startedAt == Self.t0)
        #expect(session.stepsMeasured == 0)
        #expect(session.stepsEstimated == 0)
        #expect(session.strideM == 0.655)
        #expect(session.source == .ios)
        #expect(session.endedAt == nil)
        #expect(session.totalPausesS == 0)
        #expect(store.elapsedS == 0)
        #expect(store.startFailure == nil)
    }

    @Test("Zancada inválida: invalidValue(strideM), ninguna sesión y ningún conteo", arguments: [0, -1, Double.nan, .infinity])
    func invalidStrideCreatesNothing(stride: Double) async {
        let motion = MotionStub(status: .granted)
        let store = SessionStore(clock: ClockStub(now: Self.t0), motion: motion, strideM: stride)

        await store.start()

        #expect(store.startFailure == .invalidSession(.invalidValue(field: "strideM")))
        #expect(store.session == nil)
        #expect(!store.hasSession)
        #expect(motion.updateStarts.isEmpty)
        #expect(!store.isCountingSteps)
    }

    @Test("El tiempo se lee del reloj en cada lectura")
    func elapsedFollowsClock() async {
        let clock = ClockStub(now: Self.t0)
        let store = Self.store(clock: clock)
        await store.start()

        clock.advance(by: 1)
        #expect(store.elapsedS == 1)
        clock.advance(by: 64)
        #expect(store.elapsedS == 65)
    }

    @Test("Con un instante de suelo se mide en el mayor entre él y el reloj")
    func elapsedNotBeforeInstant() async {
        let clock = ClockStub(now: Self.t0)
        let store = Self.store(clock: clock)
        #expect(store.elapsedS(notBefore: Self.t0.addingTimeInterval(5)) == 0)
        await store.start()

        clock.advance(by: 4.999)
        // La entrada del segundo 5 se evalúa antes de su instante: muestra 5, no 4.
        #expect(store.elapsedS(notBefore: Self.t0.addingTimeInterval(5)) == 5)
        // Un suelo atrasado no retrasa el reloj.
        #expect(abs(store.elapsedS(notBefore: Self.t0) - 4.999) < 0.0001)
    }

    @Test("Background: 10 min activa + 5 min en otra app ≈ 900 s")
    func backgroundTimeCounts() async {
        let clock = ClockStub(now: Self.t0)
        let store = Self.store(clock: clock)
        await store.start()

        clock.advance(by: 10 * 60)   // en primer plano
        clock.advance(by: 5 * 60)    // en otra app: ningún tick llega, el reloj sigue

        #expect(abs(store.elapsedS - 900) < 0.001)
    }

    @Test("Reloj hacia atrás: elapsedS = 0, nunca negativo")
    func clockBackwardsIsZero() async {
        let clock = ClockStub(now: Self.t0)
        let store = Self.store(clock: clock)
        await store.start()

        clock.set(Self.t0.addingTimeInterval(-120))

        #expect(store.elapsedS == 0)
    }

    @Test("Doble toque: un segundo start() no crea otra sesión ni reinicia el tiempo")
    func secondStartIsIgnored() async throws {
        let clock = ClockStub(now: Self.t0)
        let motion = MotionStub(status: .granted)
        let store = SessionStore(clock: clock, motion: motion, strideM: 0.655)
        await store.start()
        let first = try #require(store.session)

        clock.advance(by: 30)
        await store.start()

        #expect(store.session == first)
        #expect(store.session?.startedAt == Self.t0)
        #expect(store.elapsedS == 30)
        #expect(motion.updateStarts.count == 1)
    }
}

/// Espera a que el consumidor del stream procese lo emitido. Falla, no cuelga.
@MainActor
private func waitUntil(
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0..<2_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("La condición no se cumplió a tiempo", sourceLocation: sourceLocation)
}

/// Matriz de la 1.2 y decisiones de sus Design Notes sobre `SessionStore`: permiso de
/// Motion & Fitness y conteo con muestras acumuladas, todo sin hardware.
@MainActor
@Suite("SessionStore · permiso y conteo de pasos")
struct SessionStoreStepCountingTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func store(_ motion: MotionStub) -> SessionStore {
        SessionStore(clock: ClockStub(now: t0), motion: motion, strideM: 0.655)
    }

    private func steps(_ store: SessionStore) -> Int? { store.session?.stepsMeasured }

    // MARK: - Permiso

    @Test("Primera vez: pre-pantalla → diálogo → concedido → sesión y conteo")
    func firstTimeFlow() async throws {
        let motion = MotionStub(status: .notDetermined, requestAnswer: .granted)
        let store = Self.store(motion)

        await store.start()

        #expect(store.startFlow == .explainingPermission)
        #expect(store.session == nil)
        #expect(motion.requestCount == 0, "nunca se pide en frío: primero la pre-pantalla")

        await store.confirmMotionPermission()

        #expect(motion.requestCount == 1)
        #expect(store.startFlow == .idle)
        let session = try #require(store.session)
        #expect(store.hasSession)
        #expect(motion.updateStarts == [session.startedAt])
        #expect(store.isCountingSteps)
    }

    @Test("Ya concedido: sesión directa, sin pre-pantalla ni petición")
    func alreadyGranted() async throws {
        let motion = MotionStub(status: .granted)
        let store = Self.store(motion)

        await store.start()

        #expect(store.startFlow == .idle)
        let session = try #require(store.session)
        #expect(motion.requestCount == 0)
        #expect(motion.updateStarts == [session.startedAt])
    }

    @Test("Denegado o restringido al iniciar: pantalla bloqueante y ninguna sesión", arguments: [
        PermissionStatus.denied, .restricted,
    ])
    func deniedAtStart(status: PermissionStatus) async {
        let motion = MotionStub(status: status)
        let store = Self.store(motion)

        await store.start()

        #expect(store.startFlow == .blocked(.permissionDenied))
        #expect(store.session == nil)
        #expect(!store.hasSession)
        #expect(motion.requestCount == 0)
        #expect(motion.updateStarts.isEmpty)
    }

    @Test("Denegado o restringido al responder al diálogo: pantalla bloqueante y ninguna sesión", arguments: [
        PermissionStatus.denied, .restricted,
    ])
    func deniedAtDialog(answer: PermissionStatus) async {
        let motion = MotionStub(status: .notDetermined, requestAnswer: answer)
        let store = Self.store(motion)

        await store.start()
        await store.confirmMotionPermission()

        #expect(store.startFlow == .blocked(.permissionDenied))
        #expect(store.session == nil)
        #expect(motion.updateStarts.isEmpty)
    }

    @Test("Sin coprocesador: bloqueante sin Ajustes, al iniciar o al responder")
    func unavailableBlocks() async {
        let atStart = MotionStub(status: .unavailable)
        let store = Self.store(atStart)
        await store.start()
        #expect(store.startFlow == .blocked(.deviceUnsupported))
        #expect(store.session == nil)
        #expect(atStart.requestCount == 0)

        let atDialog = MotionStub(status: .notDetermined, requestAnswer: .unavailable)
        let other = Self.store(atDialog)
        await other.start()
        await other.confirmMotionPermission()
        #expect(other.startFlow == .blocked(.deviceUnsupported))
        #expect(other.session == nil)
    }

    @Test("Sin decidir tras pedir (fallo transitorio): Inicio con alerta, y el siguiente toque reintenta")
    func unresolvedAfterRequest() async throws {
        let motion = MotionStub(status: .notDetermined, requestAnswer: .notDetermined)
        let store = Self.store(motion)

        await store.start()
        await store.confirmMotionPermission()

        #expect(store.startFlow == .idle)
        #expect(store.startFailure == .permissionUnresolved)
        #expect(store.session == nil)

        store.acknowledgeStartFailure()
        #expect(store.startFailure == nil)

        await store.start()
        #expect(store.startFlow == .explainingPermission)
        await store.confirmMotionPermission()
        #expect(motion.requestCount == 2)
    }

    @Test("\"Ahora no\" en la pre-pantalla: Inicio sin sesión ni petición")
    func declineReturnsHome() async {
        let motion = MotionStub(status: .notDetermined)
        let store = Self.store(motion)

        await store.start()
        store.declineMotionPermission()

        #expect(store.startFlow == .idle)
        #expect(store.session == nil)
        #expect(motion.requestCount == 0)
    }

    @Test("\"Volver al inicio\" en la pantalla bloqueante: Inicio sin sesión")
    func leaveBlocked() async {
        let store = Self.store(MotionStub(status: .denied))

        await store.start()
        store.leaveMotionBlocked()

        #expect(store.startFlow == .idle)
        #expect(store.session == nil)
    }

    @Test("Volver a primer plano con el permiso ya concedido cierra la bloqueante sin arrancar")
    func foregroundAfterGrantingInSettings() async {
        let motion = MotionStub(status: .denied)
        let store = Self.store(motion)
        await store.start()

        motion.setStatus(.denied)
        store.motionStatusMayHaveChanged()
        #expect(store.startFlow == .blocked(.permissionDenied), "sigue denegado: sigue bloqueada")

        motion.setStatus(.granted)
        store.motionStatusMayHaveChanged()

        #expect(store.startFlow == .idle)
        #expect(store.session == nil, "no arranca sola")
        #expect(motion.updateStarts.isEmpty)
    }

    @Test("Volver a primer plano desde la bloqueante relee el permiso y decide el flujo", arguments: [
        (PermissionStatus.denied, SessionStore.StartFlow.blocked(.permissionDenied)),
        (.restricted, .blocked(.permissionDenied)),
        (.unavailable, .blocked(.deviceUnsupported)),
        (.notDetermined, .idle),
        (.granted, .idle),
    ])
    func foregroundRereadsEachStatus(status: PermissionStatus, expected: SessionStore.StartFlow) async {
        let motion = MotionStub(status: .denied)
        let store = Self.store(motion)
        await store.start()
        #expect(store.startFlow == .blocked(.permissionDenied))

        motion.setStatus(status)
        store.motionStatusMayHaveChanged()

        #expect(store.startFlow == expected)
        #expect(store.session == nil)
        #expect(motion.updateStarts.isEmpty)
    }

    @Test("Volver a primer plano fuera de la bloqueante no toca el flujo")
    func foregroundOutsideBlockedIsIgnored() async {
        let motion = MotionStub(status: .notDetermined)
        let store = Self.store(motion)
        await store.start()

        store.motionStatusMayHaveChanged()

        #expect(store.startFlow == .explainingPermission)
    }

    @Test("Un segundo toque con el diálogo en pantalla no hace nada")
    func secondTapDuringRequestIsIgnored() async throws {
        let motion = MotionStub(status: .notDetermined, requestAnswer: nil)
        let store = Self.store(motion)
        await store.start()

        let request = Task { await store.confirmMotionPermission() }
        await waitUntil { motion.hasPendingRequest }
        #expect(store.startFlow == .requestingPermission)

        await store.start()
        await store.confirmMotionPermission()
        store.declineMotionPermission()
        #expect(store.startFlow == .requestingPermission)
        #expect(motion.requestCount == 1)

        motion.resolvePermissionRequest(with: .granted)
        await request.value

        #expect(store.startFlow == .idle)
        #expect(store.session != nil)
        #expect(motion.updateStarts.count == 1)
    }

    // MARK: - Conteo

    @Test("Muestras acumuladas 0 → 120 → 350: stepsMeasured 0 → 120 → 350")
    func cumulativeSamples() async throws {
        let motion = MotionStub(status: .granted)
        let store = Self.store(motion)
        await store.start()
        #expect(steps(store) == 0)

        motion.emit(steps: 0)
        motion.emit(steps: 120)
        await waitUntil { steps(store) == 120 }
        motion.emit(steps: 350)
        await waitUntil { steps(store) == 350 }

        #expect(steps(store) == 350)
        #expect(store.session?.stepsEstimated == 0)
    }

    @Test("Muestra menor 350 → 340: stepsMeasured sigue en 350")
    func smallerSampleDoesNotSubtract() async {
        let motion = MotionStub(status: .granted)
        let store = Self.store(motion)
        await store.start()

        motion.emit(steps: 350)
        motion.emit(steps: 340)
        motion.finishUpdates()
        await store.stepCounting?.value

        #expect(steps(store) == 350)
    }

    @Test("Tras una muestra menor, el incremento se mide contra el mayor: 350 → 340 → 360 = 360")
    func incrementAgainstHighest() async {
        let motion = MotionStub(status: .granted)
        let store = Self.store(motion)
        await store.start()

        motion.emit(steps: 350)
        motion.emit(steps: 340)
        motion.emit(steps: 360)
        motion.finishUpdates()
        await store.stepCounting?.value

        #expect(steps(store) == 360)
    }

    @Test("Volver de background: 350 antes, primera muestra 900 → 900, sin estimados")
    func backgroundStepsArriveInFirstSample() async {
        let motion = MotionStub(status: .granted)
        let store = Self.store(motion)
        await store.start()

        motion.emit(steps: 350)
        await waitUntil { steps(store) == 350 }
        // En background no llega ninguna muestra; al volver, la primera ya acumula todo.
        motion.emit(steps: 900)
        await waitUntil { steps(store) == 900 }

        #expect(steps(store) == 900)
        #expect(store.session?.stepsEstimated == 0)
    }

    @Test("Stream terminado por el sistema: la sesión sigue y conserva los pasos")
    func systemEndsStream() async throws {
        let motion = MotionStub(status: .granted)
        let store = Self.store(motion)
        await store.start()

        motion.emit(steps: 420)
        motion.finishUpdates()
        await store.stepCounting?.value

        #expect(!store.isCountingSteps)
        let session = try #require(store.session)
        #expect(session.status == .active)
        #expect(session.stepsMeasured == 420)
        #expect(store.hasSession)
        #expect(motion.cancelledStreams == 0, "lo terminó el sistema, no el store")
    }
}

/// Matriz de la 1.3 sobre `SessionStore`: las métricas se fijan al abrir la sesión y se
/// recalculan con cada muestra del coprocesador, en el instante del reloj.
@MainActor
@Suite("SessionStore · métricas en vivo")
struct SessionStoreMetricsTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private struct Fixture {
        let clock: ClockStub
        let motion: MotionStub
        let store: SessionStore

        init() {
            clock = ClockStub(now: SessionStoreMetricsTests.t0)
            motion = MotionStub(status: .granted)
            store = SessionStore(clock: clock, motion: motion, strideM: 0.655)
        }

        /// Emite las muestras, cierra el stream y espera a que el store las consuma todas.
        func emitAll(_ samples: [(steps: Int, distance: Double?)]) async {
            for sample in samples { motion.emit(steps: sample.steps, distance: sample.distance) }
            motion.finishUpdates()
            await store.stepCounting?.value
        }
    }

    @Test("Sin sesión no hay métricas")
    func noSessionNoMetrics() {
        #expect(Fixture().store.metrics == nil)
    }

    @Test("Sesión recién abierta: 0 m, ritmo nil y cadencia 0")
    func freshSession() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        let metrics = try #require(fixture.store.metrics)
        #expect(metrics == SessionMetrics(distanceM: 0, paceSecPerKm: nil, cadenceSpm: 0))
    }

    @Test("Sin distancia del sistema: 4980 pasos con zancada 0,655 → 3261,90 m")
    func distanceFromSteps() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, nil)])

        #expect(try #require(fixture.store.metrics).distanceM == 3261.9)
    }

    @Test("Con distancia del sistema: muestra de 4980 pasos y 3400 m → 3400 m")
    func distanceFromSystem() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, 3400)])

        #expect(try #require(fixture.store.metrics).distanceM == 3400)
        #expect(fixture.store.session?.stepsMeasured == 4980)
    }

    @Test("Distancia del sistema menor: 3400 → 3390 sigue en 3400")
    func systemDistanceNeverDecreases() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, 3400), (4990, 3390)])

        #expect(try #require(fixture.store.metrics).distanceM == 3400)
        #expect(fixture.store.session?.stepsMeasured == 4990)
    }

    @Test("Por debajo de 100 m: 10 pasos a los 60 s → ritmo nil")
    func noPaceBelowThreshold() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.clock.advance(by: 60)
        await fixture.emitAll([(10, nil)])

        let metrics = try #require(fixture.store.metrics)
        #expect(metrics.paceSecPerKm == nil)
        #expect(PaceFormat.text(metrics.paceSecPerKm) == "—")
    }

    @Test("A los 62 min: 4980 pasos sin distancia del sistema → 1140 s/km y 80,3 spm")
    func metricsAt62Minutes() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.clock.advance(by: 3720)
        await fixture.emitAll([(4980, nil)])

        let metrics = try #require(fixture.store.metrics)
        #expect(metrics.paceSecPerKm == 1140)
        #expect(metrics.cadenceSpm == 80.3)
    }

    @Test("Distancia del sistema inválida: no muta, y el conteo sigue", arguments: [-1, Double.nan, .infinity, -.infinity])
    func invalidSystemDistance(meters: Double) async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(100, 70), (4980, meters)])

        let session = try #require(fixture.store.session)
        #expect(session.systemDistanceM == 70)
        #expect(session.stepsMeasured == 4980, "la distancia rechazada no para el conteo")
        #expect(try #require(fixture.store.metrics).distanceM == 70)
    }

    @Test("Distancia del sistema inválida sin distancia previa: se usan los pasos")
    func invalidFirstSystemDistance() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, .nan)])

        #expect(fixture.store.session?.systemDistanceM == nil)
        #expect(try #require(fixture.store.metrics).distanceM == 3261.9)
    }

    @Test("Las métricas se recalculan con cada muestra, no con el paso del tiempo (AD-21)")
    func recalculatedOnSampleNotTick() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.clock.advance(by: 60)
        fixture.motion.emit(steps: 100)
        await waitUntil { fixture.store.session?.stepsMeasured == 100 }
        let afterSample = try #require(fixture.store.metrics)
        #expect(afterSample.cadenceSpm == 100)

        fixture.clock.advance(by: 60)
        #expect(fixture.store.metrics == afterSample, "sin muestra, las métricas no cambian")

        // Una muestra sin pasos nuevos también recalcula en el instante del reloj.
        fixture.motion.emit(steps: 100)
        await waitUntil { fixture.store.metrics?.cadenceSpm == 50 }
        #expect(fixture.store.metrics?.cadenceSpm == 50)
    }
}
