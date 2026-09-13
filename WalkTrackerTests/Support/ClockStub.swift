import Domain
import Foundation
import Synchronization

/// `ClockPort` de test: el instante lo fija el test y avanza solo cuando el test lo
/// mueve. Es lo que hace comprobable "el tiempo en background cuenta" sin esperar.
final class ClockStub: ClockPort {

    private let instant: Mutex<Date>

    init(now: Date) {
        instant = Mutex(now)
    }

    var now: Date { instant.withLock { $0 } }

    /// Calendario fijo en UTC: ningún test depende de la zona de la máquina.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func set(_ date: Date) {
        instant.withLock { $0 = date }
    }

    func advance(by seconds: TimeInterval) {
        instant.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
