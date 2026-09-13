import Foundation

/// Por qué `formulas.json` no vale. La app no arranca con ninguno de estos.
public enum FormulasError: Error, Equatable, Sendable {
    /// El JSON no se puede leer o no tiene la forma del esquema.
    case malformed(String)
    case unsupportedSchemaVersion(Int)
    /// Una constante fuera de su rango admisible.
    case invalidValue(field: String)
}

/// Constantes de fórmula de `Resources/formulas.json` (epic-1-context, Constantes
/// provisionales). Las constantes portadas del JS se consolidan aquí, no en el código.
///
/// Se valida al arrancar, como el catálogo de logros, y **falla ruidosamente**: con
/// una constante inválida la app no arranca, nunca degrada a un valor de reserva.
public struct Formulas: Equatable, Sendable, Codable {

    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    /// Zancada por defecto en metros (`domain.js:22` `DEFAULT_STRIDE`).
    public let defaultStrideM: Double

    public init(schemaVersion: Int, defaultStrideM: Double) {
        self.schemaVersion = schemaVersion
        self.defaultStrideM = defaultStrideM
    }

    /// Decodifica y valida. Único punto de entrada desde datos.
    public static func decode(from data: Data) throws(FormulasError) -> Formulas {
        let formulas: Formulas
        do {
            formulas = try JSONDecoder().decode(Formulas.self, from: data)
        } catch {
            throw .malformed(String(describing: error))
        }
        try formulas.validate()
        return formulas
    }

    /// Lanza la primera causa encontrada: versión, después cada constante.
    public func validate() throws(FormulasError) {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw .unsupportedSchemaVersion(schemaVersion)
        }
        do {
            try Session.validateStride(defaultStrideM)
        } catch {
            throw .invalidValue(field: "defaultStrideM")
        }
    }
}
