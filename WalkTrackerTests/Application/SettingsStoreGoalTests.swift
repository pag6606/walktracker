import Domain
import Foundation
import Testing

@testable import WalkTracker

/// La meta semanal en el store (3.1): qué se guarda, qué se rechaza, qué suma el anillo y
/// cuándo se celebra.
///
/// **Aquí vive la decisión, y por eso la historia se puede probar sin renderizar el anillo**
/// (A-4 sigue abierto). La vista entrega el texto crudo, pinta `goalOutcome` y dibuja
/// `weeklyProgress`; parsear, validar, sumar la semana y decidir si toca celebrar es de este
/// fichero.
@MainActor
@Suite("SettingsStore · la meta semanal y el anillo")
struct SettingsStoreGoalTests {

    // MARK: - Soporte

    /// Miércoles 8 de julio de 2026, 12:00 UTC. La semana es `[lunes 6, lunes 13)`.
    private static let wednesday = Self.instant("2026-07-08T12:00:00Z")

    private static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// El store con sus tres colaboradores **explícitos**: el reloj es un `ClockStub` en UTC,
    /// porque con el reloj real la semana la fijaría el día en que se ejecute la suite.
    private static func store(
        _ storage: StorageStub = StorageStub(),
        now: Date = Self.wednesday,
        timeZone: String = "UTC",
        feedback: any FeedbackPort = FeedbackSpy()
    ) -> (StorageStub, SettingsStore, AchievementsStore) {
        let history = HistoryStore(storage: storage)
        let achievements = AchievementsStore(storage: storage)
        let settings = SettingsStore(
            storage: storage,
            history: history,
            achievements: achievements,
            feedback: feedback,
            clock: ClockStub(now: now, timeZone: timeZone)
        )
        return (storage, settings, achievements)
    }

    private static func record(_ startedAt: String, _ distanceM: Double, recovered: Bool = false) throws -> SessionRecord {
        try SessionRecord(
            id: UUID(),
            startedAt: instant(startedAt),
            endedAt: instant(startedAt),
            stepsMeasured: 0,
            stepsEstimated: 0,
            strideM: 0.655,
            distanceM: distanceM,
            durationS: 0,
            pausesS: 0,
            paceSecPerKm: nil,
            cadenceSpm: 0,
            recovered: recovered
        )
    }

    // MARK: - La semana es LOCAL en la costura donde se cablea el calendario

