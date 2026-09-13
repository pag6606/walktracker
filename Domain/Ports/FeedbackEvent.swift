import Foundation

/// Los momentos de la sesión que merecen feedback háptico y sonoro (CAP-12).
///
/// El conjunto es cerrado: un evento nuevo sin parámetros en el adapter no compila.
public enum FeedbackEvent: CaseIterable, Equatable, Sendable {
    /// Inicio de sesión.
    case sessionStart
    /// Kilómetro completado.
    case kilometer
    /// Meta semanal cumplida.
    case goal
    /// Logro desbloqueado.
    case achievement
}
