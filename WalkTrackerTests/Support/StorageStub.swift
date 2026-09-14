import Domain
import Foundation
import Synchronization

/// `StoragePort` de test: el snapshot vive en memoria. El test fija lo que hay guardado,
/// hace fallar cada operación a demanda y cuenta guardados, borrados y apartados.
final class StorageStub: StoragePort {

    private struct State {
        var snapshot: ActiveSessionSnapshot?
        /// Lo apartado por `setAsideActiveSession()` o por una lectura fallida.
        var setAside: ActiveSessionSnapshot?
        var saved: [ActiveSessionSnapshot] = []
        var clearCount = 0
        var setAsideCount = 0
        var loadCount = 0
        var loadError: StorageError?
        var saveError: StorageError?
        var clearError: StorageError?
    }

    private let state: Mutex<State>

    init(snapshot: ActiveSessionSnapshot? = nil) {
        state = Mutex(State(snapshot: snapshot))
    }

    // MARK: - StoragePort

    func loadActiveSession() throws(StorageError) -> ActiveSessionSnapshot? {
        let result: Result<ActiveSessionSnapshot?, StorageError> = state.withLock { state in
            state.loadCount += 1
            if let error = state.loadError {
                // Como el adapter: un ilegible se aparta antes de lanzar.
                if state.snapshot != nil { state.setAsideCount += 1 }
                state.setAside = state.snapshot ?? state.setAside
                state.snapshot = nil
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
        state.withLock { state in
            guard let snapshot = state.snapshot else { return }
            state.setAside = snapshot
            state.snapshot = nil
            state.setAsideCount += 1
        }
    }

    // MARK: - Control del test

    /// El snapshot guardado ahora mismo.
    var snapshot: ActiveSessionSnapshot? { state.withLock { $0.snapshot } }
    var setAside: ActiveSessionSnapshot? { state.withLock { $0.setAside } }
    /// Cada snapshot guardado, en orden.
    var saved: [ActiveSessionSnapshot] { state.withLock { $0.saved } }
    var clearCount: Int { state.withLock { $0.clearCount } }
    var setAsideCount: Int { state.withLock { $0.setAsideCount } }
    var loadCount: Int { state.withLock { $0.loadCount } }

    func setSnapshot(_ snapshot: ActiveSessionSnapshot?) {
        state.withLock { $0.snapshot = snapshot }
    }

    /// Las lecturas siguientes lanzan `error` (y apartan el snapshot, como el adapter).
    func failLoad(with error: StorageError?) {
        state.withLock { $0.loadError = error }
    }

    func failSave(with error: StorageError?) {
        state.withLock { $0.saveError = error }
    }

    func failClear(with error: StorageError?) {
        state.withLock { $0.clearError = error }
    }
}
