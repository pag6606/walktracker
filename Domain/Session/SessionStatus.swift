import Foundation

/// Estado del agregado `Session` (domain-model.md §2): `active → paused → active →
/// finished`. El "idle" de antes de iniciar no es un estado del agregado: es que no
/// hay sesión, y lo representa `SessionStore` con `session == nil`.
///
/// La 1.1 solo crea sesiones `active`; pausar, reanudar y finalizar llegan en la 1.4.
public enum SessionStatus: String, Equatable, Sendable, Codable {
    case active
    case paused
    case finished
}

/// Procedencia de la sesión (domain-model.md §7). Con arranque limpio (OQ-3) toda
/// sesión de la v1 iOS es `ios`; los otros dos casos se conservan por compatibilidad.
public enum SessionSource: String, Equatable, Sendable, Codable {
    case ios
    case v3
    case migrated
}
