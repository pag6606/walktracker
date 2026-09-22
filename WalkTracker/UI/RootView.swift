import Domain
import SwiftUI

/// Navegación de AD-14: un `TabView` de cuatro pestañas (Inicio · Historial · Logros ·
/// Ajustes) y la sesión activa como **modo** a pantalla completa sobre él, nunca como
/// quinta pestaña.
///
/// La sesión se presenta mientras `SessionStore` tenga una abierta, incluido su resumen
/// tras finalizar. La única salida es "Volver al inicio" en el resumen: el enlace de
/// presentación ignora cualquier otro intento de cerrarla (AD-20).
///
/// Como está siempre montada, es la única que pasa las fases de la escena al store
/// (`scenePhaseDidChange(to:)`), sin filtrarlas: el gap de AD-8 y la relectura del permiso
/// los decide el store. Ninguna fase pausa.
///
/// En `DEBUG` Inicio enlaza la pantalla de diagnóstico de la capa nativa (historia 8.6).
/// Llega ya construida desde la app, así que esta vista no conoce los puertos que usa;
/// en `Release` el tipo es `Never` y el enlace no existe.
struct RootView<Diagnostics: View>: View {

    let store: SessionStore
    /// Dueño de `settings.json` (AD-16). Llega cableado desde `WalkTrackerApp`, no a través del
    /// store de sesión: la sección 6 del gate prohíbe a `UI/` alcanzar los ajustes por dentro
    /// del store de sesión, y con razón — son dos dueños distintos del mismo puerto.
    ///
    /// Lo usan **dos** pestañas desde la 3.1: Ajustes, para la zancada y la meta, e Inicio, que
    /// le pide el progreso de la semana para el anillo.
    let settingsStore: SettingsStore
    /// Dueño de `sessions.json` (AD-16, 5.1). Llega cableado desde `WalkTrackerApp` por la misma
    /// razón que el de ajustes: son dueños distintos del mismo puerto y la sección 6 del gate
    /// prohíbe alcanzarlos por dentro del store de sesión. Hoy solo se le lee el aviso de
    /// historial ilegible; la lista y los totales son de la 5.2.
    let historyStore: HistoryStore
    /// Dueño de `achievements.json` **del sandbox** (AD-16, 5.1). Llega cableado desde
    /// `WalkTrackerApp` por la misma razón que los otros dos, y además por una propia: la
    /// sección 6 del gate prohíbe a `UI/` alcanzar los logros por dentro del store de sesión,
    /// que es justo el atajo que la 3.2 cerró al añadirlo a esa regla. Hoy lo lee la pestaña
    /// Logros (3.3).
    let achievementsStore: AchievementsStore
    /// El catálogo congelado de los 14 logros (AD-5), del bundle. **No es el fichero del
    /// sandbox**: es contenido, y viaja igual de aparte del store de sesión — el catálogo
    /// también está en la lista de pasos internos que la sección 6 prohíbe en `UI/`.
    let achievementCatalog: AchievementCatalog
    /// El `AppCalendar` de AD-19, de `ClockPort.calendar`: el único calendario de la app. La
    /// pestaña Logros lo necesita para la racha de los progresos y para fechar un desbloqueo en
    /// hora local. Llega como valor, no como puerto: la UI no lee el reloj, solo el calendario.
    let calendar: Calendar
    /// La zancada por omisión de `formulas.json`, para el marcador de posición de Ajustes.
    let defaultStrideM: Double
    private let diagnostics: Diagnostics?

    @Environment(\.scenePhase) private var scenePhase

    init(
        store: SessionStore,
        settingsStore: SettingsStore,
        historyStore: HistoryStore,
        achievementsStore: AchievementsStore,
        achievementCatalog: AchievementCatalog,
        calendar: Calendar,
        defaultStrideM: Double,
        @ViewBuilder diagnostics: () -> Diagnostics
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.achievementsStore = achievementsStore
        self.achievementCatalog = achievementCatalog
        self.calendar = calendar
        self.defaultStrideM = defaultStrideM
        self.diagnostics = diagnostics()
    }

    var body: some View {
        TabView {
            Tab("Inicio", systemImage: "house") {
                HomeView(
                    store: store,
                    settingsStore: settingsStore,
                    historyStore: historyStore,
                    diagnostics: diagnostics
                )
            }
            Tab("Historial", systemImage: "clock.arrow.circlepath") {
                EmptyTabView(
                    title: "Historial",
                    unavailableTitle: "Sin caminatas",
                    systemImage: "clock.arrow.circlepath",
                    description: "Las caminatas que termines aparecerán aquí."
                )
            }
            Tab("Logros", systemImage: "trophy") {
                AchievementsView(
                    catalog: achievementCatalog,
                    achievementsStore: achievementsStore,
                    historyStore: historyStore,
                    calendar: calendar
                )
            }
            Tab("Ajustes", systemImage: "gearshape") {
                SettingsView(settingsStore: settingsStore, defaultStrideM: defaultStrideM)
            }
        }
        .fullScreenCover(isPresented: sessionPresented) {
            SessionView(store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            // Cada fase va al store sin filtrar: él decide qué hace con ella.
            store.scenePhaseDidChange(to: SessionStore.ScenePhase(phase))
            // Y la semana puede haber cambiado mientras la app no estaba delante: el anillo mide
            // contra `clock.now`, que no es estado observable, así que volver de segundo plano un
            // lunes no repintaría nada y la celebración de la semana nueva no se dispararía.
            settingsStore.weekMayHaveChanged()
        }
    }

    /// Solo lectura: la vista no escribe estado del store. El `set` vacío es a
    /// propósito: el modo se cierra cuando el store sale del resumen, nunca desde la vista.
    private var sessionPresented: Binding<Bool> {
        Binding(get: { store.hasSession }, set: { _ in })
    }
}

extension RootView where Diagnostics == Never {

    init(
        store: SessionStore,
        settingsStore: SettingsStore,
        historyStore: HistoryStore,
        achievementsStore: AchievementsStore,
        achievementCatalog: AchievementCatalog,
        calendar: Calendar,
        defaultStrideM: Double
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.achievementsStore = achievementsStore
        self.achievementCatalog = achievementCatalog
        self.calendar = calendar
        self.defaultStrideM = defaultStrideM
        self.diagnostics = nil
    }
}

/// La fase de SwiftUI en el vocabulario del store. Vive en `UI/` para que `Application/` no
/// importe SwiftUI, y es interna para que la pruebe `ScenePhaseTranslationTests`: es lo único
/// que alimenta el gap de AD-8, el tope de R4, el guardado en background y la relectura del
/// permiso.
extension SessionStore.ScenePhase {

    /// Una fase futura desconocida cuenta como `.inactive`, que el store ignora.
    init(_ phase: SwiftUI.ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        case .inactive: self = .inactive
        @unknown default: self = .inactive
        }
    }
}

/// Pestaña sin datos de dominio todavía. No se inventa contenido (AD-22). Solo queda
/// **Historial**, que la llena la 5.2; Ajustes salió de este molde con la 2.3 y Logros con la
/// 3.3 — y esa salió por la puerta contraria: su grid enseña los 14 desde el primer día, así que
/// nunca tiene estado vacío que pintar.
private struct EmptyTabView: View {

    let title: LocalizedStringKey
    let unavailableTitle: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(unavailableTitle, systemImage: systemImage)
            } description: {
                Text(description)
            }
            .navigationTitle(title)
        }
    }
}
