import Foundation

/// El dominio nunca llama a `Date()`, `Date.now` ni a `Calendar.current` (AD-3, AD-19):
/// el tiempo y el calendario entran por este puerto, que es lo que hace vectorizable
/// todo cálculo temporal (AD-6).
public protocol ClockPort: Sendable {
    /// Instante actual, inyectado. Nunca `Date()` dentro del dominio.
    var now: Date { get }
    /// El único `Calendar` de la app (AD-19): ISO-8601, lunes como primer día,
    /// zona horaria del dispositivo.
    var calendar: Calendar { get }
}
