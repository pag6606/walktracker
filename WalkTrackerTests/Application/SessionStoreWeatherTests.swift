import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 2.1 sobre `SessionStore`: la captura del clima en paralelo con la apertura, su
/// tope, la escritura por el store, la pre-pantalla de ubicación y la recuperación con clima.
/// Ubicación y clima son un `LocationStub` y un `WeatherStub`: ningún test sale a la red.
@MainActor
@Suite("SessionStore · clima del inicio")
struct SessionStoreWeatherTests: SessionStoreSuite {

    private typealias Fixture = SessionStoreFixture

    private static func fixture(
        location: LocationStub = LocationStub(status: .granted),
        weather: WeatherStub = WeatherStub(),
        storage: StorageStub = StorageStub(),
        stepTimeoutS: TimeInterval = 5
    ) -> Fixture {
        Fixture(storage: storage, location: location, weather: weather, weatherStepTimeoutS: stepTimeoutS)
    }

    // MARK: - Con red y permiso

    @Test("Con red y permiso: la sesión abre al instante y el clima llega después, WMO 61 → rain, 18 °C, capturedAt del reloj")
    func capturesWeather() async throws {
        let weather = WeatherStub(response: .hang)
        let fixture = Self.fixture(weather: weather)

        await fixture.store.start()

        // Abierta y contando antes de que responda la red.
        #expect(fixture.store.hasSession)
        #expect(fixture.session?.status == .active)
        #expect(fixture.store.isCountingSteps)
        #expect(fixture.session?.weather == nil)
        #expect(fixture.store.isCapturingWeather)
        #expect(fixture.store.startFailure == nil)
        fixture.motion.emit(steps: 12)
        await waitUntil { fixture.steps == 12 }

        await waitUntil { weather.hasPendingRequest }
        fixture.clock.advance(by: 2)
        weather.resolvePendingRequests(with: .reading(WeatherStub.rainyReading))
        await waitUntil { fixture.session?.weather != nil }

        let snapshot = try #require(fixture.session?.weather)
        #expect(snapshot.wmoCode == 61)
        #expect(snapshot.condition == .rain)
        #expect(snapshot.tempC == 18)
        #expect(snapshot.feelsLikeC == 17.5)
        #expect(snapshot.humidityPct == 82)
        #expect(snapshot.uvIndex == 1.5)
        #expect(snapshot.windKmh == 12.4)
        #expect(snapshot.capturedAt == Self.t0.addingTimeInterval(2))
        #expect(!fixture.store.isCapturingWeather)
        #expect(fixture.session?.stepsMeasured == 12, "el clima no toca los pasos")
        #expect(weather.requested == [Coordinates(latitude: 40.42, longitude: -3.70)], "el clima se pide con lo que dio el LocationPort")
        #expect(fixture.location.requestCount == 0, "con el permiso concedido no se pide nada")
        #expect(fixture.store.locationPrompt == nil)
    }

    @Test("Guardado al llegar: el snapshot de la sesión lleva el clima")
    func persistsOnArrival() async throws {
        let fixture = Self.fixture()

        await fixture.store.start()
        await waitUntil { fixture.session?.weather != nil }

        let saved = try #require(fixture.storage.snapshot)
        #expect(saved.weather == fixture.session?.weather)
        #expect(saved.weather?.wmoCode == 61)
    }

    @Test("Sin lluvia: WMO 3 → condición other, wmoCode 3")
    func notRain() async throws {
        let fixture = Self.fixture(weather: WeatherStub(response: .reading(
            WeatherReading(tempC: 22, feelsLikeC: 22, wmoCode: 3, humidityPct: 40, uvIndex: 5, windKmh: 3)
        )))

        await fixture.store.start()
        await waitUntil { fixture.session?.weather != nil }

        let snapshot = try #require(fixture.session?.weather)
        #expect(snapshot.condition == .other)
        #expect(snapshot.wmoCode == 3)
    }

