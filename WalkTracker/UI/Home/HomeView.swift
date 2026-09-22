import Domain
import SwiftUI

/// Pestaña Inicio. Su CTA principal es "Iniciar caminata" (AD-14).
///
/// También presenta el flujo de permiso de Motion & Fitness (AD-11): la pre-pantalla
/// y la pantalla bloqueante ocupan la pantalla entera, sin barra de pestañas. Se pintan
/// en el sitio y no como modal a propósito: la sesión ya es el `fullScreenCover` de
/// `RootView`, y al conceder el permiso tiene que aparecer sin competir con otra
/// presentación que se esté cerrando (lo mismo para la alerta de inicio fallido).
///
/// **El anillo de meta (3.1) es la pieza dominante de la pantalla.** Sustituye al
/// `figure.walk` que ocupaba ese hueco —un icono decorativo que no decía nada— y el CTA no se
/// mueve de sitio: sigue debajo, con su mismo tamaño y su mismo sitio en el orden de VoiceOver.
///
/// **El aviso de historial ilegible (5.1) sale aquí y no en la pestaña Historial**, que todavía
/// es un marcador de posición. La decisión de Paul dice que Paul **se entera**, no que pueda
/// enterarse si va a buscarlo: Inicio es la pantalla del arranque, y un aviso escondido detrás de
/// una pestaña sería el silencio que esta historia existe para evitar. No bloquea nada: se puede
/// caminar con el historial ilegible, y lo que se guarde hoy no se escribe encima de lo que no se
/// pudo leer.
struct HomeView<Diagnostics: View>: View {

    let store: SessionStore
    /// Dueño de `settings.json` (AD-16, 2.2). Le llega cableado desde `WalkTrackerApp`, no a
    /// través del store de sesión (sección 6 del gate). De él sale el progreso de la semana —la
    /// meta, el historial y el calendario los junta él— y a él se le cuenta que el anillo se ha
    /// pintado: la vista no calcula ni decide nada.
    let settingsStore: SettingsStore
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

    /// El progreso de la semana, leyendo además el testigo que obliga a repintarlo.
    ///
    /// **El `_ =` no es ruido: es la suscripción.** `weeklyProgress` mide contra `clock.now`, que
    /// no es estado observable, así que sin leer `goalRefreshToken` aquí la vista no se entera de
    /// que la semana ha cambiado al volver de segundo plano y seguiría pintando la pasada.
    private var goalProgress: WeeklyProgress? {
        _ = settingsStore.goalRefreshToken
        return settingsStore.weeklyProgress
    }

    private var home: some View {
        // `ScrollView` dentro de un `GeometryReader`, el mismo patrón que la pantalla de sesión
        // (1.4): con Dynamic Type al máximo, el aviso de historial ilegible encima y una pantalla
        // pequeña, el anillo y el CTA no caben a la vez — y lo que se recortaría es el botón de
        // **iniciar caminata**, que es lo único que esta pantalla tiene que dejar hacer siempre.
        // El `minHeight` conserva los dos `Spacer`: cuando sobra sitio reparten el aire, y cuando
        // falta toma el relevo el scroll.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    if historyStore.showsUnreadableNotice {
                        unreadableHistoryNotice
                    }
                    Spacer()
                    // La meta va aparte del progreso: con el historial ilegible el progreso es
                    // `nil` —ausente se pinta ausente (AD-22)— pero la meta SÍ se sabe, y el pie
                    // tiene que decir la de Paul, no los 10 km por omisión.
                    GoalRingView(progress: goalProgress, goalKm: settingsStore.resolvedWeeklyGoalKm)
                        // La señal del 100 %, una vez por semana (AD-25). Es una intención del
                        // store: la vista no sabe si esta semana ya se celebró, ni escribe nada.
                        .task(id: goalProgress) { settingsStore.goalRingDidUpdate() }
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
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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
    ///
    /// El tratamiento visual lo pone `UnreadableFileNotice`, compartido con el aviso de logros
    /// de la 3.3: es el mismo aviso con dos textos, y dos copias serían dos sitios donde se
    /// puede arreglar solo uno.
    private var unreadableHistoryNotice: some View {
        UnreadableFileNotice(
            title: Text("No se pudo leer tu historial"),
            message: Text("No se ha borrado nada. Puedes seguir caminando: las caminatas nuevas no se escriben encima de lo que no se pudo leer.")
        )
    }

    /// Solo lectura más la intención de reconocerlo: la vista no escribe el estado.
    private var startFailed: Binding<Bool> {
        Binding(
            get: { store.startFailure != nil },
            set: { if !$0 { store.acknowledgeStartFailure() } }
        )
    }
}
