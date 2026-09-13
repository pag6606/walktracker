import Foundation

/// Muestra del podómetro, ya fuera de CoreMotion (AD-7, AD-12).
///
/// La muestra del framework no es `Sendable`, y sus `NSNumber` tampoco: el adapter extrae
/// estos valores **dentro del handler**, en la cola serie de CoreMotion, y solo este
/// DTO cruza al resto de la app.
public struct PedometerSample: Equatable, Sendable {
    /// Pasos acumulados en el intervalo `[start, end]`.
    public let steps: Int
    /// Distancia en **metros**, sin truncar. `nil` cuando el sistema no la estima:
    /// una métrica ausente nunca es `0` (AD-4, AD-22).
    public let distance: Double?
    /// Inicio del intervalo que cubre la muestra.
    public let start: Date
    /// Fin del intervalo que cubre la muestra.
    public let end: Date

    public init(steps: Int, distance: Double?, start: Date, end: Date) {
        self.steps = steps
        self.distance = distance
        self.start = start
        self.end = end
    }
}
