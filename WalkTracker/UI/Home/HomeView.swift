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

    var body: some View {
        // Al volver de Ajustes, la pantalla bloqueante se cierra sola si el permiso cambió:
        // la relectura la decide el store con las fases que le pasa `RootView`.
        NavigationStack {
            content
        }
        .toolbar(store.startFlow == .idle ? .automatic : .hidden, for: .tabBar)
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
        VStack(spacing: Spacing.xl) {
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
                    .font(Typography.buttonLabel)
                    .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
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
        .padding(LayoutMetrics.margin)
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
