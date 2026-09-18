import Domain
import Foundation
import Testing

/// Escenarios de la 1.5 portados a mano desde `test/session-v3-tests.js` (AD-6), más los
/// del `GapEstimator` sobre el agregado. Cada test portado cita el sitio de aserción que
/// porta; `inventory.json` los atribuye a la 1.5.
///
/// `addSteps` y `addEstimatedSteps` de la v3 son `Session.addMeasuredSteps(_:)` y
/// `addEstimatedSteps(_:)`; `finishV3`, `finish(at:)`. La `distanceM` que la v3 guarda sale
/// de `metrics(at:)`. Las cuatro funciones puras de `test/gapestimator-tests.js` ya son
/// vectores (`estimateSteps.json`, `calculateCadence.json`).
@Suite("Escenarios 1.5 · reconstrucción del background")
struct GapReconstructionScenarios {

    /// `const NOW = 1000000` (ms) y `const STRIDE = 0.655` de la suite JS.
    private static let now = Date(timeIntervalSince1970: 1_000_000 / 1000)
    private static let stride = 0.655

    private static func started() throws -> Session {
        try Session.start(at: now, strideM: stride)
    }

    /// AC-5 y AC-16: 4980 medidos y 320 estimados.
    private static func withEstimated() throws -> Session {
        var session = try started()
        try session.addMeasuredSteps(4980)
        try session.addEstimatedSteps(320)
        return session
    }

    /// AC-9 y AC-15: 100 pasos y fin a los 10 min.
    private static func finishedShort() throws -> Session {
        var session = try started()
        try session.addMeasuredSteps(100)
        try session.finish(at: now.addingTimeInterval(600))
        return session
    }

    // MARK: - Portados de la v3

    @Test("session-v3-tests.js:114 · distanceM = (4980 + 320) × zancada")
    func distanceIncludesEstimated() throws {
        let distance = try Self.withEstimated().metrics(at: Self.now).distanceM
        let expected = ((4980.0 + 320) * Self.stride * 100).rounded() / 100
        #expect(abs(distance - expected) < 0.01)
        #expect(expected == 3471.5)
    }

