import Domain
import Foundation
import Testing

/// Validación en frontera de `WorkoutRecord`: un registro inválido no llega a HealthKit.
@Suite("WorkoutRecord · validación")
struct WorkoutRecordTests {

    private static let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Cada valor fuera de rango lanza invalidValue con su campo", arguments: [
        (0.0, 100, 80.0, "end"),            // end == start
        (-1.0, 100, 80.0, "end"),           // end < start
        (60.0, -1, 80.0, "steps"),
        (60.0, 100, -1.0, "distance"),
        (60.0, 100, Double.nan, "distance"),
        (60.0, 100, Double.infinity, "distance"),
    ])
    func invalidValuesThrow(endOffset: TimeInterval, steps: Int, distance: Double, field: String) {
        #expect(throws: DomainError.invalidValue(field: field)) {
            try WorkoutRecord(
                start: Self.start,
                end: Self.start.addingTimeInterval(endOffset),
                steps: steps,
                distance: distance
            )
        }
    }

    @Test("Un registro válido conserva sus valores y su duración en segundos")
    func validRecordReportsDuration() throws {
        let record = try WorkoutRecord(start: Self.start, end: Self.start.addingTimeInterval(60), steps: 100, distance: 80)

        #expect(record.duration == 60)
        #expect(record.steps == 100)
        #expect(record.distance == 80)
    }
}
