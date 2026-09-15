import Domain
import Foundation

/// Flujo de inicio y permiso de Motion & Fitness (1.1, 1.2, AD-11): "Iniciar caminata", la
/// pre-pantalla, el diálogo del sistema, la pantalla bloqueante y la apertura de la sesión.
///
/// Escribe `startFlow` y `startFailure`, que solo cambian aquí, y al abrir la sesión
/// `session`, `metrics` y `hasSession`. Nunca pide el permiso en frío ni abre sesión sin él.
extension SessionStore {

    /// "Iniciar caminata". Con el permiso concedido abre la sesión y el conteo; sin
    /// decidir, muestra la pre-pantalla; denegado, restringido o sin coprocesador, la
    /// pantalla bloqueante. En ningún caso pide el permiso en frío.
    ///
    /// Con una sesión abierta o un flujo de permiso en curso no hace nada: un doble
    /// toque no crea otra sesión ni reinicia el cronómetro.
    func start() async {
        guard session == nil, startFlow == .idle else { return }
        startFailure = nil
        switch motion.status {
        case .granted:
            openSession()
        case .notDetermined:
            startFlow = .explainingPermission
        case .denied, .restricted:
            startFlow = .blocked(.permissionDenied)
        case .unavailable:
            startFlow = .blocked(.deviceUnsupported)
        }
    }

    /// "Continuar" en la pre-pantalla: pide el permiso y actúa según la respuesta.
    func confirmMotionPermission() async {
        guard session == nil, startFlow == .explainingPermission else { return }
        startFlow = .requestingPermission
        let status = await motion.requestPermission()
        guard startFlow == .requestingPermission else { return }
        switch status {
        case .granted:
            startFlow = .idle
            openSession()
        case .notDetermined:
            startFlow = .idle
            startFailure = .permissionUnresolved
        case .denied, .restricted:
            startFlow = .blocked(.permissionDenied)
        case .unavailable:
            startFlow = .blocked(.deviceUnsupported)
        }
    }

    /// "Ahora no" en la pre-pantalla: vuelve a Inicio sin sesión.
    func declineMotionPermission() {
        guard startFlow == .explainingPermission else { return }
        startFlow = .idle
    }

    /// "Volver al inicio" en la pantalla bloqueante.
    func leaveMotionBlocked() {
        guard case .blocked = startFlow else { return }
        startFlow = .idle
    }

    /// La app vuelve a primer plano: relee el permiso por si cambió en Ajustes. Si la
    /// pantalla bloqueante ya no aplica, se cierra a Inicio **sin arrancar sola**.
    ///
    /// Paso de `scenePhaseDidChange(to:)`, que solo lo llama tras pasar por `.background`; la
    /// UI no lo llama directamente.
    func motionStatusMayHaveChanged() {
        guard case .blocked = startFlow else { return }
        switch motion.status {
        case .denied, .restricted:
            startFlow = .blocked(.permissionDenied)
        case .unavailable:
            startFlow = .blocked(.deviceUnsupported)
        case .granted, .notDetermined:
            startFlow = .idle
        }
    }

    /// Inicio ya mostró la alerta del inicio fallido.
    func acknowledgeStartFailure() {
        startFailure = nil
    }

    /// Abre la sesión en el instante del reloj con la zancada de `formulas.json`, abre el
    /// conteo y guarda el primer snapshot. Si el dominio la rechaza, no hay sesión ni conteo.
    private func openSession() {
        do {
            let session = try Session.start(at: clock.now, strideM: strideM)
            self.session = session
            metrics = session.metrics(at: clock.now)
            hasSession = true
            countSteps(from: session.startedAt)
            measureTransition(.start, session, at: session.startedAt)
            persist()
        } catch {
            startFailure = .invalidSession(error)
        }
    }
}
