import Foundation

/// Feedback háptico y sonoro de la sesión (CAP-12) — AD-10.
///
/// No hay permiso que poseer: ni la háptica ni el sonido de sistema lo requieren.
/// La preferencia de sonido **no** vive aquí —es de `SettingsStore`—: llega en cada
/// llamada.
public protocol FeedbackPort: Sendable {
    /// Dispara la háptica de `event` y, si `soundEnabled`, su sonido de sistema.
    /// Nunca falla hacia fuera: un feedback perdido no es un fallo de sesión.
    func fire(_ event: FeedbackEvent, soundEnabled: Bool)
}
