import SwiftUI

/// Navegación de AD-14: un `TabView` de cuatro pestañas (Inicio · Historial · Logros ·
/// Ajustes) y la sesión activa como **modo** a pantalla completa sobre él, nunca como
/// quinta pestaña.
///
/// La sesión se presenta mientras `SessionStore` tenga una abierta. No hay salida
/// hasta la 1.4: el enlace de presentación ignora cualquier intento de cerrarla.
///
/// En `DEBUG` Inicio enlaza la pantalla de diagnóstico de la capa nativa (historia 8.6).
/// Llega ya construida desde la app, así que esta vista no conoce los puertos que usa;
/// en `Release` el tipo es `Never` y el enlace no existe.
struct RootView<Diagnostics: View>: View {

    let store: SessionStore
    private let diagnostics: Diagnostics?

    init(store: SessionStore, @ViewBuilder diagnostics: () -> Diagnostics) {
        self.store = store
        self.diagnostics = diagnostics()
    }

    var body: some View {
        TabView {
            Tab("Inicio", systemImage: "house") {
                HomeView(store: store, diagnostics: diagnostics)
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
                EmptyTabView(
                    title: "Logros",
                    unavailableTitle: "Sin logros",
                    systemImage: "trophy",
                    description: "Los logros que desbloquees aparecerán aquí."
                )
            }
            Tab("Ajustes", systemImage: "gearshape") {
                EmptyTabView(
                    title: "Ajustes",
                    unavailableTitle: "Sin ajustes",
                    systemImage: "gearshape",
                    description: "Todavía no hay nada que ajustar."
                )
            }
        }
        .fullScreenCover(isPresented: sessionPresented) {
            SessionView(store: store)
        }
    }

    /// Solo lectura: la vista no escribe estado del store. El `set` vacío es a
    /// propósito, porque no hay salida de la sesión antes de la 1.4.
    private var sessionPresented: Binding<Bool> {
        Binding(get: { store.hasSession }, set: { _ in })
    }
}

extension RootView where Diagnostics == Never {

    init(store: SessionStore) {
        self.store = store
        self.diagnostics = nil
    }
}

/// Pestaña sin datos de dominio todavía. No se inventa contenido (AD-22).
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
