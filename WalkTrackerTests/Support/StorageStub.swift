import Domain
import Foundation
import Synchronization

/// `StoragePort` de test: el snapshot y los ajustes viven en memoria. El test fija lo que hay
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

    init(snapshot: ActiveSessionSnapshot? = nil, settings: AppSettings? = nil) {
        state = Mutex(State(snapshot: snapshot, settings: settings))
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
                // pudo leer y sigue en su sitio.
                switch error {
                case .malformed, .unsupportedSchemaVersion:
                    state.setAsideCurrentSettings()
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

    /// Las lecturas de ajustes siguientes lanzan `error`.
    func failLoadSettings(with error: StorageError?) {
        state.withLock { $0.settingsLoadError = error }
    }

    func failSaveSettings(with error: StorageError?) {
        state.withLock { $0.settingsSaveError = error }
    }
}
