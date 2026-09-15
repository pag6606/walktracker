import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 1.6 sobre `SessionStore`: el snapshot en un `StorageStub`, el reloj en un
/// `ClockStub` y el coprocesador en un `MotionStub`. "Relanzar" es construir otro store
/// sobre el mismo almacenamiento y llamar a `restoreOnLaunch()`.
@MainActor
@Suite("SessionStore · recuperación al relanzar")
struct SessionStoreRecoveryTests {

    /// El instante del relanzamiento.
    private nonisolated static var now: Date { SessionStoreFixture.t0 }
    private nonisolated static var orphanThresholdS: TimeInterval { SessionStoreFixture.orphanThresholdS }

    private typealias Fixture = SessionStoreFixture

    /// Snapshot relativo a `now`. Por defecto: activa desde hace 20 min, 1500 pasos, 60 s de
    /// pausas, guardada ahora mismo y con un solo tramo desde el inicio.
    private nonisolated static func snapshot(
        startedAgoS: TimeInterval = 20 * 60,
        stepsMeasured: Int = 1500,
        stepsEstimated: Int = 0,
        totalPausesS: TimeInterval = 60,
        pausedAgoS: TimeInterval? = nil,
        forcePaused: Bool? = nil,
        strideM: Double = 0.655,
        systemDistanceM: Double? = nil,
        savedAgoS: TimeInterval = 0,
        lastSampleAt: Date? = nil,
        segmentStart: Date? = nil,
        segmentSteps: Int? = nil,
        distanceBaseM: Double = 0
    ) -> ActiveSessionSnapshot {
        let startedAt = now.addingTimeInterval(-startedAgoS)
        return ActiveSessionSnapshot(
            startedAt: startedAt,
            stepsMeasured: stepsMeasured,
            stepsEstimated: stepsEstimated,
            totalPausesS: totalPausesS,
            paused: forcePaused ?? (pausedAgoS != nil),
            pausedAt: pausedAgoS.map { now.addingTimeInterval(-$0) },
            strideM: strideM,
            systemDistanceM: systemDistanceM,
            savedAt: now.addingTimeInterval(-savedAgoS),
            lastSampleAt: lastSampleAt,
            segmentStart: segmentStart ?? startedAt,
            segmentSteps: segmentSteps ?? stepsMeasured,
            distanceBaseM: distanceBaseM
        )
    }

    // MARK: - Relanzar

    @Test("Relanzar activa: 20 min, 1500 pasos y 60 s de pausas → activa, 1140 s, 1500 + la consulta y \"Sesión recuperada\"")
    func relaunchActive() async throws {
        let snapshot = Self.snapshot()
        let fixture = Fixture(snapshot: snapshot)
        fixture.motion.setQueryResponse(.sample(steps: 1700, distance: nil))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .active)
        #expect(session.startedAt == snapshot.startedAt)
        #expect(fixture.store.elapsedS == 1140)
        #expect(session.stepsMeasured == 1700)
        #expect(session.stepsEstimated == 0)
        #expect(fixture.store.metrics == session.metrics(at: Self.now))
        #expect(fixture.store.hasSession)
        #expect(fixture.store.showsRecoveredNotice)
        #expect(!fixture.store.isReconciling)
        #expect(fixture.motion.queriedRanges == [.init(start: snapshot.startedAt, end: Self.now)])
        #expect(fixture.motion.updateStarts == [snapshot.startedAt], "el tramo se reabre desde su inicio")
        #expect(fixture.store.isCountingSteps)

