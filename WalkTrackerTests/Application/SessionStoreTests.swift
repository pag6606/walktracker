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
        SessionStore(clock: clock, motion: MotionStub(status: .granted), storage: StorageStub(), strideM: strideM, reconciliationTimeoutS: 0.05, orphanSessionThresholdS: 21_600)
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
        let store = SessionStore(clock: ClockStub(now: Self.t0), motion: motion, storage: StorageStub(), strideM: stride, reconciliationTimeoutS: 0.05, orphanSessionThresholdS: 21_600)

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
        let store = SessionStore(clock: clock, motion: motion, storage: StorageStub(), strideM: 0.655, reconciliationTimeoutS: 0.05, orphanSessionThresholdS: 21_600)
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
        SessionStore(clock: ClockStub(now: t0), motion: motion, storage: StorageStub(), strideM: 0.655, reconciliationTimeoutS: 0.05, orphanSessionThresholdS: 21_600)
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
            store = SessionStore(clock: clock, motion: motion, storage: StorageStub(), strideM: 0.655, reconciliationTimeoutS: 0.05, orphanSessionThresholdS: 21_600)
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

/// Matriz de la 1.4 sobre `SessionStore`: pausar, reanudar y finalizar con confirmación,
/// el stream del podómetro por tramos y el resumen hasta volver a Inicio.
@MainActor
@Suite("SessionStore · pausar, reanudar y finalizar")
struct SessionStoreLifecycleTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private struct Fixture {
        let clock: ClockStub
        let motion: MotionStub
        let store: SessionStore

        init() {
            clock = ClockStub(now: SessionStoreLifecycleTests.t0)
            motion = MotionStub(status: .granted)
            store = SessionStore(clock: clock, motion: motion, storage: StorageStub(), strideM: 0.655, reconciliationTimeoutS: 0.05, orphanSessionThresholdS: 21_600)
        }

        var steps: Int? { store.session?.stepsMeasured }

        /// Abre la sesión y deja `steps` pasos contados en el primer tramo.
        func startWalking(steps: Int, distance: Double? = nil) async {
            await store.start()
            motion.emit(steps: steps, distance: distance)
            await waitUntil { self.store.session?.stepsMeasured == steps }
        }

        /// Cierra la sesión pasando por la confirmación, como la UI.
        func finish() async {
            store.requestFinish()
            await store.confirmFinish()
        }
    }

    // MARK: - Pausar y reanudar

    @Test("Pausar: activa con 50 pasos, pausa a +300 s → paused y el tiempo se congela en 300 s")
    func pauseFreezesTime() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)

        fixture.clock.advance(by: 300)
        fixture.store.pause()

        let session = try #require(fixture.store.session)
        #expect(session.status == .paused)
        #expect(session.pausedAt == Self.t0.addingTimeInterval(300))
        #expect(fixture.store.metrics == session.metrics(at: Self.t0.addingTimeInterval(300)))
        #expect(fixture.store.metrics?.cadenceSpm == 10, "50 pasos en 300 s: las métricas se recalculan al pausar")
        #expect(fixture.store.elapsedS == 300)
        fixture.clock.advance(by: 90)
        #expect(fixture.store.elapsedS == 300)
        #expect(fixture.store.elapsedS(notBefore: Self.t0.addingTimeInterval(1000)) == 300)
    }

    @Test("Pausar cancela el stream del podómetro")
    func pauseCancelsStream() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)

        fixture.store.pause()

        #expect(!fixture.store.isCountingSteps)
        await waitUntil { fixture.motion.cancelledStreams == 1 }
        await fixture.store.stepCounting?.value
        #expect(!fixture.store.isCountingSteps)
        #expect(fixture.store.hasSession)
    }

    @Test("Reanudar: pausada desde +300 s, reanuda a +420 s → active, 120 s de pausas, 50 pasos y stream nuevo")
    func resumeOpensNewStream() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)
        fixture.clock.advance(by: 300)
        fixture.store.pause()

        fixture.clock.advance(by: 120)
        fixture.store.resume()

        let session = try #require(fixture.store.session)
        #expect(session.status == .active)
        #expect(session.totalPausesS == 120)
        #expect(session.pausedAt == nil)
        #expect(session.stepsMeasured == 50)
        #expect(fixture.motion.updateStarts == [Self.t0, Self.t0.addingTimeInterval(420)])
        #expect(fixture.store.isCountingSteps)
        #expect(fixture.store.elapsedS == 300)
        fixture.clock.advance(by: 60)
        #expect(fixture.store.elapsedS == 360, "el tiempo sigue desde donde se detuvo")
    }

    @Test("Pasos tras reanudar: 50 pasos y el tramo nuevo acumula 30 → 80")
    func stepsAfterResume() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)
        fixture.store.pause()
        fixture.store.resume()

        fixture.motion.emit(steps: 30)
        await waitUntil { fixture.steps == 80 }

        #expect(fixture.steps == 80)
    }

    @Test("Pasos durante la pausa: 200 pasos caminados en pausa no se suman al reanudar")
    func pausedStepsAreExcluded() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)
        fixture.store.pause()

        // El coprocesador sigue contando, pero el stream del tramo anterior ya está cancelado.
        fixture.motion.emit(steps: 250)
        fixture.clock.advance(by: 120)
        fixture.store.resume()
        // El stream nuevo acumula desde la reanudación: los 200 de la pausa no están.
        fixture.motion.emit(steps: 0)
        fixture.motion.emit(steps: 10)
        await waitUntil { fixture.steps == 60 }

        #expect(fixture.steps == 60)
    }

    @Test("Una muestra del tramo anterior que llega tarde no se aplica al tramo nuevo")
    func staleSampleIsIgnored() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)

        // Encolada en el stream del primer tramo, sin consumir todavía.
        fixture.motion.emit(steps: 400)
        fixture.store.pause()
        fixture.store.resume()
        fixture.motion.emit(steps: 30)
        await waitUntil { fixture.steps == 80 }
        fixture.motion.finishUpdates()
        await fixture.store.stepCounting?.value

        #expect(fixture.steps == 80)
    }

    @Test("Distancia entre tramos: 70 m antes de pausar y 20 m del tramo nuevo → 90 m")
    func distanceAddsAcrossStretches() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 100, distance: 70)
        fixture.store.pause()
        fixture.store.resume()

        fixture.motion.emit(steps: 30, distance: 20)
        await waitUntil { fixture.steps == 130 }

        #expect(fixture.store.session?.systemDistanceM == 90)
        #expect(try #require(fixture.store.metrics).distanceM == 90)
    }

    @Test("Transiciones inválidas en el store: pausar pausada y reanudar activa no hacen nada")
    func invalidTransitionsAreIgnored() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)

        fixture.clock.advance(by: 30)
        fixture.store.resume()
        #expect(fixture.store.session?.status == .active)
        #expect(fixture.motion.updateStarts.count == 1)

        fixture.store.pause()
        let paused = try #require(fixture.store.session)
        fixture.clock.advance(by: 30)
        fixture.store.pause()
        #expect(fixture.store.session == paused, "no reescribe la pausa en curso")
    }

    @Test("Segundo plano: el reloj avanza sin intención alguna y la sesión sigue activa")
    func backgroundNeverPauses() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)

        fixture.clock.advance(by: 5 * 60)

        #expect(fixture.store.session?.status == .active)
        #expect(fixture.store.isCountingSteps)
        #expect(fixture.store.elapsedS == 300)
    }

    // MARK: - Finalizar

    @Test("Cancelar el cierre: la sesión sigue en su estado, activa o en pausa")
    func cancelFinishKeepsSession() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)

        fixture.store.requestFinish()
        #expect(fixture.store.isConfirmingFinish)
        fixture.store.cancelFinish()

        #expect(!fixture.store.isConfirmingFinish)
        #expect(fixture.store.session?.status == .active)
        #expect(fixture.store.isCountingSteps)
        #expect(fixture.motion.cancelledStreams == 0)

        fixture.store.pause()
        let paused = try #require(fixture.store.session)
        fixture.store.requestFinish()
        fixture.store.cancelFinish()
        #expect(fixture.store.session == paused)
    }

    @Test("Sin sesión no se pide confirmación")
    func requestFinishWithoutSession() {
        let fixture = Fixture()
        fixture.store.requestFinish()
        #expect(!fixture.store.isConfirmingFinish)
    }

    @Test("Finalizar sin pausas: 4980 pasos, fin a +3720 s → 3720 s, 1140 s/km y 80,3 spm")
    func finishWithoutPauses() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4980)

        fixture.clock.advance(by: 3720)
        await fixture.finish()

        let session = try #require(fixture.store.session)
        #expect(session.status == .finished)
        #expect(session.endedAt == Self.t0.addingTimeInterval(3720))
        #expect(session.durationS == 3720)
        #expect(fixture.store.metrics == SessionMetrics(distanceM: 3261.9, paceSecPerKm: 1140, cadenceSpm: 80.3))
        #expect(!fixture.store.isConfirmingFinish)
        #expect(!fixture.store.isCountingSteps)
        #expect(fixture.store.hasSession, "el resumen se muestra dentro del mismo modo")
        await waitUntil { fixture.motion.cancelledStreams == 1 }
    }

    @Test("Finalizar desde pausa: pausa +600→+780, pausa abierta desde +3800 y fin a +3900 → 280 s y 3620 s")
    func finishFromPause() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4980)

        fixture.clock.set(Self.t0.addingTimeInterval(600))
        fixture.store.pause()
        fixture.clock.set(Self.t0.addingTimeInterval(780))
        fixture.store.resume()
        fixture.clock.set(Self.t0.addingTimeInterval(3800))
        fixture.store.pause()
        fixture.clock.set(Self.t0.addingTimeInterval(3900))
        await fixture.finish()

        let session = try #require(fixture.store.session)
        #expect(session.status == .finished)
        #expect(session.pausesS == 280)
        #expect(session.durationS == 3620)
        #expect(fixture.store.elapsedS == 3620)
    }

    @Test("Confirmar el cierre: las métricas finales quedan congeladas aunque siga caminando")
    func finishedMetricsAreFrozen() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4980)
        fixture.clock.advance(by: 3720)
        await fixture.finish()
        let finished = try #require(fixture.store.session)
        let metrics = try #require(fixture.store.metrics)

        fixture.clock.advance(by: 600)
        fixture.motion.emit(steps: 6000, distance: 4000)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(fixture.store.session == finished)
        #expect(fixture.store.metrics == metrics)
        #expect(fixture.store.elapsedS == 3720)
    }

    @Test("Confirmar dos veces o sobre una sesión finalizada no hace nada")
    func confirmOnFinishedIsIgnored() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 100)
        fixture.clock.advance(by: 600)
        await fixture.finish()
        let finished = try #require(fixture.store.session)

        fixture.clock.advance(by: 300)
        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        fixture.store.pause()
        fixture.store.resume()

        #expect(fixture.store.session == finished)
        #expect(!fixture.store.isConfirmingFinish)
        #expect(fixture.motion.updateStarts.count == 1)
    }

    @Test("Confirmar tras cerrarse el diálogo (cancelado por el sistema) igualmente finaliza")
    func confirmAfterDialogDismissal() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 100)

        fixture.store.requestFinish()
        fixture.store.cancelFinish()   // el diálogo se cierra antes de ejecutar la acción
        await fixture.store.confirmFinish()

        #expect(fixture.store.session?.status == .finished)
    }

    // MARK: - Resumen

    @Test("Salir del resumen: Inicio sin sesión, y la siguiente caminata empieza desde cero")
    func leaveSummaryStartsFresh() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 400, distance: 280)
        fixture.clock.advance(by: 600)
        await fixture.finish()

        fixture.store.leaveSummary()

        #expect(fixture.store.session == nil)
        #expect(fixture.store.metrics == nil)
        #expect(!fixture.store.hasSession)
        #expect(!fixture.store.isConfirmingFinish)
        #expect(fixture.store.elapsedS == 0)

        fixture.clock.advance(by: 60)
        await fixture.store.start()

        let session = try #require(fixture.store.session)
        #expect(session.startedAt == Self.t0.addingTimeInterval(660))
        #expect(session.stepsMeasured == 0)
        #expect(session.systemDistanceM == nil)
        #expect(fixture.store.metrics == SessionMetrics(distanceM: 0, paceSecPerKm: nil, cadenceSpm: 0))
        #expect(fixture.store.hasSession)
        #expect(fixture.motion.updateStarts.last == session.startedAt)

        fixture.motion.emit(steps: 10, distance: 7)
        await waitUntil { fixture.steps == 10 }
        #expect(fixture.store.session?.systemDistanceM == 7, "sin base de la sesión anterior")
    }

    @Test("Salir del resumen solo con la sesión finalizada")
    func leaveSummaryRequiresFinished() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)

        fixture.store.leaveSummary()
        #expect(fixture.store.session?.status == .active)

        fixture.store.pause()
        fixture.store.leaveSummary()
        #expect(fixture.store.session?.status == .paused)
        #expect(fixture.store.hasSession)
    }

    @Test("Con el resumen en pantalla, iniciar no abre otra sesión")
    func startDuringSummaryIsIgnored() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 50)
        await fixture.finish()
        let finished = try #require(fixture.store.session)

        await fixture.store.start()

        #expect(fixture.store.session == finished)
        #expect(fixture.motion.updateStarts.count == 1)
    }
}

