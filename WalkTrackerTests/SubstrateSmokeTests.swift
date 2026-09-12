import Foundation
import Testing

@testable import Domain
@testable import Shared

/// Caso de humo del sustrato. La historia 8.7 pone aquí los vectores de AD-6
/// (`Vectors/`) y los escenarios portados a mano (`Scenarios/`); esta suite solo
/// demuestra que el target existe, enlaza los dos módulos y corre.
@Suite("Humo del sustrato")
struct SubstrateSmokeTests {

    @Test("El snapshot en pausa congela el cronómetro y el que corre no")
    func pausedSnapshotFreezesTimer() {
        let start = Date(timeIntervalSince1970: 1_000_000)

        let running = ActivitySnapshot(
            timerStart: start,
            stepsText: "1.234",
            distanceText: "0,9 km"
        )
        #expect(running.isPaused == false)
        #expect(running.frozenElapsedText == "—")

        let paused = ActivitySnapshot(
            timerStart: start,
            frozenElapsed: 125,
            stepsText: "1.234",
            distanceText: "0,9 km"
        )
        #expect(paused.isPaused)
        #expect(paused.frozenElapsedText == "2:05")
    }

    @Test("Un ritmo ausente se representa como tal, nunca como cero")
    func absentPaceRendersAsDash() {
        let start = Date(timeIntervalSince1970: 1_000_000)

        let withoutPace = ActivitySnapshot(
            timerStart: start,
            stepsText: "12",
            distanceText: "0,0 km",
            pace: nil
        )
        #expect(withoutPace.paceText == "—")

        let withPace = ActivitySnapshot(
            timerStart: start,
            stepsText: "1.234",
            distanceText: "0,9 km",
            pace: 545
        )
        #expect(withPace.paceText == "9:05 /km")
    }

    @Test("El error del dominio es tipado y comparable")
    func domainErrorIsTyped() {
        #expect(DomainError.invalidValue(field: "steps") == .invalidValue(field: "steps"))
        #expect(DomainError.invalidValue(field: "steps") != .invalidValue(field: "distance"))
    }
}
