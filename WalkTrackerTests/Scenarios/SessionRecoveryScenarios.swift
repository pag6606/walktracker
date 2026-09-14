import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Escenarios de la 1.6 portados a mano desde `test/session-v3-tests.js` (AD-6), más la
/// restauración y la sesión huérfana (AD-18) sobre el agregado. Cada test portado cita el
/// sitio de aserción que porta; `inventory.json` los atribuye a la 1.6.
///
/// `restoreV3Session` de la v3 se reparte en dos fronteras: la forma del JSON (su
/// `TypeError`) la valida `ActiveSessionFileAdapter.decode(_:)`, y los rangos (su
/// `RangeError`), `Session.restore(...)` con `DomainError.invalidValue`. La `distanceM` que la
/// v3 guarda sale de `metrics(at:)`.
@Suite("Escenarios 1.6 · recuperación foreground")
struct SessionRecoveryScenarios {

    /// `const NOW = 1000000` (ms) y `const STRIDE = 0.655` de la suite JS.
    private static let now = Date(timeIntervalSince1970: 1_000_000 / 1000)
    private static let stride = 0.655

    /// El snapshot de AC-12: `{2450, 320, 60000 ms, activa, 0.655}`.
    private static func restoredAC12() throws -> Session {
        try Session.restore(
            startedAt: now,
            stepsMeasured: 2450,
            stepsEstimated: 320,
            totalPausesS: 60,
            paused: false,
            pausedAt: nil,
            strideM: stride,
            systemDistanceM: nil
        )
    }

    private static func restore(
        startedAt: Date = now,
        stepsMeasured: Int = 0,
        stepsEstimated: Int = 0,
        totalPausesS: TimeInterval = 0,
        paused: Bool = false,
        pausedAt: Date? = nil,
        strideM: Double = stride,
        systemDistanceM: Double? = nil
    ) throws(DomainError) -> Session {
        try Session.restore(
            startedAt: startedAt,
            stepsMeasured: stepsMeasured,
            stepsEstimated: stepsEstimated,
            totalPausesS: totalPausesS,
            paused: paused,
            pausedAt: pausedAt,
            strideM: strideM,
            systemDistanceM: systemDistanceM
        )
    }

    // MARK: - Portados de la v3 · AC-12

    @Test("session-v3-tests.js:257 · stepsMeasured restaurado")
    func stepsMeasuredRestored() throws {
        #expect(try Self.restoredAC12().stepsMeasured == 2450)
    }

    @Test("session-v3-tests.js:258 · stepsEstimated restaurado")
    func stepsEstimatedRestored() throws {
        #expect(try Self.restoredAC12().stepsEstimated == 320)
    }

    @Test("session-v3-tests.js:259 · strideM restaurada")
    func strideRestored() throws {
        #expect(try Self.restoredAC12().strideM == Self.stride)
    }

    @Test("session-v3-tests.js:260 · status = active")
    func statusRestored() throws {
        let session = try Self.restoredAC12()
        #expect(session.status == .active)
        #expect(session.pausedAt == nil)
        #expect(session.totalPausesS == 60)
        #expect(!session.recovered)
    }

    @Test("session-v3-tests.js:262 · distanceM derivada = (2450 + 320) × zancada")
    func distanceDerived() throws {
        let distance = try Self.restoredAC12().metrics(at: Self.now).distanceM
        let expected = ((2450.0 + 320) * Self.stride * 100).rounded() / 100
        #expect(abs(distance - expected) < 0.01)
    }

    // MARK: - Portados de la v3 · AC-13 (snapshot inválido)

