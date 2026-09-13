import Domain
import Foundation
import Testing

@testable import WalkTracker

/// AD-5: el catálogo real valida, y cada catálogo inválido de la matriz de la 8.7 lanza
/// su error tipado. La app no arranca con ninguno de ellos (`CompositionRoot`).
@Suite("Catálogo de logros · validación al arrancar")
struct AchievementCatalogTests {

    /// El catálogo que empaqueta la app. Los tests corren alojados en ella.
    private static func bundledData() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "achievements", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    /// El catálogo real como JSON mutable, para fabricar los inválidos a partir de él.
    private static func mutableCatalog() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: bundledData()) as? [String: Any])
    }

    private static func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private static func entries(_ object: [String: Any]) throws -> [[String: Any]] {
        try #require(object["achievements"] as? [[String: Any]])
    }

    @Test("El catálogo real valida: 14 logros con las claves de achievements.md")
    func bundledCatalogIsValid() throws {
        let catalog = try CompositionRoot.loadAchievementCatalog(from: .main)

        #expect(catalog.achievements.map(\.key) == AchievementCatalog.requiredKeys)
        #expect(catalog.definition(for: "first_5km")?.threshold == .number(5000))
        #expect(catalog.definition(for: "first_5km")?.metric == .sessionDistanceM)
        #expect(catalog.definition(for: "early_bird")?.threshold == .range(min: 5, max: 7))
        #expect(catalog.definition(for: "early_bird")?.comparison == .between)
        #expect(catalog.definition(for: "rain_walker")?.threshold == .category("rain"))
        #expect(catalog.definition(for: "speed_walker")?.comparison == .lt)
    }

    /// La semántica de los 14 logros, escrita a mano desde `achievements.md` y las
    /// decisiones de la 8.7. Es lo que impide el incidente de AD-5: un `first_10km` con
    /// umbral 1000 pasa el esquema, las claves y el recuento, pero no esta tabla.
    private static let expectedSemantics: [(key: String, metric: AchievementMetric, threshold: AchievementThreshold, comparison: AchievementComparison)] = [
        ("first_km", .sessionDistanceM, .number(1000), .gte),
        ("first_5km", .sessionDistanceM, .number(5000), .gte),
        ("first_10km", .sessionDistanceM, .number(10000), .gte),
        ("first_session", .sessionCount, .number(1), .gte),
        ("weekly_goal", .weeklyGoalMet, .number(1), .eq),
        ("rain_walker", .weatherCategory, .category("rain"), .eq),
        ("7_days_streak", .consecutiveDays, .number(7), .gte),
        ("marathon_42km", .totalDistanceM, .number(42000), .gte),
        ("speed_walker", .paceSecPerKm, .number(480), .lt),
        ("early_bird", .startHourLocal, .range(min: 5, max: 7), .between),
        ("night_walker", .startHourLocal, .range(min: 21, max: 23), .between),
        ("hot_walker", .tempC, .number(30), .gt),
        ("cold_walker", .tempC, .number(5), .lt),
        ("consistency_30", .sessionCount, .number(30), .gte),
    ]

    @Test("El catálogo real tiene exactamente la semántica de achievements.md")
    func bundledCatalogMatchesSemantics() throws {
        let catalog = try CompositionRoot.loadAchievementCatalog(from: .main)

        #expect(catalog.achievements.count == Self.expectedSemantics.count)
        for (achievement, expected) in zip(catalog.achievements, Self.expectedSemantics) {
            #expect(achievement.key == expected.key)
            #expect(achievement.metric == expected.metric, "\(expected.key): metric")
            #expect(achievement.threshold == expected.threshold, "\(expected.key): threshold")
            #expect(achievement.comparison == expected.comparison, "\(expected.key): comparison")
        }
    }

    /// Aplica un cambio a una copia del catálogo real y lo decodifica.
    private static func decodeMutated(_ change: (inout [String: Any], inout [[String: Any]]) throws -> Void) throws(AchievementCatalogError) -> AchievementCatalog {
        let data: Data
        do {
            var object = try mutableCatalog()
            var list = try entries(object)
            try change(&object, &list)
            object["achievements"] = list
            data = try Self.data(object)
        } catch {
            throw .malformed("no se pudo fabricar el caso: \(error)")
        }
        return try AchievementCatalog.decode(from: data)
    }

    private static func index(of key: String, in list: [[String: Any]]) throws -> Int {
        try #require(list.firstIndex { $0["key"] as? String == key })
    }

    @Test("schemaVersion 2: unsupportedSchemaVersion")
    func unsupportedSchemaVersionThrows() {
        #expect(throws: AchievementCatalogError.unsupportedSchemaVersion(2)) {
            try Self.decodeMutated { object, _ in object["schemaVersion"] = 2 }
        }
    }

    @Test("Comparación desconocida: unknownComparison con el logro que la trae")
    func unknownComparisonThrows() {
        #expect(throws: AchievementCatalogError.unknownComparison(key: "first_km", comparison: "gteq")) {
            try Self.decodeMutated { _, list in list[try Self.index(of: "first_km", in: list)]["comparison"] = "gteq" }
        }
    }

    @Test("13 entradas: wrongCount")
    func thirteenEntriesThrow() throws {
        var object = try Self.mutableCatalog()
        object["achievements"] = Array(try Self.entries(object).dropLast())

        #expect(throws: AchievementCatalogError.wrongCount(expected: 14, actual: 13)) {
            try AchievementCatalog.decode(from: try Self.data(object))
        }
    }

    @Test("Clave repetida: duplicateKey")
    func duplicateKeyThrows() throws {
        var object = try Self.mutableCatalog()
        var list = try Self.entries(object)
        list[1]["key"] = list[0]["key"]
        object["achievements"] = list

        #expect(throws: AchievementCatalogError.duplicateKey("first_km")) {
            try AchievementCatalog.decode(from: try Self.data(object))
        }
    }

    @Test("Métrica desconocida: unknownMetric con el logro que la trae")
    func unknownMetricThrows() throws {
        var object = try Self.mutableCatalog()
        var list = try Self.entries(object)
        list[2]["metric"] = "sessionDistanceKm"
        object["achievements"] = list

        #expect(throws: AchievementCatalogError.unknownMetric(key: "first_10km", metric: "sessionDistanceKm")) {
            try AchievementCatalog.decode(from: try Self.data(object))
        }
    }

    @Test("Una clave de achievements.md sustituida por otra: missingKeys")
    func renamedKeyThrows() throws {
        var object = try Self.mutableCatalog()
        var list = try Self.entries(object)
        list[1]["key"] = "five_km"
        object["achievements"] = list

        #expect(throws: AchievementCatalogError.missingKeys(["first_5km"])) {
            try AchievementCatalog.decode(from: try Self.data(object))
        }
    }

    @Test("Umbral incoherente con la métrica o la comparación: invalidThreshold")
    func incoherentThresholdThrows() {
        let cases: [(key: String, field: String, value: Any)] = [
            ("early_bird", "threshold", 5),          // between sin [min, max]
            ("early_bird", "threshold", [7, 5]),     // intervalo invertido
            ("rain_walker", "comparison", "gte"),    // categoría con otra comparación que eq
            ("rain_walker", "threshold", "snow"),    // categoría de clima desconocida
            ("first_km", "threshold", [1, 2]),       // intervalo sin between
            ("first_km", "threshold", "rain"),       // categoría en una métrica numérica
        ]
        for (key, field, value) in cases {
            #expect(throws: AchievementCatalogError.invalidThreshold(key: key), "\(key).\(field) = \(value)") {
                try Self.decodeMutated { _, list in list[try Self.index(of: key, in: list)][field] = value }
            }
        }
    }

    @Test("JSON que no es un catálogo: malformed, nunca un catálogo vacío")
    func malformedThrows() {
        #expect {
            try AchievementCatalog.decode(from: Data("{}".utf8))
        } throws: { error in
            guard case AchievementCatalogError.malformed = error else { return false }
            return true
        }
    }

    @Test("Un bundle sin achievements.json no da catálogo")
    func missingResourceThrows() {
        // El bundle de tests no empaqueta el catálogo: es el de la app quien lo lleva.
        let testBundle = Bundle(for: BundleToken.self)
        #expect {
            try CompositionRoot.loadAchievementCatalog(from: testBundle)
        } throws: { error in
            guard case AchievementCatalogError.malformed = error else { return false }
            return true
        }
    }
}

private final class BundleToken {}