/// Matriz de la 1.5 sobre `SessionStore`: reconciliación atómica del background por consulta
/// al sistema (AD-8), degradación al `GapEstimator` y descarte de los estimados. El timeout
/// de reconciliación es de test (0,05 s) y la consulta colgada es la del `MotionStub`.
@MainActor
@Suite("SessionStore · reconstrucción del background")
struct SessionStoreReconciliationTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let day: TimeInterval = 24 * 60 * 60

    @MainActor
    private struct Fixture {
        let clock: ClockStub
        let motion: MotionStub
        let store: SessionStore

        /// Timeout largo por defecto: una consulta inmediata nunca pierde contra el
        /// temporizador en una máquina cargada. Solo los tests del timeout lo acortan.
        init(timeoutS: TimeInterval = 5) {
            clock = ClockStub(now: SessionStoreReconciliationTests.t0)
            motion = MotionStub(status: .granted)
            store = SessionStore(clock: clock, motion: motion, storage: StorageStub(), strideM: 0.655, reconciliationTimeoutS: timeoutS, orphanSessionThresholdS: 21_600)
        }

        var session: Session? { store.session }

        /// Abre la sesión y deja `steps` pasos contados en el primer tramo.
        func startWalking(steps: Int, distance: Double? = nil) async {
            await store.start()
            motion.emit(steps: steps, distance: distance)
            await waitUntil { self.store.session?.stepsMeasured == steps }
        }

        /// 10 min activa a 80 spm (800 pasos) y 5 min en segundo plano: gap de 300 s.
        func walkTenMinutesThenBackgroundFive() async {
            await startWalking(steps: 800)
            clock.advance(by: 600)
            store.appDidEnterBackground()
            clock.advance(by: 300)
        }

        /// Lanza la reconciliación sin esperarla y espera a que la consulta colgada llegue
        /// al stub: `isReconciling` se activa antes de que la tarea registre la consulta.
        func becomeActiveInBackground() async -> Task<Void, Never> {
            let store = self.store
            let task = Task { await store.appDidBecomeActive() }
            await waitUntil { store.isReconciling && self.motion.hasPendingQuery }
            return task
        }
    }

    // MARK: - Consulta primero

    @Test("Gap con dato: tramo desde t0, 300 pasos vistos, 5 min en background y query → 820: medidos 820, estimados 0")
    func gapWithData() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 300)
        fixture.clock.advance(by: 60)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 820)
        #expect(session.stepsEstimated == 0)
        #expect(session.status == .active)
        #expect(fixture.motion.queriedRanges == [.init(start: Self.t0, end: Self.t0.addingTimeInterval(360))])
        #expect(fixture.store.metrics == session.metrics(at: fixture.clock.now))
        #expect(!fixture.store.isReconciling)

        // El stream entrega después el mismo acumulado: no se cuenta dos veces.
        fixture.motion.emit(steps: 820)
        fixture.motion.emit(steps: 830)
        await waitUntil { fixture.session?.stepsMeasured == 830 }
        #expect(fixture.session?.stepsMeasured == 830)
    }

    @Test("La distancia del sistema de la consulta entra sobre la base del tramo")
    func queryDistanceUsesStretchBase() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 100, distance: 70)
        fixture.store.pause()
        fixture.clock.advance(by: 60)
        fixture.store.resume()
        fixture.motion.emit(steps: 10, distance: 7)
        await waitUntil { fixture.session?.stepsMeasured == 110 }
        let resumedAt = fixture.clock.now

        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 400, distance: 280))
        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.first?.start == resumedAt, "se consulta el tramo en curso, no la sesión")
        #expect(fixture.session?.stepsMeasured == 500)
        #expect(fixture.session?.systemDistanceM == 350)
    }

    // MARK: - Degradación

    @Test("Query nil, vacía o con error: activa 10 min a 80 spm y gap de 300 s → ~400 estimados", arguments: [
        MotionStub.QueryResponse.none,
        .failure(.failed(operation: "pedometer")),
        .failure(.notAuthorized),
        .sample(steps: 0, distance: nil),
    ])
    func gapWithoutData(response: MotionStub.QueryResponse) async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(response)

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 800)
        #expect(session.stepsEstimated == 400)
        #expect(session.status == .active)
        #expect(fixture.store.metrics?.distanceM == 786, "(800 + 400) × 0,655")
        #expect(fixture.motion.queriedRanges.count == 1)
        #expect(!fixture.store.isReconciling)
    }

    @Test("Timeout: la consulta colgada degrada a ~400, libera los comandos y su resultado tardío se ignora")
    func timeoutDegrades() async throws {
        let fixture = Fixture(timeoutS: 0.05)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.hasPendingQuery, "la consulta sigue colgada")
        #expect(!fixture.store.isReconciling)
        #expect(fixture.session?.stepsEstimated == 400)
        fixture.store.pause()
        #expect(fixture.session?.status == .paused, "los comandos vuelven tras el timeout")

        fixture.motion.resolvePendingQueries(with: .sample(steps: 1200, distance: nil))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(fixture.session?.stepsMeasured == 800)
        #expect(fixture.session?.stepsEstimated == 400)
    }

    @Test("Sin muestra previa: activa 90 s y query nil → estimados 0")
    func noPriorSample() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 120)
        fixture.clock.advance(by: 90)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.count == 1)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.session?.stepsMeasured == 120)
    }

    @Test("Tramo de más de 7 días: no se consulta y se estima")
    func stretchOlderThanSevenDays() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.t0.addingTimeInterval(8 * Self.day))
        fixture.motion.setQueryResponse(.sample(steps: 99_999, distance: nil))

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.isEmpty)
        // 80 spm × (8 días − 600 s) / 60.
        #expect(fixture.session?.stepsEstimated == 920_800)
        #expect(fixture.session?.stepsMeasured == 800)
    }

    @Test("Tramo de justo 7 días: todavía se consulta")
    func stretchOfSevenDaysIsQueried() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.t0.addingTimeInterval(7 * Self.day))
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.count == 1)
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.session?.stepsEstimated == 0)
    }

    @Test("Query menor que lo visto: 300 pasos vistos y query → 120 se trata como sin dato")
    func queryBelowSeenIsNoData() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 300)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 120, distance: 50))

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 300)
        #expect(session.systemDistanceM == nil, "nada de la muestra incoherente se aplica")
        // 30 spm (300 pasos en 10 min) × 5 min.
        #expect(session.stepsEstimated == 150)
    }

    @Test("Una muestra del stream que llega durante la consulta no convierte la consulta en incoherente")
    func streamDuringReconciliation() async throws {
        let fixture = Fixture(timeoutS: 5)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        fixture.motion.emit(steps: 1210)
        await waitUntil { fixture.session?.stepsMeasured == 1210 }
        fixture.motion.resolvePendingQueries(with: .sample(steps: 1200, distance: nil))
        await reconciliation.value

        #expect(fixture.session?.stepsMeasured == 1210)
        #expect(fixture.session?.stepsEstimated == 0)
    }

    @Test("Timeout con el stream avanzando durante la consulta: su acumulado cubre el gap y no se estima")
    func streamDuringTimeoutDoesNotEstimate() async throws {
        let fixture = Fixture(timeoutS: 0.5)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        fixture.motion.emit(steps: 1210)
        await waitUntil { fixture.session?.stepsMeasured == 1210 }
        await reconciliation.value

        #expect(fixture.motion.hasPendingQuery, "venció el timeout, la consulta sigue colgada")
        #expect(fixture.session?.stepsMeasured == 1210)
        #expect(fixture.session?.stepsEstimated == 0)
        fixture.motion.resolvePendingQueries(with: .none)
    }

    // MARK: - Atómica

    @Test("Los diálogos de Finalizar y Descartar abiertos al empezar la reconciliación se cierran")
    func reconciliationClosesDialogs() async {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsEstimated == 400)

        fixture.store.requestFinish()
        fixture.store.requestDiscardEstimated()
        #expect(fixture.store.isConfirmingFinish)
        #expect(fixture.store.isConfirmingDiscard)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 60)
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        #expect(!fixture.store.isConfirmingFinish)
        #expect(!fixture.store.isConfirmingDiscard)
        fixture.motion.resolvePendingQueries(with: .none)
        await reconciliation.value
        // 800 medidos en 900 s son 53,3 spm × 60 s.
        #expect(fixture.session?.stepsEstimated == 400 + 53)
    }

    @Test("Comandos durante la reconciliación: pausar, finalizar, descartar y reanudar no hacen nada")
    func commandsAreRejectedWhileReconciling() async throws {
        let fixture = Fixture(timeoutS: 5)
        await fixture.walkTenMinutesThenBackgroundFive()
        // Estimados previos, para que haya algo que descartar.
        fixture.motion.setQueryResponse(.none)
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsEstimated == 400)

        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 60)
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()
        let before = try #require(fixture.session)

        fixture.store.pause()
        fixture.store.resume()
        fixture.store.requestFinish()
        #expect(!fixture.store.isConfirmingFinish)
        await fixture.store.confirmFinish()
        fixture.store.requestDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard)
        fixture.store.confirmDiscardEstimated()
        await fixture.store.appDidBecomeActive()   // volver otra vez no abre otra

        #expect(fixture.session == before)
        #expect(fixture.session?.status == .active, "SessionStatus no cambia al reconciliar")
        #expect(fixture.store.isReconciling)
        #expect(fixture.motion.queriedRanges.count == 2)
        #expect(fixture.motion.cancelledStreams == 0)

        fixture.motion.resolvePendingQueries(with: .sample(steps: 1300, distance: nil))
        await reconciliation.value
        #expect(!fixture.store.isReconciling)
        #expect(fixture.session?.stepsMeasured == 1300)

        fixture.store.pause()
        #expect(fixture.session?.status == .paused)
    }

    @Test("Salir otra vez a segundo plano mientras reconcilia conserva el gap pendiente")
    func backgroundWhileReconcilingKeepsGap() async {
        let fixture = Fixture(timeoutS: 5)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        fixture.clock.advance(by: 30)
        fixture.store.appDidEnterBackground()
        fixture.motion.resolvePendingQueries(with: .none)
        await reconciliation.value

        // Gap de 300 s desde el primer `.background`, no desde el segundo.
        #expect(fixture.session?.stepsEstimated == 400)
        // El gap ya se reconcilió: volver no consulta otra vez.
        await fixture.store.appDidBecomeActive()
        #expect(fixture.motion.queriedRanges.count == 1)
    }

    @Test("Volver sin haber pasado a segundo plano no consulta")
    func activeWithoutBackgroundDoesNothing() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(!fixture.store.isReconciling)
    }

    @Test("Pausada al volver: pausada en background no consulta ni estima")
    func pausedInBackground() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.pause()
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.session?.status == .paused)
        #expect(fixture.session?.stepsEstimated == 0)
    }

    @Test("Background con la sesión activa: sigue activa y el tiempo contó el gap")
    func backgroundNeverPauses() async {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.status == .active)
        #expect(fixture.store.elapsedS == 900)
        #expect(fixture.store.isCountingSteps)
    }

    // MARK: - Finalizar

    @Test("Finalizar desde activa: query → 830 hasta el instante del toque, cierra con 830 medidos")
    func finishReconciles() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.motion.setQueryResponse(.sample(steps: 830, distance: nil))

        fixture.store.requestFinish()
        await fixture.store.confirmFinish()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsMeasured == 830)
        #expect(session.stepsEstimated == 0)
        #expect(session.endedAt == Self.t0.addingTimeInterval(600))
        #expect(fixture.motion.queriedRanges == [.init(start: Self.t0, end: Self.t0.addingTimeInterval(600))])
        #expect(fixture.store.metrics == session.metrics(at: fixture.clock.now))
        #expect(!fixture.store.isCountingSteps)
    }

    @Test("Finalizar con la consulta lenta: reconcilia con los controles bloqueados y cierra en el instante del toque")
    func finishWaitsForSlowQuery() async throws {
        let fixture = Fixture(timeoutS: 5)
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.motion.setQueryResponse(.hang)

        let store = fixture.store
        let finishing = Task { await store.confirmFinish() }
        await waitUntil { store.isReconciling && fixture.motion.hasPendingQuery }
        fixture.clock.advance(by: 2)
        store.pause()
        #expect(fixture.session?.status == .active)

        fixture.motion.resolvePendingQueries(with: .sample(steps: 830, distance: nil))
        await finishing.value

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsMeasured == 830)
        #expect(session.durationS == 600)
        #expect(!store.isReconciling)
    }

    @Test("Finalizar sin dato: activa y query nil cierra sin estimar", arguments: [
        MotionStub.QueryResponse.none, .failure(.unavailable), .hang,
    ])
    func finishWithoutDataDoesNotEstimate(response: MotionStub.QueryResponse) async throws {
        let fixture = Fixture(timeoutS: 0.05)
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        // Un tramo que empieza con 600 s de sesión a 80 spm: un estimador que se colara aquí
        // tendría con qué estimar los 300 s siguientes.
        fixture.store.pause()
        fixture.store.resume()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(response)

        await fixture.store.confirmFinish()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsMeasured == 800)
        #expect(session.stepsEstimated == 0)
        fixture.motion.resolvePendingQueries(with: .none)
    }

    @Test("Finalizar desde pausa no consulta: el tramo ya se cerró al pausar")
    func finishFromPauseDoesNotQuery() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.pause()
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))

        await fixture.store.confirmFinish()

        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.session?.status == .finished)
        #expect(fixture.session?.stepsMeasured == 800)
    }

    @Test("El resumen conserva los estimados de la sesión")
    func finishKeepsEstimated() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()

        await fixture.store.confirmFinish()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsEstimated == 400)
        #expect(fixture.store.metrics?.distanceM == 786)
    }

    // MARK: - Descartar

    @Test("Descartar: 400 estimados y confirmar → estimados 0; distancia y ritmo recalculados")
    func discardEstimated() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        let withEstimated = try #require(fixture.store.metrics)
        #expect(withEstimated.distanceM == 786)

        fixture.store.requestDiscardEstimated()
        #expect(fixture.store.isConfirmingDiscard)
        fixture.store.confirmDiscardEstimated()

        let session = try #require(fixture.session)
        let metrics = try #require(fixture.store.metrics)
        #expect(!fixture.store.isConfirmingDiscard)
        #expect(session.stepsEstimated == 0)
        #expect(session.stepsMeasured == 800)
        #expect(metrics.distanceM == 524)
        #expect(metrics.paceSecPerKm == 1718, "900 s / 0,524 km")
        #expect(withEstimated.paceSecPerKm == 1145, "900 s / 0,786 km")
    }

    @Test("Distancia del sistema más estimados: 800 medidos con 500 m del sistema y 400 estimados → 762 m; al descartar, 500 m")
    func systemDistancePlusEstimated() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800, distance: 500)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.none)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.systemDistanceM == 500)
        #expect(fixture.session?.stepsEstimated == 400)
        #expect(fixture.store.metrics?.distanceM == 762, "500 + 400 × 0,655")

        fixture.store.requestDiscardEstimated()
        fixture.store.confirmDiscardEstimated()

        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.store.metrics?.distanceM == 500)
    }

    @Test("Cancelar el descarte deja los estimados; sin estimados no se pide confirmación")
    func cancelDiscard() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.store.requestDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard, "sin estimados no hay nada que descartar")

        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        await fixture.store.appDidBecomeActive()

        fixture.store.requestDiscardEstimated()
        fixture.store.cancelDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard)
        #expect(fixture.session?.stepsEstimated == 400)
    }

    @Test("Descartar en pausa se permite")
    func discardWhilePaused() async {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        fixture.store.pause()

        fixture.store.requestDiscardEstimated()
        fixture.store.confirmDiscardEstimated()

        #expect(fixture.session?.status == .paused)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.store.metrics?.distanceM == 524)
    }

    @Test("Mutar finalizada: descartar sobre una sesión finalizada no muta")
    func discardOnFinishedIsIgnored() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        await fixture.store.confirmFinish()
        let finished = try #require(fixture.session)

        fixture.store.requestDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard)
        fixture.store.confirmDiscardEstimated()
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        await fixture.store.appDidBecomeActive()

        #expect(fixture.session == finished)
        #expect(fixture.session?.stepsEstimated == 400)
        #expect(fixture.motion.queriedRanges.count == 2, "la del gap y la de finalizar; ninguna tras cerrar")
    }
}

