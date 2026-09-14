import Domain
import Foundation

// Arnés Swift de los vectores de AD-6. Lee los mismos ficheros que
// `Scripts/vectors/run-js.js`: ningún runtime tiene su propia copia de los datos.
// La semántica de comparación es la misma en los dos lados; si cambias una, cambia
// la otra.

// MARK: - Valor JSON

/// Valor JSON sin tipar. La entrada y la salida de cada vector son neutrales: cada
/// implementación registrada traduce a sus tipos de dominio.
enum JSONValue: Equatable, Sendable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    /// Número de la entrada. JSON no tiene `NaN` ni `Infinity`: los vectores los
    /// escriben como cadena.
    var double: Double? {
        switch self {
        case .number(let value): value
        case .string("NaN"): .nan
        case .string("Infinity"): .infinity
        case .string("-Infinity"): -.infinity
        default: nil
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

// MARK: - Ficheros de vectores

/// Las dos únicas familias de divergencia declaradas (AD-6). En Swift el vector
/// **debe pasar**: lleva el valor correcto para Swift; es `domain.js` quien lo falla.
enum VectorDivergence: String, Decodable, Sendable {
    case localTime
    case wmoCategory
}

struct DomainVector: Decodable, Sendable {

    enum Outcome: Equatable, Sendable {
        case value(JSONValue)
        /// El dominio lanza `DomainError.invalidValue(field:)` con ese campo.
        case throwsInvalidValue(field: String)
    }

    let id: String
    let sources: [String]
    let input: JSONValue
    let outcome: Outcome
    let tolerance: Double?
    /// Zona horaria del calendario con el que se evalúa el vector (IANA).
    let timeZone: String?
    let divergence: VectorDivergence?
    let covers: [String: Bool]?

    private enum CodingKeys: String, CodingKey {
        case id, sources, input, expected, `throws`, tolerance, timeZone, divergence, covers
    }

    private struct ThrowsSpec: Decodable {
        let field: String
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sources = try container.decode([String].self, forKey: .sources)
        input = try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .object([:])
        tolerance = try container.decodeIfPresent(Double.self, forKey: .tolerance)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        divergence = try container.decodeIfPresent(VectorDivergence.self, forKey: .divergence)
        covers = try container.decodeIfPresent([String: Bool].self, forKey: .covers)

        switch (container.contains(.expected), container.contains(.throws)) {
        case (true, false):
            // `contains` distingue un `"expected": null` (ritmo ausente) de la falta de clave.
            outcome = .value(try container.decode(JSONValue.self, forKey: .expected))
        case (false, true):
            outcome = .throwsInvalidValue(field: try container.decode(ThrowsSpec.self, forKey: .throws).field)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .expected, in: container,
                debugDescription: "el vector '\(id)' debe llevar \"expected\" o \"throws\", exactamente uno"
            )
        }
    }
}

struct VectorFile: Decodable, Sendable {
    let schemaVersion: Int
    let function: String
    let reference: String
    let vectors: [DomainVector]
}

// MARK: - Comparación

enum VectorMatcher {

    /// Números con tolerancia si el vector la fija; arrays elemento a elemento; objetos
    /// por las claves que el vector fija (la salida puede traer más).
    static func matches(expected: JSONValue, actual: JSONValue, tolerance: Double?) -> Bool {
        switch (expected, actual) {
        case (.null, .null):
            return true
        case (.number(let want), .number(let got)):
            if let tolerance { return abs(want - got) <= tolerance }
            return want == got
        case (.bool(let want), .bool(let got)):
            return want == got
        case (.string(let want), .string(let got)):
            return want == got
        case (.array(let want), .array(let got)):
            return want.count == got.count
                && zip(want, got).allSatisfy { matches(expected: $0, actual: $1, tolerance: tolerance) }
        case (.object(let want), .object(let got)):
            return want.allSatisfy { key, value in
                got[key].map { matches(expected: value, actual: $0, tolerance: tolerance) } ?? false
            }
        default:
            return false
        }
    }
}

// MARK: - Registro de implementaciones Swift

/// Implementación Swift de una función de vector: recibe el vector entero (para leer
/// `input` y `timeZone`) y devuelve la salida en forma neutral.
typealias VectorImplementation = @Sendable (DomainVector) throws -> JSONValue

enum VectorVerdict: Equatable, Sendable {
    case passed
    case failed(String)
    /// La función aún no está portada a Swift. Se lista, no rompe.
    case pending
}

struct VectorHarness: Sendable {

    /// Las funciones que tienen fichero de vectores. Un fichero de una función que no
    /// esté aquí es un error: obliga a decidir quién la porta.
    static let knownFunctions: Set<String> = [
        "elapsedS", "pace", "v3distance", "estimateSteps", "calculateCadence",
        "selectQuote", "updateRecentIds", "achievementCatalog", "evaluateAchievements",
        "checkStreak", "checkTimeOfDay", "weeklyProgress",
    ]

    /// **El registro.** Cada historia que porta una función al dominio Swift la añade
    /// aquí, y desde ese momento sus vectores dejan de estar pendientes y pasan a
    /// romper `verify-domain.sh` si fallan.
    ///
    /// - `elapsedS` (1.1): `Chronometer.elapsedS`.
    /// - `v3distance`, `pace` y `calculateCadence` (1.3): `MetricsCalculator`.
    static let swiftDomain = VectorHarness(implementations: [
        "elapsedS": SwiftDomainPorts.elapsedS,
        "v3distance": SwiftDomainPorts.v3distance,
        "pace": SwiftDomainPorts.pace,
        "calculateCadence": SwiftDomainPorts.calculateCadence,
    ])

    let implementations: [String: VectorImplementation]

    func verdict(for vector: DomainVector, of function: String) -> VectorVerdict {
        guard let implementation = implementations[function] else { return .pending }

        switch vector.outcome {
        case .value(let expected):
            do {
                let actual = try implementation(vector)
                return VectorMatcher.matches(expected: expected, actual: actual, tolerance: vector.tolerance)
                    ? .passed
                    : .failed("esperado \(expected), Swift da \(actual)")
            } catch {
                return .failed("esperado \(expected), Swift lanza \(error)")
            }
        case .throwsInvalidValue(let field):
            do {
                let actual = try implementation(vector)
                return .failed("esperado invalidValue(field: \(field)), Swift devuelve \(actual)")
            } catch DomainError.invalidValue(let thrownField) where thrownField == field {
                return .passed
            } catch {
                return .failed("esperado invalidValue(field: \(field)), Swift lanza \(error)")
            }
        }
    }
}

// MARK: - Traducción vector → dominio Swift

/// Una entrada de vector que la implementación registrada no sabe traducir. Rompe el
/// vector con su motivo: nunca se adivina un valor.
struct VectorInputError: Error, CustomStringConvertible {
    let description: String
}

/// Las traducciones de la entrada neutral de cada vector a los tipos del dominio
/// Swift. Es la contraparte de `ADAPTERS` en `Scripts/vectors/run-js.js`.
enum SwiftDomainPorts {

    /// Los vectores de `elapsedS` están en **milisegundos** (la firma de `domain.js:69`);
    /// el dominio Swift trabaja en segundos y con `Date`. `totalPausesMs` ausente o
    /// `null` es 0, como el `|| 0` de la referencia.
    static let elapsedS: VectorImplementation = { vector in
        let input = vector.input
        guard let startedAtMs = input["startedAtMs"]?.double, let nowMs = input["nowMs"]?.double else {
            throw VectorInputError(description: "elapsedS: faltan startedAtMs o nowMs")
        }
        let totalPausesMs: Double
        switch input["totalPausesMs"] {
        case nil, .null?: totalPausesMs = 0
        case let value?:
            guard let ms = value.double else { throw VectorInputError(description: "elapsedS: totalPausesMs no es un número") }
            totalPausesMs = ms
        }
        // La pausa abierta entra con pausar/reanudar (1.4). Hasta entonces un vector
        // que la traiga falla con su motivo en lugar de ignorarla en silencio.
        switch input["pausedAtMs"] {
        case nil, .null?: break
        default: throw VectorInputError(description: "elapsedS: pausedAtMs con pausa abierta aún no está portado (1.4)")
        }

        let elapsed = Chronometer.elapsedS(
            startedAt: Date(timeIntervalSince1970: startedAtMs / 1000),
            totalPausesS: totalPausesMs / 1000,
            now: Date(timeIntervalSince1970: nowMs / 1000)
        )
        return .number(elapsed)
    }

    /// `MetricsCalculator.distanceM`. Los pasos del vector son enteros: uno que no lo sea
    /// rompe el vector con su motivo.
    static let v3distance: VectorImplementation = { vector in
        let input = vector.input
        guard let strideM = input["strideM"]?.double else {
            throw VectorInputError(description: "v3distance: falta strideM")
        }
        let distance = try MetricsCalculator.distanceM(
            stepsMeasured: try integer(input, "stepsMeasured", in: "v3distance"),
            stepsEstimated: try integer(input, "stepsEstimated", in: "v3distance"),
            strideM: strideM
        )
        return .number(distance)
    }

    /// `MetricsCalculator.paceSecPerKm`. La v3 recibe `durationS` y `pausesS` por
    /// separado; el dominio Swift, el tiempo en movimiento: `durationS − pausesS`. Un
    /// ritmo ausente es `null`.
    static let pace: VectorImplementation = { vector in
        let input = vector.input
        guard let durationS = input["durationS"]?.double,
              let pausesS = input["pausesS"]?.double,
              let distanceM = input["distanceM"]?.double
        else {
            throw VectorInputError(description: "pace: faltan durationS, pausesS o distanceM")
        }
        let pace = try MetricsCalculator.paceSecPerKm(movingS: durationS - pausesS, distanceM: distanceM)
        return pace.map { .number(Double($0)) } ?? .null
    }

    /// `MetricsCalculator.cadenceSpm`.
    static let calculateCadence: VectorImplementation = { vector in
        let input = vector.input
        guard let activeSeconds = input["activeSeconds"]?.double else {
            throw VectorInputError(description: "calculateCadence: falta activeSeconds")
        }
        let cadence = try MetricsCalculator.cadenceSpm(
            stepsMeasured: try integer(input, "stepsMeasured", in: "calculateCadence"),
            activeSeconds: activeSeconds
        )
        return .number(cadence)
    }

    private static func integer(_ input: JSONValue, _ key: String, in function: String) throws -> Int {
        guard let value = input[key]?.double, let integer = Int(exactly: value) else {
            throw VectorInputError(description: "\(function): \(key) falta o no es un entero")
        }
        return integer
    }
}

// MARK: - Ejecución agregada

/// Resultado de pasar un registro por todos los vectores.
struct VectorRun: Sendable {
    var passed = 0
    /// Función sin portar → número de vectores pendientes.
    var pending: [String: Int] = [:]
    /// `fichero#id: motivo` de cada vector que una función portada falla.
    var failures: [String] = []

    static func evaluate(harness: VectorHarness, files: [(name: String, file: VectorFile)]) -> VectorRun {
        var run = VectorRun()
        for (name, file) in files {
            for vector in file.vectors {
                switch harness.verdict(for: vector, of: file.function) {
                case .passed:
                    run.passed += 1
                case .pending:
                    run.pending[file.function, default: 0] += 1
                case .failed(let reason):
                    run.failures.append("\(name)#\(vector.id): \(reason)")
                }
            }
        }
        return run
    }
}

// MARK: - Carga desde el bundle de tests

enum VectorBundle {

    private final class Token {}

    private static var bundle: Bundle { Bundle(for: Token.self) }

    /// XcodeGen empaqueta los `.json` de `WalkTrackerTests/` como recursos, aplanados.
    /// Solo se cargan los `<función>.json` de `VectorHarness.knownFunctions`: otro JSON
    /// del bundle (el inventario, un fixture de `Scenarios/`) no es un fichero de vectores.
    static func files() throws -> [(name: String, file: VectorFile)] {
        try VectorHarness.knownFunctions.sorted().compactMap { function in
            guard let url = bundle.url(forResource: function, withExtension: "json") else { return nil }
            return ("\(function).json", try JSONDecoder().decode(VectorFile.self, from: Data(contentsOf: url)))
        }
    }

    /// Funciones conocidas cuyo fichero no está en el bundle.
    static func missingFunctions() -> [String] {
        VectorHarness.knownFunctions.sorted().filter { bundle.url(forResource: $0, withExtension: "json") == nil }
    }
}
