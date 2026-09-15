import Synchronization

/// El primer resultado de una carrera entre tareas no estructuradas. `resolve` gana solo la
/// primera vez; `value()` lo espera, aunque se llame después de resolverse.
///
/// Lo usa la reconciliación de `SessionStore` para que la consulta del podómetro compita con
/// su timeout sin un `withTaskGroup`, que esperaría a una consulta colgada.
///
/// **Un solo esperador.** `value()` admite una única llamada en espera: una segunda antes de
/// resolverse sustituye la continuación de la primera, que no vuelve nunca. Basta para la
/// carrera de `queryWithinTimeout`, que espera una vez; no es un futuro de uso general.
final class FirstResult<Value: Sendable>: Sendable {

    private enum State {
        case waiting(CheckedContinuation<Value, Never>?)
        case resolved(Value)
    }

    private let state = Mutex(State.waiting(nil))

    /// `true` si este resultado es el que gana.
    @discardableResult
    func resolve(_ value: Value) -> Bool {
        let waiter: CheckedContinuation<Value, Never>?? = state.withLock { state in
            guard case .waiting(let continuation) = state else { return .none }
            state = .resolved(value)
            return .some(continuation)
        }
        guard let waiter else { return false }
        waiter?.resume(returning: value)
        return true
    }

    func value() async -> Value {
        await withCheckedContinuation { continuation in
            let resolved: Value? = state.withLock { state in
                switch state {
                case .resolved(let value):
                    return value
                case .waiting:
                    state = .waiting(continuation)
                    return nil
                }
            }
            if let resolved { continuation.resume(returning: resolved) }
        }
    }
}
