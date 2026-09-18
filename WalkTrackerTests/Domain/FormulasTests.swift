import Domain
import Foundation
import Testing

@testable import WalkTracker

/// `formulas.json` se valida al arrancar y falla ruidosamente, como el catálogo.
@Suite("Constantes de fórmula · validación al arrancar")
struct FormulasTests {

    /// Un `formulas.json` válido con los campos sustituidos por `overrides` (JSON crudo).
    private static func json(_ overrides: [String: String] = [:]) -> Data {
        var fields = [
            "schemaVersion": "1",
            "defaultStrideM": "0.655",
            "reconciliationTimeoutS": "3",
            "orphanSessionThresholdS": "21600",
            "maxEstimableGapS": "1200",
            "provisional": #"["reconciliationTimeoutS", "orphanSessionThresholdS"]"#,
        ]
        fields.merge(overrides) { $1 }
        let body = fields.sorted { $0.key < $1.key }.map { #""\#($0.key)": \#($0.value)"# }.joined(separator: ", ")
        return Data("{ \(body) }".utf8)
    }

    private static func formulas(
        defaultStrideM: Double = 0.655,
        reconciliationTimeoutS: Double = 3,
        orphanSessionThresholdS: Double = 21_600,
        maxEstimableGapS: Double = 1200,
        provisional: [String] = ["reconciliationTimeoutS", "orphanSessionThresholdS"]
    ) -> Formulas {
        Formulas(
            schemaVersion: 1,
            defaultStrideM: defaultStrideM,
            reconciliationTimeoutS: reconciliationTimeoutS,
            orphanSessionThresholdS: orphanSessionThresholdS,
            maxEstimableGapS: maxEstimableGapS,
            provisional: provisional
        )
    }

    @Test("El fichero real valida y trae la zancada por defecto de domain.js:22")
    func bundledFormulasAreValid() throws {
        let formulas = try CompositionRoot.loadFormulas(from: .main)
        #expect(formulas.schemaVersion == 1)
        #expect(formulas.defaultStrideM == 0.655)
    }

    @Test("El fichero real trae el timeout de reconciliación de AD-8 fijado en la 8.4: 1 s, ya no provisional")
    func bundledReconciliationTimeoutIsFixed() throws {
        let formulas = try CompositionRoot.loadFormulas(from: .main)
        #expect(formulas.reconciliationTimeoutS == 1)
        #expect(!formulas.provisional.contains("reconciliationTimeoutS"))
        #expect(!formulas.provisional.contains("defaultStrideM"), "la zancada es la portada de domain.js, no provisional")
    }

    @Test("El fichero real trae el umbral de sesión huérfana de AD-18: 6 h, decidido y fijado en la 8.4")
    func bundledOrphanThresholdIsFixed() throws {
        let formulas = try CompositionRoot.loadFormulas(from: .main)
        #expect(formulas.orphanSessionThresholdS == 21_600)
        #expect(!formulas.provisional.contains("orphanSessionThresholdS"))
    }

    @Test("Tras la 8.4 ninguna constante del fichero real queda provisional")
    func bundledHasNoProvisional() throws {
        #expect(try CompositionRoot.loadFormulas(from: .main).provisional.isEmpty)
    }

    @Test("Un JSON completo decodifica")
    func completeJSONDecodes() throws {
        #expect(try Formulas.decode(from: Self.json()) == Self.formulas())
        #expect(try Formulas.decode(from: Self.json(["provisional": "[]"])).provisional.isEmpty)
    }

    @Test("Zancada ≤ 0: invalidValue(defaultStrideM)", arguments: ["0", "-0.655"])
    func nonPositiveStrideThrows(value: String) {
        #expect(throws: FormulasError.invalidValue(field: "defaultStrideM")) {
            try Formulas.decode(from: Self.json(["defaultStrideM": value]))
        }
    }

