import Domain
import Foundation
import Synchronization

@testable import WalkTracker

/// `StoragePort` de test: los cuatro ficheros viven en memoria. El test fija lo que hay
/// guardado, hace fallar cada operación a demanda y cuenta guardados, borrados y apartados.
final class StorageStub: StoragePort {

    private struct State {
        var snapshot: ActiveSessionSnapshot?
        /// Lo apartado por `setAsideActiveSession()` o por una lectura ilegible, en orden. Como
        /// en el adapter, un apartado nunca sustituye a otro.
        var setAside: [ActiveSessionSnapshot] = []
        var saved: [ActiveSessionSnapshot] = []
        var clearCount = 0
        var loadCount = 0
        var loadError: StorageError?
        var saveError: StorageError?
        var clearError: StorageError?

        /// Ajustes (2.2). `nil` es "todavía no hay `settings.json`".
        var settings: AppSettings?
        var settingsSetAside: [AppSettings] = []
        var settingsSaved: [AppSettings] = []
        var settingsLoadCount = 0
        var settingsLoadError: StorageError?
        var settingsSaveError: StorageError?

        /// Historial de caminatas cerradas (5.1). `nil` es "todavía no hay `sessions.json`".
        var sessions: [SessionRecord]?
        var sessionsSetAside: [[SessionRecord]] = []
        var sessionsSaved: [[SessionRecord]] = []
        var sessionsLoadCount = 0
        var sessionsLoadError: StorageError?
        var sessionsSaveError: StorageError?

        /// Estado de los logros del sandbox (5.1). `nil` es "todavía no hay `achievements.json`".
        var achievements: [AchievementUnlock]?
        var achievementsSetAside: [[AchievementUnlock]] = []
        var achievementsSaved: [[AchievementUnlock]] = []
        var achievementsLoadCount = 0
        var achievementsLoadError: StorageError?
        var achievementsSaveError: StorageError?

        /// Aparta el historial actual, si lo hay, detrás de los ya apartados.
        mutating func setAsideCurrentSessions() {
            guard let sessions else { return }
            sessionsSetAside.append(sessions)
            self.sessions = nil
        }

        /// Aparta el estado de logros actual, si lo hay, detrás de los ya apartados.
        mutating func setAsideCurrentAchievements() {
            guard let achievements else { return }
            achievementsSetAside.append(achievements)
            self.achievements = nil
        }

        /// Aparta los ajustes actuales, si los hay, detrás de los ya apartados.
        mutating func setAsideCurrentSettings() {
            guard let settings else { return }
            settingsSetAside.append(settings)
            self.settings = nil
        }

        /// Aparta el snapshot actual, si lo hay, detrás de los ya apartados.
        mutating func setAsideCurrent() {
            guard let snapshot else { return }
            setAside.append(snapshot)
            self.snapshot = nil
        }
    }

    private let state: Mutex<State>

    init(
        snapshot: ActiveSessionSnapshot? = nil,
        settings: AppSettings? = nil,
        sessions: [SessionRecord]? = nil,
        achievements: [AchievementUnlock]? = nil
    ) {
        state = Mutex(State(snapshot: snapshot, settings: settings, sessions: sessions, achievements: achievements))
    }

    // MARK: - StoragePort

    func loadActiveSession() throws(StorageError) -> ActiveSessionSnapshot? {
        let result: Result<ActiveSessionSnapshot?, StorageError> = state.withLock { state in
            state.loadCount += 1
            if let error = state.loadError {
                // Como el adapter: un ilegible (`malformed`, `unsupportedSchemaVersion`) se
                // aparta antes de lanzar; con `failed` no se pudo leer y sigue en su sitio.
                switch error {
                case .malformed, .unsupportedSchemaVersion:
                    state.setAsideCurrent()
                case .failed:
                    break
                }
                return .failure(error)
            }
            return .success(state.snapshot)
        }
        return try result.get()
    }

    func saveActiveSession(_ snapshot: ActiveSessionSnapshot) throws(StorageError) {
        let error: StorageError? = state.withLock { state in
            if let error = state.saveError { return error }
            state.snapshot = snapshot
            state.saved.append(snapshot)
            return nil
        }
        if let error { throw error }
    }

