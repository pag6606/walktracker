import CoreLocation
import Domain
import Foundation
import Testing

@testable import WalkTracker

/// La traducción en el borde de `LocationAdapter` (2.1): el redondeo a 2 decimales antes de
/// entregar, la antigüedad aceptada de una ubicación del sistema y el permiso. La lectura real
/// de CoreLocation la cubre el check manual en el iPhone 14.
@Suite("LocationAdapter · redondeo y permiso")
struct LocationAdapterTests {

    @Test("Madrid 40.41683, -3.70379 sale como 40.42, -3.70")
    func roundsMadrid() {
        #expect(LocationAdapter.rounded(latitude: 40.41683, longitude: -3.70379) == Coordinates(latitude: 40.42, longitude: -3.70))
    }

    @Test("Redondeo a 2 decimales con la mitad lejos de cero, y sin -0", arguments: [
        (0.004, 0.0), (-0.004, 0.0), (51.5051, 51.51), (-33.8688, -33.87), (89.999, 90.0), (-179.994, -179.99), (12.3, 12.3),
    ])
    func roundsToHundredths(raw: Double, expected: Double) {
        let coordinates = LocationAdapter.rounded(latitude: raw, longitude: raw)
        #expect(coordinates.latitude == expected)
        #expect(coordinates.longitude == expected)
        #expect(coordinates.latitude.sign == .plus || expected != 0, "nunca -0")
    }

    @Test("Una coordenada redondeada nunca tiene más de 2 decimales")
    func neverMorePrecise() {
        for raw in stride(from: -90.0, through: 90.0, by: 0.123_457) {
            let rounded = LocationAdapter.rounded(latitude: raw, longitude: raw).latitude
            #expect(abs(rounded * 100 - (rounded * 100).rounded()) < 1e-6, "\(raw) → \(rounded)")
            #expect(abs(rounded - raw) <= 0.005 + 1e-9)
        }
    }

    @Test("Una ubicación del sistema vale hasta 5 min; una futura no")
    func freshness() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(LocationAdapter.isFresh(now, now: now))
        #expect(LocationAdapter.isFresh(now.addingTimeInterval(-300), now: now))
        #expect(!LocationAdapter.isFresh(now.addingTimeInterval(-301), now: now))
        #expect(!LocationAdapter.isFresh(now.addingTimeInterval(5), now: now))
    }

    @Test("Permiso: when in use y always conceden; denegado y restringido no")
    func permissionMapping() {
        #expect(LocationAdapter.permission(from: .notDetermined) == .notDetermined)
        #expect(LocationAdapter.permission(from: .authorizedWhenInUse) == .granted)
        #expect(LocationAdapter.permission(from: .authorizedAlways) == .granted)
        #expect(LocationAdapter.permission(from: .denied) == .denied)
        #expect(LocationAdapter.permission(from: .restricted) == .restricted)
    }

    @Test("Errores de CoreLocation: denegado es notAuthorized; el resto, failed; nunca el crudo")
    func errorMapping() {
        #expect(LocationAdapter.capabilityError(from: NSError(domain: kCLErrorDomain, code: CLError.Code.denied.rawValue)) == .notAuthorized)
        #expect(LocationAdapter.capabilityError(from: NSError(domain: kCLErrorDomain, code: CLError.Code.locationUnknown.rawValue)) == .failed(operation: "location"))
        #expect(LocationAdapter.capabilityError(from: URLError(.timedOut)) == .failed(operation: "location"))
    }
}
