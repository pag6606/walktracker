import Domain
import Foundation
import Testing

/// Escenarios de la 1.3 portados a mano desde `test/session-v3-tests.js` (AD-6). Cada
/// test cita el sitio de aserción que porta; `inventory.json` los atribuye a la 1.3.
///
/// La v3 guarda `distanceM`, `paceSecPerKm` y `cadenceSpm` en la sesión y los fija al
/// finalizar (`finishV3`); en Swift son derivadas de `Session.metrics(at:)`. Un sitio que
/// afirma una métrica de una sesión sin pausas ni estimados se porta aquí aunque el JS
/// pase por `finishV3`: sin pausas, su `durS` es el tiempo transcurrido. Los que
/// necesitan pausa (`:156`, `:181`, `:183`, `:186`) son de la 1.4, y el de estimados
/// (`:114`), de la 1.5.
@Suite("Escenarios 1.3 · métricas en vivo")
struct MetricsScenarios {

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

    // MARK: - AC-2: valores iniciales

    @Test("session-v3-tests.js:68 · distanceM = 0 al crear la sesión")
    func initialDistance() throws {
        #expect(try Self.started().metrics(at: Self.now).distanceM == 0)
    }

    @Test("session-v3-tests.js:71 · paceSecPerKm = nil al crear la sesión")
    func initialPace() throws {
        #expect(try Self.started().metrics(at: Self.now).paceSecPerKm == nil)
    }

    @Test("session-v3-tests.js:72 · cadenceSpm = 0 al crear la sesión")
    func initialCadence() throws {
        #expect(try Self.started().metrics(at: Self.now).cadenceSpm == 0)
    }

    // MARK: - AC-4 y AC-5: distancia derivada de los pasos

    @Test("session-v3-tests.js:102 · distanceM ≈ 3261,9 tras 4980 sumas de 1")
    func distanceAfterManyUnitAdds() throws {
        var session = try Self.started()
        for _ in 0..<4980 { try session.addMeasuredSteps(1) }
        let expected = 3261.9 // +(4980 * STRIDE).toFixed(2)
        #expect(abs(session.metrics(at: Self.now).distanceM - expected) <= 0.01)
    }