    func clearActiveSession() throws(StorageError) {
        let error: StorageError? = state.withLock { state in
            if let error = state.clearError { return error }
            state.snapshot = nil
            state.clearCount += 1
            return nil
        }
        if let error { throw error }
    }

    func setAsideActiveSession() throws(StorageError) {
        state.withLock { $0.setAsideCurrent() }
    }

    func loadSettings() throws(StorageError) -> AppSettings? {
        let result: Result<AppSettings?, StorageError> = state.withLock { state in
            state.settingsLoadCount += 1
            if let error = state.settingsLoadError {
                // Como el adapter: un ilegible se aparta antes de lanzar; con `failed` no se
                // pudo leer y sigue en su sitio. Y **el de un esquema del futuro tampoco se
                // aparta** (B-1): no es corrupto, es de una versión que aún no se conoce, y
                // apartarlo perdería la ventana y la zancada en cuanto Paul volviera a ella.
                switch error {
                case .unsupportedSchemaVersion(let version) where version > SettingsFileAdapter.supportedSchemaVersion:
                    break
                case .malformed, .unsupportedSchemaVersion:
                    state.setAsideCurrentSettings()
                    // Apartar es renombrar: lo que queda en disco es "no hay fichero", así que
                    // la lectura siguiente ya no falla. Sin esto el doble diría algo que el
                    // adapter no dice —un ilegible que sigue ilegible para siempre— y el store
                    // parecería bloqueado cuando ya no hay nada que proteger.
                    state.settingsLoadError = nil
                case .failed:
                    break
                }
                return .failure(error)
            }
            return .success(state.settings)
        }
        return try result.get()
    }

    func saveSettings(_ settings: AppSettings) throws(StorageError) {
        let error: StorageError? = state.withLock { state in
            if let error = state.settingsSaveError { return error }
            state.settings = settings
            state.settingsSaved.append(settings)
            return nil
        }
        if let error { throw error }
    }

    func loadSessions() throws(StorageError) -> [SessionRecord]? {
        let result: Result<[SessionRecord]?, StorageError> = state.withLock { state in
            state.sessionsLoadCount += 1
            if let error = state.sessionsLoadError {
                // Como el adapter: un ilegible se aparta antes de lanzar y deja de fallar —lo
                // apartado ya no está en disco—; un esquema del **futuro** NO se aparta y sigue
                // fallando para siempre, que es justo lo que protege el historial; y con `failed`
                // el fichero sigue en su sitio y el fallo puede ser transitorio.
                switch error {
                case .unsupportedSchemaVersion(let version) where version > SessionHistoryFileAdapter.supportedSchemaVersion:
                    break
                case .malformed, .unsupportedSchemaVersion:
                    state.setAsideCurrentSessions()
                    state.sessionsLoadError = nil
                case .failed:
                    break
                }
                return .failure(error)
            }
            return .success(state.sessions)
        }
        return try result.get()
    }

    func saveSessions(_ sessions: [SessionRecord]) throws(StorageError) {
        let error: StorageError? = state.withLock { state in
            if let error = state.sessionsSaveError { return error }
            state.sessions = sessions
            state.sessionsSaved.append(sessions)
            return nil
        }
        if let error { throw error }
    }

    func loadAchievements() throws(StorageError) -> [AchievementUnlock]? {
        let result: Result<[AchievementUnlock]?, StorageError> = state.withLock { state in
            state.achievementsLoadCount += 1
            if let error = state.achievementsLoadError {
                switch error {
                case .unsupportedSchemaVersion(let version) where version > AchievementsFileAdapter.supportedSchemaVersion:
                    break
                case .malformed, .unsupportedSchemaVersion:
                    state.setAsideCurrentAchievements()
                    state.achievementsLoadError = nil
                case .failed:
                    break
                }
                return .failure(error)
            }
            return .success(state.achievements)
        }
        return try result.get()
    }

    func saveAchievements(_ achievements: [AchievementUnlock]) throws(StorageError) {
        let error: StorageError? = state.withLock { state in
            if let error = state.achievementsSaveError { return error }
            state.achievements = achievements
            state.achievementsSaved.append(achievements)
            return nil
        }
        if let error { throw error }
    }

    // MARK: - Control del test

