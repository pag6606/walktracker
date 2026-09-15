import Domain
import Foundation
import Synchronization
import Testing

@testable import WalkTracker

/// `OpenMeteoAdapter` en el borde (2.1): la URL que sale (solo `api.open-meteo.com` por HTTPS,
/// con las coordenadas a 2 decimales), la decodificación del JSON y cada fallo que deja la
/// sesión sin clima. La red es un `URLProtocol` de test: ningún test sale a Internet.
///
/// En serie: el `URLProtocol` de test responde con un único manejador compartido.
@Suite("OpenMeteoAdapter · clima actual", .serialized)
struct OpenMeteoAdapterTests {

    private static let madrid = Coordinates(latitude: 40.42, longitude: -3.70)

    private static let body = #"""
    {"latitude":40.42,"longitude":-3.7,"timezone":"Europe/Madrid",
     "current_units":{"temperature_2m":"°C"},
     "current":{"time":"2026-09-15T10:00","interval":900,"temperature_2m":18.2,"apparent_temperature":17.4,
                "relative_humidity_2m":82,"weather_code":61,"wind_speed_10m":12.4,"uv_index":1.55}}
    """#

    /// Un adapter sobre una sesión efímera que enruta toda petición a `StubURLProtocol`.
    private static func adapter(timeoutS: TimeInterval = 3) -> OpenMeteoAdapter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OpenMeteoAdapter(session: URLSession(configuration: configuration), timeoutS: timeoutS)
    }

    // MARK: - Petición

    @Test("La petición: HTTPS a api.open-meteo.com/v1/forecast, 40.42 y -3.70, los campos actuales y timezone=auto")
    func requestURL() throws {
        let request = OpenMeteoAdapter.request(for: Self.madrid)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "api.open-meteo.com")
        #expect(components.path == "/v1/forecast")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items == [
            "latitude": "40.42",
            "longitude": "-3.70",
            "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,uv_index",
            "timezone": "auto",
        ])
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 3)
    }

    @Test("Las coordenadas van con 2 decimales y punto decimal, nunca con más precisión")
    func coordinatesFormatting() throws {
        let url = try #require(OpenMeteoAdapter.request(for: Coordinates(latitude: 0, longitude: 7.5)).url?.absoluteString)
        #expect(url.contains("latitude=0.00&longitude=7.50&"))
    }

    // MARK: - Respuesta

    @Test("JSON de Open-Meteo → lectura con WMO, temperaturas, humedad, UV y viento")
    func decodes() throws {
        let reading = try OpenMeteoAdapter.decode(Data(Self.body.utf8))
        #expect(reading == WeatherReading(tempC: 18.2, feelsLikeC: 17.4, wmoCode: 61, humidityPct: 82, uvIndex: 1.55, windKmh: 12.4))
    }

    @Test("JSON inválido, sin current, con un campo null o de otro tipo: failed(decode)", arguments: [
        "", "{", "[]", #"{"latitude":40.42}"#,
        #"{"current":{"temperature_2m":18,"apparent_temperature":17,"relative_humidity_2m":80,"weather_code":61,"wind_speed_10m":10,"uv_index":null}}"#,
        #"{"current":{"temperature_2m":"18","apparent_temperature":17,"relative_humidity_2m":80,"weather_code":61,"wind_speed_10m":10,"uv_index":1}}"#,
        #"{"current":{"apparent_temperature":17,"relative_humidity_2m":80,"weather_code":61,"wind_speed_10m":10,"uv_index":1}}"#,
    ])
    func malformed(json: String) {
        #expect(throws: CapabilityError.failed(operation: "decode")) {
            try OpenMeteoAdapter.decode(Data(json.utf8))
        }
    }

    @Test("Con red: 200 y el JSON → la lectura; la petición que llegó a la red es la de Madrid")
    func fetchesOverNetwork() async throws {
        StubURLProtocol.respond(with: .response(status: 200, body: Data(Self.body.utf8)))
        let reading = try await Self.adapter().currentWeather(at: Self.madrid)
        #expect(reading.wmoCode == 61)
        #expect(reading.tempC == 18.2)
        let sent = try #require(StubURLProtocol.requests.last?.url)
        #expect(sent.host == "api.open-meteo.com")
        #expect(sent.absoluteString.contains("latitude=40.42&longitude=-3.70"))
    }

    @Test("HTTP ≠ 200: failed, sin decodificar", arguments: [500, 404, 429])
    func httpError(status: Int) async {
        StubURLProtocol.respond(with: .response(status: status, body: Data(Self.body.utf8)))
        await #expect(throws: CapabilityError.failed(operation: "http \(status)")) {
            try await Self.adapter().currentWeather(at: Self.madrid)
        }
    }

    @Test("Sin red: failed(network)")
    func offline() async {
        StubURLProtocol.respond(with: .failure(URLError(.notConnectedToInternet)))
        await #expect(throws: CapabilityError.failed(operation: "network")) {
            try await Self.adapter().currentWeather(at: Self.madrid)
        }
    }

    @Test("JSON inválido con 200: failed(decode)")
    func invalidBody() async {
        StubURLProtocol.respond(with: .response(status: 200, body: Data("<html>".utf8)))
        await #expect(throws: CapabilityError.failed(operation: "decode")) {
            try await Self.adapter().currentWeather(at: Self.madrid)
        }
    }

    @Test("Timeout: una red que no contesta falla al agotar el tope, sin esperar a la respuesta")
    func timeout() async {
        StubURLProtocol.respond(with: .hang)
        let clock = ContinuousClock()
        let started = clock.now
        await #expect(throws: CapabilityError.failed(operation: "timeout")) {
            try await Self.adapter(timeoutS: 0.2).currentWeather(at: Self.madrid)
        }
        #expect(started.duration(to: clock.now) < .seconds(2), "vuelve con el tope, no con la red")
    }

    @Test("El tope por defecto es de 3 s (AR-12)")
    func defaultTimeout() {
        #expect(OpenMeteoAdapter.defaultTimeoutS == 3)
    }
}

/// `URLProtocol` de test: responde a toda petición con lo fijado en `respond(with:)` y guarda
/// cada petición recibida. Con `.hang` no contesta nunca.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    enum Reply: Sendable {
        case response(status: Int, body: Data)
        case failure(URLError)
        case hang
    }

    private struct State {
        var reply: Reply = .hang
        var requests: [URLRequest] = []
    }

    private static let state = Mutex(State())

    static func respond(with reply: Reply) {
        state.withLock { $0 = State(reply: reply) }
    }

    static var requests: [URLRequest] { state.withLock { $0.requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.state.withLock { state in
            state.requests.append(request)
            return state.reply
        }
        switch reply {
        case .response(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hang:
            break
        }
    }

    override func stopLoading() {}
}
