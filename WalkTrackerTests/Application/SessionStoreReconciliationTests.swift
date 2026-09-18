import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 1.5 sobre `SessionStore`: reconciliación atómica del background por consulta
/// al sistema (AD-8), degradación al `GapEstimator` y descarte de los estimados. El timeout
/// de reconciliación es el del soporte (5 s), salvo en los tests del timeout, que lo acortan
/// (0,05 s o 0,5 s); la consulta colgada es la del `MotionStub`.
@MainActor
@Suite("SessionStore · reconstrucción del background")
struct SessionStoreReconciliationTests: SessionStoreSuite {

    private static let day: TimeInterval = 24 * 60 * 60

    private typealias Fixture = SessionStoreFixture

    // MARK: - Consulta primero

    @Test("Gap con dato: tramo desde t0, 300 pasos vistos, 5 min en background y query → 820: medidos 820, estimados 0")
    func gapWithData() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 300)
        fixture.clock.advance(by: 60)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 820)
        #expect(session.stepsEstimated == 0)
        #expect(session.status == .active)
        #expect(fixture.motion.queriedRanges == [.init(start: Self.t0, end: Self.t0.addingTimeInterval(360))])
        #expect(fixture.store.metrics == session.metrics(at: fixture.clock.now))
        #expect(!fixture.store.isReconciling)

        // El stream entrega después el mismo acumulado: no se cuenta dos veces.
        fixture.motion.emit(steps: 820)
        fixture.motion.emit(steps: 830)
        await waitUntil { fixture.session?.stepsMeasured == 830 }
        #expect(fixture.session?.stepsMeasured == 830)
    }

    @Test("La distancia del sistema de la consulta entra sobre la base del tramo")
    func queryDistanceUsesStretchBase() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 100, distance: 70)
        fixture.store.pause()
        fixture.clock.advance(by: 60)
        fixture.store.resume()
        fixture.motion.emit(steps: 10, distance: 7)
        await waitUntil { fixture.session?.stepsMeasured == 110 }
        let resumedAt = fixture.clock.now

        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 400, distance: 280))
        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.first?.start == resumedAt, "se consulta el tramo en curso, no la sesión")
        #expect(fixture.session?.stepsMeasured == 500)
        #expect(fixture.session?.systemDistanceM == 350)
    }

    // MARK: - Degradación

    @Test("Sin respuesta (nil o error): activa 10 min a 80 spm y gap de 300 s → ~400 estimados", arguments: [
        MotionStub.QueryResponse.none,
        .failure(.failed(operation: "pedometer")),
        .failure(.notAuthorized),
    ])
    func gapWithoutData(response: MotionStub.QueryResponse) async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(response)

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 800)
        #expect(session.stepsEstimated == 400)
        #expect(session.status == .active)
        #expect(fixture.store.metrics?.distanceM == 786, "(800 + 400) × 0,655")
        #expect(fixture.motion.queriedRanges.count == 1)
        #expect(!fixture.store.isReconciling)
    }

    @Test("Timeout: la consulta colgada degrada a ~400, libera los comandos y su resultado tardío se ignora")
    func timeoutDegrades() async throws {
        let fixture = Fixture(timeoutS: 0.05)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.hasPendingQuery, "la consulta sigue colgada")
        #expect(!fixture.store.isReconciling)
        #expect(fixture.session?.stepsEstimated == 400)
        fixture.store.pause()
        #expect(fixture.session?.status == .paused, "los comandos vuelven tras el timeout")

        fixture.motion.resolvePendingQueries(with: .sample(steps: 1200, distance: nil))
        // La respuesta tardía ya pasó por la carrera, que la descartó y dejó su línea queryLate.
        await waitUntil { fixture.measurementLines("queryLate").count == 1 }
        #expect(fixture.session?.stepsMeasured == 800)
        #expect(fixture.session?.stepsEstimated == 400)
    }

    @Test("Sin muestra previa: activa 90 s y query nil → estimados 0")
    func noPriorSample() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 120)
        fixture.clock.advance(by: 90)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.count == 1)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.session?.stepsMeasured == 120)
    }

    @Test("Tramo de más de 7 días: no se consulta, y el gap pasa del tope de 20 min, así que tampoco se estima")
    func stretchOlderThanSevenDays() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.t0.addingTimeInterval(8 * Self.day))
        fixture.motion.setQueryResponse(.sample(steps: 99_999, distance: nil))

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.isEmpty)
        // Con la regla vieja eran 920.800 pasos fantasma: 80 spm × (8 días − 600 s) / 60.
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.session?.stepsMeasured == 800)
    }

    @Test("Tramo de más de 7 días con un gap corto: no se consulta, pero el gap cabe en el tope y sí se estima")
    func stretchOlderThanSevenDaysWithShortGapIsEstimated() async {
        // La rama que sobrevive al tope: sesión larga, gap corto. 100.800 pasos en 7 días de
        // sesión son 10 spm; el gap de 5 min añade 50.
        let fixture = Fixture()
        await fixture.startWalking(steps: 100_800)
        fixture.clock.advance(by: 7 * Self.day)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.isEmpty, "el tramo pasa de 7 días: no se consulta")
        #expect(fixture.session?.stepsEstimated == 50)
        #expect(fixture.session?.stepsMeasured == 100_800)
    }

    @Test("Tramo de justo 7 días: todavía se consulta")
    func stretchOfSevenDaysIsQueried() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.t0.addingTimeInterval(7 * Self.day))
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.count == 1)
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.session?.stepsEstimated == 0)
    }

    @Test("Query menor que lo visto: cuenta como dato, no baja los medidos y no estima (R1)")
    func queryBelowSeenIsStillData() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 300)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 120, distance: 50))

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 300, "record nunca resta")
        #expect(session.systemDistanceM == 50)
        // Con la regla vieja eran 150 pasos fantasma: 30 spm (300 pasos en 10 min) × 5 min.
        #expect(session.stepsEstimated == 0)
        #expect(fixture.measurementLines("query").first?.contains("outcome=belowSeen") == true)
    }

    @Test("Query menor que lo visto: la distancia tampoco baja, aunque la consulta traiga menos metros (R1)")
    func queryBelowSeenDoesNotLowerSystemDistance() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 300, distance: 200)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 120, distance: 50))

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 300)
        #expect(session.systemDistanceM == 200, "record nunca resta: la distancia se queda en la mayor vista")
        #expect(session.stepsEstimated == 0)
    }

    @Test("El caso real del iPhone 14: visto 2149 y consulta → 2143 tras un gap de 8,8 min, sin un solo paso estimado")
    func realBelowSeenWalkHasNoPhantomSteps() async throws {
        // Registro WTM1 del 2026-09-17, sesión 1789649385424: la consulta devolvió 6 pasos
        // menos que el acumulado del stream y la regla vieja estimó 1796 pasos fantasma.
        let fixture = Fixture()
        await fixture.startWalking(steps: 1156)
        fixture.clock.advance(by: 631)
        fixture.store.appDidEnterBackground()
        fixture.motion.emit(steps: 2149)
        await waitUntil { fixture.session?.stepsMeasured == 2149 }
        fixture.clock.advance(by: 528)
        fixture.motion.setQueryResponse(.sample(steps: 2143, distance: nil))

        await fixture.store.appDidBecomeActive()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 2149)
        #expect(session.stepsEstimated == 0)
        #expect(fixture.measurementLines("estimate").isEmpty, "con dato no se llega a estimar")
    }

    @Test("Una muestra de 0 pasos es respuesta del sistema: cuenta como dato y no estima")
    func zeroSampleCountsAsData() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.sample(steps: 0, distance: nil))

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.stepsMeasured == 800)
        #expect(fixture.session?.stepsEstimated == 0)
    }

    @Test("El stream ya trajo los pasos del gap: sin respuesta del sistema tampoco se estima (R1)")
    func streamDuringGapDoesNotEstimate() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        // La muestra de puesta al día llega antes de volver a primer plano.
        fixture.motion.emit(steps: 1200)
        await waitUntil { fixture.session?.stepsMeasured == 1200 }
        fixture.motion.setQueryResponse(.none)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.stepsMeasured == 1200)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.measurementLines("estimate").first?.contains("skipped=streamAdvanced") == true)
    }

    @Test("Gap por encima del tope de 20 min: sin respuesta del sistema no se estima nada (R1)")
    func gapAboveTheCapIsNotEstimated() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 25 * 60)
        fixture.motion.setQueryResponse(.none)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.count == 1)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.session?.stepsMeasured == 800)
    }

    @Test("Gap de justo 20 min: todavía se estima")
    func gapAtTheCapIsEstimated() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 20 * 60)
        fixture.motion.setQueryResponse(.none)

        await fixture.store.appDidBecomeActive()

        // 80 spm al empezar el gap × 20 min.
        #expect(fixture.session?.stepsEstimated == 1600)
    }

    @Test("Una muestra del stream que llega durante la consulta no convierte la consulta en incoherente")
    func streamDuringReconciliation() async throws {
        let fixture = Fixture(timeoutS: 5)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        fixture.motion.emit(steps: 1210)
        await waitUntil { fixture.session?.stepsMeasured == 1210 }
        fixture.motion.resolvePendingQueries(with: .sample(steps: 1200, distance: nil))
        await reconciliation.value

        #expect(fixture.session?.stepsMeasured == 1210)
        #expect(fixture.session?.stepsEstimated == 0)
    }

    @Test("Timeout con el stream avanzando durante la consulta: su acumulado cubre el gap y no se estima")
    func streamDuringTimeoutDoesNotEstimate() async throws {
        let fixture = Fixture(timeoutS: 0.5)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        fixture.motion.emit(steps: 1210)
        await waitUntil { fixture.session?.stepsMeasured == 1210 }
        await reconciliation.value

        #expect(fixture.motion.hasPendingQuery, "venció el timeout, la consulta sigue colgada")
        #expect(fixture.session?.stepsMeasured == 1210)
        #expect(fixture.session?.stepsEstimated == 0)
        fixture.motion.resolvePendingQueries(with: .none)
    }

    // MARK: - Atómica

    @Test("Los diálogos de Finalizar y Descartar abiertos al empezar la reconciliación se cierran")
    func reconciliationClosesDialogs() async {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsEstimated == 400)

        fixture.store.requestFinish()
        fixture.store.requestDiscardEstimated()
        #expect(fixture.store.isConfirmingFinish)
        #expect(fixture.store.isConfirmingDiscard)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 60)
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        #expect(!fixture.store.isConfirmingFinish)
        #expect(!fixture.store.isConfirmingDiscard)
        fixture.motion.resolvePendingQueries(with: .none)
        await reconciliation.value
        // 800 medidos en 900 s son 53,3 spm × 60 s.
        #expect(fixture.session?.stepsEstimated == 400 + 53)
    }

    @Test("Comandos durante la reconciliación: pausar, finalizar, descartar y reanudar no hacen nada")
    func commandsAreRejectedWhileReconciling() async throws {
        let fixture = Fixture(timeoutS: 5)
        await fixture.walkTenMinutesThenBackgroundFive()
        // Estimados previos, para que haya algo que descartar.
        fixture.motion.setQueryResponse(.none)
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsEstimated == 400)

        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 60)
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()
        let before = try #require(fixture.session)

        fixture.store.pause()
        fixture.store.resume()
        fixture.store.requestFinish()
        #expect(!fixture.store.isConfirmingFinish)
        await fixture.store.confirmFinish()
        fixture.store.requestDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard)
        fixture.store.confirmDiscardEstimated()
        await fixture.store.appDidBecomeActive()   // volver otra vez no abre otra

        #expect(fixture.session == before)
        #expect(fixture.session?.status == .active, "SessionStatus no cambia al reconciliar")
        #expect(fixture.store.isReconciling)
        #expect(fixture.motion.queriedRanges.count == 2)
        #expect(fixture.motion.cancelledStreams == 0)

        fixture.motion.resolvePendingQueries(with: .sample(steps: 1300, distance: nil))
        await reconciliation.value
        #expect(!fixture.store.isReconciling)
        #expect(fixture.session?.stepsMeasured == 1300)

        fixture.store.pause()
        #expect(fixture.session?.status == .paused)
    }

    @Test("Salir otra vez a segundo plano mientras reconcilia conserva el gap pendiente")
    func backgroundWhileReconcilingKeepsGap() async {
        let fixture = Fixture(timeoutS: 5)
        await fixture.walkTenMinutesThenBackgroundFive()
        fixture.motion.setQueryResponse(.hang)
        let reconciliation = await fixture.becomeActiveInBackground()

        fixture.clock.advance(by: 30)
        fixture.store.appDidEnterBackground()
        fixture.motion.resolvePendingQueries(with: .none)
        await reconciliation.value

        // Gap de 300 s desde el primer `.background`, no desde el segundo.
        #expect(fixture.session?.stepsEstimated == 400)
        // El gap ya se reconcilió: volver no consulta otra vez.
        await fixture.store.appDidBecomeActive()
        #expect(fixture.motion.queriedRanges.count == 1)
    }

    @Test("Dos salidas a segundo plano con el stream avanzando en medio: los pasos del gap son los de la primera y no se estima")
    func secondBackgroundKeepsTheFirstGapSteps() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        // El stream entrega la puesta al día del primer gap antes de la segunda salida: los
        // pasos del inicio del gap siguen siendo los 800 de entonces, no los 1200 de ahora.
        fixture.clock.advance(by: 120)
        fixture.motion.emit(steps: 1200)
        await waitUntil { fixture.session?.stepsMeasured == 1200 }
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 180)
        fixture.motion.setQueryResponse(.none)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.stepsMeasured == 1200)
        // Sin conservar los pasos del primer gap, la defensa no vería el avance del stream y
        // estimaría sobre una cadencia inflada.
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.measurementLines("estimate").first?.contains("skipped=streamAdvanced") == true)
    }

    @Test("Volver sin haber pasado a segundo plano no consulta")
    func activeWithoutBackgroundDoesNothing() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(!fixture.store.isReconciling)
    }

    @Test("Pausada al volver: pausada en background no consulta ni estima")
    func pausedInBackground() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.pause()
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.session?.status == .paused)
        #expect(fixture.session?.stepsEstimated == 0)
    }

    @Test("Background con la sesión activa: sigue activa y el tiempo contó el gap")
    func backgroundNeverPauses() async {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.status == .active)
        #expect(fixture.store.elapsedS == 900)
        #expect(fixture.store.isCountingSteps)
    }

    // MARK: - Finalizar

    @Test("Finalizar desde activa: query → 830 hasta el instante del toque, cierra con 830 medidos")
    func finishReconciles() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.motion.setQueryResponse(.sample(steps: 830, distance: nil))

        fixture.store.requestFinish()
        await fixture.store.confirmFinish()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsMeasured == 830)
        #expect(session.stepsEstimated == 0)
        #expect(session.endedAt == Self.t0.addingTimeInterval(600))
        #expect(fixture.motion.queriedRanges == [.init(start: Self.t0, end: Self.t0.addingTimeInterval(600))])
        #expect(fixture.store.metrics == session.metrics(at: fixture.clock.now))
        #expect(!fixture.store.isCountingSteps)
    }

    @Test("Finalizar con la consulta lenta: reconcilia con los controles bloqueados y cierra en el instante del toque")
    func finishWaitsForSlowQuery() async throws {
        let fixture = Fixture(timeoutS: 5)
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.motion.setQueryResponse(.hang)

        let store = fixture.store
        let finishing = Task { await store.confirmFinish() }
        await waitUntil { store.isReconciling && fixture.motion.hasPendingQuery }
        fixture.clock.advance(by: 2)
        store.pause()
        #expect(fixture.session?.status == .active)

        fixture.motion.resolvePendingQueries(with: .sample(steps: 830, distance: nil))
        await finishing.value

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsMeasured == 830)
        #expect(session.durationS == 600)
        #expect(!store.isReconciling)
    }

    @Test("Finalizar sin dato: activa y query nil cierra sin estimar", arguments: [
        MotionStub.QueryResponse.none, .failure(.unavailable), .hang,
    ])
    func finishWithoutDataDoesNotEstimate(response: MotionStub.QueryResponse) async throws {
        let fixture = Fixture(timeoutS: 0.05)
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        // Un tramo que empieza con 600 s de sesión a 80 spm: un estimador que se colara aquí
        // tendría con qué estimar los 300 s siguientes.
        fixture.store.pause()
        fixture.store.resume()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(response)

        await fixture.store.confirmFinish()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsMeasured == 800)
        #expect(session.stepsEstimated == 0)
        fixture.motion.resolvePendingQueries(with: .none)
    }

    @Test("Finalizar desde pausa no consulta: el tramo ya se cerró al pausar")
    func finishFromPauseDoesNotQuery() async {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.clock.advance(by: 600)
        fixture.store.pause()
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))

        await fixture.store.confirmFinish()

        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.session?.status == .finished)
        #expect(fixture.session?.stepsMeasured == 800)
    }

    @Test("El resumen conserva los estimados de la sesión")
    func finishKeepsEstimated() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()

        await fixture.store.confirmFinish()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.stepsEstimated == 400)
        #expect(fixture.store.metrics?.distanceM == 786)
    }

    // MARK: - Descartar

    @Test("Descartar: 400 estimados y confirmar → estimados 0; distancia y ritmo recalculados")
    func discardEstimated() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        let withEstimated = try #require(fixture.store.metrics)
        #expect(withEstimated.distanceM == 786)

        fixture.store.requestDiscardEstimated()
        #expect(fixture.store.isConfirmingDiscard)
        fixture.store.confirmDiscardEstimated()

        let session = try #require(fixture.session)
        let metrics = try #require(fixture.store.metrics)
        #expect(!fixture.store.isConfirmingDiscard)
        #expect(session.stepsEstimated == 0)
        #expect(session.stepsMeasured == 800)
        #expect(metrics.distanceM == 524)
        #expect(metrics.paceSecPerKm == 1718, "900 s / 0,524 km")
        #expect(withEstimated.paceSecPerKm == 1145, "900 s / 0,786 km")
    }

    @Test("Distancia del sistema más estimados: 800 medidos con 500 m del sistema y 400 estimados → 762 m; al descartar, 500 m")
    func systemDistancePlusEstimated() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800, distance: 500)
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.none)

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.systemDistanceM == 500)
        #expect(fixture.session?.stepsEstimated == 400)
        #expect(fixture.store.metrics?.distanceM == 762, "500 + 400 × 0,655")

        fixture.store.requestDiscardEstimated()
        fixture.store.confirmDiscardEstimated()

        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.store.metrics?.distanceM == 500)
    }

    @Test("Cancelar el descarte deja los estimados; sin estimados no se pide confirmación")
    func cancelDiscard() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 800)
        fixture.store.requestDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard, "sin estimados no hay nada que descartar")

        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        await fixture.store.appDidBecomeActive()

        fixture.store.requestDiscardEstimated()
        fixture.store.cancelDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard)
        #expect(fixture.session?.stepsEstimated == 400)
    }

    @Test("Descartar en pausa se permite")
    func discardWhilePaused() async {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        fixture.store.pause()

        fixture.store.requestDiscardEstimated()
        fixture.store.confirmDiscardEstimated()

        #expect(fixture.session?.status == .paused)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.store.metrics?.distanceM == 524)
    }

    @Test("Mutar finalizada: descartar sobre una sesión finalizada no muta")
    func discardOnFinishedIsIgnored() async throws {
        let fixture = Fixture()
        await fixture.walkTenMinutesThenBackgroundFive()
        await fixture.store.appDidBecomeActive()
        await fixture.store.confirmFinish()
        let finished = try #require(fixture.session)

        fixture.store.requestDiscardEstimated()
        #expect(!fixture.store.isConfirmingDiscard)
        fixture.store.confirmDiscardEstimated()
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        await fixture.store.appDidBecomeActive()

        #expect(fixture.session == finished)
        #expect(fixture.session?.stepsEstimated == 400)
        #expect(fixture.motion.queriedRanges.count == 2, "la del gap y la de finalizar; ninguna tras cerrar")
    }
}

private extension SessionStoreFixture {

    /// 10 min activa a 80 spm (800 pasos) y 5 min en segundo plano: gap de 300 s.
    func walkTenMinutesThenBackgroundFive() async {
        await startWalking(steps: 800)
        clock.advance(by: 600)
        store.appDidEnterBackground()
        clock.advance(by: 300)
    }

    /// Lanza la reconciliación sin esperarla y espera a que la consulta colgada llegue
    /// al stub: `isReconciling` se activa antes de que la tarea registre la consulta.
    func becomeActiveInBackground() async -> Task<Void, Never> {
        let store = self.store
        let task = Task { await store.appDidBecomeActive() }
        await waitUntil { store.isReconciling && self.motion.hasPendingQuery }
        return task
    }
}
