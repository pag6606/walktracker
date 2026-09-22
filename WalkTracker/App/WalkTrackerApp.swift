import Domain
import SwiftUI

@main
struct WalkTrackerApp: App {

    /// El composition root se construye una vez y se cablea a la vista raíz.
    private let root = CompositionRoot()

    var body: some Scene {
        WindowGroup {
            rootView
                // Al arrancar, la sesión del snapshot se restaura en silencio (1.6): el store
                // la presenta ya reconciliada, sin pantalla de carga.
                .task { await root.sessionStore.restoreOnLaunch() }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        RootView(
            store: root.sessionStore,
            settingsStore: root.settingsStore,
            historyStore: root.historyStore,
            // Los logros llegan por su propio camino —el store del sandbox y el catálogo
            // congelado del bundle—, no a través de `SessionStore`: son dos dueños distintos y
            // la sección 6 del gate prohíbe el atajo. El calendario es el `AppCalendar` de
            // AD-19, el mismo que usan el anillo y el cierre de sesión.
            achievementsStore: root.achievementsStore,
            achievementCatalog: root.achievementCatalog,
            calendar: root.clock.calendar,
            defaultStrideM: root.formulas.defaultStrideM
        ) {
            NativeLayerDiagnosticsView(
                clock: root.clock,
                motion: root.motion,
                feedback: root.feedback,
                health: root.health,
                liveActivity: root.liveActivity
            )
        }
        #else
        RootView(
            store: root.sessionStore,
            settingsStore: root.settingsStore,
            historyStore: root.historyStore,
            // Los logros llegan por su propio camino —el store del sandbox y el catálogo
            // congelado del bundle—, no a través de `SessionStore`: son dos dueños distintos y
            // la sección 6 del gate prohíbe el atajo. El calendario es el `AppCalendar` de
            // AD-19, el mismo que usan el anillo y el cierre de sesión.
            achievementsStore: root.achievementsStore,
            achievementCatalog: root.achievementCatalog,
            calendar: root.clock.calendar,
            defaultStrideM: root.formulas.defaultStrideM
        )
        #endif
    }
}
