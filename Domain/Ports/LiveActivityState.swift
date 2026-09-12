import Foundation

/// Magnitudes crudas de la sesión para la Live Activity (CAP-18).
///
/// El dominio entrega números; el adapter los convierte en el `ActivitySnapshot`
/// formateado de `Shared/` (AD-15). Así `Domain/` no conoce `Shared` ni ActivityKit
/// (AD-3), y el formateo vive en el adapter hasta que el Epic 7 lo lleve a `Shared`.
public struct LiveActivityState: Equatable, Sendable {
    /// Pasos de la sesión.
    public let steps: Int
    /// Distancia en **metros**, sin truncar.
    public let distance: Double
    /// Ritmo en segundos por kilómetro. `nil` cuando el dominio no lo produce (por
    /// debajo de 100 m), nunca `0` (AD-4).
    public let pace: Int?
    /// Instante desde el que se cuenta el cronómetro, **ya desplazado** por el tiempo
    /// acumulado en pausa.
    public let timerStart: Date
    /// Segundos transcurridos congelados mientras la sesión está en pausa; `nil`
    /// mientras corre.
    public let frozenElapsed: TimeInterval?

    public init(
        steps: Int,
        distance: Double,
        pace: Int?,
        timerStart: Date,
        frozenElapsed: TimeInterval? = nil
    ) {
        self.steps = steps
        self.distance = distance
        self.pace = pace
        self.timerStart = timerStart
        self.frozenElapsed = frozenElapsed
    }
}
