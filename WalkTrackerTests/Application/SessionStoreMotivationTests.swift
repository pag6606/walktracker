import Domain
import Foundation
import Testing

@testable import WalkTracker

/// La frase del arranque en el store (2.2, CAP-6): el orden dentro de `openSession()`, el
/// `quoteId` en el agregado y en el snapshot, el overlay y su descarte, la ventana de
/// recientes y las degradaciones.
///
/// Lo que NO se prueba aquí —y va a `deferred-work.md`— es la presentación: que el overlay se
/// vea, que se anuncie a VoiceOver o que respete Reduce Motion exige renderizar una vista y no
/// hay target de UI tests (A-4). La **decisión** vive en el store, y eso sí se prueba.
@MainActor
@Suite("SessionStore · frase motivacional del arranque")
struct SessionStoreMotivationTests: SessionStoreSuite {

    private static func fixture(
        quotes: QuoteBank = SessionStoreFixture.bank(100),
        random: RandomStub = RandomStub(.fixed(0)),
        storage: StorageStub = StorageStub()
    ) -> SessionStoreFixture {
        SessionStoreFixture(storage: storage, quotes: quotes, random: random)
    }

    // MARK: - El orden del arranque

    @Test("Al iniciar: la sesión ya corre y ya cuenta pasos cuando aparece la frase")
    func sessionIsRunningUnderTheQuote() async throws {
        let fixture = Self.fixture()

        await fixture.store.start()

        let session = try #require(fixture.store.session)
        #expect(session.status == .active, "el cronómetro ya cuenta por debajo")
        #expect(fixture.store.hasSession, "la sesión ya está presentada")
        #expect(fixture.store.isCountingSteps, "el podómetro ya está abierto")
        #expect(fixture.store.metrics != nil)
        #expect(fixture.store.quote != nil, "y la frase va encima")
    }

    @Test("La frase se elige y se adjunta al agregado")
    func quoteIsAttached() async throws {
        let fixture = Self.fixture()

        await fixture.store.start()

        let quote = try #require(fixture.store.quote)
        #expect(quote.id == 1, "índice 0 del banco entero: la ventana está vacía")
        #expect(fixture.store.session?.quoteId == quote.id)
    }

    @Test("El quoteId entra en el PRIMER snapshot: un force-quit temprano no lo pierde")
    func quoteIdIsInTheFirstSnapshot() async throws {
        let storage = StorageStub()
        let fixture = Self.fixture(storage: storage)

        await fixture.store.start()

        let first = try #require(storage.saved.first)
        #expect(first.quoteId == fixture.store.quote?.id)
        #expect(storage.saved.allSatisfy { $0.quoteId != nil })
    }

    // MARK: - El overlay

    @Test("Un tap descarta la frase y la sesión sigue exactamente igual por debajo")
    func dismissKeepsTheSessionRunning() async throws {
        let fixture = Self.fixture()
        await fixture.store.start()
        let quoteId = try #require(fixture.store.quote?.id)
        let stepsBefore = fixture.store.session?.stepsMeasured

        fixture.store.dismissQuote()

        #expect(fixture.store.quote == nil, "el overlay se va")
        #expect(fixture.store.session?.status == .active, "la caminata no se entera")
        #expect(fixture.store.session?.quoteId == quoteId, "el quoteId se queda en el agregado")
        #expect(fixture.store.session?.stepsMeasured == stepsBefore)
        #expect(fixture.store.isCountingSteps)
    }

    @Test("Descartar dos veces no rompe nada")
    func dismissIsIdempotent() async {
        let fixture = Self.fixture()
        await fixture.store.start()

        fixture.store.dismissQuote()
        fixture.store.dismissQuote()

        #expect(fixture.store.quote == nil)
        #expect(fixture.store.session?.status == .active)
    }