    @Test("session-v3-tests.js:270 · snapshot null → malformed en la frontera del adapter")
    func nullSnapshotIsMalformed() {
        #expect { try ActiveSessionFileAdapter.decode(Data("null".utf8)) } throws: { error in
            guard case StorageError.malformed = error else { return false }
            return true
        }
    }

    @Test("session-v3-tests.js:271 · snapshot vacío {} → malformed en la frontera del adapter")
    func emptySnapshotIsMalformed() {
        #expect { try ActiveSessionFileAdapter.decode(Data("{}".utf8)) } throws: { error in
            guard case StorageError.malformed = error else { return false }
            return true
        }
    }

    @Test("session-v3-tests.js:272 · sin strideM → malformed en la frontera del adapter")
    func missingStrideIsMalformed() {
        let json = #"{ "schemaVersion": 1, "startedAtMs": 0, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#
        #expect { try ActiveSessionFileAdapter.decode(Data(json.utf8)) } throws: { error in
            guard case StorageError.malformed = error else { return false }
            return true
        }
    }

    @Test("session-v3-tests.js:273 · strideM = 0 → invalidValue(strideM) en el dominio")
    func zeroStrideThrows() {
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try Self.restore(startedAt: Date(timeIntervalSince1970: 0), strideM: 0)
        }
    }

    @Test("session-v3-tests.js:274 · strideM = -1 → invalidValue(strideM) en el dominio")
    func negativeStrideThrows() {
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try Self.restore(startedAt: Date(timeIntervalSince1970: 0), strideM: -1)
        }
    }

    // MARK: - Restaurar

    @Test("Restaurar activa: el tiempo se recalcula desde startedAt; 20 min con 60 s de pausas → 1140 s")
    func restoredActiveTimeFromStart() throws {
        let session = try Self.restore(stepsMeasured: 1500, totalPausesS: 60)
        #expect(session.elapsedS(at: Self.now.addingTimeInterval(20 * 60)) == 1140)
    }

    @Test("Restaurar pausada: paused, con el tiempo congelado en pausedAt")
    func restoredPausedIsFrozen() throws {
        let pausedAt = Self.now.addingTimeInterval(600)
        var session = try Self.restore(stepsMeasured: 800, totalPausesS: 60, paused: true, pausedAt: pausedAt)

        #expect(session.status == .paused)
        #expect(session.pausedAt == pausedAt)
        #expect(session.elapsedS(at: pausedAt.addingTimeInterval(3600)) == 540)
        // Y reanuda con normalidad: la pausa abierta se acumula.
        try session.resume(at: pausedAt.addingTimeInterval(120))
        #expect(session.totalPausesS == 180)
        #expect(session.elapsedS(at: pausedAt.addingTimeInterval(180)) == 600)
    }

    @Test("Restaurar conserva la distancia del sistema")
    func restoredKeepsSystemDistance() throws {
        let session = try Self.restore(stepsMeasured: 1000, systemDistanceM: 700.5)
        #expect(session.systemDistanceM == 700.5)
        #expect(session.metrics(at: Self.now.addingTimeInterval(600)).distanceM == 700.5)
    }

    @Test("Snapshot inválido: pasos, pausas o distancia fuera de rango → invalidValue con su campo")
    func invalidRangesThrow() {
        #expect(throws: DomainError.invalidValue(field: "stepsMeasured")) { try Self.restore(stepsMeasured: -1) }
        #expect(throws: DomainError.invalidValue(field: "stepsEstimated")) { try Self.restore(stepsEstimated: -1) }
        #expect(throws: DomainError.invalidValue(field: "totalPausesS")) { try Self.restore(totalPausesS: -1) }
        #expect(throws: DomainError.invalidValue(field: "totalPausesS")) { try Self.restore(totalPausesS: .nan) }
        #expect(throws: DomainError.invalidValue(field: "totalPausesS")) { try Self.restore(totalPausesS: .infinity) }
        #expect(throws: DomainError.invalidValue(field: "distanceM")) { try Self.restore(systemDistanceM: -0.1) }
        #expect(throws: DomainError.invalidValue(field: "distanceM")) { try Self.restore(systemDistanceM: .nan) }
        #expect(throws: DomainError.invalidValue(field: "strideM")) { try Self.restore(strideM: .infinity) }
    }

    @Test("Snapshot inválido: pausedAt si y solo si está pausada")
    func pausedAtIffPaused() {
        #expect(throws: DomainError.invalidValue(field: "pausedAt")) { try Self.restore(paused: true, pausedAt: nil) }
        #expect(throws: DomainError.invalidValue(field: "pausedAt")) {
            try Self.restore(paused: false, pausedAt: Self.now.addingTimeInterval(60))
        }
    }

    // MARK: - Sesión huérfana (AD-18)

    @Test("Huérfana activa: se cierra en el último dato real (+40 min), finished y recovered")
    func orphanActiveClosesAtLastData() throws {
        var session = try Self.restore(stepsMeasured: 4000)
        let lastData = Self.now.addingTimeInterval(40 * 60)

        try session.closeOrphan(at: lastData)

        #expect(session.status == .finished)
        #expect(session.recovered)
        #expect(session.endedAt == lastData)
        #expect(session.durationS == 2400)
        #expect(session.stepsMeasured == 4000)
        #expect(session.stepsEstimated == 0, "sin estimar")
    }

    @Test("Huérfana pausada: la pausa abierta cuenta 0 y la duración queda en el tramo real")
    func orphanPausedKeepsRealStretch() throws {
        let lastData = Self.now.addingTimeInterval(30 * 60)
        var session = try Self.restore(
            stepsMeasured: 3000,
            totalPausesS: 120,
            paused: true,
            pausedAt: Self.now.addingTimeInterval(35 * 60)
        )

        try session.closeOrphan(at: lastData)

        #expect(session.status == .finished)
        #expect(session.recovered)
        #expect(session.durationS == 1680, "30 min − 2 min de pausas cerradas")
        #expect(session.pausesS == 120)
        #expect(session.pausedAt == nil)
    }

    @Test("finish normal no marca recovered; cerrar como huérfana una finalizada lanza y no muta")
    func orphanOnFinishedThrows() throws {
        var session = try Self.restore(stepsMeasured: 100)
        try session.finish(at: Self.now.addingTimeInterval(600))
        #expect(!session.recovered)
        let before = session

        #expect(throws: DomainError.invalidTransition(from: "finished", to: "finished")) {
            try session.closeOrphan(at: Self.now.addingTimeInterval(900))
        }
        #expect(session == before)
    }
}
