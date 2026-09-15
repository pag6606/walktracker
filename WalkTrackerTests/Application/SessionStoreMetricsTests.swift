import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 1.3 sobre `SessionStore`: las métricas se fijan al abrir la sesión y se
/// recalculan con cada muestra del coprocesador, en el instante del reloj.
@MainActor
@Suite("SessionStore · métricas en vivo")
struct SessionStoreMetricsTests {

    private typealias Fixture = SessionStoreFixture

    @Test("Sin sesión no hay métricas")
    func noSessionNoMetrics() {
        #expect(Fixture().store.metrics == nil)
    }

    @Test("Sesión recién abierta: 0 m, ritmo nil y cadencia 0")
    func freshSession() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        let metrics = try #require(fixture.store.metrics)
        #expect(metrics == SessionMetrics(distanceM: 0, paceSecPerKm: nil, cadenceSpm: 0))
    }

    @Test("Sin distancia del sistema: 4980 pasos con zancada 0,655 → 3261,90 m")
    func distanceFromSteps() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, nil)])

        #expect(try #require(fixture.store.metrics).distanceM == 3261.9)
    }

    @Test("Con distancia del sistema: muestra de 4980 pasos y 3400 m → 3400 m")
    func distanceFromSystem() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, 3400)])

        #expect(try #require(fixture.store.metrics).distanceM == 3400)
        #expect(fixture.store.session?.stepsMeasured == 4980)
    }

    @Test("Distancia del sistema menor: 3400 → 3390 sigue en 3400")
    func systemDistanceNeverDecreases() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, 3400), (4990, 3390)])

        #expect(try #require(fixture.store.metrics).distanceM == 3400)
        #expect(fixture.store.session?.stepsMeasured == 4990)
    }

    @Test("Por debajo de 100 m: 10 pasos a los 60 s → ritmo nil")
    func noPaceBelowThreshold() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.clock.advance(by: 60)
        await fixture.emitAll([(10, nil)])

        let metrics = try #require(fixture.store.metrics)
        #expect(metrics.paceSecPerKm == nil)
        #expect(PaceFormat.text(metrics.paceSecPerKm) == "—")
    }

    @Test("A los 62 min: 4980 pasos sin distancia del sistema → 1140 s/km y 80,3 spm")
    func metricsAt62Minutes() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.clock.advance(by: 3720)
        await fixture.emitAll([(4980, nil)])

        let metrics = try #require(fixture.store.metrics)
        #expect(metrics.paceSecPerKm == 1140)
        #expect(metrics.cadenceSpm == 80.3)
    }

    @Test("Distancia del sistema inválida: no muta, y el conteo sigue", arguments: [-1, Double.nan, .infinity, -.infinity])
    func invalidSystemDistance(meters: Double) async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(100, 70), (4980, meters)])

        let session = try #require(fixture.store.session)
        #expect(session.systemDistanceM == 70)
        #expect(session.stepsMeasured == 4980, "la distancia rechazada no para el conteo")
        #expect(try #require(fixture.store.metrics).distanceM == 70)
    }

    @Test("Distancia del sistema inválida sin distancia previa: se usan los pasos")
    func invalidFirstSystemDistance() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        await fixture.emitAll([(4980, .nan)])

        #expect(fixture.store.session?.systemDistanceM == nil)
        #expect(try #require(fixture.store.metrics).distanceM == 3261.9)
    }

    @Test("Las métricas se recalculan con cada muestra, no con el paso del tiempo (AD-21)")
    func recalculatedOnSampleNotTick() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.clock.advance(by: 60)
        fixture.motion.emit(steps: 100)
        await waitUntil { fixture.store.session?.stepsMeasured == 100 }
        let afterSample = try #require(fixture.store.metrics)
        #expect(afterSample.cadenceSpm == 100)

        fixture.clock.advance(by: 60)
        #expect(fixture.store.metrics == afterSample, "sin muestra, las métricas no cambian")

        // Una muestra sin pasos nuevos también recalcula en el instante del reloj.
        fixture.motion.emit(steps: 100)
        await waitUntil { fixture.store.metrics?.cadenceSpm == 50 }
        #expect(fixture.store.metrics?.cadenceSpm == 50)
    }
}

private extension SessionStoreFixture {

    /// Emite las muestras, cierra el stream y espera a que el store las consuma todas.
    func emitAll(_ samples: [(steps: Int, distance: Double?)]) async {
        for sample in samples { motion.emit(steps: sample.steps, distance: sample.distance) }
        motion.finishUpdates()
        await store.stepCounting?.value
    }
}
