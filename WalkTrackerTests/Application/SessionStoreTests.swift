import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 1.1 sobre `SessionStore`, con el reloj en un `ClockStub` y el permiso
/// ya concedido en un `MotionStub`.
@MainActor
@Suite("SessionStore · iniciar y cronómetro")
struct SessionStoreTests: SessionStoreSuite {

    @Test("Iniciar: sesión active con los valores iniciales en el instante del reloj")
    func startCreatesActiveSession() async throws {
        let store = SessionStoreFixture().store
        #expect(store.session == nil)
        #expect(!store.hasSession)
        #expect(store.elapsedS == 0)

        await store.start()

        let session = try #require(store.session)
        #expect(store.hasSession)
        #expect(session.status == .active)
        #expect(session.startedAt == Self.t0)
        #expect(session.stepsMeasured == 0)
        #expect(session.stepsEstimated == 0)
        #expect(session.strideM == 0.655)
        #expect(session.source == .ios)
        #expect(session.endedAt == nil)
        #expect(session.totalPausesS == 0)
        #expect(store.elapsedS == 0)
        #expect(store.startFailure == nil)
    }

    @Test("Zancada inválida: invalidValue(strideM), ninguna sesión y ningún conteo", arguments: [0, -1, Double.nan, .infinity])
    func invalidStrideCreatesNothing(stride: Double) async {
        let fixture = SessionStoreFixture(strideM: stride)
        let (motion, store) = (fixture.motion, fixture.store)

        await store.start()

        #expect(store.startFailure == .invalidSession(.invalidValue(field: "strideM")))
        #expect(store.session == nil)
        #expect(!store.hasSession)
        #expect(motion.updateStarts.isEmpty)
        #expect(!store.isCountingSteps)
    }

    @Test("El tiempo se lee del reloj en cada lectura")
    func elapsedFollowsClock() async {
        let fixture = SessionStoreFixture()
        let (clock, store) = (fixture.clock, fixture.store)
        await store.start()

        clock.advance(by: 1)
        #expect(store.elapsedS == 1)
        clock.advance(by: 64)
        #expect(store.elapsedS == 65)
    }

    @Test("Con un instante de suelo se mide en el mayor entre él y el reloj")
    func elapsedNotBeforeInstant() async {
        let fixture = SessionStoreFixture()
        let (clock, store) = (fixture.clock, fixture.store)
        #expect(store.elapsedS(notBefore: Self.t0.addingTimeInterval(5)) == 0)
        await store.start()

        clock.advance(by: 4.999)
        // La entrada del segundo 5 se evalúa antes de su instante: muestra 5, no 4.
        #expect(store.elapsedS(notBefore: Self.t0.addingTimeInterval(5)) == 5)
        // Un suelo atrasado no retrasa el reloj.
        #expect(abs(store.elapsedS(notBefore: Self.t0) - 4.999) < 0.0001)
    }

    @Test("Background: 10 min activa + 5 min en otra app ≈ 900 s")
    func backgroundTimeCounts() async {
        let fixture = SessionStoreFixture()
        let (clock, store) = (fixture.clock, fixture.store)
        await store.start()

        clock.advance(by: 10 * 60)   // en primer plano
        clock.advance(by: 5 * 60)    // en otra app: ningún tick llega, el reloj sigue

        #expect(abs(store.elapsedS - 900) < 0.001)
    }

    @Test("Reloj hacia atrás: elapsedS = 0, nunca negativo")
    func clockBackwardsIsZero() async {
        let fixture = SessionStoreFixture()
        let (clock, store) = (fixture.clock, fixture.store)
        await store.start()

        clock.set(Self.t0.addingTimeInterval(-120))

        #expect(store.elapsedS == 0)
    }

    @Test("Doble toque: un segundo start() no crea otra sesión ni reinicia el tiempo")
    func secondStartIsIgnored() async throws {
        let fixture = SessionStoreFixture()
        let (clock, motion, store) = (fixture.clock, fixture.motion, fixture.store)
        await store.start()
        let first = try #require(store.session)

        clock.advance(by: 30)
        await store.start()

        #expect(store.session == first)
        #expect(store.session?.startedAt == Self.t0)
        #expect(store.elapsedS == 30)
        #expect(motion.updateStarts.count == 1)
    }
}
