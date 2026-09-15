import CoreLocation
import Domain
import Foundation
import OSLog
import Synchronization

/// `LocationPort` sobre `CLLocationManager` (CAP-5) — AD-10, AD-11, AR-12.
///
/// **Aproximada y una sola vez.** `desiredAccuracy = kCLLocationAccuracyReduced` y
/// `requestLocation()`: nunca actualizaciones continuas ni precisión fina. Una ubicación del
/// sistema de hace ≤ 5 min vale sin pedir otra (`maximumAge` de la v3, `climate.js:50-76`).
///
/// **Privacidad.** Las coordenadas se redondean a 2 decimales **aquí**, antes de salir del
/// adapter (`rounded(latitude:longitude:)`): nada después ve una coordenada más precisa.
///
/// **Tope.** La lectura se abandona a los 3 s (`timeoutS`) y cuenta como fallo.
///
/// **Frontera de concurrencia.** `CLLocationManager` entrega a su delegado en el hilo donde
/// se creó: vive en `Core`, aislado al actor principal. De CoreLocation solo sale el DTO
/// `Coordinates`. El estado del permiso se copia a un `Mutex` en cada cambio, para que
/// `status` se lea desde cualquier hilo sin tocar el gestor.
final class LocationAdapter: LocationPort {

    /// Tope de la lectura (AR-12, v3 AD-14: 3 s).
    static let timeoutS: TimeInterval = 3
    /// Antigüedad máxima de una ubicación del sistema que se acepta sin pedir otra (5 min).
    static let maximumAgeS: TimeInterval = 5 * 60

    private let core: Core
    private let cachedStatus: StatusCache

    @MainActor
    init() {
        let cachedStatus = StatusCache()
        self.cachedStatus = cachedStatus
        core = Core(onStatus: { status in cachedStatus.set(status) })
    }

    // MARK: - Permiso (AD-11)

    var status: PermissionStatus { cachedStatus.value }

    func requestPermission() async -> PermissionStatus {
        await core.requestPermission()
    }

    // MARK: - Lectura aproximada

    func approximateLocation() async throws(CapabilityError) -> Coordinates {
        let result = await core.readLocation(timeoutS: Self.timeoutS, maximumAgeS: Self.maximumAgeS)
        return try result.get()
    }

    // MARK: - Traducción en el borde (expuesta para test)

    /// Redondea a 2 decimales (≈ 1 km) con la mitad lejos de cero; `-0` sale como `0`.
    static func rounded(latitude: Double, longitude: Double) -> Coordinates {
        Coordinates(latitude: roundedToHundredths(latitude), longitude: roundedToHundredths(longitude))
    }

    private static func roundedToHundredths(_ value: Double) -> Double {
        (value * 100).rounded(.toNearestOrAwayFromZero) / 100 + 0
    }

    /// Una ubicación del sistema tomada en `timestamp` sigue valiendo en `now`.
    static func isFresh(_ timestamp: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age <= maximumAgeS
    }

    static func permission(from status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    /// Traduce un error de CoreLocation a `CapabilityError`. Nunca deja salir el crudo.
    static func capabilityError(from error: any Error) -> CapabilityError {
        let nsError = error as NSError
        guard nsError.domain == kCLErrorDomain else { return .failed(operation: "location") }
        switch CLError.Code(rawValue: nsError.code) {
        case .denied: return .notAuthorized
        default: return .failed(operation: "location")
        }
    }

    /// Última copia del estado del permiso, legible desde cualquier hilo.
    private final class StatusCache: Sendable {
        private let status = Mutex(PermissionStatus.notDetermined)
        var value: PermissionStatus { status.withLock { $0 } }
        func set(_ value: PermissionStatus) { status.withLock { $0 = value } }
    }

    // MARK: - Gestor en el actor principal

    @MainActor
    private final class Core: NSObject, CLLocationManagerDelegate {

        private let manager = CLLocationManager()
        private let onStatus: @Sendable (PermissionStatus) -> Void
        private let log = Logger(subsystem: "com.walktracker.app", category: "Location")
        private var permissionWaiters: [CheckedContinuation<PermissionStatus, Never>] = []
        /// La lectura en curso, con un identificador para que el timeout no resuelva otra.
        private var pendingRead: (id: UUID, continuation: CheckedContinuation<Result<Coordinates, CapabilityError>, Never>)?

        init(onStatus: @escaping @Sendable (PermissionStatus) -> Void) {
            self.onStatus = onStatus
            super.init()
            manager.desiredAccuracy = kCLLocationAccuracyReduced
            manager.delegate = self
            onStatus(LocationAdapter.permission(from: manager.authorizationStatus))
        }

        var status: PermissionStatus { LocationAdapter.permission(from: manager.authorizationStatus) }

        func requestPermission() async -> PermissionStatus {
            guard status == .notDetermined else { return status }
            return await withCheckedContinuation { continuation in
                permissionWaiters.append(continuation)
                if permissionWaiters.count == 1 {
                    manager.requestWhenInUseAuthorization()
                }
            }
        }

        func readLocation(timeoutS: TimeInterval, maximumAgeS: TimeInterval) async -> Result<Coordinates, CapabilityError> {
            switch status {
            case .granted: break
            case .notDetermined, .denied, .restricted: return .failure(.notAuthorized)
            case .unavailable: return .failure(.unavailable)
            }
            // Una precisión negativa marca una ubicación inválida: no se usa aunque sea reciente.
            if let cached = manager.location, cached.horizontalAccuracy >= 0,
               LocationAdapter.isFresh(cached.timestamp, now: Date()) {
                return .success(LocationAdapter.rounded(latitude: cached.coordinate.latitude, longitude: cached.coordinate.longitude))
            }
            let id = UUID()
            return await withCheckedContinuation { continuation in
                // Una lectura anterior aún abierta se da por fallida: solo hay un gestor.
                finishRead(with: .failure(.failed(operation: "locationSuperseded")))
                pendingRead = (id, continuation)
                manager.requestLocation()
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeoutS))
                    guard let self, self.pendingRead?.id == id else { return }
                    self.log.info("La lectura de ubicación agotó el tope de \(timeoutS, privacy: .public) s")
                    self.manager.stopUpdatingLocation()
                    self.finishRead(with: .failure(.failed(operation: "locationTimeout")))
                }
            }
        }

        private func finishRead(with result: Result<Coordinates, CapabilityError>) {
            guard let pending = pendingRead else { return }
            pendingRead = nil
            pending.continuation.resume(returning: result)
        }

        // MARK: CLLocationManagerDelegate

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = LocationAdapter.permission(from: manager.authorizationStatus)
            MainActor.assumeIsolated {
                onStatus(status)
                guard status != .notDetermined else { return }
                let waiters = permissionWaiters
                permissionWaiters = []
                waiters.forEach { $0.resume(returning: status) }
            }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            // Nada de CoreLocation sale de aquí: solo el DTO ya redondeado.
            guard let last = locations.last else { return }
            let coordinates = LocationAdapter.rounded(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
            MainActor.assumeIsolated {
                finishRead(with: .success(coordinates))
            }
        }

        nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
            let failure = LocationAdapter.capabilityError(from: error)
            MainActor.assumeIsolated {
                log.info("Lectura de ubicación fallida: \(String(describing: failure), privacy: .public)")
                finishRead(with: .failure(failure))
            }
        }
    }
}
