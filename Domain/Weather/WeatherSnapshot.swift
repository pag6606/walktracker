import Foundation

/// Categoría interna del clima, derivada **del código WMO** y nunca de un texto localizado
/// (AD-6, divergencia `wmoCategory`): `rain` para 51–67, 80–82 y 95–99; `other` para el resto.
///
/// Es la que leerán los logros de clima del Epic 3 (`WeatherCategory.rain`). El texto que se
/// muestra ("Lluvia ligera") es cosa de la UI, a partir del mismo código.
public enum WeatherCondition: String, CaseIterable, Equatable, Sendable {
    /// Llovizna, lluvia (también helada), chubascos y tormenta.
    case rain
    /// Despejado, nubes, niebla, nieve (también granos de nieve, WMO 77) y cualquier otro código.
    case other

    /// La categoría de un código WMO 4677 (`weather_code` de Open-Meteo).
    public init(wmoCode: Int) {
        switch wmoCode {
        case 51...67, 80...82, 95...99: self = .rain
        default: self = .other
        }
    }
}

/// Clima en el instante de inicio de una sesión (CAP-5, SPEC FR-5): se captura una vez y se
/// congela en `Session.weather`; nunca se refresca.
///
/// Siempre válido: solo se materializa por `init`, que valida en la frontera lo que llega de
/// Open-Meteo o del snapshot de recuperación. `condition` no se recibe: sale de `wmoCode`.
public struct WeatherSnapshot: Equatable, Sendable {

    /// Temperatura del aire en °C.
    public let tempC: Double
    /// Sensación térmica en °C.
    public let feelsLikeC: Double
    /// Código WMO 4677 de la condición (0–99). Se conserva: los logros de clima lo leen
    /// (`evaluateAchievements.json` modela el clima como `{wmoCode, tempC}`).
    public let wmoCode: Int
    /// Categoría interna, derivada de `wmoCode`.
    public let condition: WeatherCondition
    /// Humedad relativa en %, 0–100.
    public let humidityPct: Double
    /// Índice UV, ≥ 0.
    public let uvIndex: Double
    /// Velocidad del viento en km/h, ≥ 0.
    public let windKmh: Double
    /// Instante de la captura, leído de `ClockPort` por quien la hace.
    public let capturedAt: Date

    /// Valida y crea el snapshot.
    ///
    /// - Throws: `DomainError.invalidValue` con `tempC` o `feelsLikeC` (no finitos), `wmoCode`
    ///   (fuera de 0–99), `humidityPct` (no finita o fuera de 0–100), `uvIndex` o `windKmh`
    ///   (no finitos o negativos). Se rechaza **antes** de crear el valor.
    public init(
        tempC: Double,
        feelsLikeC: Double,
        wmoCode: Int,
        humidityPct: Double,
        uvIndex: Double,
        windKmh: Double,
        capturedAt: Date
    ) throws(DomainError) {
        guard tempC.isFinite else { throw .invalidValue(field: "tempC") }
        guard feelsLikeC.isFinite else { throw .invalidValue(field: "feelsLikeC") }
        guard (0...99).contains(wmoCode) else { throw .invalidValue(field: "wmoCode") }
        guard humidityPct.isFinite, (0...100).contains(humidityPct) else { throw .invalidValue(field: "humidityPct") }
        guard uvIndex.isFinite, uvIndex >= 0 else { throw .invalidValue(field: "uvIndex") }
        guard windKmh.isFinite, windKmh >= 0 else { throw .invalidValue(field: "windKmh") }
        self.tempC = tempC
        self.feelsLikeC = feelsLikeC
        self.wmoCode = wmoCode
        self.condition = WeatherCondition(wmoCode: wmoCode)
        self.humidityPct = humidityPct
        self.uvIndex = uvIndex
        self.windKmh = windKmh
        self.capturedAt = capturedAt
    }
}