    /// El snapshot guardado ahora mismo.
    var snapshot: ActiveSessionSnapshot? { state.withLock { $0.snapshot } }
    /// Cada snapshot apartado, en orden.
    var setAside: [ActiveSessionSnapshot] { state.withLock { $0.setAside } }
    /// Cada snapshot guardado, en orden.
    var saved: [ActiveSessionSnapshot] { state.withLock { $0.saved } }
    var clearCount: Int { state.withLock { $0.clearCount } }
    var loadCount: Int { state.withLock { $0.loadCount } }

    func setSnapshot(_ snapshot: ActiveSessionSnapshot?) {
        state.withLock { $0.snapshot = snapshot }
    }

    /// Las lecturas siguientes lanzan `error`. Como el adapter, `malformed` y
    /// `unsupportedSchemaVersion` apartan el snapshot; `failed` lo deja en su sitio.
    func failLoad(with error: StorageError?) {
        state.withLock { $0.loadError = error }
    }

    func failSave(with error: StorageError?) {
        state.withLock { $0.saveError = error }
    }

    func failClear(with error: StorageError?) {
        state.withLock { $0.clearError = error }
    }

    // MARK: - Ajustes (2.2)

    /// Los ajustes guardados ahora mismo.
    var settings: AppSettings? { state.withLock { $0.settings } }
    /// Cada ajuste guardado, en orden.
    var settingsSaved: [AppSettings] { state.withLock { $0.settingsSaved } }
    /// Cada ajuste apartado, en orden.
    var settingsSetAside: [AppSettings] { state.withLock { $0.settingsSetAside } }
    var settingsLoadCount: Int { state.withLock { $0.settingsLoadCount } }

    func setSettings(_ settings: AppSettings?) {
        state.withLock { $0.settings = settings }
    }

    /// Las lecturas de ajustes siguientes lanzan `error`. Con `nil` vuelven a funcionar, que es
    /// como se expresa un fallo **transitorio**: falla al arrancar y se recupera al reintentar.
    ///
    /// `malformed` y una versión **anterior** desconocida apartan los ajustes antes de lanzar;
    /// `failed` y un esquema del **futuro** los dejan en su sitio, como el adapter.
    func failLoadSettings(with error: StorageError?) {
        state.withLock { $0.settingsLoadError = error }
    }

    func failSaveSettings(with error: StorageError?) {
        state.withLock { $0.settingsSaveError = error }
    }

    // MARK: - Historial (5.1)

    /// El historial guardado ahora mismo.
    var sessions: [SessionRecord]? { state.withLock { $0.sessions } }
    /// Cada historial guardado, en orden: el test comprueba **cuántas** escrituras hubo.
    var sessionsSaved: [[SessionRecord]] { state.withLock { $0.sessionsSaved } }
    /// Cada historial apartado, en orden.
    var sessionsSetAside: [[SessionRecord]] { state.withLock { $0.sessionsSetAside } }
    var sessionsLoadCount: Int { state.withLock { $0.sessionsLoadCount } }

    func setSessions(_ sessions: [SessionRecord]?) {
        state.withLock { $0.sessions = sessions }
    }

    /// Las lecturas del historial siguientes lanzan `error`. Con `nil` vuelven a funcionar, que
    /// es como se expresa un fallo **transitorio**. `malformed` aparta el historial antes de
    /// lanzar; `failed` y un esquema del **futuro** lo dejan en su sitio, como el adapter.
    func failLoadSessions(with error: StorageError?) {
        state.withLock { $0.sessionsLoadError = error }
    }

    func failSaveSessions(with error: StorageError?) {
        state.withLock { $0.sessionsSaveError = error }
    }

    // MARK: - Logros del sandbox (5.1)

    /// El estado de logros guardado ahora mismo.
    var achievements: [AchievementUnlock]? { state.withLock { $0.achievements } }
    var achievementsSaved: [[AchievementUnlock]] { state.withLock { $0.achievementsSaved } }
    var achievementsSetAside: [[AchievementUnlock]] { state.withLock { $0.achievementsSetAside } }
    var achievementsLoadCount: Int { state.withLock { $0.achievementsLoadCount } }

    func setAchievements(_ achievements: [AchievementUnlock]?) {
        state.withLock { $0.achievements = achievements }
    }

    func failLoadAchievements(with error: StorageError?) {
        state.withLock { $0.achievementsLoadError = error }
    }

    func failSaveAchievements(with error: StorageError?) {
        state.withLock { $0.achievementsSaveError = error }
    }
}