    @Test("session-v3-tests.js:119 · distanceM ≈ 3261,9 con 4980 medidos y sin estimados")
    func distanceWithoutEstimated() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        let expected = 3261.9
        #expect(abs(session.metrics(at: Self.now).distanceM - expected) <= 0.01)
    }

    // MARK: - AC-7 y AC-8: ritmo y cadencia a los 62 min

    @Test("session-v3-tests.js:147 · 4980 pasos en 62 min: ritmo > 0")
    func paceAt62Minutes() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        let pace = try #require(session.metrics(at: Self.at(ms: 3_720_000)).paceSecPerKm)
        #expect(pace > 0)
    }

    @Test("session-v3-tests.js:169 · 4980 pasos en 62 min: cadencia > 0")
    func cadenceIsPositive() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        #expect(session.metrics(at: Self.at(ms: 3_720_000)).cadenceSpm > 0)
    }

    @Test("session-v3-tests.js:170 · 4980 pasos en 62 min: cadencia ≈ 80,3 spm")
    func cadenceAt62Minutes() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        #expect(abs(session.metrics(at: Self.at(ms: 3_720_000)).cadenceSpm - 80.3) <= 0.5)
    }

    // MARK: - AC-14: sin ritmo por debajo de 100 m

    @Test("session-v3-tests.js:285 · 10 pasos (6,55 m) al minuto: ritmo nil")
    func noPaceBelowThreshold() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(10)
        #expect(session.metrics(at: Self.at(ms: 60_000)).paceSecPerKm == nil)
    }

    // MARK: - AC-19: distancia tras sumas en secuencia

    @Test("session-v3-tests.js:350 · distancia ≈ 65,5 m tras 100 sumas de 1, a los 10 min")
    func distanceAfterSequentialAdds() throws {
        var session = try Self.started()
        for _ in 0..<100 { try session.addMeasuredSteps(1) }
        let expected = 65.5 // +(100 * STRIDE).toFixed(2)
        #expect(abs(session.metrics(at: Self.at(ms: 600_000)).distanceM - expected) <= 0.01)
    }

    // MARK: - Propios de la plataforma nativa

    /// La matriz de la 1.3: ritmo 1140 s/km y cadencia 80,3 exactos, sin tolerancia.
    @Test("Nativo · 4980 pasos sin distancia del sistema a los 3720 s: 3261,9 m, 1140 s/km y 80,3 spm")
    func exactMetricsAt62Minutes() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        #expect(session.metrics(at: Self.at(ms: 3_720_000)) == SessionMetrics(distanceM: 3261.9, paceSecPerKm: 1140, cadenceSpm: 80.3))
    }

    @Test("Nativo · con distancia del sistema se usa esa, no la de los pasos")
    func systemDistanceWins() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        try session.recordSystemDistance(3400)

        let metrics = session.metrics(at: Self.at(ms: 3_720_000))
        #expect(metrics.distanceM == 3400)
        #expect(metrics.paceSecPerKm == 1094) // round(3720 / 3,4)
        #expect(metrics.cadenceSpm == 80.3, "la cadencia sigue siendo de los pasos medidos")
    }

    @Test("Nativo · con distancia del sistema, los estimados suman × zancada: 500 m y 400 estimados → 762 m; al descartar, 500 m")
    func systemDistancePlusEstimated() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(800)
        try session.recordSystemDistance(500)
        try session.addEstimatedSteps(400)

        #expect(session.metrics(at: Self.at(ms: 900_000)).distanceM == 762, "500 + 400 × 0,655")

        try session.discardEstimatedSteps()
        #expect(session.metrics(at: Self.at(ms: 900_000)).distanceM == 500)
    }

    @Test("Nativo · la distancia del sistema nunca baja: 3400 → 3390 sigue en 3400")
    func systemDistanceNeverDecreases() throws {
        var session = try Self.started()
        try session.recordSystemDistance(3400)
        try session.recordSystemDistance(3390)
        #expect(session.systemDistanceM == 3400)
        #expect(session.metrics(at: Self.now).distanceM == 3400)

        try session.recordSystemDistance(3410)
        #expect(session.systemDistanceM == 3410)
    }

    @Test("Nativo · una distancia del sistema de 0 m cuenta como dada")
    func zeroSystemDistanceIsRecorded() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(200)
        try session.recordSystemDistance(0)
        #expect(session.systemDistanceM == 0)
        #expect(session.metrics(at: Self.now).distanceM == 0)
    }

    @Test("Nativo · una distancia del sistema inválida se rechaza con invalidValue(distanceM) y no muta", arguments: [
        -1, -Double.leastNonzeroMagnitude, Double.nan, .infinity, -.infinity,
    ])
    func invalidSystemDistanceThrows(meters: Double) throws {
        var session = try Self.started()
        try session.addMeasuredSteps(4980)
        try session.recordSystemDistance(3400)
        let before = session

        #expect(throws: DomainError.invalidValue(field: "distanceM")) {
            try session.recordSystemDistance(meters)
        }
        #expect(session == before)
    }

    @Test("Nativo · el ritmo aparece justo a los 100 m: 152 pasos (99,56 m) no, 153 (≈100,2 m) sí")
    func paceThreshold() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(152)
        #expect(session.metrics(at: Self.at(ms: 60_000)).paceSecPerKm == nil)

        try session.addMeasuredSteps(1)
        #expect(session.metrics(at: Self.at(ms: 60_000)).paceSecPerKm == 599) // round(60 / 0,1002)

        var system = try Self.started()
        try system.recordSystemDistance(100)
        #expect(system.metrics(at: Self.at(ms: 60_000)).paceSecPerKm == 600)
    }

    @Test("Nativo · con 100 m pero sin tiempo transcurrido no hay ritmo ni cadencia")
    func noTimeNoPace() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(200)
        let metrics = session.metrics(at: Self.now)
        #expect(metrics.paceSecPerKm == nil)
        #expect(metrics.cadenceSpm == 0)
    }

    @Test("Nativo · la distancia se redondea a 2 decimales, como el toFixed(2) de la v3")
    func distanceRoundsToTwoDecimals() throws {
        #expect(try MetricsCalculator.distanceM(stepsMeasured: 1, stepsEstimated: 0, strideM: 0.655) == 0.66)
        #expect(try MetricsCalculator.distanceM(stepsMeasured: 3, stepsEstimated: 0, strideM: 0.6553) == 1.97)
    }

    @Test("Nativo · MetricsCalculator rechaza entradas no finitas en distancia, ritmo y cadencia")
    func calculatorRejectsNonFinite() {
        #expect(throws: DomainError.invalidValue(field: "movingS")) {
            try MetricsCalculator.paceSecPerKm(movingS: .nan, distanceM: 1000)
        }
        #expect(throws: DomainError.invalidValue(field: "distanceM")) {
            try MetricsCalculator.paceSecPerKm(movingS: 60, distanceM: .infinity)
        }
        #expect(throws: DomainError.invalidValue(field: "activeSeconds")) {
            try MetricsCalculator.cadenceSpm(stepsMeasured: 10, activeSeconds: .nan)
        }
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try MetricsCalculator.distanceM(stepsMeasured: 10, stepsEstimated: 0, strideM: .nan)
        }
    }
}