/// Matriz de la 1.6 sobre `SessionStore`: el snapshot en un `StorageStub`, el reloj en un
/// `ClockStub` y el coprocesador en un `MotionStub`. "Relanzar" es construir otro store
/// sobre el mismo almacenamiento y llamar a `restoreOnLaunch()`.
@MainActor
@Suite("SessionStore · recuperación al relanzar")
struct SessionStoreRecoveryTests {

    /// El instante del relanzamiento.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private nonisolated static let orphanThresholdS: TimeInterval = 6 * 60 * 60

    @MainActor
    private struct Fixture {
        let clock: ClockStub
        let motion: MotionStub
        let storage: StorageStub
        let store: SessionStore

        /// Timeout largo por defecto, como en la reconciliación: una consulta inmediata nunca
        /// pierde contra el temporizador.
        init(snapshot: ActiveSessionSnapshot? = nil, storage: StorageStub? = nil, at instant: Date = SessionStoreRecoveryTests.now) {
            clock = ClockStub(now: instant)
            motion = MotionStub(status: .granted)
            self.storage = storage ?? StorageStub(snapshot: snapshot)
            store = SessionStore(
                clock: clock,
                motion: motion,
                storage: self.storage,
                strideM: 0.655,
                reconciliationTimeoutS: 5,
                orphanSessionThresholdS: SessionStoreRecoveryTests.orphanThresholdS
            )
        }

