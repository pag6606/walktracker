import CoreMotion
import Domain
import Foundation
import OSLog
import Synchronization

/// `MotionPort` sobre `CMPedometer` (CAP-2, CAP-3) — AD-7, AD-10, AD-11, AD-12, AD-21.
///
/// Extraído de `feature/flutter-substrate:ios/Runner/AppDelegate.swift` (líneas 89-162 y
/// `PedometerStreamHandler`, 419-446). No se portan sus defectos: la distancia ya no se
/// trunca con `intValue`, y no hay un "start" que no arranca nada.
///
/// **Frontera de concurrencia.** CoreMotion llama a sus handlers en su propia cola serie.
/// `CMPedometerData` y sus `NSNumber` no son `Sendable`, así que la conversión a
/// `PedometerSample` ocurre **dentro del handler** (`sample(from:)`) y solo el DTO sale
/// de él. El `CMPedometer` compartido vive tras un `Mutex`: es lo que hace `Sendable` a
/// este tipo sin `@unchecked`.
final class MotionAdapter: MotionPort {

    private struct State: ~Copyable {
        let pedometer = CMPedometer()
        /// Stream en curso. Uno solo: `startUpdates` reemplaza el handler anterior.
        var continuation: AsyncStream<PedometerSample>.Continuation?
        /// Distingue el stream en curso de uno ya reemplazado cuyo `onTermination`
        /// llega tarde y no debe detener al nuevo.
        var generation = 0
    }

    private let state = Mutex(State())
    private let log = Logger(subsystem: "com.walktracker.app", category: "Motion")

    init() {}

    // MARK: - Permiso (AD-11)

    var status: PermissionStatus {
        guard CMPedometer.isStepCountingAvailable() else { return .unavailable }
        return Self.permission(from: CMPedometer.authorizationStatus())
    }

    func requestPermission() async -> PermissionStatus {
        guard status == .notDetermined else { return status }
        // CoreMotion no tiene API de petición: el diálogo lo dispara la primera consulta.
        let result = await withCheckedContinuation {
            (done: CheckedContinuation<Result<PedometerSample?, CapabilityError>, Never>) in
            state.withLock { state in
                let now = Date()
                state.pedometer.queryPedometerData(from: now, to: now) { @Sendable data, error in
                    done.resume(returning: Self.result(data: data, error: error))
                }
            }
        }
        let resolved = status
        if resolved == .notDetermined {
            // El sistema aún no ha publicado la decisión: manda el resultado de la consulta.
            return Self.permission(afterRequest: result)
        }
        return resolved
    }

    /// Estado que se deduce de la consulta que dispara el diálogo, cuando el sistema aún no
    /// lo publica. Solo un rechazo de permiso es `.denied`: un fallo transitorio no debe
    /// llevar a la pantalla bloqueante de Motion denegado (AD-11).
    static func permission(afterRequest result: Result<PedometerSample?, CapabilityError>) -> PermissionStatus {
        switch result {
        case .success: .granted
        case .failure(.notAuthorized): .denied
        case .failure(.unavailable): .unavailable
        case .failure(.failed): .notDetermined
        }
    }

    // MARK: - Actualizaciones continuas (AD-21)

    func updates(from start: Date) -> AsyncStream<PedometerSample> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: PedometerSample.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        guard CMPedometer.isStepCountingAvailable() else {
            continuation.finish()
            return stream
        }

        // El stream anterior se termina FUERA del lock: su `onTermination` vuelve a tomarlo
        // y el `Mutex` no es reentrante. Al haber avanzado la generación, no detiene nada.
        let (generation, previous) = state.withLock { state in
            let previous = state.continuation
            state.generation += 1
            state.continuation = continuation
            return (state.generation, previous)
        }
        previous?.finish()

        // `onTermination` puede dispararse desde el propio handler de CoreMotion —y este,
        // en teoría, de forma síncrona dentro de `startUpdates`, con el lock tomado—. Por
        // eso la parada se difiere a otra cola en vez de tomar el lock aquí mismo.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.global(qos: .utility).async {
                self.stopUpdates(generation: generation)
            }
        }

        let log = self.log
        state.withLock { state in
            // Si quien consume ya canceló, `stopUpdates` limpió la continuación: no se arranca.
            guard state.generation == generation, state.continuation != nil else { return }
            state.pedometer.startUpdates(from: start) { @Sendable data, error in
                // Cola serie de CoreMotion. Nada de CoreMotion sale de este bloque.
                switch Self.result(data: data, error: error) {
                case .success(let sample?):
                    continuation.yield(sample)
                case .success(nil):
                    break
                case .failure(let failure):
                    // El sistema detuvo el stream. `status` solo lo explica si fue el permiso.
                    log.error("Actualizaciones del podómetro terminadas: \(String(describing: failure), privacy: .public)")
                    continuation.finish()
                }
            }
        }
        return stream
    }

    private func stopUpdates(generation: Int) {
        state.withLock { state in
            guard state.generation == generation else { return }
            state.pedometer.stopUpdates()
            state.continuation = nil
        }
    }

    // MARK: - Consulta por rango (AD-8)

    func query(from start: Date, to end: Date) async throws(CapabilityError) -> PedometerSample? {
        guard CMPedometer.isStepCountingAvailable() else { throw .unavailable }
        let result = await withCheckedContinuation {
            (done: CheckedContinuation<Result<PedometerSample?, CapabilityError>, Never>) in
            state.withLock { state in
                state.pedometer.queryPedometerData(from: start, to: end) { @Sendable data, error in
                    done.resume(returning: Self.result(data: data, error: error))
                }
            }
        }
        return try result.get()
    }

    // MARK: - Traducción en el borde (expuesta para test)

    /// Convierte la muestra de CoreMotion en el DTO del puerto. Se llama **dentro del
    /// handler**. La distancia se conserva en metros con decimales y su ausencia sigue
    /// siendo `nil`, nunca `0`.
    static func sample(from data: CMPedometerData) -> PedometerSample {
        PedometerSample(
            steps: data.numberOfSteps.intValue,
            distance: data.distance?.doubleValue,
            start: data.startDate,
            end: data.endDate
        )
    }

    /// Traduce lo que CoreMotion entrega a un handler. Un error gana a los datos; sin
    /// error y sin datos, el resultado es `nil`.
    static func result(data: CMPedometerData?, error: (any Error)?) -> Result<PedometerSample?, CapabilityError> {
        if let error { return .failure(capabilityError(from: error)) }
        guard let data else { return .success(nil) }
        return .success(sample(from: data))
    }

    /// Traduce un error de CoreMotion a `CapabilityError`. Nunca deja salir el crudo.
    static func capabilityError(from error: any Error) -> CapabilityError {
        let nsError = error as NSError
        guard nsError.domain == CMErrorDomain else { return .failed(operation: "pedometer") }
        switch UInt32(truncatingIfNeeded: nsError.code) {
        case CMErrorMotionActivityNotAuthorized.rawValue:
            return .notAuthorized
        case CMErrorMotionActivityNotAvailable.rawValue, CMErrorMotionActivityNotEntitled.rawValue:
            return .unavailable
        default:
            return .failed(operation: "pedometer")
        }
    }

    static func permission(from status: CMAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
