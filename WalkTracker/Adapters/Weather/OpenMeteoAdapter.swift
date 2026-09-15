import Domain
import Foundation
import OSLog

/// `WeatherPort` sobre la API pública de Open-Meteo (CAP-5) — AD-10, AR-12, AD-24.
///
/// **La única llamada de red del producto.** HTTPS del sistema (`URLSession`) contra
/// `api.open-meteo.com`, sin clave, sin cuenta y sin dependencias. La petición solo lleva las
/// coordenadas ya redondeadas por el `LocationPort` y los campos del clima actual
/// (`climate.js:91-133`). Los datos son CC-BY 4.0: la UI muestra "Datos: Open-Meteo" (AD-24).
///
/// **Tope.** La petición se abandona a los 3 s (`timeoutS`): el temporizador compite con ella
/// y, al ganar, la cancela. Una respuesta tardía se descarta.
///
/// **Errores.** Sin red, HTTP ≠ 200, JSON inválido o timeout salen como `failed`; nunca un
/// error crudo de `URLSession` ni de `JSONDecoder`.
struct OpenMeteoAdapter: WeatherPort {

    /// Tope de la petición (AR-12, v3 AD-14: 3 s).
    static let defaultTimeoutS: TimeInterval = 3
    static let endpoint = URL(string: "https://api.open-meteo.com/v1/forecast")!
    /// Campos del clima actual que se piden, en el orden de la v3.
    static let currentFields = "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,uv_index"

    private let session: URLSession
    private let timeoutS: TimeInterval
    private let log = Logger(subsystem: "com.walktracker.app", category: "Weather")

    /// - Parameters:
    ///   - session: la sesión de URL; los tests pasan una con un `URLProtocol` propio.
    ///   - timeoutS: tope de la petición.
    init(session: URLSession? = nil, timeoutS: TimeInterval = OpenMeteoAdapter.defaultTimeoutS) {
        self.timeoutS = timeoutS
        self.session = session ?? Self.makeSession(timeoutS: timeoutS)
    }

    /// Sesión efímera: sin caché ni cookies en disco, sin esperar a que haya red.
    private static func makeSession(timeoutS: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutS
        configuration.timeoutIntervalForResource = timeoutS
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }

    // MARK: - WeatherPort

    func currentWeather(at coordinates: Coordinates) async throws(CapabilityError) -> WeatherReading {
        let request = Self.request(for: coordinates, timeoutS: timeoutS)
        let session = self.session
        let timeoutS = self.timeoutS
        let outcome: Result<(Data, URLResponse), CapabilityError> = await withTaskGroup(
            of: Result<(Data, URLResponse), CapabilityError>?.self
        ) { group in
            group.addTask {
                do {
                    return .success(try await session.data(for: request))
                } catch let error as URLError where error.code == .timedOut {
                    return .failure(.failed(operation: "timeout"))
                } catch {
                    return Task.isCancelled ? nil : .failure(.failed(operation: "network"))
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutS))
                return Task.isCancelled ? nil : .failure(.failed(operation: "timeout"))
            }
            // El primero que termina decide; cancelar al otro libera la petición o el temporizador.
            var first: Result<(Data, URLResponse), CapabilityError>?
            while first == nil, let next = await group.next() {
                first = next
            }
            group.cancelAll()
            return first ?? .failure(.failed(operation: "network"))
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try outcome.get()
        } catch {
            log.info("Clima no disponible: \(String(describing: error), privacy: .public)")
            throw error
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            log.info("Clima no disponible: HTTP \(code, privacy: .public)")
            throw .failed(operation: "http \(code)")
        }
        do {
            return try Self.decode(data)
        } catch {
            log.info("Clima no disponible: respuesta ilegible")
            throw error
        }
    }

    // MARK: - Formato (puro, expuesto para test)

    /// La petición del clima actual en `coordinates`. Las coordenadas van con 2 decimales,
    /// con punto decimal sea cual sea el idioma del dispositivo.
    static func request(for coordinates: Coordinates, timeoutS: TimeInterval = defaultTimeoutS) -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinates.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinates.longitude)),
            URLQueryItem(name: "current", value: currentFields),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutS)
        request.httpMethod = "GET"
        return request
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let relative_humidity_2m: Double
            let weather_code: Int
            let wind_speed_10m: Double
            let uv_index: Double
        }
        let current: Current
    }

    /// JSON de Open-Meteo → lectura. Solo la forma: los rangos los valida `WeatherSnapshot`.
    ///
    /// - Throws: `failed(decode)` si no es JSON, falta `current` o uno de sus campos, o un
    ///   campo es `null` o de otro tipo.
    static func decode(_ data: Data) throws(CapabilityError) -> WeatherReading {
        let current: Response.Current
        do {
            current = try JSONDecoder().decode(Response.self, from: data).current
        } catch {
            throw .failed(operation: "decode")
        }
        return WeatherReading(
            tempC: current.temperature_2m,
            feelsLikeC: current.apparent_temperature,
            wmoCode: current.weather_code,
            humidityPct: current.relative_humidity_2m,
            uvIndex: current.uv_index,
            windKmh: current.wind_speed_10m
        )
    }
}