    @Test("Congelado: el clima se captura una vez por sesión; pausar, reanudar y volver de background no lo piden otra vez")
    func capturedOnce() async throws {
        let fixture = Self.fixture()
        await fixture.store.start()
        await waitUntil { fixture.session?.weather != nil }
        let first = try #require(fixture.session?.weather)

        fixture.clock.advance(by: 60)
        fixture.store.pause()
        fixture.store.resume()
        fixture.store.appDidEnterBackground()
        await fixture.store.appDidBecomeActive()

        #expect(fixture.weather.requested.count == 1)
        #expect(fixture.location.readCount == 1)
        #expect(fixture.session?.weather == first)
    }

    // MARK: - Degradación

    @Test("Sin red, HTTP ≠ 200 o JSON inválido: sesión sin clima y sin error", arguments: [
        CapabilityError.failed(operation: "network"), .failed(operation: "http 500"), .failed(operation: "decode"),
    ])
    func weatherFailure(error: CapabilityError) async throws {
        let fixture = Self.fixture(weather: WeatherStub(response: .failure(error)))

        await fixture.store.start()
        await waitUntil { !fixture.store.isCapturingWeather }

        #expect(fixture.store.hasSession)
        #expect(fixture.session?.status == .active)
        #expect(fixture.session?.weather == nil)
        #expect(fixture.store.startFailure == nil)
        #expect(fixture.storage.snapshot?.weather == nil)
    }

    @Test("Sin ubicación: sesión sin clima, sin pedir el clima")
    func locationFailure() async {
        let location = LocationStub(status: .granted, response: .failure(.failed(operation: "locationTimeout")))
        let fixture = Self.fixture(location: location)

        await fixture.store.start()
        await waitUntil { !fixture.store.isCapturingWeather }

        #expect(fixture.session?.weather == nil)
        #expect(fixture.weather.requested.isEmpty)
        #expect(fixture.store.startFailure == nil)
    }

