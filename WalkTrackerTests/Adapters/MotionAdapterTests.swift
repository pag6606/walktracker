import CoreMotion
import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Traducción de CoreMotion al DTO del puerto (AD-7, AD-12). No requiere coprocesador:
/// se ejercita la función que el handler llama, con un `CMPedometerData` fabricado.
@Suite("MotionAdapter · traducción en el borde")
struct MotionAdapterTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let end = Date(timeIntervalSince1970: 1_000_600)

    @Test("La distancia conserva los decimales: 812,4 m no se trunca a 812")
    func distanceIsNotTruncated() {
        let data = FakePedometerData(steps: 1_100, distance: 812.4, start: start, end: end)

        let sample = MotionAdapter.sample(from: data)

        #expect(sample == PedometerSample(steps: 1_100, distance: 812.4, start: start, end: end))
    }

    @Test("Sin distancia del sistema, la muestra lleva nil, nunca 0")
    func absentDistanceStaysNil() {
        let data = FakePedometerData(steps: 37, distance: nil, start: start, end: end)

        let sample = MotionAdapter.sample(from: data)

        #expect(sample.distance == nil)
        #expect(sample.steps == 37)
    }

    @Test("Una consulta sin datos y sin error devuelve nil")
    func queryWithoutDataIsNil() throws {
        let result = MotionAdapter.result(data: nil, error: nil)

        #expect(try result.get() == nil)
    }

    @Test("Los errores de CoreMotion salen tipados, nunca crudos")
    func coreMotionErrorsAreTranslated() {
        func error(_ code: CMError) -> NSError {
            NSError(domain: CMErrorDomain, code: Int(code.rawValue))
        }
        let data = FakePedometerData(steps: 1, distance: 1, start: start, end: end)

        #expect(MotionAdapter.result(data: data, error: error(CMErrorMotionActivityNotAuthorized))
            == .failure(.notAuthorized))
        #expect(MotionAdapter.result(data: nil, error: error(CMErrorMotionActivityNotAvailable))
            == .failure(.unavailable))
        #expect(MotionAdapter.result(data: nil, error: error(CMErrorDeviceRequiresMovement))
            == .failure(.failed(operation: "pedometer")))
        #expect(MotionAdapter.result(data: nil, error: URLError(.timedOut))
            == .failure(.failed(operation: "pedometer")))
    }

    @Test("El estado de autorización de CoreMotion se traduce uno a uno", arguments: [
        (CMAuthorizationStatus.notDetermined, PermissionStatus.notDetermined),
        (.authorized, .granted),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func authorizationStatusMapping(status: CMAuthorizationStatus, expected: PermissionStatus) {
        #expect(MotionAdapter.permission(from: status) == expected)
    }

    @Test("Tras pedir permiso, solo un rechazo de permiso es .denied", arguments: [
        (Result<PedometerSample?, CapabilityError>.success(nil), PermissionStatus.granted),
        (.failure(.notAuthorized), .denied),
        (.failure(.unavailable), .unavailable),
        (.failure(.failed(operation: "pedometer")), .notDetermined),
    ])
    func permissionAfterRequest(result: Result<PedometerSample?, CapabilityError>, expected: PermissionStatus) {
        #expect(MotionAdapter.permission(afterRequest: result) == expected)
    }
}

/// `CMPedometerData` no tiene inicializador con valores: se sobrescriben sus propiedades.
private final class FakePedometerData: CMPedometerData, @unchecked Sendable {
    // `@unchecked`: doble de test inmutable tras el init; `CMPedometerData` hereda
    // `NSSecureCoding` y no declara `Sendable`, pero nada aquí se muta.

    private let fakeSteps: NSNumber
    private let fakeDistance: NSNumber?
    private let fakeStart: Date
    private let fakeEnd: Date

    init(steps: Int, distance: Double?, start: Date, end: Date) {
        fakeSteps = NSNumber(value: steps)
        fakeDistance = distance.map { NSNumber(value: $0) }
        fakeStart = start
        fakeEnd = end
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var numberOfSteps: NSNumber { fakeSteps }
    override var distance: NSNumber? { fakeDistance }
    override var startDate: Date { fakeStart }
    override var endDate: Date { fakeEnd }
}
