import SwiftUI

/// Pestaña Inicio. Su CTA principal es "Iniciar caminata" (AD-14).
///
/// También presenta el flujo de permiso de Motion & Fitness (AD-11): la pre-pantalla
/// y la pantalla bloqueante ocupan la pantalla entera, sin barra de pestañas. Se pintan
/// en el sitio y no como modal a propósito: la sesión ya es el `fullScreenCover` de
/// `RootView`, y al conceder el permiso tiene que aparecer sin competir con otra
/// presentación que se esté cerrando (lo mismo para la alerta de inicio fallido).
///
/// **El aviso de historial ilegible (5.1) sale aquí y no en la pestaña Historial**, que todavía
/// es un marcador de posición. La decisión de Paul dice que Paul **se entera**, no que pueda
/// enterarse si va a buscarlo: Inicio es la pantalla del arranque, y un aviso escondido detrás de
/// una pestaña sería el silencio que esta historia existe para evitar. No bloquea nada: se puede
/// caminar con el historial ilegible, y lo que se guarde hoy no se escribe encima de lo que no se
/// pudo leer.
struct HomeView<Diagnostics: View>: View {

    let store: SessionStore
    /// Dueño de `sessions.json` (AD-16, 5.1). Solo se le lee el aviso; la vista no decide nada.
    let historyStore: HistoryStore
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
            if historyStore.showsUnreadableNotice {
                unreadableHistoryNotice
            }
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

    /// "No se pudo leer tu historial" (5.1).
    ///
    /// **El aviso que `settings.json` no necesita.** B-1 resolvió que un fichero ilegible se
    /// aparta y no se sobrescribe, y eso vale igual aquí; lo que cambia es la consecuencia.
    /// Perder los ajustes es perder una zancada y una ventana de frases —rehacible—; perder el
    /// historial es perder caminatas que **no se pueden reconstruir** y que CAP-9 promete
    /// garantizadas. Por eso el texto dice las dos cosas que importan: que no se ha borrado nada
    /// y que se puede seguir caminando.
    ///
    /// Sin botón: no hay nada que Paul pueda hacer desde aquí, y un "Aceptar" solo serviría para
    /// que el aviso dejara de estar sin que el problema deje de estar.
    private var unreadableHistoryNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("No se pudo leer tu historial")
                    .font(.subheadline.weight(.semibold))
                Text("No se ha borrado nada. Puedes seguir caminando: las caminatas nuevas no se escriben encima de lo que no se pudo leer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Colors.error)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Surface.cardPaddingHorizontal)
        .padding(.vertical, Surface.cardPaddingVertical)
        .background(Colors.error.opacity(Surface.noticeTintOpacity), in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }

    /// Solo lectura más la intención de reconocerlo: la vista no escribe el estado.
    private var startFailed: Binding<Bool> {
        Binding(
            get: { store.startFailure != nil },
            set: { if !$0 { store.acknowledgeStartFailure() } }
        )
    }
}
