import Domain
import Foundation
import Testing

/// Escenarios de la 1.2 portados a mano desde `test/session-v3-tests.js` (AD-6). Cada
/// test cita el sitio de aserción que porta; `inventory.json` los atribuye a la 1.2.
///
/// `addSteps` de la v3 es `Session.addMeasuredSteps(_:)`. Los sitios `:102`
/// (`distanceM` tras 4980 pasos) y `:350` (distancia final) son métricas y se portan en
/// la 1.3 con su cálculo (AD-22); `:351` (`finished`) se porta en la 1.4 con el cierre.
@Suite("Escenarios 1.2 · conteo de pasos")
struct StepCountingScenarios {

    /// `const NOW = 1000000` (ms) y `const STRIDE = 0.655` de la suite JS.
    private static let now = Date(timeIntervalSince1970: 1_000_000 / 1000)
    private static let stride = 0.655

    private static func started() throws -> Session {
        try Session.start(at: now, strideM: stride)
    }

    // MARK: - AC-3: addSteps incrementa

    @Test("session-v3-tests.js:88 · stepsMeasured = 100 tras sumar 100")
    func firstAdd() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(100)
        #expect(session.stepsMeasured == 100)
    }

    @Test("session-v3-tests.js:90 · stepsMeasured = 150 tras sumar 100 y 50")
    func secondAdd() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(100)
        try session.addMeasuredSteps(50)
        #expect(session.stepsMeasured == 150)
    }

    // MARK: - AC-4: suma de muchos incrementos

    @Test("session-v3-tests.js:100 · 4980 pasos tras 4980 sumas de 1")
    func manyUnitAdds() throws {
        var session = try Self.started()
        for _ in 0..<4980 { try session.addMeasuredSteps(1) }
        #expect(session.stepsMeasured == 4980)
    }

    // MARK: - AC-17: sumar 0 no cambia nada

    @Test("session-v3-tests.js:321 · stepsMeasured = 0 tras sumar 0")
    func addingZeroIsNoOp() throws {
        let fresh = try Self.started()
        var session = fresh
        try session.addMeasuredSteps(0)
        #expect(session.stepsMeasured == 0)
        #expect(session == fresh)
    }

    @Test("session-v3-tests.js:323 · sumar 5 funciona tras sumar 0")
    func addAfterZero() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(0)
        try session.addMeasuredSteps(5)
        #expect(session.stepsMeasured == 5)
    }

    // MARK: - AC-19: sumas en secuencia

    /// En la suite JS el sitio se ejecuta 100 veces (`executions: 100`): aquí también.
    @Test("session-v3-tests.js:345 · cada una de 100 sumas de 1 deja stepsMeasured = i + 1")
    func sequentialAdds() throws {
        var session = try Self.started()
        for i in 0..<100 {
            try session.addMeasuredSteps(1)
            #expect(session.stepsMeasured == i + 1)
        }
    }

    // MARK: - Propios de la plataforma nativa

    /// La matriz de la 1.2 exige el rechazo tipado; la v3 lanza `RangeError`, que ningún
    /// test JS afirma: no cita sitio.
    @Test("Nativo · un incremento negativo se rechaza con invalidValue(steps) y no muta", arguments: [-1, Int.min])
    func negativeCountThrows(count: Int) throws {
        var session = try Self.started()
        try session.addMeasuredSteps(10)
        let before = session

        #expect(throws: DomainError.invalidValue(field: "steps")) {
            try session.addMeasuredSteps(count)
        }
        #expect(session == before)
    }

    @Test("Nativo · un incremento que desbordaría el contador se rechaza y no muta")
    func overflowThrows() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(1)
        let before = session

        #expect(throws: DomainError.invalidValue(field: "steps")) {
            try session.addMeasuredSteps(.max)
        }
        #expect(session == before)
    }

    @Test("Nativo · sumar pasos no toca stepsEstimated (CAP-3)")
    func estimatedStaysZero() throws {
        var session = try Self.started()
        try session.addMeasuredSteps(900)
        #expect(session.stepsEstimated == 0)
    }
}