        var session: Session? { store.session }
    }

    /// Snapshot relativo a `now`. Por defecto: activa desde hace 20 min, 1500 pasos, 60 s de
    /// pausas, guardada ahora mismo y con un solo tramo desde el inicio.
    private nonisolated static func snapshot(
        startedAgoS: TimeInterval = 20 * 60,
        stepsMeasured: Int = 1500,
        stepsEstimated: Int = 0,
        totalPausesS: TimeInterval = 60,
        pausedAgoS: TimeInterval? = nil,
        forcePaused: Bool? = nil,
        strideM: Double = 0.655,
        systemDistanceM: Double? = nil,
        savedAgoS: TimeInterval = 0,
        lastSampleAt: Date? = nil,
        segmentStart: Date? = nil,
        segmentSteps: Int? = nil,
        distanceBaseM: Double = 0
    ) -> ActiveSessionSnapshot {
        let startedAt = now.addingTimeInterval(-startedAgoS)
        return ActiveSessionSnapshot(
            startedAt: startedAt,
            stepsMeasured: stepsMeasured,
            stepsEstimated: stepsEstimated,
            totalPausesS: totalPausesS,
            paused: forcePaused ?? (pausedAgoS != nil),
            pausedAt: pausedAgoS.map { now.addingTimeInterval(-$0) },
            strideM: strideM,
            systemDistanceM: systemDistanceM,
            savedAt: now.addingTimeInterval(-savedAgoS),
            lastSampleAt: lastSampleAt,
            segmentStart: segmentStart ?? startedAt,
            segmentSteps: segmentSteps ?? stepsMeasured,
            distanceBaseM: distanceBaseM
        )
    }