    @Test("Al finalizar, el overlay se apaga con el podómetro y la captura de clima")
    func confirmFinishClearsTheQuote() async throws {
        let fixture = Self.fixture()
        await fixture.store.start()
        let quoteId = try #require(fixture.store.quote?.id)

        await fixture.store.confirmFinish()

        #expect(fixture.store.quote == nil, "lo que viene es el resumen, no la frase")
        #expect(fixture.store.session?.status == .finished)
        #expect(fixture.store.session?.quoteId == quoteId, "el quoteId sigue en el agregado")
    }

    @Test("Al salir del resumen, la frase no viaja a la sesión siguiente")
    func resetClearsTheQuote() async throws {
        let fixture = Self.fixture()
        await fixture.store.start()
        #expect(fixture.store.quote != nil)

        await fixture.store.confirmFinish()
        fixture.store.leaveSummary()

        #expect(fixture.store.quote == nil)
        #expect(fixture.store.session == nil)
    }

    // MARK: - Relanzar tras force-quit

    @Test("Sesión recuperada con quoteId: vuelve la frase al agregado, pero NO el overlay")
    func restoredSessionDoesNotShowTheOverlayAgain() async throws {
        // La trampa de la historia: "ya mostrada" no es lo mismo que "hay quoteId".
        let storage = StorageStub()
        let first = Self.fixture(storage: storage)
        await first.store.start()
        let shown = try #require(first.store.quote?.id)
        #expect(storage.snapshot?.quoteId == shown)

        // "Relanzar" es montar otro store sobre el mismo almacenamiento.
        let relaunched = Self.fixture(storage: storage)
        await relaunched.store.restoreOnLaunch()

        #expect(relaunched.store.session?.quoteId == shown, "el quoteId se conserva")
        #expect(relaunched.store.quote == nil, "y el overlay NO vuelve a salir")
        #expect(relaunched.store.hasSession)
    }

    @Test("Una sesión recuperada tampoco elige frase nueva")
    func restoredSessionDoesNotPickAnother() async throws {
        let storage = StorageStub()
        let first = Self.fixture(storage: storage)
        await first.store.start()
        let shown = try #require(first.store.quote?.id)

        let random = RandomStub(.fixed(0))
        let relaunched = Self.fixture(random: random, storage: storage)
        await relaunched.store.restoreOnLaunch()

        #expect(random.callCount == 0, "restaurar no pasa por el motor de motivación")
        #expect(relaunched.store.session?.quoteId == shown)
    }

    @Test("Snapshot antiguo sin quoteId: se restaura sin frase y sin apartarse")
    func oldSnapshotWithoutQuote() async throws {
        let storage = StorageStub(snapshot: ActiveSessionSnapshot(
            startedAt: Self.t0, stepsMeasured: 1200, stepsEstimated: 0, totalPausesS: 0, paused: false,
            pausedAt: nil, strideM: 0.655, systemDistanceM: nil, savedAt: Self.t0.addingTimeInterval(60),
            lastSampleAt: Self.t0.addingTimeInterval(60), segmentStart: Self.t0, segmentSteps: 1200,
            distanceBaseM: 0
        ))
        let fixture = SessionStoreFixture(storage: storage, at: Self.t0.addingTimeInterval(120), quotes: SessionStoreFixture.bank(100))

        await fixture.store.restoreOnLaunch()

        #expect(fixture.store.session?.quoteId == nil)
        #expect(fixture.store.quote == nil)
        #expect(storage.setAside.isEmpty, "no se aparta: es un snapshot válido, solo antiguo")
        #expect(fixture.store.hasSession)
    }

    // MARK: - Ventana de recientes

    @Test("La frase mostrada entra en la ventana persistida, y el fichero se escribe")
    func shownQuoteGoesIntoTheWindow() async throws {
        let storage = StorageStub()
        let fixture = Self.fixture(storage: storage)

        await fixture.store.start()

        let shown = try #require(fixture.store.quote?.id)
        #expect(fixture.settings.recentQuoteIds == [shown])
        #expect(storage.settingsSaved.last?.recentQuoteIds == [shown])
    }

