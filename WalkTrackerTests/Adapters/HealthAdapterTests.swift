import Domain
import Foundation
import HealthKit
import Synchronization
import Testing

@testable import WalkTracker

/// Filas de la matriz de la 8.6 sobre Salud, sin hardware: la puerta de permiso previa a
/// la escritura, las muestras por tipo permitido y la secuencia del builder con un doble
/// que falla donde se le pide.
@Suite("HealthAdapter · escritura de workout")
struct HealthAdapterTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let end = Date(timeIntervalSince1970: 1_000_060)

    private static func record(distance: Double = 80) throws -> WorkoutRecord {
        try WorkoutRecord(start: start, end: end, steps: 100, distance: distance)
    }

    private static func allSamples() throws -> [HKSample] {
        HealthAdapter.samples(for: try record()) { _ in true }
    }

    // MARK: Salud no disponible o denegada

    @Test("Salud no disponible → la puerta lanza .unavailable")
    func unavailableHealthThrowsUnavailable() {
        #expect(throws: CapabilityError.unavailable) {
            try HealthAdapter.requireWritePermission(.unavailable)
        }
    }

    @Test("Sin permiso concedido → la puerta lanza .notAuthorized",
          arguments: [PermissionStatus.notDetermined, .denied, .restricted])
    func missingPermissionThrowsNotAuthorized(status: PermissionStatus) {
        #expect(throws: CapabilityError.notAuthorized) {
            try HealthAdapter.requireWritePermission(status)
        }
    }

    @Test("Permiso concedido → la puerta deja pasar")
    func grantedPermissionPasses() throws {
        try HealthAdapter.requireWritePermission(.granted)
    }

    @Test("writeWorkout sin Salud o sin permiso lanza tipado y nunca crea el builder", arguments: [
        (PermissionStatus.unavailable, CapabilityError.unavailable),
        (.notDetermined, .notAuthorized),
        (.denied, .notAuthorized),
        (.restricted, .notAuthorized),
    ])
    func writeWorkoutGateNeverReachesBuilder(status: PermissionStatus, expected: CapabilityError) async throws {
        let builders = Mutex(0)
        let adapter = HealthAdapter(
            writeStatus: { _ in status },
            isSharingAuthorized: { _, _ in true },
            makeBuilder: { _ in
                builders.withLock { $0 += 1 }
                return FakeWorkoutBuilder(failing: nil)
            }
        )
        let record = try Self.record()

        await #expect(throws: expected) {
            try await adapter.writeWorkout(record)
        }
        #expect(builders.withLock { $0 } == 0)
    }

    // MARK: Muestras

    @Test("80 m → muestra de pasos en .count() y de distancia de 80 en .meter(), ambas en [start, end]")
    func samplesWithDistance() throws {
        let samples = try Self.allSamples().compactMap { $0 as? HKQuantitySample }

        #expect(samples.count == 2)
        let steps = try #require(samples.first { $0.quantityType == HealthAdapter.stepCount })
        let distance = try #require(samples.first { $0.quantityType == HealthAdapter.walkingDistance })
        #expect(steps.quantity.doubleValue(for: .count()) == 100)
        #expect(distance.quantity.doubleValue(for: .meter()) == 80)
        for sample in samples {
            #expect(sample.startDate == Self.start)
            #expect(sample.endDate == Self.end)
        }
    }

    @Test("0 m → solo la muestra de pasos")
    func samplesWithoutDistance() throws {
        let samples = HealthAdapter.samples(for: try Self.record(distance: 0)) { _ in true }

        #expect(samples.map(\.sampleType.identifier) == [HealthAdapter.stepCount.identifier])
    }

    @Test("Un tipo de cantidad denegado se omite", arguments: [
        (HealthAdapter.stepCount, HealthAdapter.walkingDistance),
        (HealthAdapter.walkingDistance, HealthAdapter.stepCount),
    ])
    func deniedQuantityTypeIsLeftOut(denied: HKQuantityType, kept: HKQuantityType) throws {
        let samples = HealthAdapter.samples(for: try Self.record()) { $0 != denied }

        #expect(samples.map(\.sampleType.identifier) == [kept.identifier])
    }

    @Test("Pasos denegados con entrenamientos permitidos → el workout se escribe igual, sin la muestra de pasos")
    func deniedStepsStillWritesWorkout() async throws {
        let builder = FakeWorkoutBuilder(failing: nil)
        let adapter = HealthAdapter(
            writeStatus: { _ in .granted },
            isSharingAuthorized: { _, type in type != HealthAdapter.stepCount },
            makeBuilder: { _ in builder }
        )

        try await adapter.writeWorkout(try Self.record())

        #expect(builder.addedTypes == [HealthAdapter.walkingDistance.identifier])
        #expect(builder.calls == [.begin, .addSamples, .endCollection, .finish])
    }

    // MARK: Fallo intermedio del builder

    @Test("Falla beginCollection → lanza y nunca llama a addSamples")
    func beginFailureNeverAddsSamples() async throws {
        let builder = FakeWorkoutBuilder(failing: .begin)
        let samples = try Self.allSamples()

        await #expect(throws: CapabilityError.failed(operation: "beginCollection")) {
            try await HealthAdapter.write(samples, from: Self.start, to: Self.end, using: builder)
        }
        #expect(builder.calls == [.begin])
    }

    @Test("Falla addSamples → lanza, descarta y no llama a finishWorkout")
    func addSamplesFailureNeverFinishes() async throws {
        let builder = FakeWorkoutBuilder(failing: .addSamples)
        let samples = try Self.allSamples()

        await #expect(throws: CapabilityError.failed(operation: "addSamples")) {
            try await HealthAdapter.write(samples, from: Self.start, to: Self.end, using: builder)
        }
        #expect(builder.calls == [.begin, .addSamples, .discard])
    }

    @Test("Falla endCollection → lanza, descarta y no llama a finishWorkout")
    func endCollectionFailureNeverFinishes() async throws {
        let builder = FakeWorkoutBuilder(failing: .endCollection)
        let samples = try Self.allSamples()

        await #expect(throws: CapabilityError.failed(operation: "endCollection")) {
            try await HealthAdapter.write(samples, from: Self.start, to: Self.end, using: builder)
        }
        #expect(builder.calls == [.begin, .addSamples, .endCollection, .discard])
    }

    @Test("finishWorkout sin entrenamiento → .failed(finishWorkout)")
    func finishWithoutWorkoutFails() async throws {
        let builder = FakeWorkoutBuilder(failing: nil, produces: false)
        let samples = try Self.allSamples()

        await #expect(throws: CapabilityError.failed(operation: "finishWorkout")) {
            try await HealthAdapter.write(samples, from: Self.start, to: Self.end, using: builder)
        }
    }

    @Test("finishWorkout lanza → .failed(finishWorkout)")
    func finishThrowingFails() async throws {
        let builder = FakeWorkoutBuilder(failing: .finish)
        let samples = try Self.allSamples()

        await #expect(throws: CapabilityError.failed(operation: "finishWorkout")) {
            try await HealthAdapter.write(samples, from: Self.start, to: Self.end, using: builder)
        }
    }

    @Test("Un error de autorización de HealthKit en un paso sale tipado, nunca crudo")
    func healthKitAuthorizationErrorIsTranslated() async throws {
        let builder = FakeWorkoutBuilder(failing: .addSamples, error: HKError(.errorAuthorizationDenied))
        let samples = try Self.allSamples()

        await #expect(throws: CapabilityError.notAuthorized) {
            try await HealthAdapter.write(samples, from: Self.start, to: Self.end, using: builder)
        }
        #expect(!builder.calls.contains(.finish))
    }

    @Test("Sin fallos → la secuencia completa termina en finishWorkout, sin descartar")
    func happyPathFinishes() async throws {
        let builder = FakeWorkoutBuilder(failing: nil)
        let samples = try Self.allSamples()

        try await HealthAdapter.write(samples, from: Self.start, to: Self.end, using: builder)

        #expect(builder.calls == [.begin, .addSamples, .endCollection, .finish])
    }
}

