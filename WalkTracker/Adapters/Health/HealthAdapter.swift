import Domain
import Foundation
import HealthKit
import OSLog

/// `HealthPort` sobre `HKHealthStore` y `HKWorkoutBuilder` (CAP-11) — AD-10, AD-11.
///
/// Extraído de `feature/flutter-substrate:ios/Runner/AppDelegate.swift` (líneas 240-325).
/// No se portan sus defectos:
/// - los resultados de `add` y `endCollection` se ignoraban y `finishWorkout` corría igual:
///   aquí cada paso usa la API `async` y **un fallo intermedio lanza** sin llegar a
///   `finishWorkout`, descartando el entrenamiento a medio construir;
/// - `quantityType(forIdentifier:)!`: los tipos se construyen con los inicializadores no
///   opcionales;
/// - los errores crudos de HealthKit: se traducen a `CapabilityError` en el borde.
///
/// `HKHealthStore` es `Sendable`; `HKWorkoutBuilder` no, y por eso nunca sale de la
/// función que lo crea.
final class HealthAdapter: HealthPort {

    private let store = HKHealthStore()
    private static let log = Logger(subsystem: "com.walktracker.app", category: "Health")

    static let stepCount = HKQuantityType(.stepCount)
    static let walkingDistance = HKQuantityType(.distanceWalkingRunning)
    private static let typesToShare: Set<HKSampleType> = [
        HKWorkoutType.workoutType(), stepCount, walkingDistance,
    ]

    /// Permiso de escritura de entrenamientos. Inyectable solo para test; por defecto, el sistema.
    private let writeStatus: @Sendable (HKHealthStore) -> PermissionStatus
    /// Si se permite escribir un tipo de cantidad concreto. Inyectable solo para test.
    private let isSharingAuthorized: @Sendable (HKHealthStore, HKQuantityType) -> Bool
    /// Crea el builder de un entrenamiento de caminata. Inyectable solo para test.
    private let makeBuilder: @Sendable (HKHealthStore) -> any WorkoutBuilding

    init(
        writeStatus: @escaping @Sendable (HKHealthStore) -> PermissionStatus = { store in
            guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
            switch store.authorizationStatus(for: HKWorkoutType.workoutType()) {
            case .notDetermined: return .notDetermined
            case .sharingAuthorized: return .granted
            case .sharingDenied: return .denied
            @unknown default: return .denied
            }
        },
        isSharingAuthorized: @escaping @Sendable (HKHealthStore, HKQuantityType) -> Bool = { store, type in
            store.authorizationStatus(for: type) == .sharingAuthorized
        },
        makeBuilder: @escaping @Sendable (HKHealthStore) -> any WorkoutBuilding = { store in
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .walking
            configuration.locationType = .outdoor
            return HealthKitWorkoutBuilder(
                builder: HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            )
        }
    ) {
        self.writeStatus = writeStatus
        self.isSharingAuthorized = isSharingAuthorized
        self.makeBuilder = makeBuilder
    }

    // MARK: - Permiso (AD-11)

    var status: PermissionStatus {
        writeStatus(store)
    }

