import Domain
import Foundation
import Testing

/// Lado Swift de AD-6. Decodifica **todos** los vectores, ejecuta los de las funciones
/// ya portadas (registradas en `VectorHarness.swiftDomain`) y lista las pendientes.
/// `Scripts/verify-domain.sh` lo corre junto al runner JS.
@Suite("Vectores de AD-6")
struct DomainVectorTests {

    @Test("Todos los ficheros de vectores decodifican y están bien formados")
    func vectorFilesAreWellFormed() throws {
        #expect(
            VectorBundle.missingFunctions().isEmpty,
            "Funciones sin fichero de vectores en el bundle: \(VectorBundle.missingFunctions()). ¿Falta `xcodegen generate`?"
        )
        let files = try VectorBundle.files()

        let iso = ISO8601DateFormatter()
        for (name, file) in files {
            #expect(file.schemaVersion == 1, "\(name): schemaVersion \(file.schemaVersion)")
            #expect(name == "\(file.function).json", "\(name): el fichero debe llamarse como su función")
            #expect(VectorHarness.knownFunctions.contains(file.function), "\(name): función '\(file.function)' desconocida")
            #expect(!file.vectors.isEmpty, "\(name): sin vectores")

            let ids = file.vectors.map(\.id)
            #expect(Set(ids).count == ids.count, "\(name): ids repetidos")

            for vector in file.vectors {
                if let identifier = vector.timeZone {
                    #expect(TimeZone(identifier: identifier) != nil, "\(name)#\(vector.id): zona '\(identifier)' desconocida para Foundation")
                }
                // Toda fecha de la entrada tiene que poder leerla el dominio Swift.
                for text in Self.dateLikeStrings(in: vector.input) {
                    #expect(iso.date(from: text) != nil, "\(name)#\(vector.id): '\(text)' no es ISO-8601 legible")
                }
            }
        }
    }

    @Test("Las funciones portadas pasan sus vectores; las demás quedan pendientes")
    func registeredFunctionsPassTheirVectors() throws {
        let run = VectorRun.evaluate(harness: .swiftDomain, files: try VectorBundle.files())
        for failure in run.failures {
            Issue.record("\(failure)")
        }

        // `verify-domain.sh` recoge estas líneas del log de xcodebuild.
        let list = run.pending.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value))" }
        print("AD-6 · Swift: \(run.passed) vectores pasan en funciones portadas.")
        print("AD-6 · Swift pendientes: \(list.isEmpty ? "ninguna" : list.joined(separator: ", "))")
    }

    private static func dateLikeStrings(in value: JSONValue) -> [String] {
        switch value {
        case .string(let text) where text.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil:
            [text]
        case .array(let items):
            items.flatMap(dateLikeStrings)
        case .object(let fields):
            fields.values.flatMap(dateLikeStrings)
        default:
            []
        }
    }
}

/// El arnés mismo: que una función registrada que falla **rompe**, que una sin
/// registrar queda pendiente y que la comparación es la de `run-js.js`. Sin esto, el
/// registro vacío de hoy no demostraría nada sobre el de mañana.
@Suite("Arnés de vectores")
struct VectorHarnessTests {

    private static func vector(_ json: String) throws -> DomainVector {
        try JSONDecoder().decode(DomainVector.self, from: Data(json.utf8))
    }

    private static let cadence = """
        { "id": "c", "sources": [], "input": { "cadenceSpm": 80, "gapS": 300 }, "expected": 400 }
        """

    @Test("Una función sin registrar queda pendiente")
    func unregisteredIsPending() throws {
        let harness = VectorHarness(implementations: [:])
        #expect(harness.verdict(for: try Self.vector(Self.cadence), of: "estimateSteps") == .pending)
    }

    @Test("Una función registrada que devuelve el valor esperado pasa")
    func registeredCorrectPasses() throws {
        let harness = VectorHarness(implementations: ["estimateSteps": { _ in .number(400) }])
        #expect(harness.verdict(for: try Self.vector(Self.cadence), of: "estimateSteps") == .passed)
    }

