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
    /// - `elapsedS` (1.1; la pausa abierta, 1.4): `Chronometer.elapsedS`.
    /// - `v3distance`, `pace` y `calculateCadence` (1.3): `MetricsCalculator`.
    /// - `estimateSteps` (1.5): `GapEstimator.estimateSteps`.
    /// - `selectQuote` y `updateRecentIds` (2.2): `MotivationEngine`.
    /// - `weeklyProgress` (3.1): `GoalEngine.weeklyProgress`.
    /// - `evaluateAchievements`, `checkStreak` y `checkTimeOfDay` (3.2): `AchievementEngine`.
    /// - `achievementCatalog` (3.2): el catálogo congelado del bundle de la app.
    static let swiftDomain = VectorHarness(implementations: [
        "elapsedS": SwiftDomainPorts.elapsedS,
        "v3distance": SwiftDomainPorts.v3distance,
        "pace": SwiftDomainPorts.pace,
        "calculateCadence": SwiftDomainPorts.calculateCadence,
        "estimateSteps": SwiftDomainPorts.estimateSteps,
        "selectQuote": SwiftDomainPorts.selectQuote,
        "updateRecentIds": SwiftDomainPorts.updateRecentIds,
        "weeklyProgress": SwiftDomainPorts.weeklyProgress,
        "achievementCatalog": SwiftDomainPorts.achievementCatalog,
        "evaluateAchievements": SwiftDomainPorts.evaluateAchievements,
        "checkStreak": SwiftDomainPorts.checkStreak,
        "checkTimeOfDay": SwiftDomainPorts.checkTimeOfDay,
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
        // Pausa abierta (1.4): `pausedAtMs` ausente o `null` es que no hay ninguna.
        let pausedAt: Date?
        switch input["pausedAtMs"] {
        case nil, .null?: pausedAt = nil
        case let value?:
            guard let ms = value.double else { throw VectorInputError(description: "elapsedS: pausedAtMs no es un número") }
            pausedAt = Date(timeIntervalSince1970: ms / 1000)
        }

        let elapsed = Chronometer.elapsedS(
            startedAt: Date(timeIntervalSince1970: startedAtMs / 1000),
            totalPausesS: totalPausesMs / 1000,
            pausedAt: pausedAt,
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

    /// `GapEstimator.estimateSteps`. `NaN` llega como la cadena `"NaN"` del vector.
    static let estimateSteps: VectorImplementation = { vector in
        let input = vector.input
        guard let cadenceSpm = input["cadenceSpm"]?.double, let gapS = input["gapS"]?.double else {
            throw VectorInputError(description: "estimateSteps: faltan cadenceSpm o gapS")
        }
        return .number(Double(try GapEstimator.estimateSteps(cadenceSpm: cadenceSpm, gapS: gapS)))
    }

    /// `MotivationEngine.selectQuote`. El azar sale de un `RandomPort` fijo en el índice 0:
    /// las conductas aleatorias están **excluidas** de los vectores (`inventory.json`,
    /// `math-random`), así que el único vector que llega aquí —banco vacío → `nil`— no depende
    /// de qué índice devuelva. La salida es la frase como `{ id, text }`, que es lo que
    /// devuelve `motivation.js`; `ignoredRecentWindow` es señal Swift y no viaja al vector.
    static let selectQuote: VectorImplementation = { vector in
        let input = vector.input
        guard case .array(let rawQuotes)? = input["quotes"] else {
            throw VectorInputError(description: "selectQuote: falta quotes o no es un array")
        }
        let quotes = try rawQuotes.map { raw throws(VectorInputError) -> Quote in
            guard let id = raw["id"]?.double, let identifier = Int(exactly: id), let text = raw["text"]?.string else {
                throw VectorInputError(description: "selectQuote: una frase sin id entero o sin text")
            }
            return Quote(id: identifier, text: text)
        }
        // El banco del vector valida como cualquier otro: un vector con ids repetidos sería un
        // vector mal escrito, y se ve aquí en vez de dar una selección tramposa.
        let bank: QuoteBank
        do {
            bank = try QuoteBank(quotes: quotes)
        } catch {
            throw VectorInputError(description: "selectQuote: el banco del vector no valida (\(error))")
        }
        let selection = MotivationEngine.selectQuote(
            from: bank,
            recentQuoteIds: try identifiers(input, "recentIds", in: "selectQuote"),
            random: FirstIndexRandom()
        )
        guard let selection else { return .null }
        return .object(["id": .number(Double(selection.quote.id)), "text": .string(selection.quote.text)])
    }

    /// `MotivationEngine.updateRecentIds`.
    static let updateRecentIds: VectorImplementation = { vector in
        let input = vector.input
        let updated = MotivationEngine.updateRecentIds(
            try identifiers(input, "recentIds", in: "updateRecentIds"),
            selectedId: try integer(input, "selectedId", in: "updateRecentIds")
        )
        return .array(updated.map { .number(Double($0)) })
    }

    /// `GoalEngine.weeklyProgress` (3.1).
    ///
    /// **El calendario sale del propio vector.** `weeklyProgress` es una función de hora
    /// (`TIME_FUNCTIONS` en `run-js.js`), así que su vector declara `timeZone` y aquí se
    /// construye con ella el `AppCalendar` de AD-19 —ISO-8601, lunes primero— en vez de usar el
    /// del `ClockStub`, que es siempre UTC: los tres vectores divergentes son precisamente los
    /// que se evalúan en `America/Guayaquil`, y con un calendario en UTC pasarían por la razón
    /// equivocada.
    ///
    /// La entrada trae `{startedAt, distanceM}` por sesión, que es lo que consume el motor. Se
    /// materializa un `SessionRecord` completo —el tipo real, no un sucedáneo— rellenando lo
    /// que el vector no fija con valores que crucen su frontera: el motor solo lee esos dos
    /// campos, y construir el tipo de verdad es lo que impide que el vector pase contra una
    /// estructura que el historial no podría contener.
    static let weeklyProgress: VectorImplementation = { vector in
        let input = vector.input
        let calendar = try appCalendar(vector, in: "weeklyProgress")
        guard let goalKm = input["weeklyGoalKm"]?.double else {
            throw VectorInputError(description: "weeklyProgress: falta weeklyGoalKm")
        }
        guard let nowText = input["now"]?.string, let now = instant(nowText) else {
            throw VectorInputError(description: "weeklyProgress: falta now o no es ISO-8601")
        }
        guard case .array(let rawSessions)? = input["sessions"] else {
            throw VectorInputError(description: "weeklyProgress: falta sessions o no es un array")
        }
        let records = try rawSessions.map { raw throws(VectorInputError) -> SessionRecord in
            guard let startedAtText = raw["startedAt"]?.string, let startedAt = instant(startedAtText) else {
                throw VectorInputError(description: "weeklyProgress: una sesión sin startedAt ISO-8601")
            }
            guard let distanceM = raw["distanceM"]?.double else {
                throw VectorInputError(description: "weeklyProgress: una sesión sin distanceM")
            }
            do {
                return try SessionRecord(
                    id: UUID(),
                    startedAt: startedAt,
                    endedAt: startedAt,
                    stepsMeasured: 0,
                    stepsEstimated: 0,
                    strideM: 0.655,
                    distanceM: distanceM,
                    durationS: 0,
                    pausesS: 0,
                    paceSecPerKm: nil,
                    cadenceSpm: 0
                )
            } catch {
                throw VectorInputError(description: "weeklyProgress: la sesión del vector no cruza la frontera (\(error))")
            }
        }

        let progress = GoalEngine.weeklyProgress(records: records, goalKm: goalKm, now: now, calendar: calendar)
        return .object([
            "completedKm": .number(progress.completedKm),
            "goalKm": .number(progress.goalKm),
            "percentage": .number(progress.percentage),
            "isComplete": .bool(progress.isComplete),
        ])
    }

    // MARK: - Logros (3.2)

    /// El catálogo congelado de los 14 logros, leído **del bundle de la app** (AD-5).
    ///
    /// Los tests corren alojados en la app, así que `Bundle.main` es la que lleva
    /// `achievements.json`. El catálogo no se declara en Swift: si se declarara, los vectores
    /// pasarían contra una copia y el fichero de datos podría irse a la deriva sin que nada lo
    /// dijera — que es exactamente el incidente de AD-5.
    ///
    /// **Hay un segundo cargador en el target de tests (`AchievementCatalogFixture.bundled`), y la
    /// duplicación es deliberada.** Este fichero importa **solo `Domain`**, a propósito: es la
    /// misma regla que hace que los vectores no puedan importar `WalkTracker` (AD-6), así que no
    /// puede llamar a `CompositionRoot.loadAchievementCatalog(from:)`. Y el fallo se trata
    /// distinto a propósito: aquí rompe **el vector que lo necesita**, con su motivo, porque el
    /// arnés existe para nombrar lo que falla; allí mata el proceso.
    static let bundledCatalog: Result<AchievementCatalog, VectorInputError> = {
        guard let url = Bundle.main.url(forResource: "achievements", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return .failure(VectorInputError(description: "achievements.json no está en el bundle de la app"))
        }
        do {
            return .success(try AchievementCatalog.decode(from: data))
        } catch {
            return .failure(VectorInputError(description: "achievements.json no valida: \(error)"))
        }
    }()

    /// `achievementCatalog`: las 14 claves del catálogo, en su orden.
    ///
    /// El vector fija **cuáles y en qué orden**, que es más de lo que afirma el test de la
    /// referencia (solo que son 14). Ejecuta el catálogo real del bundle, no una lista escrita a
    /// mano.
    static let achievementCatalog: VectorImplementation = { _ in
        let catalog = try bundledCatalog.get()
        return .object(["keys": .array(catalog.achievements.map { JSONValue.string($0.key) })])
    }

    /// `AchievementEngine.newlyUnlocked` (3.2).
    ///
    /// **El calendario sale del propio vector**, como en `weeklyProgress`: `evaluateAchievements`
    /// es una función de hora (`TIME_FUNCTIONS` en `run-js.js`) y los divergentes de `localTime`
    /// se evalúan en `America/Guayaquil`. Con un calendario en UTC pasarían por la razón
    /// equivocada, o no pasarían.
    ///
    /// La entrada trae la sesión que cierra como `{startedAt, distanceM, paceSecPerKm, weather}` y
    /// el historial como `{startedAt, distanceM}`. Se materializan `SessionRecord` **reales** —el
    /// tipo del historial, no un sucedáneo— para que ningún vector pase contra una estructura que
    /// `sessions.json` no podría contener. `alreadyUnlocked` son claves, y aquí se convierten en
    /// filas **con `unlockedAt`**: una fila sin instante es un logro en curso, no uno conseguido,
    /// y el motor las distingue.
    ///
    /// La salida va **ordenada**: es lo que fija el vector y lo que hace el adapter de `run-js.js`
    /// con la lista que devuelve `motivation.js`.
    static let evaluateAchievements: VectorImplementation = { vector in
        let input = vector.input
        let calendar = try appCalendar(vector, in: "evaluateAchievements")
        let catalog = try bundledCatalog.get()

        guard let session = input["session"] else {
            throw VectorInputError(description: "evaluateAchievements: falta session")
        }
        let record = try sessionRecord(session, in: "evaluateAchievements")
        guard case .array(let rawHistory)? = input["history"] else {
            throw VectorInputError(description: "evaluateAchievements: falta history o no es un array")
        }
        let history = try rawHistory.map { try sessionRecord($0, in: "evaluateAchievements") }
        guard case .array(let rawUnlocked)? = input["alreadyUnlocked"] else {
            throw VectorInputError(description: "evaluateAchievements: falta alreadyUnlocked o no es un array")
        }
        let alreadyUnlocked = try rawUnlocked.map { raw throws(VectorInputError) -> AchievementUnlock in
            guard let key = raw.string else {
                throw VectorInputError(description: "evaluateAchievements: alreadyUnlocked tiene algo que no es una clave")
            }
            guard let unlock = try? AchievementUnlock(key: key, unlockedAt: alreadyUnlockedAt, progress: 1) else {
                throw VectorInputError(description: "evaluateAchievements: la clave '\(key)' no cruza la frontera del desbloqueo")
            }
            return unlock
        }

        let newlyUnlocked = AchievementEngine.newlyUnlocked(
            closing: record,
            history: history,
            alreadyUnlocked: alreadyUnlocked,
            catalog: catalog,
            calendar: calendar
        )
        return .object(["newlyUnlocked": .array(newlyUnlocked.map(\.key).sorted().map { JSONValue.string($0) })])
    }

    /// `AchievementEngine.consecutiveDays` (3.2), contra el umbral del vector.
    ///
    /// La referencia (`motivation.js:154`) responde un booleano; el catálogo, en cambio, compara
    /// una **magnitud** (`consecutiveDays gte 7`). Aquí se compone lo mismo: la racha más larga
    /// del conjunto frente a los días que pide el vector. La agrupación es por **día local** del
    /// `AppCalendar`, que es la divergencia `localTime` de AD-6.
    static let checkStreak: VectorImplementation = { vector in
        let input = vector.input
        let calendar = try appCalendar(vector, in: "checkStreak")
        guard case .array(let rawInstants)? = input["startedAts"] else {
            throw VectorInputError(description: "checkStreak: falta startedAts o no es un array")
        }
        let startedAts = try rawInstants.map { raw throws(VectorInputError) -> Date in
            guard let text = raw.string, let instant = instant(text) else {
                throw VectorInputError(description: "checkStreak: un startedAt que no es ISO-8601")
            }
            return instant
        }
        let days = try integer(input, "days", in: "checkStreak")

        return .bool(AchievementEngine.consecutiveDays(startedAts: startedAts, calendar: calendar) >= days)
    }

    /// La franja horaria de un logro (`motivation.js:178`), por el camino **real** del motor.
    ///
    /// No se compara la hora a mano: se arma una definición con la métrica `startHourLocal`, el
    /// comparador `between` y el intervalo del vector, y se pasa por
    /// `AchievementEngine.isEarned`. Así estos 5 vectores ejercitan la misma extracción de hora
    /// local y la misma inclusividad de `between` que desbloquean `early_bird` y `night_walker`,
    /// en vez de una copia que podría irse a la deriva.
    ///
    /// La definición es **sintética** y no toca el catálogo: su único trabajo es llevar la franja
    /// del vector hasta el motor. `name`, `description` e `icon` no se leen para decidir nada.
    static let checkTimeOfDay: VectorImplementation = { vector in
        let input = vector.input
        let calendar = try appCalendar(vector, in: "checkTimeOfDay")
        guard let startedAtText = input["startedAt"]?.string, instant(startedAtText) != nil else {
            throw VectorInputError(description: "checkTimeOfDay: falta startedAt o no es ISO-8601")
        }
        let hourStart = try integer(input, "hourStart", in: "checkTimeOfDay")
        let hourEnd = try integer(input, "hourEnd", in: "checkTimeOfDay")
        let record = try sessionRecord(.object(["startedAt": .string(startedAtText), "distanceM": .number(0)]), in: "checkTimeOfDay")

        let franja = AchievementDefinition(
            key: "checkTimeOfDay",
            name: "",
            description: "",
            icon: "",
            metric: .startHourLocal,
            threshold: .range(min: Double(hourStart), max: Double(hourEnd)),
            comparison: .between
        )
        return .bool(AchievementEngine.isEarned(franja, closing: record, sessions: [record], calendar: calendar))
    }

    /// El instante con el que se materializa cada clave de `alreadyUnlocked`. Es el mismo que usa
    /// el adapter de `run-js.js`: lo único que importa es que **no sea nulo**, porque es lo que
    /// distingue un logro conseguido de uno en curso.
    private static let alreadyUnlockedAt = Date(timeIntervalSince1970: 1_767_225_600)

    /// El `AppCalendar` de AD-19 en la zona que declara el vector: ISO-8601 y lunes primero. Es el
    /// mismo que construyen `SystemClock` y `ClockStub`; ninguna implementación se inventa otro.
    private static func appCalendar(_ vector: DomainVector, in function: String) throws -> Calendar {
        guard let identifier = vector.timeZone, let zone = TimeZone(identifier: identifier) else {
            throw VectorInputError(description: "\(function): falta timeZone o no es una zona conocida")
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = zone
        return calendar
    }

    /// Un `SessionRecord` real a partir de lo que el vector fija de una sesión.
    ///
    /// Lo que el vector no fija se rellena con valores que **crucen la frontera** del registro, y
    /// nada más: el motor solo lee `startedAt`, `distanceM`, `paceSecPerKm`, `weather` y
    /// `recovered`. El clima del vector es `{wmoCode, tempC}` —los dos datos que leen los logros
    /// de clima— y el resto del snapshot se completa con valores válidos: la categoría sale del
    /// **código**, nunca de un texto (divergencia `wmoCategory` de AD-6).
    private static func sessionRecord(_ raw: JSONValue, in function: String) throws -> SessionRecord {
        guard let startedAtText = raw["startedAt"]?.string, let startedAt = instant(startedAtText) else {
            throw VectorInputError(description: "\(function): una sesión sin startedAt ISO-8601")
        }
        guard let distanceM = raw["distanceM"]?.double else {
            throw VectorInputError(description: "\(function): una sesión sin distanceM")
        }

        var pace: Int?
        switch raw["paceSecPerKm"] {
        case nil, .null?:
            pace = nil
        case let value?:
            guard let seconds = value.double, let exact = Int(exactly: seconds) else {
                throw VectorInputError(description: "\(function): paceSecPerKm no es un entero")
            }
            pace = exact
        }

        var weather: WeatherSnapshot?
        switch raw["weather"] {
        case nil, .null?:
            weather = nil
        case let value?:
            guard let wmo = value["wmoCode"]?.double, let wmoCode = Int(exactly: wmo),
                  let tempC = value["tempC"]?.double
            else {
                throw VectorInputError(description: "\(function): un clima sin wmoCode entero o sin tempC")
            }
            do {
                weather = try WeatherSnapshot(
                    tempC: tempC,
                    feelsLikeC: tempC,
                    wmoCode: wmoCode,
                    humidityPct: 50,
                    uvIndex: 0,
                    windKmh: 0,
                    capturedAt: startedAt
                )
            } catch {
                throw VectorInputError(description: "\(function): el clima del vector no cruza la frontera (\(error))")
            }
        }

        do {
            return try SessionRecord(
                id: UUID(),
                startedAt: startedAt,
                endedAt: startedAt,
                stepsMeasured: 0,
                stepsEstimated: 0,
                strideM: 0.655,
                distanceM: distanceM,
                durationS: 0,
                pausesS: 0,
                paceSecPerKm: pace,
                cadenceSpm: 0,
                weather: weather
            )
        } catch {
            throw VectorInputError(description: "\(function): la sesión del vector no cruza la frontera (\(error))")
        }
    }

    /// Una fecha ISO-8601 del vector, con o sin fracción de segundo y con cualquier desfase.
    private static func instant(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// `RandomPort` fijo en la primera posición: determinista, para que el vector no dependa
    /// del azar. Las conductas que sí dependen de él se prueban aparte, con `RandomStub`.
    private struct FirstIndexRandom: RandomPort {
        func index(below count: Int) -> Int? { count > 0 ? 0 : nil }
    }

    /// Una lista de ids enteros de la entrada. Ausente o `null` es la lista vacía, como el
    /// `recentQuoteIds = []` por omisión de `motivation.js`.
    private static func identifiers(_ input: JSONValue, _ key: String, in function: String) throws -> [Int] {
        switch input[key] {
        case nil, .null?:
            return []
        case .array(let items)?:
            return try items.map { item throws(VectorInputError) -> Int in
                guard let value = item.double, let identifier = Int(exactly: value) else {
                    throw VectorInputError(description: "\(function): \(key) tiene un valor que no es un entero")
                }
                return identifier
            }
        default:
            throw VectorInputError(description: "\(function): \(key) no es un array")
        }
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

    /// Los bytes crudos del fichero de una función.
    ///
    /// Existe para lo que `DomainVector` no decodifica: `expectedJs`, el valor que da
    /// `domain.js` en un vector divergente. Swift lo ignora a propósito —el vector lleva el
    /// valor de Swift en `expected`— pero hay un criterio que exige leerlo: un divergente
    /// ejecutado contra `expectedJs` **tiene que fallar**, o la divergencia declarada ya no
    /// sería una divergencia.
    static func data(for function: String) throws -> Data {
        guard let url = bundle.url(forResource: function, withExtension: "json") else {
            throw VectorInputError(description: "\(function).json no está en el bundle de tests")
        }
        return try Data(contentsOf: url)
    }

    /// Funciones conocidas cuyo fichero no está en el bundle.
    static func missingFunctions() -> [String] {
        VectorHarness.knownFunctions.sorted().filter { bundle.url(forResource: $0, withExtension: "json") == nil }
    }
}
