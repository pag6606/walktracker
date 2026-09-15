import Foundation

/// Coordenadas **aproximadas**: el `LocationPort` las entrega ya redondeadas a 2 decimales
/// (≈ 1 km). Es el único punto donde la privacidad es verificable (AR-12, AD-10): nada
/// después de él ve una coordenada más precisa.
public struct Coordinates: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Ubicación aproximada para el clima de la sesión (CAP-5) — AD-10, AD-11, AR-12.
///
/// Una sola lectura de baja precisión, nunca continua ni precisa. Sin permiso o sin ubicación
/// la sesión sigue sin clima: nunca bloquea.
public protocol LocationPort: Sendable {
    /// Estado del permiso de ubicación "mientras se usa", propiedad del adapter (AD-11).
    var status: PermissionStatus { get }

    /// Pide el permiso si aún no se ha decidido y devuelve el estado resultante.
    /// Debe ir precedido de pre-pantalla (AD-11); el puerto no la muestra.
    func requestPermission() async -> PermissionStatus

    /// Una lectura aproximada, **redondeada a 2 decimales** antes de devolverla y acotada a
    /// 3 s (AR-12). Una ubicación reciente del sistema (≤ 5 min) vale.
    ///
    /// - Throws: `notAuthorized` sin permiso; `unavailable` si el sistema no ofrece ubicación;
    ///   `failed` si la lectura falla o agota el tope.
    func approximateLocation() async throws(CapabilityError) -> Coordinates
}
