import Domain
import Foundation
import Testing

/// Escenarios de la 1.4 portados a mano desde `test/session-v3-tests.js` (AD-6). Cada
/// test cita el sitio de aserción que porta; `inventory.json` los atribuye a la 1.4.
///
/// `pause`, `resume` y `finishV3` de la v3 son `Session.pause(at:)`, `resume(at:)` y
/// `finish(at:)`; `addSteps`, `addMeasuredSteps(_:)`. Las métricas finales (`distanceM`,
/// `paceSecPerKm`, `cadenceSpm`) salen de `metrics(at:)`, que en una sesión finalizada
/// usa `durationS`. `totalPausesMs` y `pausedAtMs` son `totalPausesS` y `pausedAt`.
/// `:200` y `:297` afirman `addEstimatedSteps`, que es de la 1.5.
@Suite("Escenarios 1.4 · pausar, reanudar y finalizar")
struct SessionLifecycleScenarios {

    /// `const NOW = 1000000` (ms) y `const STRIDE = 0.655` de la suite JS.
    private static let now = Date(timeIntervalSince1970: 1_000_000 / 1000)
    private static let stride = 0.655

    private static func started() throws -> Session {
        try Session.start(at: now, strideM: stride)
    }

    /// `NOW + ms` de la suite JS.
    private static func at(ms: Double) -> Date {
        now.addingTimeInterval(ms / 1000)
    }

    /// AC-6 a AC-8: 4980 pasos y fin a los 62 min, sin pausas.
    private static func finishedWithoutPauses() throws -> Session {
        var session = try started()
        try session.addMeasuredSteps(4980)
        try session.finish(at: at(ms: 3_720_000))
        return session
    }

    /// AC-7 y AC-8: 4980 pasos, pausa de 3 min (+600 s → +780 s) y fin a los 65 min.
    private static func finishedWithPause() throws -> Session {
        var session = try started()
        try session.addMeasuredSteps(4980)
        try session.pause(at: at(ms: 600_000))
        try session.resume(at: at(ms: 780_000))
        try session.finish(at: at(ms: 3_900_000))
        return session
    }

    /// AC-9 y AC-15: 100 pasos y fin a los 10 min.
    private static func finishedShort() throws -> Session {
        var session = try started()
        try session.addMeasuredSteps(100)
        try session.finish(at: at(ms: 600_000))
        return session
    }

    // MARK: - AC-6: duración al finalizar

    @Test("session-v3-tests.js:131 · status = finished tras finalizar")
    func finishSetsStatus() throws {
        #expect(try Self.finishedWithoutPauses().status == .finished)
    }

    @Test("session-v3-tests.js:132 · endedAt es el instante de fin")
    func finishSetsEndedAt() throws {
        #expect(try Self.finishedWithoutPauses().endedAt == Self.at(ms: 3_720_000))
    }

    @Test("session-v3-tests.js:133 · durationS ≈ 3720 a los 62 min")
    func finishDuration() throws {
        let duration = try #require(try Self.finishedWithoutPauses().durationS)
        #expect(abs(duration - 3720) <= 1)
    }

    // MARK: - AC-7: ritmo con pausas

    @Test("session-v3-tests.js:155 · pausesS = 180 con una pausa de 3 min")
    func pausesAreRounded() throws {
        #expect(try Self.finishedWithPause().pausesS == 180)
    }

    @Test("session-v3-tests.js:156 · con pausas hay ritmo")
    func paceWithPauses() throws {
        let session = try Self.finishedWithPause()
        #expect(session.metrics(at: Self.at(ms: 3_900_000)).paceSecPerKm != nil)
    }

    // MARK: - AC-8: cadencia y ritmo sobre durationS neto

    @Test("session-v3-tests.js:181 · cadencia con pausas ≈ 80,3 spm")
    func cadenceWithPauses() throws {
        let session = try Self.finishedWithPause()
        #expect(abs(session.metrics(at: Self.at(ms: 3_900_000)).cadenceSpm - 80.3) <= 0.5)
    }

    @Test("session-v3-tests.js:183 · la cadencia al finalizar es la del cálculo en vivo sobre durationS")
    func finalCadenceMatchesLive() throws {
        let session = try Self.finishedWithPause()
        let duration = try #require(session.durationS)
        let live = try MetricsCalculator.cadenceSpm(stepsMeasured: 4980, activeSeconds: TimeInterval(duration))
        #expect(abs(session.metrics(at: Self.at(ms: 3_900_000)).cadenceSpm - live) <= 0.05)
    }

    @Test("session-v3-tests.js:186 · el ritmo usa durationS neto sin volver a restar las pausas")
    func finalPaceUsesNetDuration() throws {
        let session = try Self.finishedWithPause()
        let duration = try #require(session.durationS)
        let metrics = session.metrics(at: Self.at(ms: 3_900_000))
        let pace = try #require(metrics.paceSecPerKm)
        let expected = (Double(duration) / (metrics.distanceM / 1000)).rounded(.toNearestOrAwayFromZero)
        #expect(abs(Double(pace) - expected) <= 1)
    }

