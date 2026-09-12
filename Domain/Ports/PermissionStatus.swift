import Foundation

/// Estado del permiso de una capacidad de sistema, tal como lo expone su puerto.
///
/// Lo posee el adapter y **nadie más consulta al sistema** (AD-11): una vista o un
/// store leen `status` del puerto, nunca la API de autorización del framework. La
/// respuesta a "falta esta capacidad" vive en `DegradationPolicy`, no aquí.
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
