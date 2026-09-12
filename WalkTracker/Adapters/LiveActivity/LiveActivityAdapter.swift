import ActivityKit
import Domain
import Foundation
import OSLog
import Shared
import Synchronization

/// `LiveActivityPort` sobre ActivityKit (CAP-18) — AD-10, AD-11, AD-15, AD-21.
///
/// Extraído de `feature/flutter-substrate:ios/Runner/AppDelegate.swift` (líneas 327-414).
/// No se portan ni sus comprobaciones de disponibilidad de iOS 16.2 (AD-2) ni su
/// `WalktrackerActivityAttributes` con `ContentState` propio: el contrato es
/// `Shared/WalkTrackerActivityAttributes` + `ActivitySnapshot` (AD-15).
///
/// **Formateo.** El puerto recibe magnitudes crudas (`LiveActivityState`) y este adapter
/// las convierte en el `ActivitySnapshot` ya formateado que la extensión solo pinta. Vive
/// aquí hasta que el Epic 7 lo lleve a `Shared`.
///
/// `Activity` no es `Sendable`: no se guarda. Se guarda su `id`, solo en memoria, y la
/// actividad se busca en `Activity.activities` en cada operación. `update` y `end` solo
/// actúan sobre la que inició este lanzamiento; las de lanzamientos anteriores las retira
/// `start` antes de pedir una nueva.
final class LiveActivityAdapter: LiveActivityPort {

    private typealias WalkActivity = Activity<WalkTrackerActivityAttributes>

    private let currentID = Mutex<String?>(nil)
    private let log = Logger(subsystem: "com.walktracker.app", category: "LiveActivity")

    /// Si el usuario permite Live Activities. Inyectable solo para test; por defecto, el sistema.
    private let areActivitiesEnabled: @Sendable () -> Bool
    /// Pide la actividad al sistema y devuelve su `id`. Inyectable solo para test.
    private let requestActivity: @Sendable (WalkTrackerActivityAttributes, ActivitySnapshot) throws -> String

    init(
        areActivitiesEnabled: @escaping @Sendable () -> Bool = {
            ActivityAuthorizationInfo().areActivitiesEnabled
        },
        requestActivity: @escaping @Sendable (WalkTrackerActivityAttributes, ActivitySnapshot) throws -> String = {
            attributes, snapshot in
            try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: snapshot, staleDate: nil),
                pushType: nil
            ).id
        }
    ) {
        self.areActivitiesEnabled = areActivitiesEnabled
        self.requestActivity = requestActivity
    }

    // MARK: - Permiso (AD-11)

    var status: PermissionStatus {
        areActivitiesEnabled() ? .granted : .denied
    }

    // MARK: - Ciclo de vida

    func start(sessionID: UUID, state: LiveActivityState) async throws(CapabilityError) {
        guard areActivitiesEnabled() else { throw .notAuthorized }

        // Una sola Live Activity de sesión: cualquier resto (de esta ejecución o de una
        // anterior que no llegó a terminarla) se retira antes.
        for activity in WalkActivity.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        do {
            let id = try requestActivity(
                WalkTrackerActivityAttributes(sessionID: sessionID),
                Self.snapshot(from: state)
            )
            currentID.withLock { $0 = id }
        } catch {
            throw capabilityError(from: error)
        }
    }

    func update(_ state: LiveActivityState) async {
        guard let activity = currentActivity() else { return }
        await activity.update(ActivityContent(state: Self.snapshot(from: state), staleDate: nil))
    }

    func end() async {
        let activity = currentActivity()
        currentID.withLock { $0 = nil }
        await activity?.end(nil, dismissalPolicy: .immediate)
    }

    private func currentActivity() -> WalkActivity? {
        guard let id = currentID.withLock({ $0 }) else { return nil }
        return WalkActivity.activities.first { $0.id == id }
    }

    // MARK: - Traducción en el borde (expuesta para test)

    private static let locale = Locale(identifier: "es_ES")

    /// Magnitudes crudas → contrato formateado de la extensión (AD-15). La distancia se
    /// formatea en kilómetros con dos decimales a partir de los metros, sin truncar antes.
    static func snapshot(from state: LiveActivityState) -> ActivitySnapshot {
        ActivitySnapshot(
            timerStart: state.timerStart,
            frozenElapsed: state.frozenElapsed,
            stepsText: state.steps.formatted(.number.locale(locale)),
            distanceText: (state.distance / 1000)
                .formatted(.number.precision(.fractionLength(2)).locale(locale)) + " km",
            pace: state.pace
        )
    }

    private func capabilityError(from error: any Error) -> CapabilityError {
        log.error("Activity.request falló: \(String(describing: error), privacy: .public)")
        guard let activityError = error as? ActivityAuthorizationError else {
            return .failed(operation: "request")
        }
        switch activityError {
        case .denied, .unentitled:
            return .notAuthorized
        case .unsupported, .unsupportedTarget:
            return .unavailable
        default:
            return .failed(operation: "request")
        }
    }
}