    // MARK: - AC-9 y AC-15: inmutable tras finalizar

    @Test("session-v3-tests.js:198 · status = finished con 100 pasos a los 10 min")
    func shortFinishSetsStatus() throws {
        #expect(try Self.finishedShort().status == .finished)
    }

    @Test("session-v3-tests.js:199 · sumar pasos a una sesión finalizada lanza")
    func addStepsOnFinishedThrows() throws {
        var session = try Self.finishedShort()
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "addMeasuredSteps")) {
            try session.addMeasuredSteps(1)
        }
    }

    @Test("session-v3-tests.js:201 · finalizar una sesión finalizada lanza")
    func finishOnFinishedThrows() throws {
        var session = try Self.finishedShort()
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "finished")) {
            try session.finish(at: Self.at(ms: 900_000))
        }
    }

    @Test("session-v3-tests.js:202 · la zancada se conserva al finalizar")
    func strideIsPreserved() throws {
        #expect(try Self.finishedShort().strideM == Self.stride)
    }

    @Test("session-v3-tests.js:296 · sumar pasos a una sesión finalizada → error de dominio")
    func addStepsOnFinishedIsDomainError() throws {
        var session = try Self.finishedShort()
        #expect(throws: DomainError.self) {
            try session.addMeasuredSteps(1)
        }
    }

    // MARK: - AC-10: pausar y reanudar

    private struct PauseResume {
        var paused: Session
        var resumed: Session
    }

    /// 50 pasos, pausa a +300 s y reanuda a +420 s.
    private static func pauseAndResume() throws -> PauseResume {
        var session = try started()
        try session.addMeasuredSteps(50)
        try session.pause(at: at(ms: 300_000))
        let paused = session
        try session.resume(at: at(ms: 420_000))
        return PauseResume(paused: paused, resumed: session)
    }

    @Test("session-v3-tests.js:215 · status = paused tras pausar")
    func pauseSetsStatus() throws {
        #expect(try Self.pauseAndResume().paused.status == .paused)
    }

    @Test("session-v3-tests.js:216 · pausedAt fijado al pausar")
    func pauseSetsPausedAt() throws {
        #expect(try Self.pauseAndResume().paused.pausedAt == Self.at(ms: 300_000))
    }

    @Test("session-v3-tests.js:218 · status = active tras reanudar")
    func resumeSetsStatus() throws {
        #expect(try Self.pauseAndResume().resumed.status == .active)
    }

    @Test("session-v3-tests.js:219 · totalPausesS = 120 tras una pausa de 2 min")
    func resumeAccumulatesPause() throws {
        #expect(try Self.pauseAndResume().resumed.totalPausesS == 120)
    }

    @Test("session-v3-tests.js:220 · pausedAt vuelve a nil al reanudar")
    func resumeClearsPausedAt() throws {
        #expect(try Self.pauseAndResume().resumed.pausedAt == nil)
    }

    @Test("session-v3-tests.js:222 · los pasos se conservan tras la pausa")
    func stepsSurvivePause() throws {
        #expect(try Self.pauseAndResume().resumed.stepsMeasured == 50)
    }

    @Test("session-v3-tests.js:224 · 80 pasos tras sumar 30 al reanudar")
    func stepsCountAfterResume() throws {
        var session = try Self.pauseAndResume().resumed
        try session.addMeasuredSteps(30)
        #expect(session.stepsMeasured == 80)
    }

    // MARK: - AC-19: finalizar tras sumas en secuencia

    @Test("session-v3-tests.js:351 · finished tras 100 sumas de 1")
    func finishAfterSequentialAdds() throws {
        var session = try Self.started()
        for _ in 0..<100 { try session.addMeasuredSteps(1) }
        try session.finish(at: Self.at(ms: 600_000))
        #expect(session.status == .finished)
    }

    // MARK: - Propios de la plataforma nativa

    @Test("Nativo · en pausa el tiempo se congela: pausada a +300 s sigue en 300 s")
    func pauseFreezesElapsed() throws {
        var session = try Self.started()
        try session.pause(at: Self.at(ms: 300_000))
        #expect(session.elapsedS(at: Self.at(ms: 300_000)) == 300)
        #expect(session.elapsedS(at: Self.at(ms: 3_000_000)) == 300)
    }

    @Test("Nativo · tras reanudar el tiempo sigue desde donde se detuvo")
    func resumeContinuesElapsed() throws {
        let session = try Self.pauseAndResume().resumed
        #expect(session.elapsedS(at: Self.at(ms: 420_000)) == 300)
        #expect(session.elapsedS(at: Self.at(ms: 480_000)) == 360)
    }

    @Test("Nativo · pausar en el instante del inicio también congela")
    func pauseAtStartFreezes() throws {
        var session = try Self.started()
        try session.pause(at: Self.now)
        #expect(session.elapsedS(at: Self.at(ms: 60_000)) == 0)
        try session.resume(at: Self.at(ms: 60_000))
        #expect(session.totalPausesS == 60)
        #expect(session.elapsedS(at: Self.at(ms: 90_000)) == 30)
    }

    @Test("Nativo · finalizar sin pausas: 4980 pasos a +3720 s → 3720 s, 1140 s/km y 80,3 spm")
    func exactFinishWithoutPauses() throws {
        let session = try Self.finishedWithoutPauses()
        #expect(session.durationS == 3720)
        #expect(session.pausesS == 0)
        #expect(session.pausedAt == nil)
        #expect(session.metrics(at: Self.at(ms: 3_720_000)) == SessionMetrics(distanceM: 3261.9, paceSecPerKm: 1140, cadenceSpm: 80.3))
    }

    @Test("Nativo · finalizar desde pausa acumula la pausa abierta: pausesS 280 y durationS 3620")
    func finishFromPauseAccumulatesOpenPause() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        try session.pause(at: Self.at(ms: 600_000))
        try session.resume(at: Self.at(ms: 780_000))
        try session.pause(at: Self.at(ms: 3_800_000))
        try session.finish(at: Self.at(ms: 3_900_000))

        #expect(session.status == .finished)
        #expect(session.endedAt == Self.at(ms: 3_900_000))
        #expect(session.pausedAt == nil)
        #expect(session.totalPausesS == 280)
        #expect(session.pausesS == 280)
        #expect(session.durationS == 3620)
    }

    @Test("Nativo · una sesión finalizada queda congelada en durationS, sea cual sea el instante")
    func finishedIsFrozen() throws {
        let session = try Self.finishedWithoutPauses()
        let atEnd = session.metrics(at: Self.at(ms: 3_720_000))
        #expect(session.elapsedS(at: Self.at(ms: 9_000_000)) == 3720)
        #expect(session.metrics(at: Self.at(ms: 9_000_000)) == atEnd)
        #expect(session.metrics(at: Self.now) == atEnd)
    }

    @Test("Nativo · durationS y pausesS se redondean al entero, la mitad sube")
    func durationAndPausesAreRounded() throws {
        var session = try Self.started()
        try session.pause(at: Self.at(ms: 10_000))
        try session.resume(at: Self.at(ms: 10_500))
        try session.finish(at: Self.at(ms: 61_000))
        #expect(session.pausesS == 1)       // 0,5 → 1
        #expect(session.durationS == 61)    // 60,5 → 61
    }

    @Test("Nativo · una pausa con el reloj hacia atrás no resta tiempo en movimiento")
    func negativePauseCountsAsZero() throws {
        var session = try Self.started()
        try session.pause(at: Self.at(ms: 300_000))
        try session.resume(at: Self.at(ms: 200_000))
        #expect(session.totalPausesS == 0)
    }

    @Test("Nativo · transiciones inválidas: lanzan invalidTransition y no mutan")
    func invalidTransitionsThrow() throws {
        var active = try Self.started()
        try active.addMeasuredSteps(50)
        let activeBefore = active
        #expect(throws: DomainError.invalidTransition(from: "active", to: "active")) {
            try active.resume(at: Self.at(ms: 60_000))
        }
        #expect(active == activeBefore)

        var paused = activeBefore
        try paused.pause(at: Self.at(ms: 300_000))
        let pausedBefore = paused
        #expect(throws: DomainError.invalidTransition(from: "paused", to: "paused")) {
            try paused.pause(at: Self.at(ms: 360_000))
        }
        #expect(paused == pausedBefore, "pausar una pausada no reescribe la pausa en curso")

        var finished = pausedBefore
        try finished.finish(at: Self.at(ms: 400_000))
        let finishedBefore = finished
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "paused")) {
            try finished.pause(at: Self.at(ms: 500_000))
        }
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "active")) {
            try finished.resume(at: Self.at(ms: 500_000))
        }
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "finished")) {
            try finished.finish(at: Self.at(ms: 500_000))
        }
        #expect(finished == finishedBefore)
    }

    @Test("Nativo · en pausa y finalizada no se suman pasos ni distancia del sistema")
    func noMutationsOutsideActive() throws {
        var paused = try Self.started()
        try paused.pause(at: Self.at(ms: 60_000))
        let pausedBefore = paused
        #expect(throws: DomainError.invalidTransition(from: "paused", to: "addMeasuredSteps")) {
            try paused.addMeasuredSteps(200)
        }
        #expect(throws: DomainError.invalidTransition(from: "paused", to: "recordSystemDistance")) {
            try paused.recordSystemDistance(150)
        }
        #expect(paused == pausedBefore)

        var finished = try Self.finishedShort()
        let finishedBefore = finished
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "recordSystemDistance")) {
            try finished.recordSystemDistance(150)
        }
        #expect(finished == finishedBefore)
    }
}
