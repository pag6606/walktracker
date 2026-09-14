import Domain
import Foundation
import Synchronization

/// `MotionPort` de test: sin coprocesador. El test fija el permiso, decide qué responde
/// el diálogo y emite a mano las muestras acumuladas del stream.
///
/// A diferencia del adapter (`.bufferingNewest(1)`), el stream no descarta muestras:
/// así un test puede afirmar sobre cada una sin depender de cuándo corre el consumidor.
///
/// La consulta por rango responde lo que fije `queryResponse` y registra cada rango
/// consultado. Con `.hang` queda en vilo hasta `resolvePendingQueries(with:)`, como una
/// consulta de CoreMotion que no vuelve.
final class MotionStub: MotionPort {

    /// Qué responde `query(from:to:)`.
    enum QueryResponse: Sendable {
        /// Una muestra con esos pasos acumulados en el rango consultado.
        case sample(steps: Int, distance: Double?)
        /// El sistema no tiene datos para el rango.
        case none
        case failure(CapabilityError)
        /// No vuelve hasta `resolvePendingQueries(with:)`.
        case hang
    }

    /// Un rango consultado.
    struct QueriedRange: Equatable, Sendable {
        let start: Date
        let end: Date
    }

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
        var queryResponse: QueryResponse = .none
        var queriedRanges: [QueriedRange] = []
        var pendingQueries: [(range: QueriedRange, continuation: CheckedContinuation<QueryResponse, Never>)] = []
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
        let range = QueriedRange(start: start, end: end)
        let immediate: QueryResponse = state.withLock { state in
            state.queriedRanges.append(range)
            return state.queryResponse
        }
        var response = immediate
        if case .hang = immediate {
            response = await withCheckedContinuation { continuation in
                state.withLock { $0.pendingQueries.append((range, continuation)) }
            }
        }
        switch response {
        case .sample(let steps, let distance):
            return PedometerSample(steps: steps, distance: distance, start: start, end: end)
        case .none, .hang:
            return nil
        case .failure(let error):
            throw error
        }
    }

    // MARK: - Control del test

    var requestCount: Int { state.withLock { $0.requestCount } }
    var hasPendingRequest: Bool { state.withLock { $0.pendingRequest != nil } }
    /// Los `start` con que se abrió cada stream de actualizaciones.
    var updateStarts: [Date] { state.withLock { $0.updateStarts } }
    var cancelledStreams: Int { state.withLock { $0.cancelledStreams } }
    /// Cada rango consultado, en orden.
    var queriedRanges: [QueriedRange] { state.withLock { $0.queriedRanges } }
    var hasPendingQuery: Bool { state.withLock { !$0.pendingQueries.isEmpty } }

    /// Fija la respuesta de las consultas siguientes.
    func setQueryResponse(_ response: QueryResponse) {
        state.withLock { $0.queryResponse = response }
    }

    /// Resuelve las consultas colgadas con `response` (`.hang` cuenta como `.none`).
    func resolvePendingQueries(with response: QueryResponse) {
        let pending = state.withLock { state in
            defer { state.pendingQueries = [] }
            return state.pendingQueries
        }
        pending.forEach { $0.continuation.resume(returning: response) }
    }

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

    /// Emite una muestra **acumulada** desde el inicio del stream en curso. `distance`, en
    /// metros, es la distancia acumulada del sistema; `nil` si no la da.
    func emit(steps: Int, distance: Double? = nil) {
        let (continuation, start) = state.withLock { ($0.continuation, $0.updateStarts.last) }
        let from = start ?? Date(timeIntervalSince1970: 0)
        continuation?.yield(PedometerSample(steps: steps, distance: distance, start: from, end: from))
    }

    /// El sistema termina el stream sin que nadie lo cancele.
    func finishUpdates() {
        let continuation = state.withLock { $0.continuation }
        continuation?.finish()
    }
}
