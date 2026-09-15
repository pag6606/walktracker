import Domain
import Foundation
import OSLog

/// Clima del inicio (2.1, CAP-5, AD-7, AD-11): la pre-pantalla de ubicación sobre la sesión ya
/// abierta, la captura en paralelo con su tope y la escritura del snapshot en la sesión.
///
/// **Nunca bloquea.** La sesión abre y cuenta pasos igual que sin clima: la captura corre en
/// paralelo y, si llega dentro de sus topes, este store la adjunta y guarda el snapshot.
/// Sin red, con el permiso denegado o restringido, sin ubicación o con timeout, la sesión se
/// queda sin clima, sin ningún error visible.
///
/// **Un tope por paso (AR-12).** La lectura de ubicación tiene su tope de `weatherStepTimeoutS`
/// (3 s) y la petición a Open-Meteo el suyo (3 s), como la v3: la captura dura como mucho la suma
/// desde que empieza, al abrir la sesión con el permiso concedido o al concederlo desde la
/// pre-pantalla. Cada carrera va sin `withTaskGroup` (lección de la 1.5): una lectura colgada no
/// retiene la salida.
///
/// Escribe `weatherCapture`, `isCapturingWeather`, `locationPrompt` y
/// `declinedLocationPromptThisLaunch` (solo aquí) y, al llegar el clima, `session` y `metrics`.
extension SessionStore {

    /// Tras abrir una sesión nueva: con el permiso concedido captura el clima; sin decidir y si
    /// Paul no dijo "Ahora no" en esta ejecución, muestra la pre-pantalla; denegado, restringido o
    /// sin ubicación, nada (sin diálogo, sin clima).
    func beginWeatherForNewSession() {
        switch location.status {
        case .granted:
            startWeatherCapture()
        case .notDetermined:
            guard !declinedLocationPromptThisLaunch else { return }
            locationPrompt = .offering
        case .denied, .restricted, .unavailable:
            log.info("Sin permiso de ubicación: la sesión sigue sin clima")
        }
    }

    /// "Permitir" en la pre-pantalla: lanza el diálogo del sistema y, si se concede, empieza la
    /// captura en ese momento, con su tope.
    func confirmLocationPermission() async {
        guard locationPrompt == .offering else { return }
        locationPrompt = .requesting
        let status = await location.requestPermission()
        // La sesión pudo cerrarse, o Paul dijo "Ahora no", con el diálogo pendiente: ya no hay
        // pre-pantalla y la respuesta tardía no reabre nada ni captura.
        guard locationPrompt == .requesting else { return }
        locationPrompt = nil
        if status == .granted {
            startWeatherCapture()
        } else {
            log.info("Permiso de ubicación no concedido (\(String(describing: status), privacy: .public)): sesión sin clima")
        }
    }

    /// "Ahora no" en la pre-pantalla: sin clima en esta sesión, y la pre-pantalla no vuelve a
    /// salir al iniciar mientras la app siga abierta.
    ///
    /// También con el diálogo pedido (`.requesting`): si el sistema nunca responde, es la salida.
    /// La respuesta que llegue después no reabre nada ni captura.
    func declineLocationPermission() {
        guard locationPrompt != nil else { return }
        locationPrompt = nil
        declinedLocationPromptThisLaunch = true
    }

    /// Cancela la captura en curso y quita la pre-pantalla. Al finalizar y en el reset: un clima
    /// que llega después nunca toca una sesión cerrada.
    func cancelWeatherCapture() {
        weatherCapture?.cancel()
        weatherCapture = nil
        isCapturingWeather = false
        locationPrompt = nil
    }

    /// Empieza la captura del clima de la sesión abierta, si aún no tiene y no hay otra en curso.
    private func startWeatherCapture() {
        guard let session, session.status != .finished, session.weather == nil, weatherCapture == nil else { return }
        let location = self.location
        let weather = self.weather
        let stepTimeoutS = weatherStepTimeoutS
        let log = self.log
        let startedAt = session.startedAt
        isCapturingWeather = true
        weatherCapture = Task { [weak self] in
            let reading = await Self.readingWithinTimeouts(location: location, weather: weather, stepTimeoutS: stepTimeoutS, log: log)
            guard !Task.isCancelled, let self else { return }
            self.completeWeatherCapture(reading, forSessionStartedAt: startedAt)
        }
    }

    /// La captura terminó: con lectura, la valida, la adjunta a la sesión todavía abierta y guarda
    /// el snapshot; sin ella, la sesión sigue sin clima.
    private func completeWeatherCapture(_ reading: WeatherReading?, forSessionStartedAt startedAt: Date) {
        weatherCapture = nil
        isCapturingWeather = false
        guard let reading else { return }
        guard var session, session.startedAt == startedAt, session.status != .finished, session.weather == nil else { return }
        let now = clock.now
        do {
            let snapshot = try WeatherSnapshot(
                tempC: reading.tempC,
                feelsLikeC: reading.feelsLikeC,
                wmoCode: reading.wmoCode,
                humidityPct: reading.humidityPct,
                uvIndex: reading.uvIndex,
                windKmh: reading.windKmh,
                capturedAt: now
            )
            try session.attachWeather(snapshot)
        } catch {
            log.error("Clima rechazado en la frontera: \(String(describing: error), privacy: .public)")
            return
        }
        self.session = session
        metrics = session.metrics(at: now)
        persist()
    }

    /// Ubicación y después clima, cada paso con su tope de `stepTimeoutS` (AR-12: 3 s en la
    /// lectura de ubicación y 3 s en Open-Meteo, como la v3). `nil` con cualquier fallo, al agotar
    /// un tope o si la captura se cancela entre los dos pasos.
    private nonisolated static func readingWithinTimeouts(
        location: any LocationPort,
        weather: any WeatherPort,
        stepTimeoutS: TimeInterval,
        log: Logger
    ) async -> WeatherReading? {
        guard let coordinates = await firstWithin(stepTimeoutS, step: "ubicación", log: log, { () async throws(CapabilityError) -> Coordinates in
            try await location.approximateLocation()
        }) else { return nil }
        // Una sesión cerrada mientras se leía la ubicación no llega a pedir el clima.
        guard !Task.isCancelled else { return nil }
        return await firstWithin(stepTimeoutS, step: "clima", log: log) { () async throws(CapabilityError) -> WeatherReading in
            try await weather.currentWeather(at: coordinates)
        }
    }

    /// `operation` acotada por `timeoutS`: el primero que termina gana. Sin `withTaskGroup`
    /// (lección de la 1.5): una operación colgada no retiene la salida; la que pierde se cancela y
    /// su resultado tardío se ignora. Cancelar a quien espera también resuelve `nil`.
    private nonisolated static func firstWithin<Value: Sendable>(
        _ timeoutS: TimeInterval,
        step: String,
        log: Logger,
        _ operation: @escaping @Sendable () async throws(CapabilityError) -> Value
    ) async -> Value? {
        let race = FirstResult<Value?>()
        let work = Task.detached {
            do throws(CapabilityError) {
                race.resolve(try await operation())
            } catch {
                log.info("Sin clima (\(step, privacy: .public)): \(String(describing: error), privacy: .public)")
                race.resolve(nil)
            }
        }
        let timer = Task.detached {
            try? await Task.sleep(for: .seconds(timeoutS))
            if race.resolve(nil) {
                log.info("Sin clima: \(step, privacy: .public) agotó el tope de \(timeoutS, privacy: .public) s")
            }
        }
        let value = await withTaskCancellationHandler {
            await race.value()
        } onCancel: {
            race.resolve(nil)
        }
        timer.cancel()
        work.cancel()
        return value
    }
}
