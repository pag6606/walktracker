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
        let root = CompositionRoot(
            clock: ClockStub(now: now), motion: MotionStub(status: .granted), storage: storage,
            location: LocationStub(status: .denied), weather: WeatherStub()
        )

        await root.sessionStore.restoreOnLaunch()

        let session = try #require(root.sessionStore.session)
        #expect(storage.loadCount == 1)
        #expect(session.status == .active)
        #expect(!session.recovered)
        #expect(session.stepsMeasured == 4000)
    }

    @Test("El store recibe la ubicación y el clima del composition root: al iniciar, el clima del WeatherPort llega a la sesión")
    func storeGetsLocationAndWeather() async throws {
        let location = LocationStub(status: .granted)
        let weather = WeatherStub()
        let root = CompositionRoot(
            clock: ClockStub(now: Date(timeIntervalSince1970: 1_800_000_000)), motion: MotionStub(status: .granted),
            storage: StorageStub(), location: location, weather: weather
        )

        await root.sessionStore.start()
        await waitUntil { root.sessionStore.session?.weather != nil }

        #expect(location.readCount == 1)
        #expect(weather.requested.count == 1)
        #expect(root.sessionStore.session?.weather?.wmoCode == 61)
        #expect(root.sessionStore.weatherStepTimeoutS == 3, "el tope de AR-12, en cada paso")
    }
}