    @Test("Sin settings.json (primera vez): la ventana está vacía y se elige de las 100")
    func firstLaunchHasAnEmptyWindow() async throws {
        let storage = StorageStub()
        let random = RandomStub(.fixed(0))
        let fixture = Self.fixture(random: random, storage: storage)
        #expect(storage.settings == nil)

        await fixture.store.start()

        #expect(random.counts == [100], "sin ventana, el conjunto es el banco entero")
        #expect(storage.settings != nil, "y el fichero se crea al guardar")
    }

    @Test("Ajustes corruptos: se parte de la ventana vacía y no se pierde la sesión")
    func corruptSettings() async throws {
        let storage = StorageStub(settings: AppSettings(recentQuoteIds: [1, 2, 3]))
        storage.failLoadSettings(with: .malformed("basura"))
        let random = RandomStub(.fixed(0))

        let fixture = Self.fixture(random: random, storage: storage)
        await fixture.store.start()

        #expect(storage.settingsSetAside.count == 1, "se aparta, como hace el snapshot")
        #expect(random.counts == [100], "se elige de las 100: la ventana se perdió, no se adivina")
        #expect(fixture.store.session != nil, "y la caminata arranca igual")
    }

    @Test("Una ventana guardada se respeta al elegir")
    func storedWindowIsHonoured() async throws {
        let storage = StorageStub(settings: AppSettings(recentQuoteIds: Array(1...20)))
        let random = RandomStub(.fixed(0))
        let fixture = Self.fixture(random: random, storage: storage)

        await fixture.store.start()

        #expect(random.counts == [80])
        #expect(fixture.store.quote?.id == 21)
    }

    @Test("Todas excluidas: se ignora el filtro, pero la frase SÍ se muestra y SÍ se adjunta")
    func ignoredRecentWindowStillShowsAQuote() async throws {
        // El fallback heredado a nivel de store, que el banco de 100 de las demás suites no
        // alcanza nunca: banco de 3 y ventana con esos 3. Registrarlo con `log.info` es lo
        // único que cambia; el usuario tiene que seguir viendo una frase.
        let storage = StorageStub(settings: AppSettings(recentQuoteIds: [1, 2, 3]))
        let random = RandomStub(.fixed(2))
        let fixture = Self.fixture(quotes: SessionStoreFixture.bank(3), random: random, storage: storage)

        await fixture.store.start()

        let quote = try #require(fixture.store.quote, "el fallback no puede dejar la caminata sin frase")
        #expect(random.counts == [3], "el conjunto vuelve a ser el banco entero")
        #expect(fixture.store.session?.quoteId == quote.id, "y la frase se adjunta al agregado")
        #expect([1, 2, 3].contains(quote.id), "el id elegido estaba en la ventana: por eso hubo fallback")
        #expect(storage.saved.first?.quoteId == quote.id, "también entra en el primer snapshot")
    }

    @Test("Un fallo al guardar los ajustes no cuesta la caminata")
    func settingsSaveFailureIsSurvivable() async throws {
        let storage = StorageStub()
        storage.failSaveSettings(with: .failed(operation: "write"))
        let fixture = Self.fixture(storage: storage)

        await fixture.store.start()

        #expect(fixture.store.session != nil)
        #expect(fixture.store.quote != nil)
        #expect(fixture.settings.recentQuoteIds.count == 1, "la ventana en memoria sí avanza")
    }

    // MARK: - 20 caminatas seguidas

    @Test("20 caminatas consecutivas: ninguna frase repetida, y la ventana persiste entre ellas")
    func twentyConsecutiveWalksWithoutRepeats() async throws {
        // El almacenamiento es el mismo en las 20: es lo que hace que la ventana sobreviva a
        // cada cierre de sesión. El azar, siempre el índice 0: sin la ventana las 20 serían la
        // misma frase.
        let storage = StorageStub()
        let bank = SessionStoreFixture.bank(100)
        var shown: [Int] = []

        for walk in 0..<20 {
            let fixture = SessionStoreFixture(storage: storage, quotes: bank, random: RandomStub(.fixed(0)))
            await fixture.store.start()
            let quote = try #require(fixture.store.quote, "caminata \(walk): sin frase")
            shown.append(quote.id)
            await fixture.store.confirmFinish()
            fixture.store.leaveSummary()
        }

        #expect(shown.count == 20)
        #expect(Set(shown).count == 20, "ninguna repetida en la secuencia: \(shown)")
        #expect(storage.settings?.recentQuoteIds == shown, "la ventana guardada es la secuencia entera")
    }

