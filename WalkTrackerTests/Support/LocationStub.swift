import Domain
import Foundation
import Synchronization

/// `LocationPort` de test: sin CoreLocation. El test fija el permiso, lo que responde el
/// diálogo y lo que devuelve la lectura, y cuenta peticiones y lecturas.
final class LocationStub: LocationPort {

    /// Qué responde `approximateLocation()`.
    enum Response: Sendable {
        case coordinates(Coordinates)
        /// Las coordenadas tras `seconds` de espera real.
        case delayed(Coordinates, seconds: TimeInterval)
        case failure(CapabilityError)
        /// No vuelve hasta `resolvePendingReads(with:)`.
        case hang
    }

    private struct State {
        var status: PermissionStatus
        /// Lo que responde el diálogo. `nil`: la petición queda en vilo hasta
        /// `resolvePermissionRequest(with:)`, como un sistema que nunca llama al delegado.
        var requestAnswer: PermissionStatus?
        var pendingRequest: CheckedContinuation<PermissionStatus, Never>?
        var response: Response
        var requestCount = 0
        var readCount = 0
        var pendingReads: [CheckedContinuation<Response, Never>] = []
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - status: permiso antes de pedirlo.
    ///   - requestAnswer: estado que deja el diálogo; `nil` lo deja pendiente.
    ///   - response: lo que devuelve la lectura. Por defecto, Madrid ya redondeado (40.42, -3.70).
    init(
        status: PermissionStatus,
        requestAnswer: PermissionStatus? = .granted,
        response: Response = .coordinates(Coordinates(latitude: 40.42, longitude: -3.70))
    ) {
        state = Mutex(State(status: status, requestAnswer: requestAnswer, response: response))
    }

    // MARK: - LocationPort

    var status: PermissionStatus { state.withLock { $0.status } }

    func requestPermission() async -> PermissionStatus {
        let answer: PermissionStatus? = state.withLock { state in
            state.requestCount += 1
            guard let answer = state.requestAnswer else { return nil }
            if state.status == .notDetermined { state.status = answer }
            return state.status
        }
        if let answer { return answer }
        return await withCheckedContinuation { continuation in
            state.withLock { $0.pendingRequest = continuation }
        }
    }

    func approximateLocation() async throws(CapabilityError) -> Coordinates {
        let immediate: Response = state.withLock { state in
            state.readCount += 1
            return state.response
        }
        var response = immediate
        if case .hang = immediate {
            response = await withCheckedContinuation { continuation in
                state.withLock { $0.pendingReads.append(continuation) }
            }
        }
        switch response {
        case .coordinates(let coordinates): return coordinates
        case .delayed(let coordinates, let seconds):
            try? await Task.sleep(for: .seconds(seconds))
            return coordinates
        case .failure(let error): throw error
        case .hang: throw .failed(operation: "hang")
        }
    }

    // MARK: - Control del test

    var requestCount: Int { state.withLock { $0.requestCount } }
    var readCount: Int { state.withLock { $0.readCount } }
    var hasPendingRead: Bool { state.withLock { !$0.pendingReads.isEmpty } }
    var hasPendingRequest: Bool { state.withLock { $0.pendingRequest != nil } }

    /// Responde a la petición de permiso pendiente con `status`.
    func resolvePermissionRequest(with status: PermissionStatus) {
        let pending = state.withLock { state in
            state.status = status
            defer { state.pendingRequest = nil }
            return state.pendingRequest
        }
        pending?.resume(returning: status)
    }

    /// Cambia el permiso "en Ajustes", fuera de la app.
    func setStatus(_ status: PermissionStatus) {
        state.withLock { $0.status = status }
    }

    func setResponse(_ response: Response) {
        state.withLock { $0.response = response }
    }

    /// Resuelve las lecturas colgadas con `response`.
    func resolvePendingReads(with response: Response) {
        let pending = state.withLock { state in
            defer { state.pendingReads = [] }
            return state.pendingReads
        }
        pending.forEach { $0.resume(returning: response) }
    }
}
