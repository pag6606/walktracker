import ActivityKit
import Domain
import Foundation
import Synchronization
import Testing

@testable import WalkTracker

/// Magnitudes crudas → `ActivitySnapshot` formateado (AD-15).
@Suite("LiveActivityAdapter · snapshot")
struct LiveActivityAdapterTests {

    @Test("Los metros se formatean en km con decimales y sin truncar; el resto pasa tal cual")
    func snapshotFormatsRawState() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let state = LiveActivityState(steps: 12_345, distance: 812.4, pace: 545, timerStart: start, frozenElapsed: 125)

        let snapshot = LiveActivityAdapter.snapshot(from: state)

        #expect(snapshot.distanceText == "0,81 km")
        #expect(snapshot.timerStart == start)
        #expect(snapshot.frozenElapsed == 125)
        #expect(snapshot.pace == 545)
        #expect(snapshot.stepsText == "12.345")
    }
}

/// Fila de la matriz de la 8.6: con las Live Activities desactivadas, `start` lanza un
/// error tipado, nunca llega a pedir la actividad al sistema, y nada más se rompe.
@Suite("LiveActivityAdapter · desactivadas")
struct LiveActivityDisabledTests {

    @Test("Desactivadas → start lanza .notAuthorized y nunca llega a request; update y end no rompen")
    func disabledStartThrowsWithoutRequesting() async {
        let requests = Mutex(0)
        let adapter = LiveActivityAdapter(
            areActivitiesEnabled: { false },
            requestActivity: { _, _ in
                requests.withLock { $0 += 1 }
                return "no-debería-existir"
            }
        )
        let state = LiveActivityState(steps: 10, distance: 8, pace: nil, timerStart: Date(timeIntervalSince1970: 0))

        await #expect(throws: CapabilityError.notAuthorized) {
            try await adapter.start(sessionID: UUID(), state: state)
        }

        #expect(requests.withLock { $0 } == 0)
        #expect(adapter.status == .denied)
        // Sin actividad en curso, update y end son no-ops.
        await adapter.update(state)
        await adapter.end()
        #expect(requests.withLock { $0 } == 0)
    }
}

/// Traducción de un fallo de `Activity.request` con las Live Activities activadas.
@Suite("LiveActivityAdapter · fallo de request")
struct LiveActivityRequestFailureTests {

    enum Failure: Sendable, CustomTestStringConvertible {
        case denied, unsupported, other
        var testDescription: String { "\(self)" }
    }

    @Test("Un request fallido sale tipado, nunca crudo", arguments: [
        (Failure.denied, CapabilityError.notAuthorized),
        (.unsupported, .unavailable),
        (.other, .failed(operation: "request")),
    ])
    func failedRequestIsTranslated(failure: Failure, expected: CapabilityError) async {
        let adapter = LiveActivityAdapter(
            areActivitiesEnabled: { true },
            requestActivity: { _, _ in
                switch failure {
                case .denied: throw ActivityAuthorizationError.denied
                case .unsupported: throw ActivityAuthorizationError.unsupported
                case .other: throw URLError(.unknown)
                }
            }
        )
        let state = LiveActivityState(steps: 0, distance: 0, pace: nil, timerStart: Date(timeIntervalSince1970: 0))

        await #expect(throws: expected) {
            try await adapter.start(sessionID: UUID(), state: state)
        }
    }
}