    // MARK: - Degradaciones

    @Test("Banco vacío: no hay frase, no hay overlay y la sesión sigue")
    func emptyBank() async {
        let random = RandomStub(.fixed(0))
        let fixture = Self.fixture(quotes: .empty, random: random)

        await fixture.store.start()

        #expect(fixture.store.session?.status == .active)
        #expect(fixture.store.session?.quoteId == nil)
        #expect(fixture.store.quote == nil)
        #expect(random.callCount == 0, "con el banco vacío no se pide ni un índice")
        #expect(fixture.settings.recentQuoteIds.isEmpty, "y no se registra nada en la ventana")
    }

    @Test("Un azar que no elige tampoco deja la sesión a medias")
    func randomWithoutIndex() async {
        let fixture = SessionStoreFixture(quotes: SessionStoreFixture.bank(100), random: RandomStub(.none))

        await fixture.store.start()

        #expect(fixture.store.session?.status == .active)
        #expect(fixture.store.session?.quoteId == nil)
        #expect(fixture.store.quote == nil)
    }

    @Test("La frase se elige una sola vez: pausar, reanudar y reconciliar no la cambian")
    func quoteIsChosenOnce() async throws {
        let random = RandomStub(.increasing)
        let fixture = Self.fixture(random: random)
        await fixture.store.start()
        let quoteId = try #require(fixture.store.session?.quoteId)

        fixture.store.pause()
        fixture.store.resume()
        fixture.store.appDidEnterBackground()
        await fixture.store.appDidBecomeActive()

        #expect(fixture.store.session?.quoteId == quoteId)
        #expect(random.callCount == 1, "el motor solo corre en el arranque")
        #expect(fixture.settings.recentQuoteIds == [quoteId])
    }

    @Test("Un doble toque en Iniciar no elige dos frases")
    func doubleStartPicksOneQuote() async throws {
        let random = RandomStub(.increasing)
        let fixture = Self.fixture(random: random)

        await fixture.store.start()
        await fixture.store.start()

        #expect(random.callCount == 1)
        #expect(fixture.settings.recentQuoteIds.count == 1)
    }

    // MARK: - El agregado

    @Test("attachQuote congela la frase: un segundo intento lanza y no muta")
    func attachQuoteFreezes() throws {
        var session = try Session.start(at: Self.t0, strideM: 0.655)
        try session.attachQuote(7)

        #expect(throws: DomainError.invalidTransition(from: "active", to: "replaceQuote")) {
            try session.attachQuote(9)
        }
        #expect(session.quoteId == 7)
    }

    @Test("Una sesión finalizada no admite frase")
    func finishedSessionRejectsQuote() throws {
        var session = try Session.start(at: Self.t0, strideM: 0.655)
        try session.finish(at: Self.t0.addingTimeInterval(60))

        #expect(throws: DomainError.invalidTransition(from: "finished", to: "attachQuote")) {
            try session.attachQuote(7)
        }
        #expect(session.quoteId == nil)
    }

    @Test("restore devuelve el quoteId sin comprobarlo contra el banco")
    func restoreKeepsTheQuoteId() throws {
        let session = try Session.restore(
            startedAt: Self.t0, stepsMeasured: 0, stepsEstimated: 0, totalPausesS: 0, paused: false,
            pausedAt: nil, strideM: 0.655, systemDistanceM: nil, quoteId: 900
        )

        #expect(session.quoteId == 900, "un id que ya no está en el banco no invalida la sesión")
    }
}