    @Test("Una función registrada que devuelve otro valor falla")
    func registeredWrongFails() throws {
        let harness = VectorHarness(implementations: ["estimateSteps": { _ in .number(401) }])
        guard case .failed = harness.verdict(for: try Self.vector(Self.cadence), of: "estimateSteps") else {
            Issue.record("un valor distinto no se detectó")
            return
        }
    }

    @Test("Una función portada que falla sus vectores reales produce fallos, y no pendientes")
    func wrongRegisteredFunctionFailsTheRealRun() throws {
        let files = try VectorBundle.files()
        let wrong = VectorHarness(implementations: ["estimateSteps": { _ in .number(-1) }])

        let run = VectorRun.evaluate(harness: wrong, files: files)

        #expect(!run.failures.isEmpty)
        #expect(run.failures.allSatisfy { $0.hasPrefix("estimateSteps.json#") })
        #expect(run.pending["estimateSteps"] == nil)
    }

    @Test("Un vector divergente también tiene que pasar en Swift")
    func divergentMustPassInSwift() throws {
        let divergent = try Self.vector("""
            { "id": "d", "sources": [], "divergence": "localTime", "timeZone": "America/Guayaquil",
              "input": {}, "expected": true }
            """)
        let wrong = VectorHarness(implementations: ["checkTimeOfDay": { _ in .bool(false) }])
        #expect(wrong.verdict(for: divergent, of: "checkTimeOfDay") != .passed)
    }

    @Test("Un error esperado se compara por el campo inválido")
    func thrownFieldIsCompared() throws {
        let throwing = try Self.vector("""
            { "id": "t", "sources": [], "input": { "cadenceSpm": "NaN", "gapS": 300 },
              "throws": { "field": "cadenceSpm", "js": "TypeError" } }
            """)
        #expect(throwing.input["cadenceSpm"]?.double?.isNaN == true)

        let right = VectorHarness(implementations: ["estimateSteps": { _ in throw DomainError.invalidValue(field: "cadenceSpm") }])
        let otherField = VectorHarness(implementations: ["estimateSteps": { _ in throw DomainError.invalidValue(field: "gapS") }])
        let noThrow = VectorHarness(implementations: ["estimateSteps": { _ in .number(0) }])

        #expect(right.verdict(for: throwing, of: "estimateSteps") == .passed)
        #expect(otherField.verdict(for: throwing, of: "estimateSteps") != .passed)
        #expect(noThrow.verdict(for: throwing, of: "estimateSteps") != .passed)
    }

