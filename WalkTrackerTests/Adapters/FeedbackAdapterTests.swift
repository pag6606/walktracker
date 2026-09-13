import Domain
import Testing

@testable import WalkTracker

/// El mapa de eventos a parámetros es el del original
/// (`feature/flutter-substrate:ios/Runner/AppDelegate.swift`, `feedbackParams` y
/// `fireSound`): intensidad, nitidez y `SystemSoundID`.
@Suite("FeedbackAdapter · parámetros por evento")
struct FeedbackAdapterTests {

    @Test("Cada evento conserva los parámetros del original", arguments: [
        (FeedbackEvent.sessionStart, Float(0.8), Float(0.5), UInt32(1054)),
        (FeedbackEvent.kilometer, Float(0.6), Float(0.5), UInt32(1057)),
        (FeedbackEvent.goal, Float(1.0), Float(0.8), UInt32(1025)),
        (FeedbackEvent.achievement, Float(1.0), Float(0.8), UInt32(1025)),
    ])
    func parametersMatchOriginal(event: FeedbackEvent, intensity: Float, sharpness: Float, soundID: UInt32) {
        let parameters = FeedbackAdapter.parameters(for: event)

        #expect(parameters.intensity == intensity)
        #expect(parameters.sharpness == sharpness)
        #expect(parameters.soundID == soundID)
    }
}
