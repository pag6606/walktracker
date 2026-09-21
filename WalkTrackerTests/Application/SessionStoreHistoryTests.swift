import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de la 5.1 sobre `SessionStore`: la caminata cerrada se guarda, el snapshot solo se
/// borra si el guardado fue bien, la huérfana entra con su marca y una caminata ya guardada no
/// resucita al relanzar.
///
/// "Relanzar" es construir otro `SessionStoreFixture` sobre el mismo `StorageStub`: el snapshot y
/// el historial vuelven con él, como los ficheros del sandbox.
@MainActor
@Suite("SessionStore · la caminata cerrada se guarda")
struct SessionStoreHistoryTests: SessionStoreSuite {

    private typealias Fixture = SessionStoreFixture

    private nonisolated static var orphanThresholdS: TimeInterval { SessionStoreFixture.orphanThresholdS }

    // MARK: - Caminata normal

    /// El criterio de aceptación que hoy no se cumple: **hoy no queda nada**.
    @Test("Una caminata terminada queda como registro inmutable con sus campos materializados")
    func finishedWalkBecomesARecord() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        await fixture.finish()

        let session = try #require(fixture.store.session)
        let metrics = try #require(fixture.store.metrics)
        let guardadas = try #require(fixture.storage.sessions)
        #expect(guardadas.count == 1)
        let record = try #require(guardadas.first)

