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

    @Test("El store recibe el tope de gap estimable de formulas.json: un gap de 25 min no estima y uno de 20 sí")
    func storeGetsMaxEstimableGap() async throws {
        // Comportamental: si el cableado cogiera otra constante (p. ej. las 6 h del umbral de
        // huérfana), el gap de 25 min cabría y estimaría.
        let clock = ClockStub(now: Date(timeIntervalSince1970: 1_800_000_000))
        let motion = MotionStub(status: .granted)
        let root = CompositionRoot(
            clock: clock, motion: motion, storage: StorageStub(),
            location: LocationStub(status: .denied), weather: WeatherStub()
        )
        let store = root.sessionStore
        #expect(store.maxEstimableGapS == root.formulas.maxEstimableGapS)

        await store.start()
        motion.emit(steps: 800)
        await waitUntil { store.session?.stepsMeasured == 800 }
        clock.advance(by: 600)
        store.appDidEnterBackground()
        clock.advance(by: 25 * 60)
        motion.setQueryResponse(.none)
        await store.appDidBecomeActive()
        #expect(store.session?.stepsEstimated == 0, "25 min pasan del tope de 20 de formulas.json")

        // Y con un gap de justo 20 min, la misma degradación sí estima: 800 pasos en 35 min de
        // sesión son 22,9 spm (la cadencia se redondea a un decimal) × 20 min.
        store.appDidEnterBackground()
        clock.advance(by: 20 * 60)
        await store.appDidBecomeActive()
        #expect(store.session?.stepsEstimated == 458)
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
