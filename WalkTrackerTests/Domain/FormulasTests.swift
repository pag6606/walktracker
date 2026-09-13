import Domain
import Foundation
import Testing

@testable import WalkTracker

/// `formulas.json` se valida al arrancar y falla ruidosamente, como el catálogo.
@Suite("Constantes de fórmula · validación al arrancar")
struct FormulasTests {

    @Test("El fichero real valida y trae la zancada por defecto de domain.js:22")
    func bundledFormulasAreValid() throws {
        let formulas = try CompositionRoot.loadFormulas(from: .main)
        #expect(formulas.schemaVersion == 1)
        #expect(formulas.defaultStrideM == 0.655)
    }

    @Test("Zancada ≤ 0: invalidValue(defaultStrideM)", arguments: ["0", "-0.655"])
    func nonPositiveStrideThrows(value: String) {
        #expect(throws: FormulasError.invalidValue(field: "defaultStrideM")) {
            try Formulas.decode(from: Data(#"{ "schemaVersion": 1, "defaultStrideM": \#(value) }"#.utf8))
        }
    }

    @Test("Zancada no finita: invalidValue(defaultStrideM)")
    func nonFiniteStrideThrows() {
        #expect(throws: FormulasError.invalidValue(field: "defaultStrideM")) {
            try Formulas(schemaVersion: 1, defaultStrideM: .nan).validate()
        }
        #expect(throws: FormulasError.invalidValue(field: "defaultStrideM")) {
            try Formulas(schemaVersion: 1, defaultStrideM: .infinity).validate()
        }
    }

    @Test("schemaVersion 2: unsupportedSchemaVersion")
    func unsupportedSchemaVersionThrows() {
        #expect(throws: FormulasError.unsupportedSchemaVersion(2)) {
            try Formulas.decode(from: Data(#"{ "schemaVersion": 2, "defaultStrideM": 0.655 }"#.utf8))
        }
    }

    @Test("Sin la constante o sin JSON: malformed, nunca un valor de reserva", arguments: [
        #"{ "schemaVersion": 1 }"#, #"{ "schemaVersion": 1, "defaultStrideM": "0.655" }"#, "no es json",
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