    @Test("Comparación: tolerancia, null y objetos por las claves fijadas")
    func matcherSemantics() {
        #expect(VectorMatcher.matches(expected: .number(0.66), actual: .number(0.655), tolerance: 0.01))
        #expect(!VectorMatcher.matches(expected: .number(0.66), actual: .number(0.655), tolerance: nil))
        #expect(VectorMatcher.matches(expected: .null, actual: .null, tolerance: nil))
        #expect(!VectorMatcher.matches(expected: .null, actual: .number(0), tolerance: nil))
        #expect(VectorMatcher.matches(
            expected: .object(["isComplete": .bool(false)]),
            actual: .object(["isComplete": .bool(false), "percentage": .number(100)]),
            tolerance: nil
        ))
        #expect(!VectorMatcher.matches(
            expected: .object(["isComplete": .bool(false)]),
            actual: .object(["percentage": .number(100)]),
            tolerance: nil
        ))
        #expect(!VectorMatcher.matches(expected: .array([.number(1)]), actual: .array([.number(1), .number(2)]), tolerance: nil))
    }

    @Test("elapsedS está portado: sus vectores reales pasan y no quedan pendientes")
    func elapsedSIsPorted() throws {
        let files = try VectorBundle.files().filter { $0.file.function == "elapsedS" }
        #expect(!files.isEmpty)

        let run = VectorRun.evaluate(harness: .swiftDomain, files: files)

        #expect(run.failures.isEmpty, "\(run.failures)")
        #expect(run.pending["elapsedS"] == nil)
        #expect(run.passed == files.reduce(0) { $0 + $1.file.vectors.count })
    }

    @Test("v3distance está portado: sus vectores reales pasan y no quedan pendientes")
    func v3distanceIsPorted() throws {
        try Self.expectPorted("v3distance")
    }

    @Test("pace está portado: sus vectores reales pasan y no quedan pendientes")
    func paceIsPorted() throws {
        try Self.expectPorted("pace")
    }

    @Test("calculateCadence está portado: sus vectores reales pasan y no quedan pendientes")
    func calculateCadenceIsPorted() throws {
        try Self.expectPorted("calculateCadence")
    }

    @Test("pace: el tiempo en movimiento es durationS − pausesS, no durationS")
    func paceSubtractsPauses() throws {
        let paused = try Self.vector("""
            { "id": "p", "sources": [], "input": { "durationS": 3720, "pausesS": 120, "distanceM": 3370.63 },
              "expected": 1068 }
            """)
        let ignoringPauses = VectorHarness(implementations: ["pace": { vector in
            let pace = try MetricsCalculator.paceSecPerKm(
                movingS: vector.input["durationS"]?.double ?? 0,
                distanceM: vector.input["distanceM"]?.double ?? 0
            )
            return pace.map { .number(Double($0)) } ?? .null
        }])

        #expect(VectorHarness.swiftDomain.verdict(for: paused, of: "pace") == .passed)
        #expect(ignoringPauses.verdict(for: paused, of: "pace") != .passed)
    }

    @Test("v3distance y calculateCadence: un número de pasos no entero rompe el vector con su motivo", arguments: [
        "v3distance", "calculateCadence",
    ])
    func stepsMustBeIntegers(function: String) throws {
        let fractional = try Self.vector("""
            { "id": "f", "sources": [],
              "input": { "stepsMeasured": 1.5, "stepsEstimated": 0, "strideM": 0.655, "activeSeconds": 60 },
              "expected": 0 }
            """)
        guard case .failed(let reason) = VectorHarness.swiftDomain.verdict(for: fractional, of: function) else {
            Issue.record("\(function): unos pasos fraccionarios no rompieron el vector")
            return
        }
        #expect(reason.contains("stepsMeasured"))
    }

    private static func expectPorted(_ function: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let files = try VectorBundle.files().filter { $0.file.function == function }
        #expect(!files.isEmpty, sourceLocation: sourceLocation)

        let run = VectorRun.evaluate(harness: .swiftDomain, files: files)

        #expect(run.failures.isEmpty, "\(run.failures)", sourceLocation: sourceLocation)
        #expect(run.pending[function] == nil, sourceLocation: sourceLocation)
        #expect(run.passed == files.reduce(0) { $0 + $1.file.vectors.count }, sourceLocation: sourceLocation)
    }

    @Test("elapsedS: una pausa abierta en el vector falla con su motivo, no se ignora")
    func elapsedSRejectsOpenPause() throws {
        let open = try Self.vector("""
            { "id": "p", "sources": [],
              "input": { "startedAtMs": 0, "totalPausesMs": 0, "nowMs": 60000, "pausedAtMs": 30000 },
              "expected": 30 }
            """)
        guard case .failed = VectorHarness.swiftDomain.verdict(for: open, of: "elapsedS") else {
            Issue.record("una pausa abierta sin portar no rompió el vector")
            return
        }
    }

    @Test("Un vector sin expected ni throws no decodifica")
    func vectorNeedsExactlyOneOutcome() {
        #expect(throws: DecodingError.self) {
            try Self.vector(#"{ "id": "x", "sources": [], "input": {} }"#)
        }
    }
}
