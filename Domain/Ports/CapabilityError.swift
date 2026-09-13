import Foundation

/// Error tipado de los puertos de capacidad de sistema (AD-10, AD-11).
///
/// Un adapter **nunca** deja escapar un error crudo de CoreMotion, HealthKit o
/// ActivityKit: lo traduce a uno de estos casos en el borde. La única traducción a
/// mensaje de usuario vive en la UI (Consistency Conventions · Errores).
public enum CapabilityError: Error, Equatable, Sendable {
    /// El dispositivo o el sistema no ofrece la capacidad (sin coprocesador, Salud no
    /// disponible, Live Activities no soportadas).
    case unavailable
    /// La capacidad existe pero no hay permiso: denegado, restringido o aún sin decidir.
    case notAuthorized
    /// El sistema devolvió un fallo durante `operation`. El nombre de la operación es
    /// diagnóstico, no un mensaje de usuario.
    case failed(operation: String)
}
