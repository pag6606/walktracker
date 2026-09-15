import SwiftUI
import Testing

@testable import WalkTracker

/// La traducción de la fase de SwiftUI a la del store (`RootView.swift`). Es lo único que
/// alimenta `scenePhaseDidChange(to:)`: un `.background` traducido mal deja sin gap (AD-8), sin
/// tope de R4, sin guardado en background y sin relectura del permiso.
@Suite("RootView · fase de SwiftUI → fase del store")
struct ScenePhaseTranslationTests {

    @Test("Cada fase de SwiftUI se traduce a la misma fase del store", arguments: [
        (SwiftUI.ScenePhase.active, SessionStore.ScenePhase.active),
        (.background, .background),
        (.inactive, .inactive),
    ])
    func translatesEachPhase(phase: SwiftUI.ScenePhase, expected: SessionStore.ScenePhase) {
        #expect(SessionStore.ScenePhase(phase) == expected)
    }
}
