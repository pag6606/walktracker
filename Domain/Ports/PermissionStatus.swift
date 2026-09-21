import Foundation

/// Estado del permiso de una capacidad de sistema, tal como lo expone su puerto.
///
/// Lo posee el adapter y **nadie más consulta al sistema** (AD-11): una vista o un
/// store leen `status` del puerto, nunca la API de autorización del framework.
///
/// La respuesta a "falta esta capacidad" **no vive aquí**: la decide cada frontera, según
/// la tabla de AD-11, y no hay ni va a haber un tipo que la centralice (enmienda del
/// 2026-09-21). Las dos fronteras escritas hoy:
///
/// - **Movimiento** — `SessionStore.start()` (`Application/SessionStore+StartFlow.swift`):
///   `.denied`/`.restricted` y `.unavailable` llevan a `MotionBlockedView`. Es la **única**
///   degradación bloqueante del producto.
/// - **Ubicación** — `SessionStore.beginWeatherForNewSession()`
///   (`Application/SessionStore+Weather.swift`): cualquier estado que no sea `.granted` deja
///   la sesión sin clima, nunca la bloquea.
///
/// La tercera fila viva de la tabla —"red no disponible"— **no pasa por aquí**: no es un
/// permiso, no tiene `status` en ningún puerto, y se expresa como `CapabilityError` y un
/// `nil` silencioso en `OpenMeteoAdapter` y `SessionStore+Weather`.
public enum PermissionStatus: Equatable, Sendable {
    /// El usuario aún no ha decidido. Pedirlo exige pre-pantalla (AD-11).
    case notDetermined
    /// Concedido: la capacidad puede usarse.
    case granted
    /// Denegado por el usuario. Solo Ajustes lo revierte.
    case denied
    /// Restringido por el sistema (control parental, MDM). El usuario no puede concederlo.
    case restricted
    /// El dispositivo no ofrece la capacidad, con independencia del permiso.
    case unavailable
}
