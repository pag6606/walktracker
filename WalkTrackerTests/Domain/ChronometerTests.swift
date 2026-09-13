import Domain
import Foundation
import Testing

/// `elapsedS = (now − startedAt) − totalPausesS`, nunca negativo.
@Suite("Cronómetro wall-clock")
struct ChronometerTests {

    private static let start = Date(timeIntervalSince1970: 1_000)

    @Test("Resta el inicio y las pausas")
    func subtractsPauses() {
        let now = Self.start.addingTimeInterval(62 * 60)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 120, now: now) == 3600)
    }

    @Test("El reloj hacia atrás da 0, nunca un negativo")
    func clockGoingBackwardsIsZero() {
        let now = Self.start.addingTimeInterval(-30)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 0, now: now) == 0)
    }

    @Test("Pausas mayores que el total dan 0")
    func pausesLongerThanTotalAreZero() {
        let now = Self.start.addingTimeInterval(60)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 120, now: now) == 0)
    }

    @Test("En el instante de inicio es 0")
    func zeroAtStart() {
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 0, now: Self.start) == 0)
    }

    @Test("La sesión delega en el cronómetro con sus propias pausas")
    func sessionElapsed() throws {
        let session = try Session.start(at: Self.start, strideM: 0.655)
        #expect(session.elapsedS(at: Self.start.addingTimeInterval(125)) == 125)
    }
}
