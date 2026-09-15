import Foundation

/// El clima actual tal como lo da el proveedor, sin validar ni fechar. `SessionStore` lo
/// convierte en `WeatherSnapshot`, que valida los rangos y toma `capturedAt` de `ClockPort`.
public struct WeatherReading: Equatable, Sendable {
    public let tempC: Double
    public let feelsLikeC: Double
    /// Código WMO 4677 de la condición.
    public let wmoCode: Int
    public let humidityPct: Double
    public let uvIndex: Double
    public let windKmh: Double

    public init(tempC: Double, feelsLikeC: Double, wmoCode: Int, humidityPct: Double, uvIndex: Double, windKmh: Double) {
        self.tempC = tempC
        self.feelsLikeC = feelsLikeC
        self.wmoCode = wmoCode
        self.humidityPct = humidityPct
        self.uvIndex = uvIndex
        self.windKmh = windKmh
    }
}

/// Clima actual en unas coordenadas aproximadas (CAP-5) — AD-10, AR-12, AD-24.
///
/// Es la **única** llamada de red del producto: HTTPS del sistema, sin dependencias ni
/// terceros, acotada a 3 s. Un fallo nunca llega al usuario: la sesión sigue sin clima.
public protocol WeatherPort: Sendable {
    /// El clima actual en `coordinates`, que ya llegan redondeadas del `LocationPort`.
    ///
    /// - Throws: `failed` sin red, con una respuesta HTTP ≠ 200, un JSON inválido o al agotar
    ///   el tope.
    func currentWeather(at coordinates: Coordinates) async throws(CapabilityError) -> WeatherReading
}
