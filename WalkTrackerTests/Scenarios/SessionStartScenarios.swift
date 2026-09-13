import Domain
import Foundation
import Testing

/// Escenarios de la 1.1 portados a mano desde `test/session-v3-tests.js` (AD-6). Cada
/// test cita el sitio de aserción que porta; `inventory.json` los atribuye a la 1.1.
///
/// Los sitios `:68` (`distanceM`), `:71` (`paceSecPerKm`) y `:72` (`cadenceSpm`) son
/// métricas derivadas y se portan en la 1.3 con su cálculo (AD-22).
@Suite("Escenarios 1.1 · crear sesión")
struct SessionStartScenarios {

    /// `const NOW = 1000000` (ms) y `const STRIDE = 0.655` de la suite JS.
    private static let now = Date(timeIntervalSince1970: 1_000_000 / 1000)
    private static let stride = 0.655

    private static func started() throws -> Session {
        try Session.start(at: now, strideM: stride)
    }

    // MARK: - AC-1: validación de strideM

    @Test("session-v3-tests.js:52 · la sesión conserva la zancada")
    func keepsStride() throws {
        #expect(try Self.started().strideM == Self.stride)
    }

    @Test("session-v3-tests.js:53 · strideM = 0 se rechaza")
    func zeroStrideThrows() {
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try Session.start(at: Self.now, strideM: 0)
        }
    }

    @Test("session-v3-tests.js:54 · strideM = −1 se rechaza")
    func negativeStrideThrows() {
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try Session.start(at: Self.now, strideM: -1)
        }
    }

    /// El JS distingue `TypeError`; en Swift es el mismo `invalidValue`.
    @Test("session-v3-tests.js:55 · strideM = NaN se rechaza")
    func nanStrideThrows() {
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try Session.start(at: Self.now, strideM: .nan)
        }
    }

    // MARK: - AC-2: estado inicial

    @Test("session-v3-tests.js:65 · stepsMeasured = 0")
    func measuredStepsStartAtZero() throws {
        #expect(try Self.started().stepsMeasured == 0)
    }

    @Test("session-v3-tests.js:66 · stepsEstimated = 0")
    func estimatedStepsStartAtZero() throws {
        #expect(try Self.started().stepsEstimated == 0)
    }

    /// `:52` afirma que la zancada se conserva al crear; `:67` la repasa como parte del
    /// estado inicial completo, junto a los contadores y el estado.
    @Test("session-v3-tests.js:67 · estado inicial con strideM = STRIDE")
    func initialStateStride() throws {
        let session = try Self.started()
        #expect(session.strideM == Self.stride)
        #expect(session.status == .active)
        #expect(session.stepsMeasured == 0 && session.stepsEstimated == 0)
    }

    @Test("session-v3-tests.js:69 · status = active")
    func startsActive() throws {
        #expect(try Self.started().status == .active)
    }

    @Test("session-v3-tests.js:70 · startedAt = ahora")
    func startedAtIsNow() throws {
        #expect(try Self.started().startedAt == Self.now)
    }

    @Test("session-v3-tests.js:73 · pausas = 0")
    func noPauses() throws {
        #expect(try Self.started().totalPausesS == 0)
    }

    @Test("session-v3-tests.js:74 · sin endedAt")
    func noEndedAt() throws {
        #expect(try Self.started().endedAt == nil)
    }

    // MARK: - Propios de la plataforma nativa

    /// La matriz de la 1.1 exige también el infinito, que `Number.isFinite` rechaza en
    /// la v3 pero ningún test JS afirma: no cita sitio.
    @Test("Nativo · strideM infinito se rechaza", arguments: [Double.infinity, -.infinity])
    func infiniteStrideThrows(stride: Double) {
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try Session.start(at: Self.now, strideM: stride)
        }
    }

    @Test("Nativo · source = ios (domain-model.md §7)")
    func sourceIsIOS() throws {
        #expect(try Self.started().source == .ios)
    }
}
