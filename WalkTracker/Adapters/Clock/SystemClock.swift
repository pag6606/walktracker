import Domain
import Foundation

/// Implementación de `ClockPort` en el borde (AD-10). Es el **único** sitio del
/// producto donde se construye un `Calendar` y donde se lee el reloj del sistema:
/// `Calendar.current` está prohibido en todas partes (AD-19).
public struct SystemClock: ClockPort {

    public init() {}

    public var now: Date { Date() }

    /// El único `AppCalendar` (AD-19): ISO-8601, lunes como primer día, zona horaria
    /// del dispositivo. Semana ISO, rachas y agrupación del historial usan este.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone.current
        return calendar
    }
}
