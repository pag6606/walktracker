import Foundation

/// Conteo de pasos del coprocesador (CAP-2, CAP-3) — AD-7, AD-10, AD-11, AD-21.
///
/// Dos modos que **no se combinan** (AD-21): actualizaciones continuas mientras hay
/// sesión activa, y consulta por rango reservada a la reconciliación (AD-8).
public protocol MotionPort: Sendable {
    /// Estado del permiso de Motion & Fitness, propiedad del adapter (AD-11).
    var status: PermissionStatus { get }

    /// Pide el permiso si aún no se ha decidido y devuelve el estado resultante.
    /// Debe ir precedido de pre-pantalla (AD-11); el puerto no la muestra.
    func requestPermission() async -> PermissionStatus

    /// Actualizaciones continuas desde `start`. Cada muestra es **acumulada** desde
    /// `start`, no incremental. Cancelar la iteración detiene el podómetro. Si el stream
    /// termina sin que quien consume lo cancele, es que el sistema lo detuvo; `status` lo
    /// explica solo cuando la causa es el permiso.
    func updates(from start: Date) -> AsyncStream<PedometerSample>

    /// Pasos y distancia en `[start, end]`. `nil` si el sistema no tiene datos para ese
    /// rango. El sistema solo cubre 7 días y **fuera de ese rango devuelve datos
    /// parciales sin error**: quien llama no consulta gaps más antiguos (AD-8).
    func query(from start: Date, to end: Date) async throws(CapabilityError) -> PedometerSample?
}