    @Test("session-v3-tests.js:200 · addEstimatedSteps sobre una finalizada lanza (AC-9)")
    func addEstimatedOnFinishedThrowsAC9() throws {
        var finished = try Self.finishedShort()
        let before = finished
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "addEstimatedSteps")) {
            try finished.addEstimatedSteps(1)
        }
        #expect(finished == before)
    }

    @Test("session-v3-tests.js:297 · addEstimatedSteps sobre una finalizada lanza (AC-15)")
    func addEstimatedOnFinishedThrowsAC15() throws {
        var finished = try Self.finishedShort()
        let before = finished
        #expect(throws: DomainError.self) {
            try finished.addEstimatedSteps(1)
        }
        #expect(finished == before)
    }

    @Test("session-v3-tests.js:308 · stepsEstimated = 320")
    func estimatedAreKept() throws {
        #expect(try Self.withEstimated().stepsEstimated == 320)
    }

    @Test("session-v3-tests.js:309 · stepsMeasured no cambia al sumar estimados")
    func measuredUnchanged() throws {
        #expect(try Self.withEstimated().stepsMeasured == 4980)
    }

    @Test("session-v3-tests.js:311 · la distancia incluye los estimados")
    func distanceIncludesEstimatedAC16() throws {
        let distance = try Self.withEstimated().metrics(at: Self.now).distanceM
        #expect(abs(distance - 3471.5) < 0.01)
    }

    // MARK: - Agregado

    @Test("Nativo · addEstimatedSteps: negativo o desbordante lanza invalidValue(steps) y no muta")
    func addEstimatedValidatesCount() throws {
        var session = try Self.withEstimated()
        let before = session
        #expect(throws: DomainError.invalidValue(field: "steps")) { try session.addEstimatedSteps(-1) }
        #expect(throws: DomainError.invalidValue(field: "steps")) { try session.addEstimatedSteps(.max) }
        try session.addEstimatedSteps(0)
        #expect(session == before)
    }

    @Test("Nativo · addEstimatedSteps en pausa lanza invalidTransition: no se estima en pausa")
    func addEstimatedWhilePausedThrows() throws {
        var session = try Self.started()
        try session.pause(at: Self.now.addingTimeInterval(60))
        #expect(throws: DomainError.invalidTransition(from: "paused", to: "addEstimatedSteps")) {
            try session.addEstimatedSteps(10)
        }
        #expect(session.stepsEstimated == 0)
    }

    @Test("Nativo · descartar: 400 estimados → 0; distancia y ritmo se recalculan sin ellos")
    func discardRecalculates() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(800)
        try session.addEstimatedSteps(400)
        let at = Self.now.addingTimeInterval(600)
        let withEstimated = session.metrics(at: at)

        try session.discardEstimatedSteps()

        let metrics = session.metrics(at: at)
        #expect(session.stepsEstimated == 0)
        #expect(session.stepsMeasured == 800)
        #expect(withEstimated.distanceM == 786)
        #expect(metrics.distanceM == 524)
        #expect(withEstimated.paceSecPerKm == 763)
        #expect(metrics.paceSecPerKm == 1145)
        #expect(metrics.cadenceSpm == withEstimated.cadenceSpm, "la cadencia nunca contó los estimados")
    }

    @Test("Nativo · descartar en pausa se permite; en una finalizada lanza invalidTransition y no muta")
    func discardByStatus() throws {
        var paused = try Self.started()
        try paused.addEstimatedSteps(50)
        try paused.pause(at: Self.now.addingTimeInterval(60))
        try paused.discardEstimatedSteps()
        #expect(paused.stepsEstimated == 0)

        var finished = try Self.started()
        try finished.addEstimatedSteps(50)
        try finished.finish(at: Self.now.addingTimeInterval(600))
        let before = finished
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "discardEstimatedSteps")) {
            try finished.discardEstimatedSteps()
        }
        #expect(finished == before)
    }

    // MARK: - GapEstimator sobre la sesión

    /// Tope de gap estimable de `formulas.json` (R1): 20 min.
    private static let maxGapS: TimeInterval = 1200

    /// Desenlace del gap con el tope del proyecto, y la cadencia tomada en `gapStart`.
    private static func gapOutcome(
        _ session: Session,
        measuredAtGapStart: Int,
        gapStart: Date,
        gapS: TimeInterval,
        maxGapS: TimeInterval = GapReconstructionScenarios.maxGapS
    ) -> GapEstimator.Outcome {
        GapEstimator.outcome(
            for: session,
            measuredAtGapStart: measuredAtGapStart,
            gapStart: gapStart,
            gapEnd: gapStart.addingTimeInterval(gapS),
            maxEstimableGapS: maxGapS
        )
    }

    @Test("Nativo · GapEstimator: activa 10 min a 80 spm y gap de 300 s → 400 estimados")
    func estimatorAt80Spm() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(800)
        let gapStart = Self.now.addingTimeInterval(600)

        #expect(session.metrics(at: gapStart).cadenceSpm == 80)
        #expect(Self.gapOutcome(session, measuredAtGapStart: 800, gapStart: gapStart, gapS: 300) == .estimated(400))
    }

    @Test("Nativo · GapEstimator: con menos de 120 s de muestra previa el gap es 0")
    func estimatorNeedsPriorSample() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(120)
        let gapStart = Self.now.addingTimeInterval(90)

        #expect(Self.gapOutcome(session, measuredAtGapStart: 120, gapStart: gapStart, gapS: 300) == .skipped(.noPriorSample))
        // Justo en el umbral ya estima: 240 pasos en 120 s son 120 spm × 5 min.
        try session.addMeasuredSteps(120)
        let atThreshold = Self.now.addingTimeInterval(GapEstimator.minPriorSampleS)
        #expect(Self.gapOutcome(session, measuredAtGapStart: 240, gapStart: atThreshold, gapS: 300) == .estimated(600))
    }

    @Test("Nativo · GapEstimator: en pausa o finalizada el gap es 0")
    func estimatorOnlyWhenActive() throws {
        var paused = try Self.started()
        try paused.addMeasuredSteps(800)
        try paused.pause(at: Self.now.addingTimeInterval(600))
        let gapStart = Self.now.addingTimeInterval(600)
        #expect(Self.gapOutcome(paused, measuredAtGapStart: 800, gapStart: gapStart, gapS: 300) == .skipped(.notActive))

        var finished = try Self.started()
        try finished.addMeasuredSteps(800)
        try finished.finish(at: gapStart)
        #expect(Self.gapOutcome(finished, measuredAtGapStart: 800, gapStart: gapStart, gapS: 300) == .skipped(.notActive))
    }

    @Test("Nativo · GapEstimator: la cadencia es solo de pasos medidos, nunca de los estimados")
    func estimatorIgnoresEstimated() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(800)
        try session.addEstimatedSteps(4000)
        let gapStart = Self.now.addingTimeInterval(600)

        #expect(Self.gapOutcome(session, measuredAtGapStart: 800, gapStart: gapStart, gapS: 300) == .estimated(400))
    }

    @Test("Nativo · GapEstimator: la cadencia sale de los pasos del inicio del gap, no de los de ahora (R1)")
    func estimatorUsesCadenceAtGapStart() throws {
        // Caso real del registro WTM1 del 2026-09-17 (sesión 1789649385424): al empezar el gap
        // había 1156 pasos y 631 s de sesión; al volver, 2149. El gap duró 528 s (8,8 min).
        let gapStart = Self.now.addingTimeInterval(631)

        // Con la cadencia del inicio del gap: 1156 pasos en 631 s son 109,9 spm × 8,8 min.
        var atGapStart = try Self.started()
        try atGapStart.addMeasuredSteps(1156)
        #expect(Self.gapOutcome(atGapStart, measuredAtGapStart: 1156, gapStart: gapStart, gapS: 528) == .estimated(967))

        // Con los pasos de ahora —lo que hacía la regla vieja— la cadencia se dobla (204,3 spm)
        // y salen 1798: los 1796 pasos fantasma que esa caminata sumó.
        var afterGap = try Self.started()
        try afterGap.addMeasuredSteps(2149)
        #expect(Self.gapOutcome(afterGap, measuredAtGapStart: 2149, gapStart: gapStart, gapS: 528) == .estimated(1798))
    }

    @Test("Nativo · GapEstimator: si los medidos crecieron desde el inicio del gap no se estima (R1)")
    func estimatorSkipsWhenStreamAdvanced() throws {
        // El caso real completo: al abrir el gap había 1156 pasos y el stream entregó hasta 2149
        // antes de volver. Estimar los contaría dos veces, así que la defensa corta.
        var session = try Self.started()
        try session.addMeasuredSteps(2149)
        let gapStart = Self.now.addingTimeInterval(631)

        #expect(Self.gapOutcome(session, measuredAtGapStart: 1156, gapStart: gapStart, gapS: 528) == .skipped(.streamAdvanced))
        // Sin crecer (iguales) sí se estima.
        #expect(Self.gapOutcome(session, measuredAtGapStart: 2149, gapStart: gapStart, gapS: 528) == .estimated(1798))
    }

    @Test("Nativo · GapEstimator: por encima del tope de gap no se estima nada; justo en el tope sí (R1)")
    func estimatorCapsTheGap() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(800)
        let gapStart = Self.now.addingTimeInterval(600)

        // 25 min de gap con un tope de 20 min.
        #expect(Self.gapOutcome(session, measuredAtGapStart: 800, gapStart: gapStart, gapS: 1500) == .skipped(.gapAboveCap))
        // Justo en el tope: 80 spm × 20 min.
        #expect(Self.gapOutcome(session, measuredAtGapStart: 800, gapStart: gapStart, gapS: 1200) == .estimated(1600))
        // Un segundo por encima ya no estima.
        #expect(Self.gapOutcome(session, measuredAtGapStart: 800, gapStart: gapStart, gapS: 1201) == .skipped(.gapAboveCap))
    }

    @Test("Nativo · GapEstimator: un gap negativo (reloj hacia atrás) es 0")
    func estimatorNegativeGap() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(800)
        let gapStart = Self.now.addingTimeInterval(600)

        #expect(Self.gapOutcome(session, measuredAtGapStart: 800, gapStart: gapStart, gapS: -30) == .skipped(.noCadence))
    }

    @Test("Nativo · estimateSteps: una entrada infinita > 0 lanza con su campo; ≤ 0 da 0")
    func estimateStepsInfinite() {
        #expect(throws: DomainError.invalidValue(field: "cadenceSpm")) {
            try GapEstimator.estimateSteps(cadenceSpm: .infinity, gapS: 300)
        }
        #expect(throws: DomainError.invalidValue(field: "gapS")) {
            try GapEstimator.estimateSteps(cadenceSpm: 80, gapS: .infinity)
        }
        #expect(throws: DomainError.invalidValue(field: "steps")) {
            try GapEstimator.estimateSteps(cadenceSpm: .greatestFiniteMagnitude, gapS: 3600)
        }
        #expect((try? GapEstimator.estimateSteps(cadenceSpm: -.infinity, gapS: 300)) == 0)
    }
}
