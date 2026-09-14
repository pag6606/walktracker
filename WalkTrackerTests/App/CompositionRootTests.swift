import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El cableado del composition root que ningún test del store ve.
@MainActor
@Suite("CompositionRoot · cableado del store")
struct CompositionRootTests {

    @Test("El store recibe el almacenamiento y el umbral de huérfana de formulas.json: una sesión de hace 1 h se restaura activa")
    func storeGetsStorageAndOrphanThreshold() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let startedAt = now.addingTimeInterval(-60 * 60)
        let storage = StorageStub(snapshot: ActiveSessionSnapshot(
            startedAt: startedAt, stepsMeasured: 4000, stepsEstimated: 0, totalPausesS: 0, paused: false,
            pausedAt: nil, strideM: 0.655, systemDistanceM: nil, savedAt: now, lastSampleAt: now,
            segmentStart: startedAt, segmentSteps: 4000, distanceBaseM: 0
        ))
        let root = CompositionRoot(clock: ClockStub(now: now), motion: MotionStub(status: .granted), storage: storage)

        await root.sessionStore.restoreOnLaunch()

        let session = try #require(root.sessionStore.session)
        #expect(storage.loadCount == 1)
        #expect(session.status == .active)
        #expect(!session.recovered)
        #expect(session.stepsMeasured == 4000)
    }
}
