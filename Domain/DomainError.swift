import Foundation

/// Errores tipados del dominio (AD-4). El dominio nunca lanza errores crudos del
/// sistema: una única traducción a mensaje de usuario vive en la capa de UI.
public enum DomainError: Error, Equatable, Sendable {
    /// Un valor cruzó la frontera del dominio fuera de su rango admisible.
    case invalidValue(field: String)
    /// Se emitió un comando que el estado actual del agregado no admite.
    case invalidTransition(from: String, to: String)
}