    // MARK: - Relanzar

    @Test("Relanzar activa: 20 min, 1500 pasos y 60 s de pausas → activa, 1140 s, 1500 + la consulta y \"Sesión recuperada\"")
    func relaunchActive() async throws {
        let snapshot = Self.snapshot()
        let fixture = Fixture(snapshot: snapshot)
        fixture.motion.setQueryResponse(.sample(steps: 1700, distance: nil))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .active)
        #expect(session.startedAt == snapshot.startedAt)
        #expect(fixture.store.elapsedS == 1140)
        #expect(session.stepsMeasured == 1700)
        #expect(session.stepsEstimated == 0)
        #expect(fixture.store.metrics == session.metrics(at: Self.now))
        #expect(fixture.store.hasSession)
        #expect(fixture.store.showsRecoveredNotice)
        #expect(!fixture.store.isReconciling)
        #expect(fixture.motion.queriedRanges == [.init(start: snapshot.startedAt, end: Self.now)])
        #expect(fixture.motion.updateStarts == [snapshot.startedAt], "el tramo se reabre desde su inicio")
        #expect(fixture.store.isCountingSteps)

        // El snapshot queda al día con lo reconciliado.
        let saved = try #require(fixture.storage.snapshot)
        #expect(saved.stepsMeasured == 1700)
        #expect(saved.segmentSteps == 1700)
        #expect(saved.savedAt == Self.now)
    }

    @Test("El tramo reabierto conserva el máximo visto: sus acumulados solo suman lo nuevo")
    func restoredSegmentKeepsHighest() async throws {
        let resumedAt = Self.now.addingTimeInterval(-10 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            systemDistanceM: 1000, segmentStart: resumedAt, segmentSteps: 900, distanceBaseM: 400
        ))
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: 600))

        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.stepsMeasured == 1500)
        #expect(fixture.motion.updateStarts == [resumedAt])

        fixture.motion.emit(steps: 900, distance: 600)
        fixture.motion.emit(steps: 950, distance: 630)
        await waitUntil { fixture.session?.stepsMeasured == 1550 }
        #expect(fixture.session?.stepsMeasured == 1550)
        #expect(fixture.session?.systemDistanceM == 1030, "base del tramo 400 + 630")
    }

    @Test("Relanzar sin dato: consulta nil y gap de 300 s desde el último guardado a 80 spm → ~400")
    func relaunchWithoutData() async throws {
        // 20 min desde el inicio con 60 s de pausas; guardado hace 300 s con 840 s netos: 1120 pasos son 80 spm.
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 1120, savedAgoS: 300))
        fixture.motion.setQueryResponse(.none)

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 1120)
        #expect(session.stepsEstimated == 400)
        #expect(abs((fixture.store.metrics?.distanceM ?? 0) - (1120 + 400) * 0.655) < 0.01)
        #expect(fixture.store.hasSession)
        #expect(fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.snapshot?.stepsEstimated == 400, "lo estimado queda guardado")
    }

    @Test("Restaurar v3: {2450, 320, 60000 ms, activa, 0,655} → pasos, zancada y estado; distancia (2450 + 320) × 0,655")
    func restoreV3Snapshot() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 2450, stepsEstimated: 320))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 2450)
        #expect(session.stepsEstimated == 320)
        #expect(session.strideM == 0.655)
        #expect(session.status == .active)
        #expect(abs((fixture.store.metrics?.distanceM ?? 0) - (2450 + 320) * 0.655) < 0.01)
    }

    @Test("Relanzar pausada: pausada, sin consulta ni stream, con el tiempo congelado en pausedAt")
    func relaunchPaused() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 800, pausedAgoS: 5 * 60, savedAgoS: 5 * 60))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .paused)
        #expect(fixture.store.elapsedS == 840, "15 min hasta la pausa − 60 s de pausas cerradas")
        fixture.clock.advance(by: 600)
        #expect(fixture.store.elapsedS == 840)
        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.motion.updateStarts.isEmpty)
        #expect(session.stepsEstimated == 0)
        #expect(fixture.store.hasSession)
        #expect(fixture.store.showsRecoveredNotice)

        // Reanudar abre un tramo nuevo desde cero.
        fixture.store.resume()
        #expect(fixture.motion.updateStarts == [fixture.clock.now])
        fixture.motion.emit(steps: 10)
        await waitUntil { fixture.session?.stepsMeasured == 810 }
        #expect(fixture.session?.stepsMeasured == 810)
    }

    @Test("Mientras reconcilia al arrancar no se presenta: la sesión aparece ya consolidada")
    func presentsOnlyAfterReconciling() async throws {
        let fixture = Fixture(snapshot: Self.snapshot())
        fixture.motion.setQueryResponse(.hang)
        let store = fixture.store

        let restoring = Task { await store.restoreOnLaunch() }
        await waitUntil { store.isReconciling && fixture.motion.hasPendingQuery }
        #expect(!store.hasSession)
        #expect(!store.showsRecoveredNotice)
        store.pause()
        #expect(store.session?.status == .active, "los comandos siguen rechazados")

        fixture.motion.resolvePendingQueries(with: .sample(steps: 1600, distance: nil))
        await restoring.value

        #expect(store.hasSession)
        #expect(store.session?.stepsMeasured == 1600)
    }

    // MARK: - Sesión huérfana (AD-18)

    @Test("Huérfana: startedAt por encima del umbral y último dato a +40 min → finished en +40 min, recovered, sin consulta")
    func orphanIsClosed() async throws {
        let snapshot = Self.snapshot(startedAgoS: 7 * 60 * 60, stepsMeasured: 4000, totalPausesS: 0, savedAgoS: 6 * 60 * 60)
        let lastSampleAt = snapshot.startedAt.addingTimeInterval(40 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 7 * 60 * 60, stepsMeasured: 4000, totalPausesS: 0, savedAgoS: 6 * 60 * 60, lastSampleAt: lastSampleAt
        ))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.recovered)
        #expect(session.endedAt == lastSampleAt)
        #expect(session.durationS == 2400)
        #expect(session.stepsMeasured == 4000)
        #expect(session.stepsEstimated == 0)
        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.motion.updateStarts.isEmpty)
        #expect(fixture.store.hasSession, "su resumen se muestra una vez")
        #expect(!fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.snapshot == nil)
        #expect(fixture.storage.clearCount == 1)

        fixture.store.leaveSummary()
        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
    }

    @Test("Huérfana cerrada al arrancar: 4000 pasos en 2400 s → el store publica 2620 m, 916 s/km y 100 spm para el resumen")
    func orphanPublishesMetrics() async throws {
        let base = Self.snapshot(startedAgoS: 7 * 60 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 7 * 60 * 60, stepsMeasured: 4000, totalPausesS: 0, savedAgoS: 6 * 60 * 60,
            lastSampleAt: base.startedAt.addingTimeInterval(40 * 60)
        ))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.durationS == 2400)
        let metrics = try #require(fixture.store.metrics, "sin métricas el resumen quedaría en blanco")
        #expect(metrics.distanceM == 2620, "4000 × 0,655")
        #expect(metrics.paceSecPerKm == 916, "2400 s / 2,62 km")
        #expect(metrics.cadenceSpm == 100, "4000 pasos en 40 min")
        #expect(metrics == session.metrics(at: try #require(session.endedAt)))
    }

    @Test("Huérfana sin ninguna muestra: se cierra en startedAt con 0 s")
    func orphanWithoutSamples() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(startedAgoS: 8 * 60 * 60, stepsMeasured: 0, totalPausesS: 0))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.recovered)
        #expect(session.endedAt == session.startedAt)
        #expect(session.durationS == 0)
    }

    @Test("Huérfana pausada: se cierra en el último dato y la pausa abierta cuenta 0")
    func orphanPaused() async throws {
        let base = Self.snapshot(startedAgoS: 10 * 60 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 10 * 60 * 60, stepsMeasured: 3000, totalPausesS: 120,
            pausedAgoS: 10 * 60 * 60 - 35 * 60, lastSampleAt: base.startedAt.addingTimeInterval(30 * 60)
        ))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session?.durationS == 1680)
        #expect(fixture.session?.recovered == true)
    }

    @Test("Huérfana con una pausa cerrada tras el último dato: se recorta en la última reanudación y la pausa no se come tiempo andado")
    func orphanWithPauseAfterLastData() async throws {
        // Camina 0–40 min (último dato a +40), pausa 50–60, reanuda a +60 y la app muere.
        let base = Self.snapshot(startedAgoS: 7 * 60 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 7 * 60 * 60, stepsMeasured: 3000, totalPausesS: 600,
            lastSampleAt: base.startedAt.addingTimeInterval(40 * 60),
            segmentStart: base.startedAt.addingTimeInterval(60 * 60), segmentSteps: 0
        ))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.recovered)
        #expect(session.endedAt == base.startedAt.addingTimeInterval(60 * 60))
        #expect(session.durationS == 3000, "60 min hasta la reanudación − 10 min de pausa")
        #expect(session.pausesS == 600)
    }

    @Test("Justo en el umbral no es huérfana: se restaura")
    func atThresholdRestores() async {
        let fixture = Fixture(snapshot: Self.snapshot(startedAgoS: Self.orphanThresholdS))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session?.status == .active)
        #expect(fixture.session?.recovered == false)
    }

    // MARK: - Sin snapshot, ilegible o inválido

    @Test("Sin snapshot: Inicio normal, nada que restaurar")
    func noSnapshot() async {
        let fixture = Fixture()

        await fixture.store.restoreOnLaunch()

        #expect(fixture.storage.loadCount == 1)
        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(!fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.saved.isEmpty)
    }

    @Test("Snapshot ilegible: se aparta, Inicio normal y se puede iniciar", arguments: [
        StorageError.malformed("JSON roto"), .unsupportedSchemaVersion(2),
    ])
    func unreadableSnapshot(error: StorageError) async {
        let snapshot = Self.snapshot()
        let fixture = Fixture(snapshot: snapshot)
        fixture.storage.failLoad(with: error)

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(fixture.storage.snapshot == nil)
        #expect(fixture.storage.setAside == [snapshot], "apartado, no destruido")
        #expect(fixture.storage.clearCount == 0)
        #expect(fixture.motion.queriedRanges.isEmpty)

        fixture.storage.failLoad(with: nil)
        await fixture.store.start()
        #expect(fixture.session?.status == .active)
    }

    @Test("Lectura fallida (failed): Inicio normal y el snapshot sigue en su sitio, sin apartar")
    func failedReadKeepsSnapshot() async {
        let snapshot = Self.snapshot()
        let fixture = Fixture(snapshot: snapshot)
        fixture.storage.failLoad(with: .failed(operation: "read"))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(fixture.storage.loadCount == 1)
        #expect(throws: StorageError.failed(operation: "read")) { try fixture.storage.loadActiveSession() }
        #expect(fixture.storage.snapshot == snapshot, "no se pudo leer: no se aparta")
        #expect(fixture.storage.setAside.isEmpty)
        #expect(fixture.storage.clearCount == 0)
    }

    @Test("Snapshot inválido: rechazado en la frontera, apartado sin borrar e Inicio normal", arguments: [
        SessionStoreRecoveryTests.snapshot(strideM: 0),
        SessionStoreRecoveryTests.snapshot(strideM: -1),
        SessionStoreRecoveryTests.snapshot(stepsMeasured: -1),
        SessionStoreRecoveryTests.snapshot(totalPausesS: -1),
        SessionStoreRecoveryTests.snapshot(forcePaused: true),
        SessionStoreRecoveryTests.snapshot(segmentSteps: -1),
        SessionStoreRecoveryTests.snapshot(distanceBaseM: -1),
    ])
    func invalidSnapshot(snapshot: ActiveSessionSnapshot) async {
        let fixture = Fixture(snapshot: snapshot)

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(fixture.storage.setAside == [snapshot])
        #expect(fixture.storage.clearCount == 0)
        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.motion.updateStarts.isEmpty)
    }

    @Test("Solo restaura una vez, y nunca sobre una sesión ya abierta")
    func restoresOnce() async {
        let fixture = Fixture(snapshot: Self.snapshot())
        await fixture.store.restoreOnLaunch()
        await fixture.store.restoreOnLaunch()
        #expect(fixture.storage.loadCount == 1)

        let other = Fixture(snapshot: Self.snapshot(stepsMeasured: 99))
        await other.store.start()
        await other.store.restoreOnLaunch()
        #expect(other.session?.stepsMeasured == 0)
        #expect(other.storage.loadCount == 0)
    }

    // MARK: - Guardar y borrar

    @Test("Autosave: activa con muestras cada 2,5 s durante 25 s → el de iniciar + 2 por muestras (≥ 10 s), no 10")
    func autosaveBySamples() async {
        let fixture = Fixture()
        await fixture.store.start()
        #expect(fixture.storage.saved.count == 1, "al iniciar")

        for index in 1...10 {
            fixture.clock.advance(by: 2.5)
            fixture.motion.emit(steps: index * 4, end: fixture.clock.now)
            await waitUntil { fixture.session?.stepsMeasured == index * 4 }
        }

        #expect(fixture.storage.saved.count == 3)
        #expect(fixture.storage.saved.map(\.savedAt) == [0, 10, 20].map { Self.now.addingTimeInterval($0) })
        #expect(fixture.storage.saved.last?.stepsMeasured == 32, "la muestra de los 20 s")
    }

    @Test("Quieto no hay escrituras: sin muestras el reloj no guarda")
    func noSamplesNoWrites() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.clock.advance(by: 600)
        #expect(fixture.storage.saved.count == 1)
    }

    @Test("Se guarda al iniciar, pausar, reanudar y pasar a background; al finalizar se borra y relanzar no restaura")
    func saveMomentsAndClearOnFinish() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        #expect(fixture.storage.saved.count == 1)

        fixture.clock.advance(by: 5)
        fixture.store.pause()
        #expect(fixture.storage.saved.count == 2)
        #expect(fixture.storage.snapshot?.paused == true)
        #expect(fixture.storage.snapshot?.pausedAt == fixture.clock.now)

        fixture.clock.advance(by: 5)
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.saved.count == 3, "también en pausa")

        fixture.store.resume()
        #expect(fixture.storage.saved.count == 4)
        #expect(fixture.storage.snapshot?.paused == false)
        #expect(fixture.storage.snapshot?.segmentStart == fixture.clock.now)
        #expect(fixture.storage.snapshot?.totalPausesS == 5)

        fixture.clock.advance(by: 5)
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.saved.count == 5)
        #expect(fixture.storage.snapshot?.savedAt == fixture.clock.now)

        await fixture.store.appDidBecomeActive()
        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        #expect(fixture.storage.snapshot == nil)
        #expect(fixture.storage.clearCount == 1)

        let relaunched = Fixture(storage: fixture.storage, at: fixture.clock.now)
        await relaunched.store.restoreOnLaunch()
        #expect(relaunched.session == nil)
        #expect(!relaunched.store.hasSession)
    }

    @Test("La consulta de la reconciliación no mueve lastSampleAt: el snapshot conserva el último paso real")
    func queryDoesNotMoveLastSampleAt() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: Self.now.addingTimeInterval(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.advance(by: 60)
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.now.addingTimeInterval(5 * 60 * 60))
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.stepsMeasured == 820)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.now.addingTimeInterval(60))
    }

    // MARK: - Tope de lastSampleAt tras un gap (R4)

    /// `Self.now` + `seconds`.
    private static func at(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }

    /// Inicia en `now`, recibe 300 pasos con `end` +60 s y pasa a background a los +600 s: el
    /// tope queda pendiente en +600 s y el snapshot, con `lastSampleAt` +60 s.
    private static func walkThenBackground(_ fixture: Fixture) async {
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: at(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.set(at(600))
        fixture.store.appDidEnterBackground()
    }

    /// Emite una muestra del stream con el reloj en `end` y espera a su autosave, que deja ver
    /// `lastSampleAt` en el snapshot. El llamante garantiza ≥ 10 s desde el último guardado.
    private static func emitAndAutosave(_ fixture: Fixture, steps: Int, end: Date) async {
        let saves = fixture.storage.saved.count
        fixture.clock.set(end)
        fixture.motion.emit(steps: steps, end: end)
        await waitUntil { fixture.storage.saved.count == saves + 1 }
    }

    @Test("R4 · la muestra de puesta al día llega antes de la vuelta: lastSampleAt se queda en el inicio del gap y la siguiente lo mueve")
    func catchUpBeforeReturnIsCapped() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)

        // La puesta al día del stream (900, `end` = +5 h) se procesa antes que la vuelta.
        let back = Self.at(5 * 60 * 60)
        await Self.emitAndAutosave(fixture, steps: 900, end: back)
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600), "topado en el inicio del gap")

        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))

        let next = back.addingTimeInterval(30)
        await Self.emitAndAutosave(fixture, steps: 930, end: next)
        #expect(fixture.storage.snapshot?.lastSampleAt == next, "el tope ya se liberó")
    }

    @Test("R4 · la consulta ya cubrió el gap: la puesta al día sin pasos nuevos libera el tope sin mover lastSampleAt; la siguiente lo mueve")
    func catchUpWithoutStepsReleasesCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsMeasured == 900)

        await Self.emitAndAutosave(fixture, steps: 900, end: back.addingTimeInterval(10))
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(60), "no sumó pasos: no lo mueve")

        let next = back.addingTimeInterval(30)
        await Self.emitAndAutosave(fixture, steps: 930, end: next)
        #expect(fixture.session?.stepsMeasured == 930)
        #expect(fixture.storage.snapshot?.lastSampleAt == next, "sin recortar al inicio del gap")
    }

    @Test("R4 · la consulta no libera el tope: con la consulta por debajo del stream, la puesta al día que suma pasos sigue topada")
    func queryDoesNotReleaseCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsMeasured == 820)

        await Self.emitAndAutosave(fixture, steps: 900, end: back.addingTimeInterval(10))
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))
    }

    @Test("R4 · una muestra del stream durante la consulta colgada no lleva lastSampleAt más allá del inicio del gap")
    func sampleDuringQueryIsCapped() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.hang)
        let returning = Task { await fixture.store.appDidBecomeActive() }
        await waitUntil { fixture.motion.hasPendingQuery }

        fixture.motion.emit(steps: 900, end: back)
        await waitUntil { fixture.session?.stepsMeasured == 900 }
        fixture.motion.resolvePendingQueries(with: .sample(steps: 900, distance: nil))
        await returning.value

        #expect(fixture.storage.snapshot?.savedAt == back, "guardado tras reconciliar")
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))
    }

    @Test("R4 · una muestra previa al gap procesada tras ir a background (end +590 s) no libera el tope: la puesta al día sigue topada en +600 s")
    func sampleBeforeGapDoesNotReleaseCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)

        // Encolada antes de la salida a background y consumida después.
        fixture.clock.set(Self.at(700))
        fixture.motion.emit(steps: 350, end: Self.at(590))
        await waitUntil { fixture.session?.stepsMeasured == 350 }

        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))
        await fixture.store.appDidBecomeActive()
        await Self.emitAndAutosave(fixture, steps: 900, end: back.addingTimeInterval(10))

        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))
    }

    @Test("R4 · pausada no fija tope: background y vuelta en pausa, reanudar, y la primera muestra mueve lastSampleAt a su end real")
    func pausedBackgroundDoesNotCap() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: Self.at(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.set(Self.at(100))
        fixture.store.pause()
        fixture.clock.set(Self.at(600))
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.at(5 * 60 * 60))
        await fixture.store.appDidBecomeActive()

        fixture.clock.set(Self.at(5 * 60 * 60 + 60))
        fixture.store.resume()
        let end = Self.at(5 * 60 * 60 + 90)
        await Self.emitAndAutosave(fixture, steps: 50, end: end)

        #expect(fixture.session?.stepsMeasured == 350)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · restaurar una pausada no fija tope: al reanudar, la primera muestra mueve lastSampleAt a su end real")
    func restoredPausedDoesNotCap() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(
            pausedAgoS: 5 * 60, savedAgoS: 5 * 60, lastSampleAt: Self.at(-6 * 60)
        ))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.status == .paused)

        fixture.clock.set(Self.at(60))
        fixture.store.resume()
        let end = Self.at(90)
        await Self.emitAndAutosave(fixture, steps: 50, end: end)

        #expect(fixture.session?.stepsMeasured == 1550)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · nunca retrocede: un último dato posterior al inicio del gap (+700 s frente a +600 s) se conserva tras la vuelta")
    func capNeverMovesLastSampleAtBack() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: Self.at(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        // Una muestra real con `end` +700 s se procesa justo antes de que llegue la salida a
        // background, fechada con el reloj en +600 s.
        fixture.clock.set(Self.at(600))
        fixture.motion.emit(steps: 400, end: Self.at(700))
        await waitUntil { fixture.session?.stepsMeasured == 400 }
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(700))

        let back = Self.at(5 * 60 * 60)
        await Self.emitAndAutosave(fixture, steps: 900, end: back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(700), "el tope (+600 s) no lo hace retroceder")
    }

    @Test("R4 · dos gaps sin muestra entre medias: se conserva el tope más temprano")
    func twoGapsKeepEarliestCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        fixture.clock.set(Self.at(60 * 60))
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        // Vuelve a salir sin que el stream haya entregado nada desde la primera salida.
        fixture.clock.set(Self.at(2 * 60 * 60))
        fixture.store.appDidEnterBackground()
        await Self.emitAndAutosave(fixture, steps: 1000, end: Self.at(3 * 60 * 60))

        #expect(fixture.session?.stepsMeasured == 1000)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600), "el tope de la primera salida, no el de la segunda")
    }

    @Test("R4 · pausar libera el tope pendiente: tras reanudar, la muestra mueve lastSampleAt a su end real")
    func pauseReleasesCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        fixture.clock.set(back.addingTimeInterval(60))
        fixture.store.pause()
        fixture.clock.set(back.addingTimeInterval(120))
        fixture.store.resume()
        let end = back.addingTimeInterval(150)
        await Self.emitAndAutosave(fixture, steps: 50, end: end)

        #expect(fixture.session?.stepsMeasured == 950)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · finalizar libera el tope pendiente: la sesión siguiente del mismo store mueve lastSampleAt con su end real")
    func finishReleasesCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        fixture.clock.set(back.addingTimeInterval(60))
        await fixture.store.start()
        let end = back.addingTimeInterval(90)
        await Self.emitAndAutosave(fixture, steps: 40, end: end)

        #expect(fixture.session?.stepsMeasured == 40)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · restaurar: la primera muestra del stream no lleva lastSampleAt más allá de savedAt (+20 min); la siguiente lo mueve")
    func firstStreamSampleAfterRestoreIsCapped() async throws {
        // Empezó hace 30 min, guardada a los +20 min con el último paso a los +19 min.
        let base = Self.snapshot(startedAgoS: 30 * 60)
        let savedAt = base.startedAt.addingTimeInterval(20 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 30 * 60, savedAgoS: 10 * 60, lastSampleAt: base.startedAt.addingTimeInterval(19 * 60)
        ))
        fixture.motion.setQueryResponse(.sample(steps: 1500, distance: nil))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.status == .active)
        #expect(fixture.storage.snapshot?.lastSampleAt == base.startedAt.addingTimeInterval(19 * 60))

        await Self.emitAndAutosave(fixture, steps: 1600, end: Self.at(10))
        #expect(fixture.session?.stepsMeasured == 1600)
        #expect(fixture.storage.snapshot?.lastSampleAt == savedAt)

        await Self.emitAndAutosave(fixture, steps: 1650, end: Self.at(40))
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(40))
    }

    @Test("Pausar, reanudar y relanzar: el snapshot guarda el tramo que escribe el store y el stream reabierto solo suma lo nuevo")
    func pausedAndResumedSegmentSurvivesRelaunch() async throws {
        let first = Fixture()
        await first.store.start()
        first.motion.emit(steps: 1000, distance: 700)
        await waitUntil { first.session?.stepsMeasured == 1000 }
        first.clock.advance(by: 600)
        first.store.pause()
        first.clock.advance(by: 60)
        first.store.resume()
        let resumedAt = first.clock.now
        first.motion.emit(steps: 200, distance: 140)
        await waitUntil { first.session?.stepsMeasured == 1200 }
        first.clock.advance(by: 30)
        first.store.appDidEnterBackground()

        let saved = try #require(first.storage.snapshot)
        #expect(saved.segmentStart == resumedAt)
        #expect(saved.segmentSteps == 200)
        #expect(saved.distanceBaseM == 700)
        #expect(saved.stepsMeasured == 1200)
        #expect(saved.systemDistanceM == 840)

        // El sistema mata la app y Paul la reabre en el mismo instante.
        let relaunched = Fixture(storage: first.storage, at: first.clock.now)
        relaunched.motion.setQueryResponse(.sample(steps: 200, distance: 140))
        await relaunched.store.restoreOnLaunch()
        #expect(relaunched.motion.updateStarts == [resumedAt])

        relaunched.motion.emit(steps: 250, distance: 175)
        await waitUntil { relaunched.session?.stepsMeasured == 1250 }
        #expect(relaunched.session?.stepsMeasured == 1250)
        #expect(relaunched.session?.systemDistanceM == 875, "base 700 + 175")
        #expect(relaunched.store.metrics?.distanceM == 875)
    }

    @Test("Restaurar sin dato y volver de background: solo se estima el gap nuevo de 60 s, no [savedAt, ahora]")
    func backgroundAfterRestoreEstimatesOnlyNewGap() async throws {
        // 1120 pasos a 80 spm y ~400 estimados al restaurar (como relaunchWithoutData).
        let snapshot = Self.snapshot(stepsMeasured: 1120, savedAgoS: 300)
        let fixture = Fixture(snapshot: snapshot)
        fixture.motion.setQueryResponse(.none)
        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.stepsEstimated == 400)

        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 60)
        await fixture.store.appDidBecomeActive()

        // Cadencia al salir: 1120 pasos en 1140 s = 58,9 spm; 1 min → 59. Con el gap pendiente
        // desde savedAt serían 480 más (80 spm × 6 min).
        #expect(fixture.session?.stepsEstimated == 459)
        #expect(fixture.motion.queriedRanges.last == .init(start: snapshot.startedAt, end: Self.now.addingTimeInterval(60)))
    }

    @Test("Volver de background guarda el snapshot reconciliado")
    func becomeActiveSavesReconciled() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300)
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.advance(by: 60)
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.snapshot?.stepsMeasured == 300)
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))

        await fixture.store.appDidBecomeActive()

        let saved = try #require(fixture.storage.snapshot)
        #expect(saved.stepsMeasured == 820)
        #expect(saved.segmentSteps == 820)
        #expect(saved.savedAt == fixture.clock.now)
    }

    @Test("Descartar los estimados restaurados guarda stepsEstimated = 0: un crash no los resucita")
    func discardSavesSnapshot() async {
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 1120, savedAgoS: 300))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.storage.snapshot?.stepsEstimated == 400)

        fixture.store.requestDiscardEstimated()
        fixture.store.confirmDiscardEstimated()

        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.storage.snapshot?.stepsEstimated == 0)
    }

    @Test("Salir del resumen limpia el aviso y lastSampleAt: la sesión nueva del mismo store empieza sin ellos")
    func leaveSummaryResetsRecoveryState() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(lastSampleAt: Self.now.addingTimeInterval(-60)))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.now.addingTimeInterval(-60))

        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        fixture.clock.advance(by: 60)
        await fixture.store.start()

        #expect(!fixture.store.showsRecoveredNotice)
        let first = try #require(fixture.storage.saved.last)
        #expect(first.startedAt == fixture.clock.now)
        #expect(first.lastSampleAt == nil)
    }

    @Test("lastSampleAt es el end de la última muestra que sumó pasos")
    func lastSampleAtOnlyWhenStepsAdded() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.motion.emit(steps: 100, end: Self.now.addingTimeInterval(30))
        await waitUntil { fixture.session?.stepsMeasured == 100 }
        fixture.motion.emit(steps: 100, distance: 70, end: Self.now.addingTimeInterval(60))
        await waitUntil { fixture.session?.systemDistanceM == 70 }
        fixture.clock.advance(by: 90)
        fixture.store.appDidEnterBackground()

        #expect(fixture.storage.snapshot?.lastSampleAt == Self.now.addingTimeInterval(30))
    }

    @Test("Force-quit y relanzar: la sesión vuelve con el tiempo real y el \"Sesión recuperada\" no sale al volver de background")
    func forceQuitRoundTrip() async throws {
        let first = Fixture()
        await first.store.start()
        first.motion.emit(steps: 600, end: Self.now.addingTimeInterval(300))
        await waitUntil { first.session?.stepsMeasured == 600 }
        first.clock.advance(by: 300)
        first.store.appDidEnterBackground()
        #expect(!first.store.showsRecoveredNotice)

        // El sistema mata la app. Dos minutos después, Paul la reabre.
        let relaunched = Fixture(storage: first.storage, at: Self.now.addingTimeInterval(420))
        relaunched.motion.setQueryResponse(.sample(steps: 840, distance: nil))
        await relaunched.store.restoreOnLaunch()

        #expect(relaunched.session?.startedAt == Self.now)
        #expect(relaunched.store.elapsedS == 420)
        #expect(relaunched.session?.stepsMeasured == 840)
        #expect(relaunched.session?.stepsEstimated == 0)
        #expect(relaunched.store.showsRecoveredNotice)

        relaunched.store.dismissRecoveredNotice()
        relaunched.store.appDidEnterBackground()
        relaunched.clock.advance(by: 60)
        await relaunched.store.appDidBecomeActive()
        #expect(!relaunched.store.showsRecoveredNotice)
    }

    @Test("Un guardado fallido no rompe la sesión y la siguiente muestra lo reintenta")
    func failedSaveRetries() async {
        let fixture = Fixture()
        fixture.storage.failSave(with: .failed(operation: "write"))
        await fixture.store.start()
        #expect(fixture.session?.status == .active)
        #expect(fixture.storage.saved.isEmpty)

        fixture.storage.failSave(with: nil)
        fixture.clock.advance(by: 1)
        fixture.motion.emit(steps: 5)
        await waitUntil { fixture.session?.stepsMeasured == 5 }
        #expect(fixture.storage.saved.count == 1, "sin guardado previo, la muestra guarda")
    }
}
