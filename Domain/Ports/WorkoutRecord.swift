import Foundation

/// Caminata lista para escribirse en Apple Salud como entrenamiento (CAP-11).
///
/// Metros y segundos, como todo el dominio. Se valida en la frontera: un intervalo
/// invertido no llega nunca a HealthKit, que lo rechaza con una excepción de
/// Objective-C en vez de con un error.
public struct WorkoutRecord: Equatable, Sendable {
    /// Inicio de la caminata.
    public let start: Date
    /// Fin de la caminata. Estrictamente posterior a `start`.
    public let end: Date
    /// Pasos de la sesión. No negativos.
    public let steps: Int
    /// Distancia en **metros**, sin truncar. No negativa y finita.
    public let distance: Double

    public init(start: Date, end: Date, steps: Int, distance: Double) throws(DomainError) {
        guard end > start else { throw .invalidValue(field: "end") }
        guard steps >= 0 else { throw .invalidValue(field: "steps") }
        guard distance >= 0, distance.isFinite else { throw .invalidValue(field: "distance") }
        self.start = start
        self.end = end
        self.steps = steps
        self.distance = distance
    }

    /// Duración en segundos.
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
