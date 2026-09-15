import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 1.4 sobre `SessionStore`: pausar, reanudar y finalizar con confirmación,
/// el stream del podómetro por tramos y el resumen hasta volver a Inicio.
@MainActor
@Suite("SessionStore · pausar, reanudar y finalizar")
struct SessionStoreLifecycleTests: SessionStoreSuite {

    private typealias Fixture = SessionStoreFixture

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
        // Finalizar ya canceló el stream del tramo: lo que emita desde aquí no llega al store.
        await waitUntil { fixture.motion.cancelledStreams == 1 }
        fixture.motion.emit(steps: 6000, distance: 4000)

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

private extension SessionStoreFixture {

    /// Cierra la sesión pasando por la confirmación, como la UI.
    func finish() async {
        store.requestFinish()
        await store.confirmFinish()
    }
}
