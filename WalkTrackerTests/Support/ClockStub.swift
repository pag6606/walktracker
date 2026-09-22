import Domain
import Foundation
import Synchronization

/// `ClockPort` de test: el instante lo fija el test y avanza solo cuando el test lo
/// mueve. Es lo que hace comprobable "el tiempo en background cuenta" sin esperar.
final class ClockStub: ClockPort {

    private let instant: Mutex<Date>
    /// Zona del `AppCalendar` de este doble. **UTC por omisión**, que es lo que han usado todos
    /// los tests desde que existe.
    private let zone: TimeZone

    /// - Parameter timeZone: zona IANA del calendario. Por omisión `"UTC"`, para que ningún test
    ///   dependa de la zona de la máquina.
    ///
    ///   **Un test que quiera comprobar que la hora es LOCAL tiene que pasar otra** (3.2): con
    ///   UTC el calendario local y el de `motivation.js` dan lo mismo, así que sustituir
    ///   `clock.calendar` por un `Calendar` en UTC —que es lo que AD-19 prohíbe— salía en verde.
    ///   Los vectores tapaban el hueco solo a medias: llaman al motor **directamente** con la
    ///   zona del vector, sin pasar por la costura donde el calendario se cablea.
    init(now: Date, timeZone: String = "UTC") {
        instant = Mutex(now)
        zone = TimeZone(identifier: timeZone) ?? TimeZone(identifier: "UTC")!
    }

    var now: Date { instant.withLock { $0 } }

    /// El `AppCalendar` de AD-19 en la zona de este doble: ISO-8601 y lunes primero.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = zone
        return calendar
    }

    func set(_ date: Date) {
        instant.withLock { $0 = date }
    }

    func advance(by seconds: TimeInterval) {
        instant.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
