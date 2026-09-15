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
    /// Tope en segundos de la reconciliación atómica del background (AD-8): al agotarse,
    /// la consulta cuenta como sin dato y los comandos se liberan. > 0 y finito.
    /// Fijado en la 8.4 (1 s): max(1 s, 5 × la consulta más lenta medida en el iPhone 14),
    /// según `8-4-medicion-referencia.md`.
    public let reconciliationTimeoutS: Double
    /// Umbral en segundos de la sesión huérfana (AD-18): al arrancar, una sesión con
    /// `now − startedAt` por encima no se restaura, se cierra recortada al último dato real.
    /// > 0 y finito. 6 h: valor decidido por Paul (1.6), no medible en una caminata; la 8.4 lo
    /// deja fijado sin medición.
    public let orphanSessionThresholdS: Double
    /// Nombres de las constantes cuyo valor aún es provisional (epic-1-context, Constantes
    /// provisionales). Cada nombre debe ser una constante de este fichero.
    public let provisional: [String]

    /// Las constantes que `provisional` puede nombrar.
    public static let constantNames: Set<String> = ["defaultStrideM", "reconciliationTimeoutS", "orphanSessionThresholdS"]

    public init(
        schemaVersion: Int,
        defaultStrideM: Double,
        reconciliationTimeoutS: Double,
        orphanSessionThresholdS: Double,
        provisional: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.defaultStrideM = defaultStrideM
        self.reconciliationTimeoutS = reconciliationTimeoutS
        self.orphanSessionThresholdS = orphanSessionThresholdS
        self.provisional = provisional
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
        guard reconciliationTimeoutS.isFinite, reconciliationTimeoutS > 0 else {
            throw .invalidValue(field: "reconciliationTimeoutS")
        }
        guard orphanSessionThresholdS.isFinite, orphanSessionThresholdS > 0 else {
            throw .invalidValue(field: "orphanSessionThresholdS")
        }
        guard provisional.allSatisfy(Self.constantNames.contains) else {
            throw .invalidValue(field: "provisional")
        }
    }
}
