import Domain
import Foundation
import Synchronization

/// `WeatherPort` de test: sin red. El test fija la respuesta y lee las coordenadas pedidas.
final class WeatherStub: WeatherPort {

    /// Qué responde `currentWeather(at:)`.
    enum Response: Sendable {
        case reading(WeatherReading)
        /// La lectura tras `seconds` de espera real.
        case delayed(WeatherReading, seconds: TimeInterval)
        case failure(CapabilityError)
        /// No vuelve hasta `resolvePendingRequests(with:)`, como una red que no contesta.
        case hang
    }

    /// La lectura de la matriz de la 2.1: WMO 61 (lluvia ligera), 18 °C.
    static let rainyReading = WeatherReading(tempC: 18, feelsLikeC: 17.5, wmoCode: 61, humidityPct: 82, uvIndex: 1.5, windKmh: 12.4)

    private struct State {
        var response: Response
        var requested: [Coordinates] = []
        var pending: [CheckedContinuation<Response, Never>] = []
    }

    private let state: Mutex<State>

    init(response: Response = .reading(WeatherStub.rainyReading)) {
        state = Mutex(State(response: response))
    }

    // MARK: - WeatherPort

    func currentWeather(at coordinates: Coordinates) async throws(CapabilityError) -> WeatherReading {
        let immediate: Response = state.withLock { state in
            state.requested.append(coordinates)
            return state.response
        }
        var response = immediate
        if case .hang = immediate {
            response = await withCheckedContinuation { continuation in
                state.withLock { $0.pending.append(continuation) }
            }
        }
        switch response {
        case .reading(let reading): return reading
        case .delayed(let reading, let seconds):
            try? await Task.sleep(for: .seconds(seconds))
            return reading
        case .failure(let error): throw error
        case .hang: throw .failed(operation: "hang")
        }
    }

    // MARK: - Control del test

    /// Las coordenadas de cada petición, en orden.
    var requested: [Coordinates] { state.withLock { $0.requested } }
    var hasPendingRequest: Bool { state.withLock { !$0.pending.isEmpty } }

    func setResponse(_ response: Response) {
        state.withLock { $0.response = response }
    }

    /// Resuelve las peticiones colgadas con `response`: una respuesta tardía.
    func resolvePendingRequests(with response: Response) {
        let pending = state.withLock { state in
            defer { state.pending = [] }
            return state.pending
        }
        pending.forEach { $0.resume(returning: response) }
    }

    /// Resuelve solo la petición colgada más antigua con `response`; las demás siguen en vilo.
    func resolveOldestPendingRequest(with response: Response) {
        let oldest = state.withLock { state in
            state.pending.isEmpty ? nil : state.pending.removeFirst()
        }
        oldest?.resume(returning: response)
    }

    /// Peticiones colgadas ahora mismo.
    var pendingRequestCount: Int { state.withLock { $0.pending.count } }
}
