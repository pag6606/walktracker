import Domain
import Foundation
import Synchronization

/// `MotionPort` de test: sin coprocesador. El test fija el permiso, decide qué responde
/// el diálogo y emite a mano las muestras acumuladas del stream.
///
/// A diferencia del adapter (`.bufferingNewest(1)`), el stream no descarta muestras:
/// así un test puede afirmar sobre cada una sin depender de cuándo corre el consumidor.
final class MotionStub: MotionPort {

    private struct State {
        var status: PermissionStatus
        /// Lo que responde el diálogo. `nil`: la petición queda en vilo hasta
        /// `resolvePermissionRequest(with:)`.
        var requestAnswer: PermissionStatus?
        var pendingRequest: CheckedContinuation<PermissionStatus, Never>?
        var requestCount = 0
        var updateStarts: [Date] = []
        var continuation: AsyncStream<PedometerSample>.Continuation?
        var cancelledStreams = 0
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - status: permiso antes de pedirlo.
    ///   - requestAnswer: estado que deja el diálogo; `nil` lo deja pendiente.
    init(status: PermissionStatus, requestAnswer: PermissionStatus? = .granted) {
        state = Mutex(State(status: status, requestAnswer: requestAnswer))
    }

    // MARK: - MotionPort

    var status: PermissionStatus { state.withLock { $0.status } }

    func requestPermission() async -> PermissionStatus {
        let answer: PermissionStatus? = state.withLock { state in
            state.requestCount += 1
            if let answer = state.requestAnswer { state.status = answer }
            return state.requestAnswer
        }
        if let answer { return answer }
        let resolved = await withCheckedContinuation { continuation in
            state.withLock { $0.pendingRequest = continuation }
        }
        return resolved
    }

    func updates(from start: Date) -> AsyncStream<PedometerSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: PedometerSample.self)
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination {
                self?.state.withLock { $0.cancelledStreams += 1 }
            }
        }
        state.withLock { state in
            state.updateStarts.append(start)
            state.continuation = continuation
        }
        return stream
    }

    func query(from start: Date, to end: Date) async throws(CapabilityError) -> PedometerSample? {
        nil
    }

    // MARK: - Control del test

    var requestCount: Int { state.withLock { $0.requestCount } }
    var hasPendingRequest: Bool { state.withLock { $0.pendingRequest != nil } }
    /// Los `start` con que se abrió cada stream de actualizaciones.
    var updateStarts: [Date] { state.withLock { $0.updateStarts } }
    var cancelledStreams: Int { state.withLock { $0.cancelledStreams } }

    /// Cambia el permiso "en Ajustes", fuera de la app.
    func setStatus(_ status: PermissionStatus) {
        state.withLock { $0.status = status }
    }

    /// Responde a la petición pendiente con `status`.
    func resolvePermissionRequest(with status: PermissionStatus) {
        let pending = state.withLock { state in
            state.status = status
            defer { state.pendingRequest = nil }
            return state.pendingRequest
        }
        pending?.resume(returning: status)
    }

    /// Emite una muestra **acumulada** desde el inicio del stream en curso.
    func emit(steps: Int) {
        let (continuation, start) = state.withLock { ($0.continuation, $0.updateStarts.last) }
        let from = start ?? Date(timeIntervalSince1970: 0)
        continuation?.yield(PedometerSample(steps: steps, distance: nil, start: from, end: from))
    }

    /// El sistema termina el stream sin que nadie lo cancele.
    func finishUpdates() {
        let continuation = state.withLock { $0.continuation }
        continuation?.finish()
    }
}
