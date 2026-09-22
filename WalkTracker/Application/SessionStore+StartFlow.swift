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

    /// Abre la sesión en el instante del reloj con la zancada que toque **ahora**, abre el
    /// conteo y guarda el primer snapshot. Si el dominio la rechaza, no hay sesión ni conteo.
    ///
    /// **La zancada se resuelve aquí, no en el init del store** (2.3, criterio central). Se le
    /// pregunta al dueño de los ajustes en el momento de abrir: si Paul recalibró hace un
    /// instante, esta sesión ya nace con el valor nuevo **sin relanzar la app**; si nunca la
    /// tocó, nace con el default de `formulas.json`. Con el `let` del store leído al
    /// construirlo, recalibrar no habría surtido efecto hasta el siguiente lanzamiento.
    ///
    /// El clima (2.1) va después y en paralelo: la apertura nunca lo espera.
    ///
    /// La frase (2.2) entra **después de `hasSession = true`**, con la sesión ya contando y
    /// presentada, y **antes de `persist()`**, para que su `quoteId` viaje en el primer
    /// snapshot: es síncrona y local, así que no hay nada que esperar.
    private func openSession() {
        do {
            let strideM = settings.resolvedStrideM(default: defaultStrideM)
            let session = try Session.start(at: clock.now, strideM: strideM)
            self.session = session
            metrics = session.metrics(at: clock.now)
            hasSession = true
            countSteps(from: session.startedAt)
            measureTransition(.start, session, at: session.startedAt)
            // La caminata ha empezado de verdad —el dominio la aceptó y ya está contando—, así
            // que se confirma con una vibración corta (CAP-12, 4.1). Es el **punto único** donde
            // nace una sesión: los dos entrantes (`start()` y `confirmMotionPermission()`) pasan
            // por aquí, así que un disparo cubre los dos y no hay forma de abrir una sesión
            // muda. Va antes de `persist()` para que la confirmación no espere a un fichero.
            //
            // `soundEnabled: false` es la decisión D1: la preferencia de sonido llega con la 4.2.
            // No lleva `try` ni condiciona nada de lo que viene detrás: el puerto promete que un
            // feedback perdido no es un fallo de sesión.
            feedback.fire(.sessionStart, soundEnabled: false)
            attachQuoteForNewSession()
            persist()
            beginWeatherForNewSession()
        } catch {
            startFailure = .invalidSession(error)
        }
    }
}
