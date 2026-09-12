import ActivityKit
import Foundation

/// Atributos estáticos de la Live Activity. Vive aparte de `ActivitySnapshot` porque
/// la conformidad a `ActivityAttributes` exige `import ActivityKit` y el contrato de
/// datos no debe arrastrar el framework (AD-15).
public struct WalkTrackerActivityAttributes: ActivityAttributes {

    /// El estado dinámico es el snapshot compartido: un único `ContentState`, para que
    /// dos historias no elijan formatos incompatibles (AD-15).
    public typealias ContentState = ActivitySnapshot

    /// Identidad de la sesión que esta actividad representa.
    public let sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }
}