    @Test("Timeout: Open-Meteo no responde dentro del tope → sin clima; la respuesta tardía se ignora")
    func timeoutIgnoresLateResponse() async {
        let weather = WeatherStub(response: .hang)
        let fixture = Self.fixture(weather: weather, stepTimeoutS: 0.05)

        await fixture.store.start()
        await waitUntil { !fixture.store.isCapturingWeather }
        #expect(fixture.session?.weather == nil)

        weather.resolvePendingRequests(with: .reading(WeatherStub.rainyReading))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fixture.session?.weather == nil)
        #expect(fixture.store.hasSession)
    }

    @Test("Un tope por paso: una ubicación de 2 s y un clima de 2 s con topes de 3 s llegan, aunque sumen más de 3 s")
    func timeoutPerStep() async throws {
        // A escala: topes de 0,3 s y cada paso de 0,2 s; juntos, 0,4 s superan un tope.
        let location = LocationStub(status: .granted, response: .delayed(Coordinates(latitude: 40.42, longitude: -3.70), seconds: 0.2))
        let weather = WeatherStub(response: .delayed(WeatherStub.rainyReading, seconds: 0.2))
        let fixture = Self.fixture(location: location, weather: weather, stepTimeoutS: 0.3)

        await fixture.store.start()
        await waitUntil { !fixture.store.isCapturingWeather }

        #expect(fixture.session?.weather?.wmoCode == 61)
    }

    @Test("Una ubicación colgada agota su tope: sin clima y sin pedir el clima")
    func hangingLocationTimesOut() async {
        let location = LocationStub(status: .granted, response: .hang)
        let fixture = Self.fixture(location: location, stepTimeoutS: 0.05)

        await fixture.store.start()
        await waitUntil { !fixture.store.isCapturingWeather }

        #expect(fixture.session?.weather == nil)
        #expect(fixture.weather.requested.isEmpty)
        location.resolvePendingReads(with: .coordinates(Coordinates(latitude: 1, longitude: 1)))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fixture.weather.requested.isEmpty, "la ubicación tardía no llega a pedir el clima")
        #expect(fixture.session?.weather == nil)
    }

    @Test("Un clima colgado tras una ubicación a tiempo agota su propio tope: sin clima")
    func hangingWeatherTimesOut() async {
        let weather = WeatherStub(response: .hang)
        let fixture = Self.fixture(
            location: LocationStub(status: .granted, response: .delayed(Coordinates(latitude: 40.42, longitude: -3.70), seconds: 0.03)),
            weather: weather,
            stepTimeoutS: 0.05
        )

        await fixture.store.start()
        await waitUntil { !fixture.store.isCapturingWeather }

        #expect(weather.requested.count == 1)
        #expect(fixture.session?.weather == nil)
        weather.resolvePendingRequests(with: .reading(WeatherStub.rainyReading))
    }

    @Test("Finalizar mientras se lee la ubicación: no se llega a pedir el clima")
    func cancelledBetweenSteps() async {
        let location = LocationStub(status: .granted, response: .hang)
        let fixture = Self.fixture(location: location)
        await fixture.store.start()
        await waitUntil { location.hasPendingRead }

        await fixture.store.confirmFinish()
        location.resolvePendingReads(with: .coordinates(Coordinates(latitude: 1, longitude: 1)))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(fixture.weather.requested.isEmpty)
        #expect(fixture.session?.weather == nil)
    }

    @Test("Clima durante una reconciliación: queda en la sesión y en el snapshot guardado al terminar appDidBecomeActive()")
    func weatherDuringReconciliation() async throws {
        let weather = WeatherStub(response: .hang)
        let fixture = Self.fixture(weather: weather)
        await fixture.startWalking(steps: 100)
        await waitUntil { weather.hasPendingRequest }
        fixture.motion.setQueryResponse(.hang)
        fixture.clock.advance(by: 60)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 120)

        let becameActive = Task { await fixture.store.appDidBecomeActive() }
        await waitUntil { fixture.motion.hasPendingQuery }
        #expect(fixture.store.isReconciling)

        weather.resolvePendingRequests(with: .reading(WeatherStub.rainyReading))
        await waitUntil { fixture.session?.weather != nil }
        #expect(fixture.storage.snapshot?.weather == nil, "no se guarda a mitad de la reconciliación")

        fixture.motion.resolvePendingQueries(with: .sample(steps: 250, distance: nil))
        await becameActive.value

        let session = try #require(fixture.session)
        #expect(!fixture.store.isReconciling)
        #expect(session.stepsMeasured == 250)
        #expect(session.weather?.wmoCode == 61, "la reconciliación conserva el clima que llegó durante la espera")
        #expect(fixture.storage.snapshot?.weather == session.weather)
        #expect(fixture.storage.snapshot?.stepsMeasured == 250)
    }

    @Test("Permiso denegado, restringido o sin ubicación: no se pide ubicación ni clima, sin pre-pantalla, en varias sesiones",
          arguments: [PermissionStatus.denied, .restricted, .unavailable])
    func deniedNeverAsks(status: PermissionStatus) async {
        let fixture = Self.fixture(location: LocationStub(status: status))

        for _ in 0..<3 {
            await fixture.store.start()
            #expect(fixture.store.hasSession)
            #expect(fixture.store.locationPrompt == nil)
            #expect(!fixture.store.isCapturingWeather)
            await fixture.store.confirmFinish()
            fixture.store.leaveSummary()
        }

        #expect(fixture.location.requestCount == 0)
        #expect(fixture.location.readCount == 0)
        #expect(fixture.weather.requested.isEmpty)
    }

    // MARK: - Sesión cerrada

    @Test("Clima tras finalizar: la sesión termina antes de que llegue → no se escribe en la finalizada")
    func noWeatherAfterFinish() async throws {
        let weather = WeatherStub(response: .hang)
        let fixture = Self.fixture(weather: weather)
        await fixture.store.start()
        await waitUntil { weather.hasPendingRequest }

        await fixture.store.confirmFinish()
        #expect(!fixture.store.isCapturingWeather)
        weather.resolvePendingRequests(with: .reading(WeatherStub.rainyReading))
        try? await Task.sleep(for: .milliseconds(50))

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.weather == nil)
        #expect(fixture.storage.snapshot == nil, "el clima tardío no resucita el snapshot borrado")
    }

    @Test("Un clima tardío de una sesión no llega a la siguiente, ni cierra su captura")
    func lateWeatherDoesNotReachNextSession() async throws {
        let weather = WeatherStub(response: .hang)
        let fixture = Self.fixture(weather: weather)
        await fixture.store.start()
        await waitUntil { weather.hasPendingRequest }
        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()

        fixture.clock.advance(by: 600)
        await fixture.store.start()
        await waitUntil { weather.pendingRequestCount == 2 }

        // Solo la petición de la sesión anterior responde: la nueva sigue esperando la suya.
        weather.resolveOldestPendingRequest(with: .reading(WeatherStub.rainyReading))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fixture.store.isCapturingWeather)
        #expect(fixture.session?.weather == nil)
        #expect(fixture.session?.startedAt == Self.t0.addingTimeInterval(600))

        weather.resolveOldestPendingRequest(with: .reading(
            WeatherReading(tempC: 25, feelsLikeC: 26, wmoCode: 1, humidityPct: 30, uvIndex: 6, windKmh: 5)
        ))
        await waitUntil { fixture.session?.weather != nil }

        #expect(fixture.session?.weather?.wmoCode == 1)
        #expect(fixture.session?.weather?.capturedAt == Self.t0.addingTimeInterval(600))
        #expect(!fixture.store.isCapturingWeather)
    }

    // MARK: - Recuperación

    @Test("Recuperación: force-quit con clima capturado y relanzar → la sesión restaurada conserva el clima, sin capturar otro")
    func relaunchKeepsWeather() async throws {
        let storage = StorageStub()
        let first = Self.fixture(storage: storage)
        await first.store.start()
        await waitUntil { first.session?.weather != nil }
        let captured = try #require(first.session?.weather)

        let relaunched = Self.fixture(weather: WeatherStub(response: .failure(.failed(operation: "network"))), storage: storage)
        relaunched.clock.set(Self.t0.addingTimeInterval(120))
        await relaunched.store.restoreOnLaunch()

        #expect(relaunched.session?.weather == captured)
        #expect(relaunched.store.hasSession)
        #expect(relaunched.weather.requested.isEmpty)
        #expect(!relaunched.store.isCapturingWeather)
        #expect(relaunched.storage.snapshot?.weather == captured)
    }

    @Test("Una sesión restaurada sin clima no lo captura ni muestra la pre-pantalla")
    func restoredWithoutWeatherStaysWithout() async {
        let storage = StorageStub()
        let first = Self.fixture(location: LocationStub(status: .denied), storage: storage)
        await first.store.start()

        let relaunched = Self.fixture(location: LocationStub(status: .notDetermined), storage: storage)
        await relaunched.store.restoreOnLaunch()

        #expect(relaunched.store.hasSession)
        #expect(relaunched.session?.weather == nil)
        #expect(relaunched.store.locationPrompt == nil)
        #expect(relaunched.location.readCount == 0)
    }

    // MARK: - Pre-pantalla

    @Test("Pre-pantalla · Permitir: sesión abierta y contando; la captura empieza al conceder y el clima llega")
    func promptAllow() async throws {
        let location = LocationStub(status: .notDetermined, requestAnswer: .granted)
        let fixture = Self.fixture(location: location)

        await fixture.store.start()

        #expect(fixture.store.hasSession)
        #expect(fixture.store.isCountingSteps)
        #expect(fixture.store.locationPrompt == .offering)
        #expect(!fixture.store.isCapturingWeather)
        #expect(location.readCount == 0, "nada se pide antes de Permitir")
        fixture.motion.emit(steps: 30)
        await waitUntil { fixture.steps == 30 }

        fixture.clock.advance(by: 8)
        await fixture.store.confirmLocationPermission()

        #expect(location.requestCount == 1)
        #expect(fixture.store.locationPrompt == nil)
        await waitUntil { fixture.session?.weather != nil }
        #expect(fixture.session?.weather?.capturedAt == Self.t0.addingTimeInterval(8))
        #expect(fixture.steps == 30)
    }

    @Test("Pre-pantalla · Permitir y denegado en el diálogo: sin clima y no vuelve a preguntar")
    func promptAllowThenDenied() async {
        let location = LocationStub(status: .notDetermined, requestAnswer: .denied)
        let fixture = Self.fixture(location: location)

        await fixture.store.start()
        await fixture.store.confirmLocationPermission()

        #expect(fixture.store.locationPrompt == nil)
        #expect(!fixture.store.isCapturingWeather)
        #expect(fixture.session?.weather == nil)

        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        await fixture.store.start()
        #expect(fixture.store.locationPrompt == nil)
        #expect(location.requestCount == 1)
        #expect(location.readCount == 0)
    }

    @Test("Pre-pantalla · Ahora no: sin clima, y en otra caminata de la misma ejecución no vuelve a salir")
    func promptDecline() async {
        let location = LocationStub(status: .notDetermined)
        let fixture = Self.fixture(location: location)

        await fixture.store.start()
        #expect(fixture.store.locationPrompt == .offering)
        fixture.store.declineLocationPermission()

        #expect(fixture.store.locationPrompt == nil)
        #expect(fixture.session?.weather == nil)
        #expect(fixture.store.hasSession, "la sesión sigue")

        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        await fixture.store.start()

        #expect(fixture.store.hasSession)
        #expect(fixture.store.locationPrompt == nil)
        #expect(fixture.session?.weather == nil)
        #expect(location.requestCount == 0)
        #expect(location.readCount == 0)
        #expect(fixture.weather.requested.isEmpty)
    }

    @Test("Pre-pantalla sin responder: finalizar la quita, y la siguiente caminata vuelve a ofrecerla")
    func promptClearedOnFinish() async {
        let fixture = Self.fixture(location: LocationStub(status: .notDetermined))

        await fixture.store.start()
        #expect(fixture.store.locationPrompt == .offering)
        await fixture.store.confirmFinish()
        #expect(fixture.store.locationPrompt == nil)

        fixture.store.leaveSummary()
        await fixture.store.start()
        #expect(fixture.store.locationPrompt == .offering)
    }

    @Test("La pre-pantalla no bloquea los controles: pausar, reanudar y contar con ella en pantalla")
    func promptDoesNotBlock() async throws {
        let fixture = Self.fixture(location: LocationStub(status: .notDetermined))
        await fixture.store.start()
        #expect(fixture.store.locationPrompt == .offering)

        fixture.motion.emit(steps: 40)
        await waitUntil { fixture.steps == 40 }
        fixture.clock.advance(by: 30)
        fixture.store.pause()
        #expect(fixture.session?.status == .paused)
        fixture.store.resume()
        #expect(fixture.session?.status == .active)
        #expect(fixture.store.locationPrompt == .offering)
    }

    @Test("Diálogo del sistema que nunca responde: \"Ahora no\" quita la pre-pantalla, y la respuesta tardía no reabre ni captura")
    func declineWhileRequesting() async {
        let location = LocationStub(status: .notDetermined, requestAnswer: nil)
        let fixture = Self.fixture(location: location)
        await fixture.store.start()

        let allow = Task { await fixture.store.confirmLocationPermission() }
        await waitUntil { location.hasPendingRequest }
        #expect(fixture.store.locationPrompt == .requesting)

        fixture.store.declineLocationPermission()
        #expect(fixture.store.locationPrompt == nil)

        location.resolvePermissionRequest(with: .granted)
        await allow.value
        #expect(fixture.store.locationPrompt == nil)
        #expect(!fixture.store.isCapturingWeather)
        #expect(location.readCount == 0)
        #expect(fixture.session?.weather == nil)

        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        location.setStatus(.notDetermined)
        await fixture.store.start()
        #expect(fixture.store.locationPrompt == nil, "cuenta como \"Ahora no\" de esta ejecución")
    }

    @Test("Las intenciones de la pre-pantalla sin pre-pantalla no hacen nada")
    func promptIntentsWithoutPrompt() async {
        let location = LocationStub(status: .notDetermined)
        let fixture = Self.fixture(location: location)

        await fixture.store.confirmLocationPermission()
        fixture.store.declineLocationPermission()

        #expect(location.requestCount == 0)
        await fixture.store.start()
        #expect(fixture.store.locationPrompt == .offering, "declinar sin pre-pantalla no cuenta como \"Ahora no\"")
    }
}