    func requestAuthorization() async throws(CapabilityError) -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else { throw .unavailable }
        do {
            try await store.requestAuthorization(toShare: Self.typesToShare, read: [])
        } catch {
            throw Self.capabilityError(from: error, operation: "requestAuthorization")
        }
        return status
    }

    // MARK: - Escritura

    func writeWorkout(_ record: WorkoutRecord) async throws(CapabilityError) {
        try Self.requireWritePermission(status)
        let store = self.store
        let isSharingAuthorized = self.isSharingAuthorized
        let samples = Self.samples(for: record) { isSharingAuthorized(store, $0) }
        try await Self.write(samples, from: record.start, to: record.end, using: makeBuilder(store))
    }

    /// Puerta previa a la escritura (AD-11): sin Salud, `.unavailable`; sin permiso
    /// concedido —denegado, restringido o sin decidir—, `.notAuthorized`.
    static func requireWritePermission(_ status: PermissionStatus) throws(CapabilityError) {
        switch status {
        case .granted: return
        case .unavailable: throw .unavailable
        case .notDetermined, .denied, .restricted: throw .notAuthorized
        }
    }

    /// Muestras de pasos y, si hay distancia, de metros, en el intervalo del registro — solo
    /// de los tipos cuya escritura está permitida. El usuario puede permitir entrenamientos y
    /// denegar pasos o distancia: la muestra denegada se omite y el entrenamiento se escribe
    /// igual, en vez de hacer fallar `addSamples` y descartarlo entero.
    static func samples(
        for record: WorkoutRecord,
        isSharingAuthorized: (HKQuantityType) -> Bool
    ) -> [HKSample] {
        var samples: [HKSample] = []
        if isSharingAuthorized(stepCount) {
            samples.append(
                HKQuantitySample(
                    type: stepCount,
                    quantity: HKQuantity(unit: .count(), doubleValue: Double(record.steps)),
                    start: record.start,
                    end: record.end
                )
            )
        }
        // Como el original: sin distancia medida no se escribe una muestra de 0 m.
        if record.distance > 0, isSharingAuthorized(walkingDistance) {
            samples.append(
                HKQuantitySample(
                    type: walkingDistance,
                    quantity: HKQuantity(unit: .meter(), doubleValue: record.distance),
                    start: record.start,
                    end: record.end
                )
            )
        }
        return samples
    }

    /// La secuencia `begin → add → end → finish`, separada del `HKWorkoutBuilder` real para
    /// poder probar sus caminos de fallo sin hardware. Cada paso propaga su fallo; un fallo
    /// en `add` o `end` descarta el entrenamiento y **nunca** llega a `finish` — el defecto
    /// del original, que ignoraba ambos resultados.
    static func write(
        _ samples: [HKSample],
        from start: Date,
        to end: Date,
        using builder: some WorkoutBuilding
    ) async throws(CapabilityError) {
        do {
            try await builder.beginCollection(at: start)
        } catch {
            throw capabilityError(from: error, operation: "beginCollection")
        }

        // Sin tipos permitidos no hay muestras: el entrenamiento se escribe solo.
        if !samples.isEmpty {
            do {
                try await builder.addSamples(samples)
            } catch {
                builder.discardWorkout()
                throw capabilityError(from: error, operation: "addSamples")
            }
        }

        do {
            try await builder.endCollection(at: end)
        } catch {
            builder.discardWorkout()
            throw capabilityError(from: error, operation: "endCollection")
        }

        let produced: Bool
        do {
            produced = try await builder.finishWorkout()
        } catch {
            throw capabilityError(from: error, operation: "finishWorkout")
        }
        guard produced else {
            throw .failed(operation: "finishWorkout")
        }
    }

    // MARK: - Traducción en el borde

    /// Traduce un error de HealthKit a `CapabilityError`. El crudo se registra, nunca sale.
    static func capabilityError(from error: any Error, operation: String) -> CapabilityError {
        log.error("\(operation, privacy: .public) falló: \(String(describing: error), privacy: .public)")
        guard let healthError = error as? HKError else { return .failed(operation: operation) }
        switch healthError.code {
        case .errorHealthDataUnavailable:
            return .unavailable
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined, .errorHealthDataRestricted:
            return .notAuthorized
        default:
            return .failed(operation: operation)
        }
    }
}

/// Los pasos de `HKWorkoutBuilder` que usa la escritura. Existe solo para que
/// `HealthAdapter.write` sea probable con un doble; en producción lo implementa
/// `HealthKitWorkoutBuilder`.
protocol WorkoutBuilding {
    func beginCollection(at start: Date) async throws
    func addSamples(_ samples: [HKSample]) async throws
    func endCollection(at end: Date) async throws
    /// `true` si HealthKit produjo el entrenamiento.
    func finishWorkout() async throws -> Bool
    func discardWorkout()
}

/// `WorkoutBuilding` sobre el `HKWorkoutBuilder` real. No es `Sendable`, como el builder
/// que envuelve: nunca sale de `writeWorkout`.
struct HealthKitWorkoutBuilder: WorkoutBuilding {

    let builder: HKWorkoutBuilder

    func beginCollection(at start: Date) async throws {
        try await builder.beginCollection(at: start)
    }

    func addSamples(_ samples: [HKSample]) async throws {
        try await builder.addSamples(samples)
    }

    func endCollection(at end: Date) async throws {
        try await builder.endCollection(at: end)
    }

    func finishWorkout() async throws -> Bool {
        try await builder.finishWorkout() != nil
    }

    func discardWorkout() {
        builder.discardWorkout()
    }
}
