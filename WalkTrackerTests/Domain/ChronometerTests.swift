import Domain
import Foundation
import Testing

/// `elapsedS = (now − startedAt) − totalPausesS − pausa abierta`, nunca negativo.
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

    @Test("Resta la pausa abierta: 60 s con una pausa abierta desde el segundo 30 → 30 s")
    func subtractsOpenPause() {
        let now = Self.start.addingTimeInterval(60)
        let pausedAt = Self.start.addingTimeInterval(30)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 0, pausedAt: pausedAt, now: now) == 30)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 10, pausedAt: pausedAt, now: now) == 20)
    }

    @Test("Una pausa abierta que no es posterior al inicio se ignora, como domain.js:75")
    func ignoresPauseNotAfterStart() {
        let now = Self.start.addingTimeInterval(60)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 0, pausedAt: Self.start.addingTimeInterval(-5), now: now) == 60)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 0, pausedAt: nil, now: now) == 60)
    }

    @Test("Con la pausa abierta tampoco da un negativo")
    func openPauseNeverNegative() {
        let now = Self.start.addingTimeInterval(60)
        #expect(Chronometer.elapsedS(startedAt: Self.start, totalPausesS: 50, pausedAt: Self.start.addingTimeInterval(30), now: now) == 0)
    }

    @Test("La sesión delega en el cronómetro con sus propias pausas")
    func sessionElapsed() throws {
        let session = try Session.start(at: Self.start, strideM: 0.655)
        #expect(session.elapsedS(at: Self.start.addingTimeInterval(125)) == 125)
    }
}