        #expect(record.startedAt == Self.t0)
        #expect(record.endedAt == Self.t0.addingTimeInterval(1_800))
        #expect(record.stepsMeasured == 4_100)
        #expect(record.stepsEstimated == 0)
        #expect(record.strideM == session.strideM)
        #expect(record.durationS == session.durationS)
        #expect(record.pausesS == session.pausesS)
        #expect(record.source == .ios)
        #expect(!record.recovered)
        #expect(!record.degraded)
        // Las derivadas van MATERIALIZADAS, no recalculadas al leer (AD-22).
        #expect(record.distanceM == metrics.distanceM)
        #expect(record.paceSecPerKm == metrics.paceSecPerKm)
        #expect(record.cadenceSpm == metrics.cadenceSpm)
        #expect(!fixture.store.finishedWalkNotPersisted)
    }

    @Test("Y el snapshot se borra: relanzar ya no la restaura ni la vuelve a presentar")
    func snapshotIsClearedAfterSaving() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 100)
        fixture.clock.advance(by: 600)
        await fixture.finish()

        #expect(fixture.storage.snapshot == nil)
        #expect(fixture.storage.clearCount == 1)

        fixture.store.leaveSummary()
        let relanzado = Fixture(storage: fixture.storage, at: Self.t0.addingTimeInterval(600))
        await relanzado.store.restoreOnLaunch()

        #expect(relanzado.store.session == nil)
        #expect(relanzado.history.records.count == 1, "y sigue estando en el historial")
    }

    /// El criterio de aceptación entero: se cierra la app y se reabre, y el registro sigue ahí.
    @Test("Sobrevive al relanzar: el registro vuelve íntegro, campo a campo")
    func theRecordSurvivesARelaunch() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        await fixture.finish()
        let guardado = try #require(fixture.storage.sessions?.first)
        fixture.store.leaveSummary()

        let relanzado = Fixture(storage: fixture.storage, at: Self.t0.addingTimeInterval(2_000))

        #expect(relanzado.history.records == [guardado])
    }

    @Test("Los pasos estimados viajan desglosados, nunca sumados")
    func estimatedStepsAreBrokenDownInTheRecord() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 1_000)
        // El gap de background de la 1.5: el sistema no da dato y se estima con la cadencia.
        fixture.clock.advance(by: 600)
        fixture.store.appDidEnterBackground()
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.none)
        await fixture.store.appDidBecomeActive()
        let estimados = try #require(fixture.store.session?.stepsEstimated)
        try #require(estimados > 0)

        await fixture.finish()

        let record = try #require(fixture.storage.sessions?.first)
        #expect(record.stepsMeasured == 1_000)
        #expect(record.stepsEstimated == estimados)
        #expect(record.stepsTotal == 1_000 + estimados)
    }

    @Test("El clima y la frase viajan al registro; sin ellos, ausentes")
    func weatherAndQuoteTravelWithTheRecord() async throws {
        let conClima = Fixture(
            location: LocationStub(status: .granted),
            weather: WeatherStub(),
            quotes: Fixture.bank(5),
            random: RandomStub(.fixed(0))
        )
        await conClima.startWalking(steps: 100)
        await waitUntil { conClima.store.session?.weather != nil }
        let clima = try #require(conClima.store.session?.weather)
        let frase = try #require(conClima.store.session?.quoteId)
        conClima.clock.advance(by: 600)
        await conClima.finish()

        let record = try #require(conClima.storage.sessions?.first)
        #expect(record.weather == clima)
        #expect(record.quoteId == frase)

        let sinNada = Fixture()
        await sinNada.startWalking(steps: 100)
        sinNada.clock.advance(by: 600)
        await sinNada.finish()

        let pelado = try #require(sinNada.storage.sessions?.first)
        #expect(pelado.weather == nil)
        #expect(pelado.quoteId == nil)
    }

    // MARK: - Fallo al guardar

    /// **La mutación obligatoria**: borrar el snapshot antes de guardar. Con el orden invertido,
    /// este test es el que se cae.
    @Test("Si el guardado falla, el snapshot NO se borra y el resumen lo dice")
    func aFailedSaveKeepsTheSnapshot() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))

        await fixture.finish()

        #expect(fixture.store.finishedWalkNotPersisted, "y se avisa ANTES de salir del resumen")
        #expect(fixture.storage.snapshot != nil, "el snapshot sigue: es la única copia que queda")
        #expect(fixture.storage.clearCount == 0)
        #expect(fixture.storage.sessions == nil)
        #expect(fixture.store.session?.status == .finished, "el resumen se muestra igual")
    }

    @Test("Y la caminata se recupera al relanzar")
    func theWalkComesBackAfterAFailedSave() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        // Una muestra pasado el intervalo de autosave: el snapshot en disco ya lleva los pasos.
        fixture.clock.advance(by: 1_800)
        fixture.motion.emit(steps: 4_200)
        await waitUntil { fixture.storage.snapshot?.stepsMeasured == 4_200 }
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))
        await fixture.finish()
        fixture.store.leaveSummary()

        let relanzado = Fixture(storage: fixture.storage, at: Self.t0.addingTimeInterval(1_900))
        await relanzado.store.restoreOnLaunch()

        #expect(relanzado.store.hasSession, "la caminata vuelve")
        #expect(relanzado.store.session?.startedAt == Self.t0)
        #expect(relanzado.store.session?.stepsMeasured == 4_200)
        #expect(relanzado.history.records.isEmpty, "y no estaba guardada: por eso vuelve")
    }

    /// El último instante en que el registro sigue a mano: si el disco se recupera, la caminata
    /// se guarda y el snapshot se puede borrar.
    @Test("Salir del resumen reintenta el guardado, y si entra borra el snapshot")
    func leavingTheSummaryRetriesTheSave() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))
        await fixture.finish()
        try #require(fixture.store.finishedWalkNotPersisted)

        fixture.storage.failSaveSessions(with: nil)
        fixture.store.leaveSummary()

        #expect(fixture.storage.sessions?.count == 1)
        #expect(fixture.storage.snapshot == nil, "ya está a salvo en su sitio definitivo")
        #expect(!fixture.store.finishedWalkNotPersisted)
    }

    @Test("Si el reintento tampoco entra, el snapshot sigue y la caminata vuelve al relanzar")
    func aFailedRetryStillKeepsTheSnapshot() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        fixture.storage.failSaveSessions(with: .failed(operation: "write"))
        await fixture.finish()

        fixture.store.leaveSummary()

        #expect(fixture.storage.snapshot != nil)
        #expect(fixture.storage.sessions == nil)
        #expect(!fixture.store.finishedWalkNotPersisted, "el aviso es de la sesión que se acaba de soltar")
    }

    /// Un historial que no se pudo leer bloquea la escritura (B-1) y eso llega hasta aquí: la
    /// caminata no se guarda, pero **tampoco se pierde**, porque el snapshot sigue.
    @Test("Con el historial ilegible no se escribe encima, y la caminata queda en el snapshot")
    func anUnreadableHistoryBlocksTheSaveWithoutLosingTheWalk() async throws {
        let storage = StorageStub()
        storage.failLoadSessions(with: .unsupportedSchemaVersion(99))
        let fixture = Fixture(storage: storage)
        try #require(fixture.history.showsUnreadableNotice)

        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        await fixture.finish()

        #expect(fixture.store.finishedWalkNotPersisted)
        #expect(storage.sessionsSaved.isEmpty, "no se escribe encima de lo que no se pudo leer")
        #expect(storage.snapshot != nil)
    }

    // MARK: - Ventana de duplicado

    /// **Entre guardar y borrar el snapshot** la caminata existe en los dos ficheros. Si la app
    /// muere ahí, al relanzar no puede archivarse otra vez ni volver a presentarse.
    @Test("Una caminata ya guardada no se restaura ni se archiva otra vez al relanzar")
    func anAlreadySavedWalkIsNotResurrected() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        // El corte: el guardado entra y el borrado del snapshot no.
        fixture.storage.failClear(with: .failed(operation: "remove"))
        await fixture.finish()
        let snapshot = try #require(fixture.storage.snapshot)
        try #require(fixture.storage.sessions?.count == 1)

        let relanzado = Fixture(storage: fixture.storage, at: snapshot.startedAt.addingTimeInterval(1_900))
        relanzado.storage.failClear(with: nil)
        await relanzado.store.restoreOnLaunch()

        #expect(relanzado.store.session == nil, "no vuelve como sesión viva")
        #expect(!relanzado.store.hasSession)
        #expect(relanzado.history.records.count == 1, "ni se duplica en el historial")
        #expect(relanzado.storage.snapshot == nil, "y el snapshot se termina de borrar")
    }

    /// El caso peor: el corte ocurre y encima pasa el umbral de huérfana. Sin esta guarda, la
    /// caminata guardada entraría **otra vez** en el historial, marcada como recuperada.
    @Test("Y tampoco pasado el umbral de huérfana")
    func anAlreadySavedWalkIsNotArchivedAsOrphan() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 4_100)
        fixture.clock.advance(by: 1_800)
        fixture.storage.failClear(with: .failed(operation: "remove"))
        await fixture.finish()
        try #require(fixture.storage.snapshot != nil)

        let relanzado = Fixture(storage: fixture.storage, at: Self.t0.addingTimeInterval(Self.orphanThresholdS + 3_600))
        relanzado.storage.failClear(with: nil)
        await relanzado.store.restoreOnLaunch()

        #expect(relanzado.history.records.count == 1)
        #expect(relanzado.history.records.first?.recovered == false, "la que hay sigue siendo la que Paul cerró")
        #expect(relanzado.store.session == nil)
    }

    // MARK: - Sesión huérfana

    /// AD-18: se archiva **con su marca** y no dispara logros. El segundo sitio que cierra una
    /// sesión, el que era fácil de olvidar.
    @Test("La huérfana entra en el historial marcada, suma distancia y no cuenta para logros")
    func theOrphanIsArchivedWithItsMark() async throws {
        let startedAt = Self.t0.addingTimeInterval(-(Self.orphanThresholdS + 3_600))
        let snapshot = ActiveSessionSnapshot(
            startedAt: startedAt,
            stepsMeasured: 3_000,
            stepsEstimated: 0,
            totalPausesS: 0,
            paused: false,
            pausedAt: nil,
            strideM: 0.655,
            systemDistanceM: nil,
            savedAt: startedAt.addingTimeInterval(1_800),
            lastSampleAt: startedAt.addingTimeInterval(1_800),
            segmentStart: startedAt,
            segmentSteps: 3_000,
            distanceBaseM: 0
        )
        let fixture = Fixture(storage: StorageStub(snapshot: snapshot))

        await fixture.store.restoreOnLaunch()

        let record = try #require(fixture.storage.sessions?.first)
        #expect(record.recovered, "entra con su marca")
        #expect(!record.countsForAchievements, "AD-18: no dispara logros")
        #expect(record.startedAt == startedAt)
        #expect(record.endedAt == startedAt.addingTimeInterval(1_800), "recortada a su último dato real")
        #expect(record.stepsMeasured == 3_000)
        #expect(record.distanceM > 0, "pero su distancia es real: la contó el coprocesador")
        #expect(record.distanceM == fixture.store.metrics?.distanceM)
        #expect(fixture.storage.snapshot == nil, "y el snapshot se borra, porque el guardado entró")
    }

    @Test("Si el guardado de la huérfana falla, su snapshot NO se borra")
    func aFailedOrphanSaveKeepsItsSnapshot() async throws {
        let startedAt = Self.t0.addingTimeInterval(-(Self.orphanThresholdS + 3_600))
        let snapshot = ActiveSessionSnapshot(
            startedAt: startedAt,
            stepsMeasured: 3_000,
            stepsEstimated: 0,
            totalPausesS: 0,
            paused: false,
            pausedAt: nil,
            strideM: 0.655,
            systemDistanceM: nil,
            savedAt: startedAt.addingTimeInterval(1_800),
            lastSampleAt: startedAt.addingTimeInterval(1_800),
            segmentStart: startedAt,
            segmentSteps: 3_000,
            distanceBaseM: 0
        )
        let storage = StorageStub(snapshot: snapshot)
        storage.failSaveSessions(with: .failed(operation: "write"))
        let fixture = Fixture(storage: storage)

        await fixture.store.restoreOnLaunch()

        #expect(storage.snapshot != nil)
        #expect(fixture.store.finishedWalkNotPersisted)
        #expect(fixture.store.hasSession, "su resumen se muestra igual")
    }

    // MARK: - Métrica degradada

    /// `metrics(at:)` devuelve `distanceM: 0` con `degraded: true` cuando algo no cuadra (B-3).
    /// **Un 0 en disco es indistinguible de una caminata sin pasos**, y el registro es inmutable:
    /// la marca tiene que viajar con él o la información se pierde para siempre.
    ///
    /// Se prueba sobre el materializador y no sobre una caminata entera a propósito: desde B-3 la
    /// frontera de escritura y `validateStride` hacen esa degradación **inalcanzable** desde la
    /// UI, y montar una sesión imposible para provocarla probaría el montaje, no el mapeo.
    @Test("La marca de métrica degradada viaja del cálculo al registro")
    func theDegradedMarkReachesTheRecord() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 100)
        fixture.clock.advance(by: 600)
        await fixture.finish()
        let session = try #require(fixture.store.session)

        let degradada = SessionMetrics(distanceM: 0, paceSecPerKm: nil, cadenceSpm: 10, degraded: true)
        let record = try #require(fixture.store.finishedRecord(session, metrics: degradada))

        #expect(record.degraded)
        #expect(record.distanceM == 0)
        let sana = try #require(fixture.store.finishedRecord(session, metrics: SessionMetrics(distanceM: 0, paceSecPerKm: nil, cadenceSpm: 10)))
        #expect(!sana.degraded)
    }
}

private extension SessionStoreFixture {

    /// Cierra la sesión pasando por la confirmación, como la UI.
    func finish() async {
        store.requestFinish()
        await store.confirmFinish()
    }
}