    /// **La misma exposición que la 3.2 destapó en el cierre de sesión, y viene de la 3.1.** Los
    /// 15 vectores de `weeklyProgress` llaman a `GoalEngine` **directamente** con la zona que
    /// declaran; por `SettingsStore+Goal.swift`, que es donde `clock.calendar` se cablea de
    /// verdad, no pasa ninguno — y el reloj de los tests estaba clavado en UTC, así que
    /// sustituirlo ahí por un `Calendar` en UTC (lo que AD-19 prohíbe) salía en verde.
    ///
    /// El caso: son las **20:00 del domingo 12 en Guayaquil**, que en UTC ya es el **lunes 13 a
    /// la 01:00**. En hora local Paul sigue en su semana y el anillo enseña los 7,5 km del sábado;
    /// con el calendario en UTC la semana ya habría cambiado y el anillo se vaciaría solo la
    /// noche del domingo.
    @Test("El anillo suma la semana LOCAL: el domingo por la noche en Guayaquil sigue en su semana")
    func theWeekIsLocalAtTheWiringSeam() throws {
        // Sábado 11 de julio, 15:00 en Guayaquil.
        let sabado = try Self.record("2026-07-11T20:00:00Z", 7_500)
        let storage = StorageStub(sessions: [sabado])
        // "Ahora": domingo 12 a las 20:00 locales = lunes 13 a la 01:00 UTC.
        let domingoNoche = Self.instant("2026-07-13T01:00:00Z")
        let (_, settings, _) = Self.store(storage, now: domingoNoche, timeZone: "America/Guayaquil")

        let progress = try #require(settings.weeklyProgress)

        #expect(progress.completedKm == 7.5, "con el calendario en UTC ya sería lunes, otra semana, y esto sería 0")
        #expect(
            GoalEngine.weekKey(for: domingoNoche, calendar: settings.clock.calendar) == "2026-W28",
            "en UTC este mismo instante es 2026-W29"
        )
    }

    // MARK: - Guardar la meta

    @Test("Guardar una meta válida: se persiste y el anillo pasa a medir contra ella")
    func savesValidGoal() throws {
        let (storage, settings, _) = Self.store(StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 7500)]))

        settings.saveGoal(fromText: "15")

        #expect(settings.goalOutcome == .saved)
        #expect(settings.weeklyGoalKm == 15)
        #expect(storage.settingsSaved.map(\.weeklyGoalKm) == [15], "una sola escritura por pulsación")
        #expect(settings.weeklyProgress?.goalKm == 15)
        #expect(settings.weeklyProgress?.percentage == 50)
    }

    @Test("Sin fijarla nunca, el anillo usa 10 km y no se escribe nada")
    func unsetGoalUsesTheDefault() {
        let (storage, settings, _) = Self.store()

        #expect(settings.weeklyGoalKm == nil)
        #expect(settings.resolvedWeeklyGoalKm == 10)
        #expect(settings.weeklyProgress?.goalKm == 10)
        #expect(storage.settingsSaved.isEmpty, "no tocarla no escribe nada")
    }

    @Test("Guardar la meta no toca la zancada ni la ventana de frases, que están en el mismo fichero")
    func savingTheGoalKeepsTheOtherSettings() throws {
        var stored = AppSettings(recentQuoteIds: [1, 2, 3])
        try stored.setStrideM(0.67)
        let (storage, settings, _) = Self.store(StorageStub(settings: stored))

        settings.saveGoal(fromText: "12,5")

        #expect(settings.weeklyGoalKm == 12.5)
        #expect(settings.strideM == 0.67)
        #expect(settings.recentQuoteIds == [1, 2, 3])
        #expect(storage.settingsSaved.last?.strideM == 0.67)
        #expect(storage.settingsSaved.last?.recentQuoteIds == [1, 2, 3])
    }

    @Test("Guardar dos veces: gana la última, y cada pulsación escribe una vez")
    func lastSaveWins() {
        let (storage, settings, _) = Self.store()

        settings.saveGoal(fromText: "15")
        settings.saveGoal(fromText: "20")

        #expect(settings.weeklyGoalKm == 20)
        #expect(storage.settingsSaved.map(\.weeklyGoalKm) == [15, 20])
    }

    // MARK: - Rechazos (nada se persiste)

    @Test("Se rechaza con mensaje y el fichero NO cambia", arguments: [
        ("", SettingsStore.GoalRejection.notANumber),
        ("abc", .notANumber),
        (",", .notANumber),
        ("0", .notPositive),
        ("-3", .notPositive),
    ])
    func rejectedGoalsDoNotTouchTheFile(text: String, rejection: SettingsStore.GoalRejection) {
        let (storage, settings, _) = Self.store()

        settings.saveGoal(fromText: text)

        #expect(settings.goalOutcome == .rejected(rejection))
        #expect(settings.weeklyGoalKm == nil)
        #expect(storage.settingsSaved.isEmpty, "un valor inválido no llega ni a intentar escribir")
    }

    @Test("Por debajo del mínimo se rechaza diciendo CUÁL es el mínimo, no 'mayor que cero'")
    func belowTheMinimumIsItsOwnRejection() {
        let (storage, settings, _) = Self.store()

        settings.saveGoal(fromText: "0,5")

        #expect(settings.goalOutcome == .rejected(.belowMinimum(AppSettings.minimumWeeklyGoalKm)))
        #expect(settings.weeklyGoalKm == nil)
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("El mínimo exacto se guarda")
    func theMinimumGoalIsAccepted() {
        let (storage, settings, _) = Self.store()

        settings.saveGoal(fromText: "1")

        #expect(settings.goalOutcome == .saved)
        #expect(settings.weeklyGoalKm == 1)
        #expect(storage.settingsSaved.map(\.weeklyGoalKm) == [1])
    }

    @Test("Un número que no es finito se rechaza por NO CABER, no por no ser positivo")
    func nonFiniteGoalIsRejectedAsTooLarge() {
        let (storage, settings, _) = Self.store()

        settings.saveGoal(fromText: String(repeating: "9", count: 400))

        #expect(settings.goalOutcome == .rejected(.notFinite))
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("Un rechazo no pisa la meta que ya estaba guardada")
    func rejectionKeepsTheStoredGoal() {
        let (storage, settings, _) = Self.store()
        settings.saveGoal(fromText: "15")

        settings.saveGoal(fromText: "0")

        #expect(settings.goalOutcome == .rejected(.notPositive))
        #expect(settings.weeklyGoalKm == 15)
        #expect(storage.settingsSaved.count == 1, "la segunda pulsación no escribió")
    }

    // MARK: - Volver al valor por defecto

    @Test("Quitar la meta la borra del fichero y devuelve los 10 km")
    func clearingTheGoalWritesAndReturnsToDefault() {
        let (storage, settings, _) = Self.store()
        settings.saveGoal(fromText: "15")

        settings.clearGoal()

        #expect(settings.goalOutcome == .clearedToDefault)
        #expect(settings.weeklyGoalKm == nil)
        #expect(settings.resolvedWeeklyGoalKm == 10)
        #expect(storage.settingsSaved.last?.weeklyGoalKm == nil)
    }

    @Test("Quitarla sin nada que quitar no escribe nada y apaga el mensaje")
    func clearingWithoutGoalWritesNothing() {
        let (storage, settings, _) = Self.store()
        settings.saveGoal(fromText: "abc")

        settings.clearGoal()

        #expect(settings.goalOutcome == nil)
        #expect(storage.settingsSaved.isEmpty)
    }

    // MARK: - El mensaje no sobrevive a la pantalla

    @Test("Escribir otra vez apaga el mensaje; salir de Ajustes, también")
    func theMessageDoesNotOutliveThePulse() {
        let (_, settings, _) = Self.store()

        settings.saveGoal(fromText: "15")
        settings.goalEditingDidChange()
        #expect(settings.goalOutcome == nil)

        settings.saveGoal(fromText: "15")
        settings.goalScreenDidDisappear()
        #expect(settings.goalOutcome == nil)
    }

    // MARK: - El disco falla

    @Test("Con el disco caído la meta vale para esta ejecución, pero el mensaje NO dice 'guardada'")
    func diskFailureIsNotSaved() {
        let storage = StorageStub()
        storage.failSaveSettings(with: .failed(operation: "write"))
        let (_, settings, _) = Self.store(storage)

        settings.saveGoal(fromText: "15")

        #expect(settings.goalOutcome == .notPersisted)
        #expect(settings.goalOutcome?.isSaved == false)
        #expect(settings.weeklyGoalKm == 15, "el anillo de esta ejecución ya la usa")
    }

    @Test("Con los ajustes ilegibles no se escribe encima: la meta se aplica en memoria y se dice")
    func unreadableSettingsAreNotOverwritten() {
        let storage = StorageStub()
        storage.failLoadSettings(with: .unsupportedSchemaVersion(99))
        let (_, settings, _) = Self.store(storage)

        settings.saveGoal(fromText: "15")

        #expect(settings.goalOutcome == .notPersisted)
        #expect(storage.settingsSaved.isEmpty, "B-1: un esquema del futuro no se sobrescribe")
    }

    // MARK: - El progreso del anillo

    @Test("El anillo suma las caminatas de la semana y no las de la anterior")
    func theRingSumsThisWeekOnly() throws {
        let records = try [
            Self.record("2026-06-28T10:00:00Z", 10_000),
            Self.record("2026-07-06T10:00:00Z", 3000),
            Self.record("2026-07-07T10:00:00Z", 4000),
        ]
        let (_, settings, _) = Self.store(StorageStub(sessions: records))

        let progress = try #require(settings.weeklyProgress)

        #expect(progress.completedKm == 7)
        #expect(progress.percentage == 70)
        #expect(progress.isComplete == false)
    }

    @Test("Una caminata huérfana suma en el anillo, aunque no cuente para logros")
    func orphanWalksSumInTheRing() throws {
        let (_, settings, _) = Self.store(StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000, recovered: true)]))

        #expect(settings.weeklyProgress?.completedKm == 12)
        #expect(settings.weeklyProgress?.isComplete == true)
    }

    @Test("Con el historial ilegible el anillo NO miente: no hay progreso, y no es 0 %")
    func unreadableHistoryHasNoProgress() {
        let storage = StorageStub()
        storage.failLoadSessions(with: .malformed("bytes"))
        let (_, settings, achievements) = Self.store(storage)

        #expect(settings.weeklyProgress == nil, "0 % afirmaría que Paul no ha caminado, y eso nadie lo sabe")
        #expect(settings.goalRingDidUpdate() == false, "y sin saberlo no se celebra ni se desbloquea nada")
        #expect(achievements.unlock(forKey: AchievementsStore.weeklyGoalKey) == nil)
    }

    // MARK: - La celebración, una por semana (AD-25)

    @Test("Al cumplir la meta: se desbloquea weekly_goal y se celebra, UNA vez por semana")
    func reachingTheGoalCelebratesOnce() throws {
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        let (_, settings, achievements) = Self.store(storage)

        #expect(settings.goalRingDidUpdate() == true, "la primera vez de la semana sí")
        #expect(settings.goalRingDidUpdate() == false, "refrescar la pantalla no vuelve a celebrar")

        let unlocked = try #require(achievements.unlock(forKey: AchievementsStore.weeklyGoalKey))
        #expect(unlocked.isUnlocked)
        #expect(unlocked.unlockedAt == Self.wednesday)
        #expect(storage.achievementsSaved.count == 1, "el desbloqueo se escribió una sola vez")
        #expect(storage.settingsSaved.last?.lastGoalCelebratedWeek == "2026-W28")
    }

    @Test("Sin llegar a la meta no se celebra ni se desbloquea nada")
    func belowTheGoalNothingHappens() throws {
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 9995)])
        let (_, settings, achievements) = Self.store(storage)

        #expect(settings.goalRingDidUpdate() == false, "9 995 m no cumplen una meta de 10 km")
        #expect(achievements.unlock(forKey: AchievementsStore.weeklyGoalKey) == nil)
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("La semana siguiente vuelve a celebrar, y el logro NO se re-desbloquea")
    func theNextWeekCelebratesAgain() throws {
        let storage = StorageStub(sessions: try [
            Self.record("2026-07-06T10:00:00Z", 12_000),
            Self.record("2026-07-13T10:00:00Z", 12_000),
        ])
        let (_, thisWeek, achievements) = Self.store(storage)
        #expect(thisWeek.goalRingDidUpdate() == true)

        // Lunes siguiente: otro store, como si la app se hubiera relanzado. La semana celebrada
        // viaja en `settings.json`, no en memoria.
        let history = HistoryStore(storage: storage)
        let nextWeek = SettingsStore(
            storage: storage,
            history: history,
            achievements: achievements,
            feedback: FeedbackSpy(),
            clock: ClockStub(now: Self.instant("2026-07-13T12:00:00Z"))
        )

        #expect(nextWeek.goalRingDidUpdate() == true, "semana nueva, celebración nueva")
        #expect(storage.settingsSaved.last?.lastGoalCelebratedWeek == "2026-W29")
        #expect(storage.achievementsSaved.count == 1, "pero `weekly_goal` es de por vida: no se re-dispara")
    }

    @Test("Bajar la meta puede completar la semana: 12 km caminados y vuelta a los 10 por defecto")
    func loweringTheGoalCompletesTheWeek() throws {
        // La celebración no depende solo del historial: lo único que esta pantalla deja hacer es
        // cambiar la meta, y hasta ahora ningún test la ejercitaba por esa vía.
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        let (_, settings, achievements) = Self.store(storage)
        settings.saveGoal(fromText: "15")

        #expect(settings.goalRingDidUpdate() == false, "12 de 15 km todavía no")

        settings.clearGoal()

        #expect(settings.weeklyProgress?.isComplete == true, "12 de 10 km sí")
        #expect(settings.goalRingDidUpdate() == true, "y se celebra ahora, no la semana que viene")
        #expect(achievements.unlock(forKey: AchievementsStore.weeklyGoalKey)?.isUnlocked == true)
    }

    @Test("Subir la meta por encima de lo caminado no 'descelebra' la semana")
    func raisingTheGoalDoesNotUncelebrate() throws {
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        let (_, settings, _) = Self.store(storage)
        #expect(settings.goalRingDidUpdate() == true)

        settings.saveGoal(fromText: "20")

        #expect(settings.weeklyProgress?.isComplete == false)
        #expect(settings.lastGoalCelebratedWeek == "2026-W28", "lo celebrado, celebrado está")
        #expect(settings.goalRingDidUpdate() == false)
    }

    // MARK: - El disco falla durante la celebración

    @Test("Si la semana celebrada no se puede escribir, SE CELEBRA igual y no se repite en esta ejecución")
    func celebrationSurvivesADiskFailure() throws {
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        storage.failSaveSettings(with: .failed(operation: "write"))
        let (_, settings, _) = Self.store(storage)

        #expect(settings.goalRingDidUpdate() == true, "celebrar dos veces molesta; no celebrar nunca rompe la promesa")
        #expect(storage.settings?.lastGoalCelebratedWeek == nil, "no quedó escrito")
        #expect(settings.lastGoalCelebratedWeek == "2026-W28", "pero sí en memoria")
        #expect(settings.goalRingDidUpdate() == false, "así que dentro de esta ejecución no se repite")
    }

    @Test("Si el fichero de logros no se puede escribir, la celebración NO se cancela")
    func anUnwritableAchievementsFileDoesNotCancelTheCelebration() throws {
        // Son dos cosas distintas (AD-25): el anillo está al 100 % lo escriba quien lo escriba.
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        storage.failLoadAchievements(with: .unsupportedSchemaVersion(99))
        let (_, settings, achievements) = Self.store(storage)

        #expect(settings.goalRingDidUpdate() == true)
        #expect(achievements.unlock(forKey: AchievementsStore.weeklyGoalKey) == nil, "el logro no se pudo escribir")
        #expect(storage.achievementsSaved.isEmpty)
        #expect(settings.lastGoalCelebratedWeek == "2026-W28", "y la semana sí quedó celebrada")
    }

    // MARK: - La semana cambia debajo

    @Test("Volver de segundo plano un lunes: la semana nueva se mira, y se celebra si toca")
    func theWeekIsRecheckedWhenTheAppComesBack() throws {
        // `clock.now` no es estado observable: sin `weekMayHaveChanged()` el anillo seguiría
        // pintando la semana pasada y la celebración de la nueva no se dispararía nunca.
        let clock = ClockStub(now: Self.instant("2026-07-12T20:00:00Z"))
        let storage = StorageStub(sessions: try [
            Self.record("2026-07-06T10:00:00Z", 12_000),
            Self.record("2026-07-13T10:00:00Z", 12_000),
        ])
        let history = HistoryStore(storage: storage)
        let settings = SettingsStore(
            storage: storage,
            history: history,
            achievements: AchievementsStore(storage: storage),
            feedback: FeedbackSpy(),
            clock: clock
        )
        #expect(settings.goalRingDidUpdate() == true)
        let tokenBefore = settings.goalRefreshToken

        clock.set(Self.instant("2026-07-13T12:00:00Z"))
        settings.weekMayHaveChanged()

        #expect(settings.goalRefreshToken != tokenBefore, "el testigo que obliga a repintar el anillo se ha movido")
        #expect(settings.lastGoalCelebratedWeek == "2026-W29", "la semana nueva se celebró al volver")
        #expect(settings.weeklyProgress?.completedKm == 12)
    }

    // MARK: - La señal visible de la celebración (3.4)

    /// El otro canal del **mismo** suceso. La háptica de la 4.1 no necesita pantalla; el aviso
    /// sí, y por eso la señal es **estado observable** y no el `Bool` de retorno, que los dos
    /// llamadores descartan (decisión D1 de la 3.4).
    @Test("Cumplir la meta enciende el aviso visible, y descartarlo lo apaga")
    func meetingTheGoalRaisesTheVisibleNotice() throws {
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        let (_, settings, _) = Self.store(storage)
        #expect(!settings.showsGoalCelebration, "sin mirar el anillo todavía no hay nada que celebrar")

        #expect(settings.goalRingDidUpdate() == true)
        #expect(settings.showsGoalCelebration, "la meta cumplida se celebra a la vista, no solo vibrando")

        settings.dismissGoalCelebration()
        #expect(!settings.showsGoalCelebration)
        #expect(settings.lastGoalCelebratedWeek == "2026-W28", "descartar el aviso NO descelebra la semana")
        #expect(settings.goalRingDidUpdate() == false, "y volver a Inicio no lo vuelve a encender")
        #expect(!settings.showsGoalCelebration)
    }

    @Test("Sin llegar a la meta no hay aviso que enseñar")
    func belowTheGoalRaisesNoNotice() throws {
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 9995)])
        let (_, settings, _) = Self.store(storage)

        #expect(settings.goalRingDidUpdate() == false)
        #expect(!settings.showsGoalCelebration)
    }

    /// La fila "meta fuera de Inicio" de la matriz: el aviso **no se pierde** por no estar
    /// mirando el anillo. Con la señal colgada del valor de retorno esto era imposible —
    /// `weekMayHaveChanged()` lo descarta— y es justo el caso más probable, porque se llama al
    /// volver a primer plano.
    @Test("La meta que se cumple con la app en otra pestaña deja su aviso esperando")
    func theNoticeSurvivesAWeekChangeFromAnotherTab() throws {
        let clock = ClockStub(now: Self.instant("2026-07-12T20:00:00Z"))
        let storage = StorageStub(sessions: try [
            Self.record("2026-07-06T10:00:00Z", 12_000),
            Self.record("2026-07-13T10:00:00Z", 12_000),
        ])
        let settings = SettingsStore(
            storage: storage,
            history: HistoryStore(storage: storage),
            achievements: AchievementsStore(storage: storage),
            feedback: FeedbackSpy(),
            clock: clock
        )
        #expect(settings.goalRingDidUpdate() == true)
        settings.dismissGoalCelebration()

        // Lunes: la semana cambia con la app en segundo plano, sin que nadie pinte el anillo.
        clock.set(Self.instant("2026-07-13T12:00:00Z"))
        settings.weekMayHaveChanged()

        #expect(settings.showsGoalCelebration, "el aviso de la semana nueva espera a que haya dónde mostrarlo")
    }

    @Test("Descartar un aviso que no está encendido no hace nada")
    func dismissingNothingIsHarmless() {
        let (_, settings, _) = Self.store()

        settings.dismissGoalCelebration()

        #expect(!settings.showsGoalCelebration)
    }

    // MARK: - El canal de feedback (4.1)

    /// El cuarto de los cuatro disparos de la 4.1. Va **donde se decide que se celebra** y no
    /// donde se pinta: la sección 10 del gate prohíbe `CoreHaptics` en `WalkTracker/UI/`, y los
    /// dos entrantes de `goalRingDidUpdate()` —`HomeView` al pintar el anillo y
    /// `weekMayHaveChanged()` al volver de background— comparten este único punto.
    @Test("Cumplir la meta por primera vez esta semana dispara un .goal, sin sonido")
    func meetingTheGoalFiresOnce() throws {
        let feedback = FeedbackSpy()
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        let (_, settings, _) = Self.store(storage, feedback: feedback)

        #expect(settings.goalRingDidUpdate() == true)

        #expect(feedback.fired == [.init(event: .goal, soundEnabled: false)])
    }

    /// Volver a Inicio, repintar el anillo o relanzar **no** vuelven a vibrar: la semana celebrada
    /// vive en `settings.json`, y el disparo cuelga del mismo `return true` que la celebración.
    @Test("Repintar el anillo con la meta ya celebrada no vuelve a vibrar")
    func repaintingTheRingDoesNotFireAgain() throws {
        let feedback = FeedbackSpy()
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        let (_, settings, _) = Self.store(storage, feedback: feedback)
        #expect(settings.goalRingDidUpdate() == true)

        #expect(settings.goalRingDidUpdate() == false)
        #expect(settings.goalRingDidUpdate() == false)

        #expect(feedback.count(of: .goal) == 1, "una vibración por semana, no una por repintado")
    }

    @Test("La meta sin cumplir no vibra")
    func anIncompleteGoalDoesNotFire() throws {
        let feedback = FeedbackSpy()
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 3_000)])
        let (_, settings, _) = Self.store(storage, feedback: feedback)

        #expect(settings.goalRingDidUpdate() == false)

        #expect(feedback.events.isEmpty)
    }

    /// Semana nueva, celebración nueva **y vibración nueva**: el disparo sigue a la señal, no al
    /// desbloqueo de `weekly_goal`, que es de por vida y no se re-dispara.
    @Test("La semana siguiente vuelve a vibrar, aunque weekly_goal ya esté conseguido")
    func aNewWeekFiresAgain() throws {
        let feedback = FeedbackSpy()
        let storage = StorageStub(sessions: try [
            Self.record("2026-07-06T10:00:00Z", 12_000),
            Self.record("2026-07-13T10:00:00Z", 12_000),
        ])
        let (_, thisWeek, achievements) = Self.store(storage, feedback: feedback)
        #expect(thisWeek.goalRingDidUpdate() == true)

        let nextWeek = SettingsStore(
            storage: storage,
            history: HistoryStore(storage: storage),
            achievements: achievements,
            feedback: feedback,
            clock: ClockStub(now: Self.instant("2026-07-13T12:00:00Z"))
        )
        #expect(nextWeek.goalRingDidUpdate() == true)

        #expect(feedback.count(of: .goal) == 2)
        #expect(storage.achievementsSaved.count == 1, "pero el logro de por vida se escribió una sola vez")
    }

    @Test("Relanzar la app en la misma semana NO vuelve a celebrar")
    func relaunchingInTheSameWeekDoesNotCelebrateAgain() throws {
        let storage = StorageStub(sessions: try [Self.record("2026-07-06T10:00:00Z", 12_000)])
        let (_, settings, achievements) = Self.store(storage)
        #expect(settings.goalRingDidUpdate() == true)

        let relaunched = SettingsStore(
            storage: storage,
            history: HistoryStore(storage: storage),
            achievements: achievements,
            feedback: FeedbackSpy(),
            clock: ClockStub(now: Self.instant("2026-07-09T08:00:00Z"))
        )

        #expect(relaunched.lastGoalCelebratedWeek == "2026-W28", "la semana celebrada se leyó del fichero")
        #expect(relaunched.goalRingDidUpdate() == false)
    }
}
