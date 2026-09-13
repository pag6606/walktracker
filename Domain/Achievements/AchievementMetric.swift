import Foundation

/// Magnitud que evalúa un logro (AD-5). **Enum cerrado:** el evaluador de logros es un
/// `switch` exhaustivo sobre él, así que una métrica nueva sin rama no compila. Una
/// métrica que el catálogo nombre y no esté aquí hace fallar el arranque.
public enum AchievementMetric: String, CaseIterable, Codable, Sendable {
    /// Distancia de la sesión que se cierra, en metros.
    case sessionDistanceM
    /// Distancia acumulada de todas las sesiones, incluida la que se cierra, en metros.
    case totalDistanceM
    /// Número de sesiones, incluida la que se cierra.
    case sessionCount
    /// Días locales consecutivos con al menos una sesión.
    case consecutiveDays
    /// Hora local entera de inicio de la sesión (0–23).
    case startHourLocal
    /// Categoría interna del clima de la sesión, derivada del código WMO (no del texto).
    case weatherCategory
    /// Temperatura del clima de la sesión, en °C.
    case tempC
    /// Ritmo de la sesión en segundos por kilómetro. Ausente por debajo de 100 m (AD-4).
    case paceSecPerKm
    /// La meta semanal se cumplió: `1`. La evalúa `GoalEngine`, no el cierre de sesión.
    case weeklyGoalMet
}

/// Comparación de la métrica con el umbral (AD-5, esquema ampliado el 2026-09-12).
/// `between` es inclusiva en los dos extremos.
public enum AchievementComparison: String, CaseIterable, Codable, Sendable {
    case gte, lte, eq, gt, lt, between
}

/// Categoría interna del clima. Solo existe la que usa el catálogo.
public enum WeatherCategory: String, CaseIterable, Codable, Sendable {
    case rain
}

/// Umbral de un logro: número, intervalo `[min, max]` para `between`, o categoría de
/// clima para `weatherCategory`. En JSON: `1000`, `[5, 7]` o `"rain"`.
public enum AchievementThreshold: Equatable, Sendable, Codable {
    case number(Double)
    case range(min: Double, max: Double)
    case category(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .category(value)
        } else if let bounds = try? container.decode([Double].self), bounds.count == 2 {
            self = .range(min: bounds[0], max: bounds[1])
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "threshold debe ser un número, [min, max] o una cadena"
            ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .number(let value): try value.encode(to: encoder)
        case .range(let min, let max): try [min, max].encode(to: encoder)
        case .category(let value): try value.encode(to: encoder)
        }
    }
}
