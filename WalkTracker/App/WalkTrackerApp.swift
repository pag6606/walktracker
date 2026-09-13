import SwiftUI

@main
struct WalkTrackerApp: App {

    /// El composition root se construye una vez y se cablea a la vista raíz.
    private let root = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            RootView(store: root.sessionStore) {
                NativeLayerDiagnosticsView(
                    clock: root.clock,
                    motion: root.motion,
                    feedback: root.feedback,
                    health: root.health,
                    liveActivity: root.liveActivity
                )
            }
            #else
            RootView(store: root.sessionStore)
            #endif
        }
    }
}