/// Doble de `HKWorkoutBuilder` que registra los pasos y falla en el que se le indique.
/// `Sendable` por su `Mutex`, para poder devolverlo desde la factoría inyectada.
private final class FakeWorkoutBuilder: WorkoutBuilding, Sendable {

    enum Step: Equatable, Sendable { case begin, addSamples, endCollection, finish, discard }

    private struct Log: ~Copyable {
        var calls: [Step] = []
        var addedTypes: [String] = []
    }

    private let log = Mutex(Log())
    private let failing: Step?
    private let produces: Bool
    private let error: any Error & Sendable

    var calls: [Step] { log.withLock { $0.calls } }
    var addedTypes: [String] { log.withLock { $0.addedTypes } }

    init(failing: Step?, produces: Bool = true, error: any Error & Sendable = TestError()) {
        self.failing = failing
        self.produces = produces
        self.error = error
    }

    private func record(_ step: Step) throws {
        log.withLock { $0.calls.append(step) }
        if step == failing { throw error }
    }

    func beginCollection(at start: Date) async throws { try record(.begin) }

    func addSamples(_ samples: [HKSample]) async throws {
        let identifiers = samples.map(\.sampleType.identifier)
        log.withLock { $0.addedTypes += identifiers }
        try record(.addSamples)
    }

    func endCollection(at end: Date) async throws { try record(.endCollection) }
    func finishWorkout() async throws -> Bool { try record(.finish); return produces }
    func discardWorkout() { log.withLock { $0.calls.append(.discard) } }
}

private struct TestError: Error {}
