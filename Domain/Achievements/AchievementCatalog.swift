import Foundation

/// Un logro del catálogo: metadatos y umbral. La evaluación es Swift, no datos (AD-5).
public struct AchievementDefinition: Equatable, Sendable, Codable {
    /// Clave estable de `achievements.md`. Nunca se renumera.
    public let key: String
    public let name: String
    public let description: String
    /// Emoji de la insignia. Es dato del catálogo, no chrome (AD-5).
    public let icon: String
    public let metric: AchievementMetric
    public let threshold: AchievementThreshold
    public let comparison: AchievementComparison

    public init(
        key: String,
        name: String,
        description: String,
        icon: String,
        metric: AchievementMetric,
        threshold: AchievementThreshold,
        comparison: AchievementComparison
    ) {
        self.key = key
        self.name = name
        self.description = description
        self.icon = icon
        self.metric = metric
        self.threshold = threshold
        self.comparison = comparison
    }

    private enum CodingKeys: String, CodingKey {
        case key, name, description, icon, metric, threshold, comparison
    }

    /// `metric` y `comparison` se leen como cadena para que una desconocida sea un
    /// error tipado que nombra el logro, no un `DecodingError` genérico.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decode(String.self, forKey: .icon)
        threshold = try container.decode(AchievementThreshold.self, forKey: .threshold)

        let rawMetric = try container.decode(String.self, forKey: .metric)
        guard let metric = AchievementMetric(rawValue: rawMetric) else {
            throw AchievementCatalogError.unknownMetric(key: key, metric: rawMetric)
        }
        self.metric = metric

        let rawComparison = try container.decode(String.self, forKey: .comparison)
        guard let comparison = AchievementComparison(rawValue: rawComparison) else {
            throw AchievementCatalogError.unknownComparison(key: key, comparison: rawComparison)
        }
        self.comparison = comparison
    }
}

/// Por qué el catálogo no vale. La app no arranca con ninguno de estos (AD-5).
public enum AchievementCatalogError: Error, Equatable, Sendable {
    /// El JSON no se puede leer o no tiene la forma del esquema.
    case malformed(String)
    case unsupportedSchemaVersion(Int)
    case wrongCount(expected: Int, actual: Int)
    case duplicateKey(String)
    /// Claves de `achievements.md` que el catálogo no trae. Con 14 entradas y sin
    /// repetidas, una clave ajena siempre deja otra de `achievements.md` fuera.
    case missingKeys([String])
    case unknownMetric(key: String, metric: String)
    case unknownComparison(key: String, comparison: String)
    /// El umbral no casa con la métrica o la comparación: `between` sin `[min, max]`,
    /// `weatherCategory` sin categoría conocida o con otra comparación que `eq`, o un
    /// número donde hace falta otra cosa.
    case invalidThreshold(key: String)
}

/// Catálogo de logros cargado de `Resources/achievements.json` (AD-5, CAP-8).
///
/// Se valida al arrancar y **falla ruidosamente**: con un catálogo inválido la app no
/// arranca, nunca degrada a un catálogo parcial.
public struct AchievementCatalog: Equatable, Sendable, Codable {

    public static let supportedSchemaVersion = 1

    /// Las 14 claves de `achievements.md`, en su orden. Duplicarlas aquí es la
    /// comprobación: el fichero de datos no puede validarse contra sí mismo.
    public static let requiredKeys: [String] = [
        "first_km", "first_5km", "first_10km", "first_session", "weekly_goal",
        "rain_walker", "7_days_streak", "marathon_42km", "speed_walker", "early_bird",
        "night_walker", "hot_walker", "cold_walker", "consistency_30",
    ]

    public let schemaVersion: Int
    public let achievements: [AchievementDefinition]

    public init(schemaVersion: Int, achievements: [AchievementDefinition]) {
        self.schemaVersion = schemaVersion
        self.achievements = achievements
    }

    /// Decodifica y valida. Único punto de entrada desde datos.
    public static func decode(from data: Data) throws(AchievementCatalogError) -> AchievementCatalog {
        let catalog: AchievementCatalog
        do {
            catalog = try JSONDecoder().decode(AchievementCatalog.self, from: data)
        } catch let error as AchievementCatalogError {
            throw error
        } catch {
            throw .malformed(String(describing: error))
        }
        try catalog.validate()
        return catalog
    }

    /// Lanza la primera causa encontrada, en este orden: versión, número de entradas,
    /// claves repetidas, claves que faltan, umbrales.
    public func validate() throws(AchievementCatalogError) {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw .unsupportedSchemaVersion(schemaVersion)
        }
        guard achievements.count == Self.requiredKeys.count else {
            throw .wrongCount(expected: Self.requiredKeys.count, actual: achievements.count)
        }

        var seen = Set<String>()
        for achievement in achievements where !seen.insert(achievement.key).inserted {
            throw .duplicateKey(achievement.key)
        }

        let missing = Self.requiredKeys.filter { !seen.contains($0) }
        guard missing.isEmpty else { throw .missingKeys(missing) }

        for achievement in achievements where !achievement.hasCoherentThreshold {
            throw .invalidThreshold(key: achievement.key)
        }
    }

    /// El logro de una clave, si existe.
    public func definition(for key: String) -> AchievementDefinition? {
        achievements.first { $0.key == key }
    }
}

private extension AchievementDefinition {

    var hasCoherentThreshold: Bool {
        switch (metric, comparison, threshold) {
        case (.weatherCategory, .eq, .category(let raw)):
            return WeatherCategory(rawValue: raw) != nil
        case (.weatherCategory, _, _), (_, _, .category):
            return false
        case (_, .between, .range(let min, let max)):
            return min.isFinite && max.isFinite && min <= max
        case (_, .between, _), (_, _, .range):
            return false
        case (_, _, .number(let value)):
            return value.isFinite
        }
    }
}
