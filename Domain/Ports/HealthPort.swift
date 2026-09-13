import Foundation

/// Escritura de caminatas en Apple Salud (CAP-11) — AD-10, AD-11.
///
/// Si Salud falta o falla, la sesión se guarda local igual y el resumen dice "no
/// sincronizado" (AD-11): por eso todo fallo es un `CapabilityError`, nunca un error
/// crudo de HealthKit.
public protocol HealthPort: Sendable {
    /// Estado del permiso de **escritura** de entrenamientos, propiedad del adapter
    /// (AD-11). HealthKit no revela el permiso de lectura, y aquí no se lee nada.
    var status: PermissionStatus { get }

    /// Pide autorización de escritura y devuelve el estado resultante. Debe ir
    /// precedida de pre-pantalla (AD-11); el puerto no la muestra.
    func requestAuthorization() async throws(CapabilityError) -> PermissionStatus

    /// Escribe `record` como entrenamiento de caminata. Lanza si Salud no está
    /// disponible, si no hay permiso, o si falla **cualquier** paso intermedio.
    func writeWorkout(_ record: WorkoutRecord) async throws(CapabilityError)
}
