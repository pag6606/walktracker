import SwiftUI

@main
struct WalkTrackerApp: App {

    /// El composition root se construye una vez y se cablea a la vista raíz.
    private let root = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            RootView(clock: root.clock)
        }
    }
}