        // El snapshot queda al día con lo reconciliado.
        let saved = try #require(fixture.storage.snapshot)
        #expect(saved.stepsMeasured == 1700)
        #expect(saved.segmentSteps == 1700)
        #expect(saved.savedAt == Self.now)
    }

    @Test("El tramo reabierto conserva el máximo visto: sus acumulados solo suman lo nuevo")
    func restoredSegmentKeepsHighest() async throws {
        let resumedAt = Self.now.addingTimeInterval(-10 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            systemDistanceM: 1000, segmentStart: resumedAt, segmentSteps: 900, distanceBaseM: 400
        ))
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: 600))

        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.stepsMeasured == 1500)
        #expect(fixture.motion.updateStarts == [resumedAt])

        fixture.motion.emit(steps: 900, distance: 600)
        fixture.motion.emit(steps: 950, distance: 630)
        await waitUntil { fixture.session?.stepsMeasured == 1550 }
        #expect(fixture.session?.stepsMeasured == 1550)
        #expect(fixture.session?.systemDistanceM == 1030, "base del tramo 400 + 630")
    }

    @Test("Relanzar sin dato: consulta nil y gap de 300 s desde el último guardado a 80 spm → ~400")
    func relaunchWithoutData() async throws {
        // 20 min desde el inicio con 60 s de pausas; guardado hace 300 s con 840 s netos: 1120 pasos son 80 spm.
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 1120, savedAgoS: 300))
        fixture.motion.setQueryResponse(.none)

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 1120)
        #expect(session.stepsEstimated == 400)
        #expect(abs((fixture.store.metrics?.distanceM ?? 0) - (1120 + 400) * 0.655) < 0.01)
        #expect(fixture.store.hasSession)
        #expect(fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.snapshot?.stepsEstimated == 400, "lo estimado queda guardado")
    }

    @Test("Restaurar v3: {2450, 320, 60000 ms, activa, 0,655} → pasos, zancada y estado; distancia (2450 + 320) × 0,655")
    func restoreV3Snapshot() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 2450, stepsEstimated: 320))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.stepsMeasured == 2450)
        #expect(session.stepsEstimated == 320)
        #expect(session.strideM == 0.655)
        #expect(session.status == .active)
        #expect(abs((fixture.store.metrics?.distanceM ?? 0) - (2450 + 320) * 0.655) < 0.01)
    }

    @Test("Relanzar pausada: pausada, sin consulta ni stream, con el tiempo congelado en pausedAt")
    func relaunchPaused() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 800, pausedAgoS: 5 * 60, savedAgoS: 5 * 60))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .paused)
        #expect(fixture.store.elapsedS == 840, "15 min hasta la pausa − 60 s de pausas cerradas")
        fixture.clock.advance(by: 600)
        #expect(fixture.store.elapsedS == 840)
        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.motion.updateStarts.isEmpty)
        #expect(session.stepsEstimated == 0)
        #expect(fixture.store.hasSession)
        #expect(fixture.store.showsRecoveredNotice)

        // Reanudar abre un tramo nuevo desde cero.
        fixture.store.resume()
        #expect(fixture.motion.updateStarts == [fixture.clock.now])
        fixture.motion.emit(steps: 10)
        await waitUntil { fixture.session?.stepsMeasured == 810 }
        #expect(fixture.session?.stepsMeasured == 810)
    }

    @Test("Mientras reconcilia al arrancar no se presenta: la sesión aparece ya consolidada")
    func presentsOnlyAfterReconciling() async throws {
        let fixture = Fixture(snapshot: Self.snapshot())
        fixture.motion.setQueryResponse(.hang)
        let store = fixture.store

        let restoring = Task { await store.restoreOnLaunch() }
        await waitUntil { store.isReconciling && fixture.motion.hasPendingQuery }
        #expect(!store.hasSession)
        #expect(!store.showsRecoveredNotice)
        store.pause()
        #expect(store.session?.status == .active, "los comandos siguen rechazados")

        fixture.motion.resolvePendingQueries(with: .sample(steps: 1600, distance: nil))
        await restoring.value

        #expect(store.hasSession)
        #expect(store.session?.stepsMeasured == 1600)
    }

    // MARK: - Sesión huérfana (AD-18)

    @Test("Huérfana: startedAt por encima del umbral y último dato a +40 min → finished en +40 min, recovered, sin consulta")
    func orphanIsClosed() async throws {
        let snapshot = Self.snapshot(startedAgoS: 7 * 60 * 60, stepsMeasured: 4000, totalPausesS: 0, savedAgoS: 6 * 60 * 60)
        let lastSampleAt = snapshot.startedAt.addingTimeInterval(40 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 7 * 60 * 60, stepsMeasured: 4000, totalPausesS: 0, savedAgoS: 6 * 60 * 60, lastSampleAt: lastSampleAt
        ))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.recovered)
        #expect(session.endedAt == lastSampleAt)
        #expect(session.durationS == 2400)
        #expect(session.stepsMeasured == 4000)
        #expect(session.stepsEstimated == 0)
        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.motion.updateStarts.isEmpty)
        #expect(fixture.store.hasSession, "su resumen se muestra una vez")
        #expect(!fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.snapshot == nil)
        #expect(fixture.storage.clearCount == 1)

        fixture.store.leaveSummary()
        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
    }

    @Test("Huérfana cerrada al arrancar: 4000 pasos en 2400 s → el store publica 2620 m, 916 s/km y 100 spm para el resumen")
    func orphanPublishesMetrics() async throws {
        let base = Self.snapshot(startedAgoS: 7 * 60 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 7 * 60 * 60, stepsMeasured: 4000, totalPausesS: 0, savedAgoS: 6 * 60 * 60,
            lastSampleAt: base.startedAt.addingTimeInterval(40 * 60)
        ))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.durationS == 2400)
        let metrics = try #require(fixture.store.metrics, "sin métricas el resumen quedaría en blanco")
        #expect(metrics.distanceM == 2620, "4000 × 0,655")
        #expect(metrics.paceSecPerKm == 916, "2400 s / 2,62 km")
        #expect(metrics.cadenceSpm == 100, "4000 pasos en 40 min")
        #expect(metrics == session.metrics(at: try #require(session.endedAt)))
    }

    @Test("Huérfana sin ninguna muestra: se cierra en startedAt con 0 s")
    func orphanWithoutSamples() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(startedAgoS: 8 * 60 * 60, stepsMeasured: 0, totalPausesS: 0))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.status == .finished)
        #expect(session.recovered)
        #expect(session.endedAt == session.startedAt)
        #expect(session.durationS == 0)
    }

    @Test("Huérfana pausada: se cierra en el último dato y la pausa abierta cuenta 0")
    func orphanPaused() async throws {
        let base = Self.snapshot(startedAgoS: 10 * 60 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 10 * 60 * 60, stepsMeasured: 3000, totalPausesS: 120,
            pausedAgoS: 10 * 60 * 60 - 35 * 60, lastSampleAt: base.startedAt.addingTimeInterval(30 * 60)
        ))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session?.durationS == 1680)
        #expect(fixture.session?.recovered == true)
    }

    @Test("Huérfana con una pausa cerrada tras el último dato: se recorta en la última reanudación y la pausa no se come tiempo andado")
    func orphanWithPauseAfterLastData() async throws {
        // Camina 0–40 min (último dato a +40), pausa 50–60, reanuda a +60 y la app muere.
        let base = Self.snapshot(startedAgoS: 7 * 60 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 7 * 60 * 60, stepsMeasured: 3000, totalPausesS: 600,
            lastSampleAt: base.startedAt.addingTimeInterval(40 * 60),
            segmentStart: base.startedAt.addingTimeInterval(60 * 60), segmentSteps: 0
        ))

        await fixture.store.restoreOnLaunch()

        let session = try #require(fixture.session)
        #expect(session.recovered)
        #expect(session.endedAt == base.startedAt.addingTimeInterval(60 * 60))
        #expect(session.durationS == 3000, "60 min hasta la reanudación − 10 min de pausa")
        #expect(session.pausesS == 600)
    }

    @Test("Justo en el umbral no es huérfana: se restaura")
    func atThresholdRestores() async {
        let fixture = Fixture(snapshot: Self.snapshot(startedAgoS: Self.orphanThresholdS))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session?.status == .active)
        #expect(fixture.session?.recovered == false)
    }

    // MARK: - Sin snapshot, ilegible o inválido

    @Test("Sin snapshot: Inicio normal, nada que restaurar")
    func noSnapshot() async {
        let fixture = Fixture()

        await fixture.store.restoreOnLaunch()

        #expect(fixture.storage.loadCount == 1)
        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(!fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.saved.isEmpty)
    }

    @Test("Snapshot ilegible: se aparta, Inicio normal y se puede iniciar", arguments: [
        StorageError.malformed("JSON roto"), .unsupportedSchemaVersion(2),
    ])
    func unreadableSnapshot(error: StorageError) async {
        let snapshot = Self.snapshot()
        let fixture = Fixture(snapshot: snapshot)
        fixture.storage.failLoad(with: error)

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(fixture.storage.snapshot == nil)
        #expect(fixture.storage.setAside == [snapshot], "apartado, no destruido")
        #expect(fixture.storage.clearCount == 0)
        #expect(fixture.motion.queriedRanges.isEmpty)

        fixture.storage.failLoad(with: nil)
        await fixture.store.start()
        #expect(fixture.session?.status == .active)
    }

    @Test("Lectura fallida (failed): Inicio normal y el snapshot sigue en su sitio, sin apartar")
    func failedReadKeepsSnapshot() async {
        let snapshot = Self.snapshot()
        let fixture = Fixture(snapshot: snapshot)
        fixture.storage.failLoad(with: .failed(operation: "read"))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(fixture.storage.loadCount == 1)
        #expect(throws: StorageError.failed(operation: "read")) { try fixture.storage.loadActiveSession() }
        #expect(fixture.storage.snapshot == snapshot, "no se pudo leer: no se aparta")
        #expect(fixture.storage.setAside.isEmpty)
        #expect(fixture.storage.clearCount == 0)
    }

    @Test("Snapshot inválido: rechazado en la frontera, apartado sin borrar e Inicio normal", arguments: [
        SessionStoreRecoveryTests.snapshot(strideM: 0),
        SessionStoreRecoveryTests.snapshot(strideM: -1),
        SessionStoreRecoveryTests.snapshot(stepsMeasured: -1),
        SessionStoreRecoveryTests.snapshot(totalPausesS: -1),
        SessionStoreRecoveryTests.snapshot(forcePaused: true),
        SessionStoreRecoveryTests.snapshot(segmentSteps: -1),
        SessionStoreRecoveryTests.snapshot(distanceBaseM: -1),
    ])
    func invalidSnapshot(snapshot: ActiveSessionSnapshot) async {
        let fixture = Fixture(snapshot: snapshot)

        await fixture.store.restoreOnLaunch()

        #expect(fixture.session == nil)
        #expect(!fixture.store.hasSession)
        #expect(fixture.storage.setAside == [snapshot])
        #expect(fixture.storage.clearCount == 0)
        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(fixture.motion.updateStarts.isEmpty)
    }

    @Test("Solo restaura una vez, y nunca sobre una sesión ya abierta")
    func restoresOnce() async {
        let fixture = Fixture(snapshot: Self.snapshot())
        await fixture.store.restoreOnLaunch()
        await fixture.store.restoreOnLaunch()
        #expect(fixture.storage.loadCount == 1)

        let other = Fixture(snapshot: Self.snapshot(stepsMeasured: 99))
        await other.store.start()
        await other.store.restoreOnLaunch()
        #expect(other.session?.stepsMeasured == 0)
        #expect(other.storage.loadCount == 0)
    }

    // MARK: - Guardar y borrar

    @Test("Autosave: activa con muestras cada 2,5 s durante 25 s → el de iniciar + 2 por muestras (≥ 10 s), no 10")
    func autosaveBySamples() async {
        let fixture = Fixture()
        await fixture.store.start()
        #expect(fixture.storage.saved.count == 1, "al iniciar")

        for index in 1...10 {
            fixture.clock.advance(by: 2.5)
            fixture.motion.emit(steps: index * 4, end: fixture.clock.now)
            await waitUntil { fixture.session?.stepsMeasured == index * 4 }
        }

        #expect(fixture.storage.saved.count == 3)
        #expect(fixture.storage.saved.map(\.savedAt) == [0, 10, 20].map { Self.now.addingTimeInterval($0) })
        #expect(fixture.storage.saved.last?.stepsMeasured == 32, "la muestra de los 20 s")
    }

    @Test("Quieto no hay escrituras: sin muestras el reloj no guarda")
    func noSamplesNoWrites() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.clock.advance(by: 600)
        #expect(fixture.storage.saved.count == 1)
    }

    @Test("Se guarda al iniciar, pausar, reanudar y pasar a background; al finalizar se borra y relanzar no restaura")
    func saveMomentsAndClearOnFinish() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        #expect(fixture.storage.saved.count == 1)

        fixture.clock.advance(by: 5)
        fixture.store.pause()
        #expect(fixture.storage.saved.count == 2)
        #expect(fixture.storage.snapshot?.paused == true)
        #expect(fixture.storage.snapshot?.pausedAt == fixture.clock.now)

        fixture.clock.advance(by: 5)
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.saved.count == 3, "también en pausa")

        fixture.store.resume()
        #expect(fixture.storage.saved.count == 4)
        #expect(fixture.storage.snapshot?.paused == false)
        #expect(fixture.storage.snapshot?.segmentStart == fixture.clock.now)
        #expect(fixture.storage.snapshot?.totalPausesS == 5)

        fixture.clock.advance(by: 5)
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.saved.count == 5)
        #expect(fixture.storage.snapshot?.savedAt == fixture.clock.now)

        await fixture.store.appDidBecomeActive()
        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        #expect(fixture.storage.snapshot == nil)
        #expect(fixture.storage.clearCount == 1)

        let relaunched = Fixture(storage: fixture.storage, at: fixture.clock.now)
        await relaunched.store.restoreOnLaunch()
        #expect(relaunched.session == nil)
        #expect(!relaunched.store.hasSession)
    }

    @Test("La consulta de la reconciliación no mueve lastSampleAt: el snapshot conserva el último paso real")
    func queryDoesNotMoveLastSampleAt() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: Self.now.addingTimeInterval(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.advance(by: 60)
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.now.addingTimeInterval(5 * 60 * 60))
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))

        await fixture.store.appDidBecomeActive()

        #expect(fixture.session?.stepsMeasured == 820)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.now.addingTimeInterval(60))
    }

    // MARK: - Tope de lastSampleAt tras un gap (R4)

    /// `Self.now` + `seconds`.
    private static func at(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
    }

    /// Inicia en `now`, recibe 300 pasos con `end` +60 s y pasa a background a los +600 s: el
    /// tope queda pendiente en +600 s y el snapshot, con `lastSampleAt` +60 s.
    private static func walkThenBackground(_ fixture: Fixture) async {
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: at(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.set(at(600))
        fixture.store.appDidEnterBackground()
    }

    /// Emite una muestra del stream con el reloj en `end` y espera a su autosave, que deja ver
    /// `lastSampleAt` en el snapshot. El llamante garantiza ≥ 10 s desde el último guardado.
    private static func emitAndAutosave(_ fixture: Fixture, steps: Int, end: Date) async {
        let saves = fixture.storage.saved.count
        fixture.clock.set(end)
        fixture.motion.emit(steps: steps, end: end)
        await waitUntil { fixture.storage.saved.count == saves + 1 }
    }

    @Test("R4 · la muestra de puesta al día llega antes de la vuelta: lastSampleAt se queda en el inicio del gap y la siguiente lo mueve")
    func catchUpBeforeReturnIsCapped() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)

        // La puesta al día del stream (900, `end` = +5 h) se procesa antes que la vuelta.
        let back = Self.at(5 * 60 * 60)
        await Self.emitAndAutosave(fixture, steps: 900, end: back)
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600), "topado en el inicio del gap")

        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))

        let next = back.addingTimeInterval(30)
        await Self.emitAndAutosave(fixture, steps: 930, end: next)
        #expect(fixture.storage.snapshot?.lastSampleAt == next, "el tope ya se liberó")
    }

    @Test("R4 · la consulta ya cubrió el gap: la puesta al día sin pasos nuevos libera el tope sin mover lastSampleAt; la siguiente lo mueve")
    func catchUpWithoutStepsReleasesCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsMeasured == 900)

        await Self.emitAndAutosave(fixture, steps: 900, end: back.addingTimeInterval(10))
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(60), "no sumó pasos: no lo mueve")

        let next = back.addingTimeInterval(30)
        await Self.emitAndAutosave(fixture, steps: 930, end: next)
        #expect(fixture.session?.stepsMeasured == 930)
        #expect(fixture.storage.snapshot?.lastSampleAt == next, "sin recortar al inicio del gap")
    }

    @Test("R4 · la consulta no libera el tope: con la consulta por debajo del stream, la puesta al día que suma pasos sigue topada")
    func queryDoesNotReleaseCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))
        await fixture.store.appDidBecomeActive()
        #expect(fixture.session?.stepsMeasured == 820)

        await Self.emitAndAutosave(fixture, steps: 900, end: back.addingTimeInterval(10))
        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))
    }

    @Test("R4 · una muestra del stream durante la consulta colgada no lleva lastSampleAt más allá del inicio del gap")
    func sampleDuringQueryIsCapped() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.hang)
        let returning = Task { await fixture.store.appDidBecomeActive() }
        await waitUntil { fixture.motion.hasPendingQuery }

        fixture.motion.emit(steps: 900, end: back)
        await waitUntil { fixture.session?.stepsMeasured == 900 }
        fixture.motion.resolvePendingQueries(with: .sample(steps: 900, distance: nil))
        await returning.value

        #expect(fixture.storage.snapshot?.savedAt == back, "guardado tras reconciliar")
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))
    }

    @Test("R4 · una muestra previa al gap procesada tras ir a background (end +590 s) no libera el tope: la puesta al día sigue topada en +600 s")
    func sampleBeforeGapDoesNotReleaseCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)

        // Encolada antes de la salida a background y consumida después.
        fixture.clock.set(Self.at(700))
        fixture.motion.emit(steps: 350, end: Self.at(590))
        await waitUntil { fixture.session?.stepsMeasured == 350 }

        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))
        await fixture.store.appDidBecomeActive()
        await Self.emitAndAutosave(fixture, steps: 900, end: back.addingTimeInterval(10))

        #expect(fixture.session?.stepsMeasured == 900)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600))
    }

    @Test("R4 · pausada no fija tope: background y vuelta en pausa, reanudar, y la primera muestra mueve lastSampleAt a su end real")
    func pausedBackgroundDoesNotCap() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: Self.at(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.set(Self.at(100))
        fixture.store.pause()
        fixture.clock.set(Self.at(600))
        fixture.store.appDidEnterBackground()
        fixture.clock.set(Self.at(5 * 60 * 60))
        await fixture.store.appDidBecomeActive()

        fixture.clock.set(Self.at(5 * 60 * 60 + 60))
        fixture.store.resume()
        let end = Self.at(5 * 60 * 60 + 90)
        await Self.emitAndAutosave(fixture, steps: 50, end: end)

        #expect(fixture.session?.stepsMeasured == 350)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · restaurar una pausada no fija tope: al reanudar, la primera muestra mueve lastSampleAt a su end real")
    func restoredPausedDoesNotCap() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(
            pausedAgoS: 5 * 60, savedAgoS: 5 * 60, lastSampleAt: Self.at(-6 * 60)
        ))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.status == .paused)

        fixture.clock.set(Self.at(60))
        fixture.store.resume()
        let end = Self.at(90)
        await Self.emitAndAutosave(fixture, steps: 50, end: end)

        #expect(fixture.session?.stepsMeasured == 1550)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · nunca retrocede: un último dato posterior al inicio del gap (+700 s frente a +600 s) se conserva tras la vuelta")
    func capNeverMovesLastSampleAtBack() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300, end: Self.at(60))
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        // Una muestra real con `end` +700 s se procesa justo antes de que llegue la salida a
        // background, fechada con el reloj en +600 s.
        fixture.clock.set(Self.at(600))
        fixture.motion.emit(steps: 400, end: Self.at(700))
        await waitUntil { fixture.session?.stepsMeasured == 400 }
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(700))

        let back = Self.at(5 * 60 * 60)
        await Self.emitAndAutosave(fixture, steps: 900, end: back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(700), "el tope (+600 s) no lo hace retroceder")
    }

    @Test("R4 · dos gaps sin muestra entre medias: se conserva el tope más temprano")
    func twoGapsKeepEarliestCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        fixture.clock.set(Self.at(60 * 60))
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        // Vuelve a salir sin que el stream haya entregado nada desde la primera salida.
        fixture.clock.set(Self.at(2 * 60 * 60))
        fixture.store.appDidEnterBackground()
        await Self.emitAndAutosave(fixture, steps: 1000, end: Self.at(3 * 60 * 60))

        #expect(fixture.session?.stepsMeasured == 1000)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(600), "el tope de la primera salida, no el de la segunda")
    }

    @Test("R4 · pausar libera el tope pendiente: tras reanudar, la muestra mueve lastSampleAt a su end real")
    func pauseReleasesCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        fixture.clock.set(back.addingTimeInterval(60))
        fixture.store.pause()
        fixture.clock.set(back.addingTimeInterval(120))
        fixture.store.resume()
        let end = back.addingTimeInterval(150)
        await Self.emitAndAutosave(fixture, steps: 50, end: end)

        #expect(fixture.session?.stepsMeasured == 950)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · finalizar libera el tope pendiente: la sesión siguiente del mismo store mueve lastSampleAt con su end real")
    func finishReleasesCap() async throws {
        let fixture = Fixture()
        await Self.walkThenBackground(fixture)
        let back = Self.at(5 * 60 * 60)
        fixture.clock.set(back)
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()

        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        fixture.clock.set(back.addingTimeInterval(60))
        await fixture.store.start()
        let end = back.addingTimeInterval(90)
        await Self.emitAndAutosave(fixture, steps: 40, end: end)

        #expect(fixture.session?.stepsMeasured == 40)
        #expect(fixture.storage.snapshot?.lastSampleAt == end)
    }

    @Test("R4 · restaurar: la primera muestra del stream no lleva lastSampleAt más allá de savedAt (+20 min); la siguiente lo mueve")
    func firstStreamSampleAfterRestoreIsCapped() async throws {
        // Empezó hace 30 min, guardada a los +20 min con el último paso a los +19 min.
        let base = Self.snapshot(startedAgoS: 30 * 60)
        let savedAt = base.startedAt.addingTimeInterval(20 * 60)
        let fixture = Fixture(snapshot: Self.snapshot(
            startedAgoS: 30 * 60, savedAgoS: 10 * 60, lastSampleAt: base.startedAt.addingTimeInterval(19 * 60)
        ))
        fixture.motion.setQueryResponse(.sample(steps: 1500, distance: nil))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.status == .active)
        #expect(fixture.storage.snapshot?.lastSampleAt == base.startedAt.addingTimeInterval(19 * 60))

        await Self.emitAndAutosave(fixture, steps: 1600, end: Self.at(10))
        #expect(fixture.session?.stepsMeasured == 1600)
        #expect(fixture.storage.snapshot?.lastSampleAt == savedAt)

        await Self.emitAndAutosave(fixture, steps: 1650, end: Self.at(40))
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.at(40))
    }

    @Test("Pausar, reanudar y relanzar: el snapshot guarda el tramo que escribe el store y el stream reabierto solo suma lo nuevo")
    func pausedAndResumedSegmentSurvivesRelaunch() async throws {
        let first = Fixture()
        await first.store.start()
        first.motion.emit(steps: 1000, distance: 700)
        await waitUntil { first.session?.stepsMeasured == 1000 }
        first.clock.advance(by: 600)
        first.store.pause()
        first.clock.advance(by: 60)
        first.store.resume()
        let resumedAt = first.clock.now
        first.motion.emit(steps: 200, distance: 140)
        await waitUntil { first.session?.stepsMeasured == 1200 }
        first.clock.advance(by: 30)
        first.store.appDidEnterBackground()

        let saved = try #require(first.storage.snapshot)
        #expect(saved.segmentStart == resumedAt)
        #expect(saved.segmentSteps == 200)
        #expect(saved.distanceBaseM == 700)
        #expect(saved.stepsMeasured == 1200)
        #expect(saved.systemDistanceM == 840)

        // El sistema mata la app y Paul la reabre en el mismo instante.
        let relaunched = Fixture(storage: first.storage, at: first.clock.now)
        relaunched.motion.setQueryResponse(.sample(steps: 200, distance: 140))
        await relaunched.store.restoreOnLaunch()
        #expect(relaunched.motion.updateStarts == [resumedAt])

        relaunched.motion.emit(steps: 250, distance: 175)
        await waitUntil { relaunched.session?.stepsMeasured == 1250 }
        #expect(relaunched.session?.stepsMeasured == 1250)
        #expect(relaunched.session?.systemDistanceM == 875, "base 700 + 175")
        #expect(relaunched.store.metrics?.distanceM == 875)
    }

    @Test("Restaurar sin dato y volver de background: solo se estima el gap nuevo de 60 s, no [savedAt, ahora]")
    func backgroundAfterRestoreEstimatesOnlyNewGap() async throws {
        // 1120 pasos a 80 spm y ~400 estimados al restaurar (como relaunchWithoutData).
        let snapshot = Self.snapshot(stepsMeasured: 1120, savedAgoS: 300)
        let fixture = Fixture(snapshot: snapshot)
        fixture.motion.setQueryResponse(.none)
        await fixture.store.restoreOnLaunch()
        #expect(fixture.session?.stepsEstimated == 400)

        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 60)
        await fixture.store.appDidBecomeActive()

        // Cadencia al salir: 1120 pasos en 1140 s = 58,9 spm; 1 min → 59. Con el gap pendiente
        // desde savedAt serían 480 más (80 spm × 6 min).
        #expect(fixture.session?.stepsEstimated == 459)
        #expect(fixture.motion.queriedRanges.last == .init(start: snapshot.startedAt, end: Self.now.addingTimeInterval(60)))
    }

    @Test("Volver de background guarda el snapshot reconciliado")
    func becomeActiveSavesReconciled() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 300)
        await waitUntil { fixture.session?.stepsMeasured == 300 }
        fixture.clock.advance(by: 60)
        fixture.store.appDidEnterBackground()
        #expect(fixture.storage.snapshot?.stepsMeasured == 300)
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))

        await fixture.store.appDidBecomeActive()

        let saved = try #require(fixture.storage.snapshot)
        #expect(saved.stepsMeasured == 820)
        #expect(saved.segmentSteps == 820)
        #expect(saved.savedAt == fixture.clock.now)
    }

    @Test("Descartar los estimados restaurados guarda stepsEstimated = 0: un crash no los resucita")
    func discardSavesSnapshot() async {
        let fixture = Fixture(snapshot: Self.snapshot(stepsMeasured: 1120, savedAgoS: 300))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.storage.snapshot?.stepsEstimated == 400)

        fixture.store.requestDiscardEstimated()
        fixture.store.confirmDiscardEstimated()

        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.storage.snapshot?.stepsEstimated == 0)
    }

    @Test("Salir del resumen limpia el aviso y lastSampleAt: la sesión nueva del mismo store empieza sin ellos")
    func leaveSummaryResetsRecoveryState() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(lastSampleAt: Self.now.addingTimeInterval(-60)))
        await fixture.store.restoreOnLaunch()
        #expect(fixture.store.showsRecoveredNotice)
        #expect(fixture.storage.snapshot?.lastSampleAt == Self.now.addingTimeInterval(-60))

        fixture.store.requestFinish()
        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()
        fixture.clock.advance(by: 60)
        await fixture.store.start()

        #expect(!fixture.store.showsRecoveredNotice)
        let first = try #require(fixture.storage.saved.last)
        #expect(first.startedAt == fixture.clock.now)
        #expect(first.lastSampleAt == nil)
    }

    @Test("Reset · salir del resumen de una sesión restaurada con todo el estado de sesión fuera de su valor inicial: vuelve al inicial, cancela el stream y start() abre una limpia")
    func leaveSummaryResetsAllSessionState() async throws {
        let savedAt = Self.at(-300)
        let fixture = Fixture(snapshot: Self.snapshot(
            stepsMeasured: 1120, systemDistanceM: 700, savedAgoS: 300, lastSampleAt: Self.at(-400), distanceBaseM: 100
        ))
        let store = fixture.store
        await store.restoreOnLaunch()
        #expect(store.showsRecoveredNotice)
        #expect(try #require(fixture.session).stepsEstimated > 0, "gap sin dato: estimado")
        #expect(store.lastSampleAtCap == savedAt, "tope pendiente desde savedAt")

        fixture.clock.advance(by: 60)
        store.requestFinish()
        await store.confirmFinish()
        #expect(fixture.session?.status == .finished)

        // `confirmFinish()` ya limpia el gap, el tope, el conteo y los diálogos: el reset no puede
        // depender de ello. Con la sesión en el resumen se fuerza cada campo fuera de su valor
        // inicial, con un stream vivo, para que falte la línea que falte del reset se note.
        store.countSteps(from: fixture.clock.now)
        let cancelledBeforeReset = fixture.motion.cancelledStreams
        store.isConfirmingFinish = true
        store.isConfirmingDiscard = true
        store.backgroundedAt = Self.now
        store.highestCumulativeSteps = 1120
        store.distanceBaseM = 100
        store.lastSampleAt = Self.at(-400)
        store.lastSampleAtCap = savedAt

        // Antes: nada está en su valor inicial.
        #expect(store.session != nil)
        #expect(store.metrics != nil)
        #expect(store.hasSession)
        #expect(store.isConfirmingFinish)
        #expect(store.isConfirmingDiscard)
        #expect(store.showsRecoveredNotice)
        #expect(store.isCountingSteps)
        #expect(store.stepCounting != nil)
        #expect(store.segmentStart != nil)
        #expect(store.backgroundedAt != nil)
        #expect(store.highestCumulativeSteps != 0)
        #expect(store.distanceBaseM != 0)
        #expect(store.lastSampleAt != nil)
        #expect(store.lastSampleAtCap != nil)
        #expect(store.lastSavedAt != nil)

        store.leaveSummary()

        // Después: todo en su valor inicial, y el stream vivo cancelado, no solo soltado.
        #expect(store.session == nil)
        #expect(store.metrics == nil)
        #expect(!store.hasSession)
        #expect(!store.isConfirmingFinish)
        #expect(!store.isConfirmingDiscard)
        #expect(!store.showsRecoveredNotice)
        #expect(!store.isCountingSteps)
        #expect(!store.isReconciling)
        #expect(store.stepCounting == nil)
        #expect(store.segmentStart == nil)
        #expect(store.backgroundedAt == nil)
        #expect(store.highestCumulativeSteps == 0)
        #expect(store.distanceBaseM == 0)
        #expect(store.lastSampleAt == nil)
        #expect(store.lastSampleAtCap == nil)
        #expect(store.lastSavedAt == nil)
        await waitUntil { fixture.motion.cancelledStreams == cancelledBeforeReset + 1 }
        #expect(store.startFlow == .idle)
        #expect(store.startFailure == nil)
        #expect(store.elapsedS == 0)
        await store.restoreOnLaunch()
        #expect(fixture.storage.loadCount == 1, "restaurar sigue siendo una vez por arranque")

        fixture.clock.advance(by: 60)
        await store.start()

        let session = try #require(fixture.session)
        let startedAt = fixture.clock.now
        #expect(session.status == .active)
        #expect(session.startedAt == startedAt)
        #expect(session.stepsMeasured == 0)
        #expect(session.stepsEstimated == 0)
        #expect(session.systemDistanceM == nil)
        #expect(!session.recovered)
        #expect(store.metrics == SessionMetrics(distanceM: 0, paceSecPerKm: nil, cadenceSpm: 0))
        #expect(store.hasSession)
        #expect(!store.showsRecoveredNotice)
        #expect(fixture.motion.updateStarts.last == startedAt)
        let first = try #require(fixture.storage.saved.last)
        #expect(first.startedAt == startedAt)
        #expect(first.segmentStart == startedAt)
        #expect(first.segmentSteps == 0)
        #expect(first.distanceBaseM == 0)
        #expect(first.lastSampleAt == nil)

        let end = startedAt.addingTimeInterval(10)
        await Self.emitAndAutosave(fixture, steps: 10, end: end)
        #expect(fixture.session?.stepsMeasured == 10)
        #expect(fixture.session?.systemDistanceM == nil)
        #expect(fixture.storage.snapshot?.lastSampleAt == end, "sin tope heredado")
        fixture.motion.emit(steps: 20, distance: 7, end: end.addingTimeInterval(5))
        await waitUntil { fixture.session?.stepsMeasured == 20 }
        #expect(fixture.session?.systemDistanceM == 7, "sin base de distancia heredada")
    }

    @Test("lastSampleAt es el end de la última muestra que sumó pasos")
    func lastSampleAtOnlyWhenStepsAdded() async throws {
        let fixture = Fixture()
        await fixture.store.start()

        fixture.motion.emit(steps: 100, end: Self.now.addingTimeInterval(30))
        await waitUntil { fixture.session?.stepsMeasured == 100 }
        fixture.motion.emit(steps: 100, distance: 70, end: Self.now.addingTimeInterval(60))
        await waitUntil { fixture.session?.systemDistanceM == 70 }
        fixture.clock.advance(by: 90)
        fixture.store.appDidEnterBackground()

        #expect(fixture.storage.snapshot?.lastSampleAt == Self.now.addingTimeInterval(30))
    }

    @Test("Force-quit y relanzar: la sesión vuelve con el tiempo real y el \"Sesión recuperada\" no sale al volver de background")
    func forceQuitRoundTrip() async throws {
        let first = Fixture()
        await first.store.start()
        first.motion.emit(steps: 600, end: Self.now.addingTimeInterval(300))
        await waitUntil { first.session?.stepsMeasured == 600 }
        first.clock.advance(by: 300)
        first.store.appDidEnterBackground()
        #expect(!first.store.showsRecoveredNotice)

        // El sistema mata la app. Dos minutos después, Paul la reabre.
        let relaunched = Fixture(storage: first.storage, at: Self.now.addingTimeInterval(420))
        relaunched.motion.setQueryResponse(.sample(steps: 840, distance: nil))
        await relaunched.store.restoreOnLaunch()

        #expect(relaunched.session?.startedAt == Self.now)
        #expect(relaunched.store.elapsedS == 420)
        #expect(relaunched.session?.stepsMeasured == 840)
        #expect(relaunched.session?.stepsEstimated == 0)
        #expect(relaunched.store.showsRecoveredNotice)

        relaunched.store.dismissRecoveredNotice()
        relaunched.store.appDidEnterBackground()
        relaunched.clock.advance(by: 60)
        await relaunched.store.appDidBecomeActive()
        #expect(!relaunched.store.showsRecoveredNotice)
    }

    @Test("Un guardado fallido no rompe la sesión y la siguiente muestra lo reintenta")
    func failedSaveRetries() async {
        let fixture = Fixture()
        fixture.storage.failSave(with: .failed(operation: "write"))
        await fixture.store.start()
        #expect(fixture.session?.status == .active)
        #expect(fixture.storage.saved.isEmpty)

        fixture.storage.failSave(with: nil)
        fixture.clock.advance(by: 1)
        fixture.motion.emit(steps: 5)
        await waitUntil { fixture.session?.stepsMeasured == 5 }
        #expect(fixture.storage.saved.count == 1, "sin guardado previo, la muestra guarda")
    }
}

private extension SessionStoreFixture {

    /// Un store recién lanzado sobre un almacenamiento con `snapshot` guardado.
    init(snapshot: ActiveSessionSnapshot) {
        self.init(storage: StorageStub(snapshot: snapshot))
    }
}
