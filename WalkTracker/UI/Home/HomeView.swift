import SwiftUI

/// Pestaña Inicio. Su CTA principal es "Iniciar caminata" (AD-14).
///
/// También presenta el flujo de permiso de Motion & Fitness (AD-11): la pre-pantalla
/// y la pantalla bloqueante ocupan la pantalla entera, sin barra de pestañas. Se pintan
/// en el sitio y no como modal a propósito: la sesión ya es el `fullScreenCover` de
/// `RootView`, y al conceder el permiso tiene que aparecer sin competir con otra
/// presentación que se esté cerrando (lo mismo para la alerta de inicio fallido).
struct HomeView<Diagnostics: View>: View {

    let store: SessionStore
    let diagnostics: Diagnostics?

    @Environment(\.scenePhase) private var scenePhase
    /// La app pasó por `.background` (p. ej. un viaje a Ajustes) desde el último `.active`.
    @State private var returnedFromBackground = false

    var body: some View {
        NavigationStack {
            content
        }
        .toolbar(store.startFlow == .idle ? .automatic : .hidden, for: .tabBar)
        .onChange(of: scenePhase) { _, phase in
            // Al volver de Ajustes, la pantalla bloqueante relee el permiso. Solo tras
            // pasar por `.background`: cerrar el diálogo del sistema es `inactive → active`,
            // y en ese instante el permiso aún puede leerse `.notDetermined`.
            switch phase {
            case .background:
                returnedFromBackground = true
            case .active where returnedFromBackground:
                returnedFromBackground = false
                store.motionStatusMayHaveChanged()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.startFlow {
        case .idle:
            home
        case .explainingPermission, .requestingPermission:
            MotionPermissionView(
                isRequesting: store.startFlow == .requestingPermission,
                onContinue: { Task { await store.confirmMotionPermission() } },
                onDecline: store.declineMotionPermission
            )
            .toolbar(.hidden, for: .navigationBar)
        case .blocked(let reason):
            MotionBlockedView(reason: reason, onBack: store.leaveMotionBlocked)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var home: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.walk")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Button {
                Task { await store.start() }
            } label: {
                Text("Iniciar caminata")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .disabled(store.hasSession)
            Spacer()
            if let diagnostics {
                // Solo `DEBUG` y no es UI de producto: fuera del String Catalog.
                NavigationLink {
                    diagnostics
                } label: {
                    Text(verbatim: "Diagnóstico de la capa nativa")
                }
            }
        }
        .padding()
        .navigationTitle("Inicio")
        .alert("No se pudo iniciar la caminata", isPresented: startFailed) {
            Button("Aceptar", role: .cancel) {}
        }
    }

    /// Solo lectura más la intención de reconocerlo: la vista no escribe el estado.
    private var startFailed: Binding<Bool> {
        Binding(
            get: { store.startFailure != nil },
            set: { if !$0 { store.acknowledgeStartFailure() } }
        )
    }
}