    @Test("Zancada no finita: invalidValue(defaultStrideM)")
    func nonFiniteStrideThrows() {
        #expect(throws: FormulasError.invalidValue(field: "defaultStrideM")) {
            try Self.formulas(defaultStrideM: .nan).validate()
        }
        #expect(throws: FormulasError.invalidValue(field: "defaultStrideM")) {
            try Self.formulas(defaultStrideM: .infinity).validate()
        }
    }

    @Test("Timeout de reconciliación ≤ 0: invalidValue(reconciliationTimeoutS)", arguments: ["0", "-3"])
    func nonPositiveTimeoutThrows(value: String) {
        #expect(throws: FormulasError.invalidValue(field: "reconciliationTimeoutS")) {
            try Formulas.decode(from: Self.json(["reconciliationTimeoutS": value]))
        }
    }

    @Test("Timeout de reconciliación no finito: invalidValue(reconciliationTimeoutS)", arguments: [Double.nan, .infinity])
    func nonFiniteTimeoutThrows(value: Double) {
        #expect(throws: FormulasError.invalidValue(field: "reconciliationTimeoutS")) {
            try Self.formulas(reconciliationTimeoutS: value).validate()
        }
    }

    @Test("Umbral de sesión huérfana ≤ 0: invalidValue(orphanSessionThresholdS)", arguments: ["0", "-21600"])
    func nonPositiveOrphanThresholdThrows(value: String) {
        #expect(throws: FormulasError.invalidValue(field: "orphanSessionThresholdS")) {
            try Formulas.decode(from: Self.json(["orphanSessionThresholdS": value]))
        }
    }

    @Test("Umbral de sesión huérfana no finito: invalidValue(orphanSessionThresholdS)", arguments: [Double.nan, .infinity])
    func nonFiniteOrphanThresholdThrows(value: Double) {
        #expect(throws: FormulasError.invalidValue(field: "orphanSessionThresholdS")) {
            try Self.formulas(orphanSessionThresholdS: value).validate()
        }
    }

    @Test("El fichero real trae el tope de gap estimable de R1: 20 min, decidido por Paul y no provisional")
    func bundledMaxEstimableGapIsFixed() throws {
        let formulas = try CompositionRoot.loadFormulas(from: .main)
        #expect(formulas.maxEstimableGapS == 1200)
        #expect(!formulas.provisional.contains("maxEstimableGapS"))
    }

    @Test("Tope de gap estimable ≤ 0: invalidValue(maxEstimableGapS)", arguments: ["0", "-1200"])
    func nonPositiveMaxEstimableGapThrows(value: String) {
        #expect(throws: FormulasError.invalidValue(field: "maxEstimableGapS")) {
            try Formulas.decode(from: Self.json(["maxEstimableGapS": value]))
        }
    }

    @Test("Tope de gap estimable no finito: invalidValue(maxEstimableGapS)", arguments: [Double.nan, .infinity])
    func nonFiniteMaxEstimableGapThrows(value: Double) {
        #expect(throws: FormulasError.invalidValue(field: "maxEstimableGapS")) {
            try Self.formulas(maxEstimableGapS: value).validate()
        }
    }

    @Test("provisional con un nombre que no es una constante: invalidValue(provisional)", arguments: [
        ["reconciliationTimeout"], ["reconciliationTimeoutS", "orphanSessionThreshold"], ["schemaVersion"], ["maxEstimableGap"],
    ])
    func unknownProvisionalThrows(names: [String]) {
        #expect(throws: FormulasError.invalidValue(field: "provisional")) {
            try Self.formulas(provisional: names).validate()
        }
    }

    @Test("schemaVersion 2: unsupportedSchemaVersion")
    func unsupportedSchemaVersionThrows() {
        #expect(throws: FormulasError.unsupportedSchemaVersion(2)) {
            try Formulas.decode(from: Self.json(["schemaVersion": "2"]))
        }
    }

    @Test("Sin una constante o sin JSON: malformed, nunca un valor de reserva", arguments: [
        #"{ "schemaVersion": 1 }"#,
        #"{ "schemaVersion": 1, "defaultStrideM": "0.655", "reconciliationTimeoutS": 3, "orphanSessionThresholdS": 21600, "maxEstimableGapS": 1200, "provisional": [] }"#,
        #"{ "schemaVersion": 1, "defaultStrideM": 0.655, "orphanSessionThresholdS": 21600, "maxEstimableGapS": 1200, "provisional": [] }"#,
        #"{ "schemaVersion": 1, "defaultStrideM": 0.655, "reconciliationTimeoutS": 3, "maxEstimableGapS": 1200, "provisional": [] }"#,
        #"{ "schemaVersion": 1, "defaultStrideM": 0.655, "reconciliationTimeoutS": 3, "orphanSessionThresholdS": 21600, "provisional": [] }"#,
        #"{ "schemaVersion": 1, "defaultStrideM": 0.655, "reconciliationTimeoutS": 3, "orphanSessionThresholdS": 21600, "maxEstimableGapS": 1200 }"#,
        #"{ "schemaVersion": 1, "defaultStrideM": 0.655, "reconciliationTimeoutS": 3, "orphanSessionThresholdS": 21600, "maxEstimableGapS": 1200, "provisional": "reconciliationTimeoutS" }"#,
        "no es json",
    ])
    func malformedThrows(json: String) {
        #expect {
            try Formulas.decode(from: Data(json.utf8))
        } throws: { error in
            guard case FormulasError.malformed = error else { return false }
            return true
        }
    }

    @Test("Un bundle sin formulas.json no da constantes")
    func missingResourceThrows() {
        let testBundle = Bundle(for: FormulasBundleToken.self)
        #expect {
            try CompositionRoot.loadFormulas(from: testBundle)
        } throws: { error in
            guard case FormulasError.malformed = error else { return false }
            return true
        }
    }
}

private final class FormulasBundleToken {}
