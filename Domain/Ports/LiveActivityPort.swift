import Foundation

/// Live Activity de la sesión en curso (CAP-18) — AD-10, AD-11, AD-15, AD-21.
///
/// Actualización **por evento** (km, pausa, reanudación, fin), nunca periódica: el
/// reloj lo anima la extensión (AD-21). Si no está disponible se omite; no es un
/// fallo de sesión (AD-11).
public protocol LiveActivityPort: Sendable {
    /// Si el usuario permite Live Activities para la app, propiedad del adapter (AD-11).
    var status: PermissionStatus { get }

    /// Muestra la Live Activity de `sessionID` con `state`. Si ya había una de esta
    /// app, la termina antes.
    func start(sessionID: UUID, state: LiveActivityState) async throws(CapabilityError)

    /// Actualiza la Live Activity en curso. Sin actividad en curso, no hace nada.
    func update(_ state: LiveActivityState) async

    /// Termina la Live Activity en curso y la retira. Sin actividad en curso, no hace nada.
    func end() async
}
