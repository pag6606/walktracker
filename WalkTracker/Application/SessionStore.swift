import Domain
import Foundation
import Observation
import OSLog

/// Único escritor de la sesión (AD-7). Las vistas leen su estado y llaman a sus
/// intenciones; nunca escriben una propiedad. Adapters y timers solo le publican
/// eventos.
///
/// La 1.1 cubre iniciar y el cronómetro; la 1.2, el permiso de Motion & Fitness y el
/// conteo de pasos del coprocesador. La sesión no se persiste (1.6, 5.1): cerrar la app
/// la descarta y se vuelve a Inicio.
@MainActor
@Observable
final class SessionStore {

    /// Paso del flujo de inicio en que está Inicio. Solo con el permiso concedido se
    /// crea la sesión (AD-11).
    enum StartFlow: Equatable, Sendable {
        /// Nada en curso: Inicio muestra "Iniciar caminata".
        case idle
        /// Pre-pantalla explicativa, antes de pedir el permiso (AD-11).
        case explainingPermission
        /// El diálogo del sistema está en pantalla. Un segundo toque no hace nada.
        case requestingPermission
        /// Pantalla completa bloqueante: la única degradación bloqueante (AD-11).
        case blocked(MotionBlock)
    }

    /// Por qué no se puede contar pasos.
    enum MotionBlock: Equatable, Sendable {
        /// Denegado o restringido: solo Ajustes lo revierte.
        case permissionDenied
        /// Sin coprocesador (o el simulador): Ajustes no lo arregla.
        case deviceUnsupported
    }

    /// Por qué el último intento de iniciar no abrió sesión, para la alerta de Inicio.
    enum StartFailure: Equatable, Sendable {
        /// El dominio rechazó crear la sesión.
        case invalidSession(DomainError)
        /// Tras pedirlo, el permiso sigue sin decidir (fallo transitorio): se reintenta
        /// con el siguiente toque.
        case permissionUnresolved
    }

    /// La sesión en curso, o `nil` antes de iniciar ("idle").
    private(set) var session: Session?
    /// Hay una sesión abierta y la UI la presenta como modo a pantalla completa (AD-14).
    /// Guardado aparte de `session` a propósito: cada muestra del podómetro muta la
    /// sesión, y quien solo necesita saber si hay una no debe redibujarse por ello.
    private(set) var hasSession = false
    private(set) var startFlow: StartFlow = .idle
    /// Motivo del último inicio fallido, hasta que Inicio lo reconoce.
    private(set) var startFailure: StartFailure?
    /// El stream del podómetro sigue abierto. Pasa a `false` si el sistema lo termina.
    private(set) var isCountingSteps = false

    @ObservationIgnored private let clock: any ClockPort
    @ObservationIgnored private let motion: any MotionPort
    /// Zancada con la que nace cada sesión. Hoy es la de `formulas.json`; el perfil de
    /// calibración la sustituirá.
    @ObservationIgnored private let strideM: Double
    /// Mayor acumulado del podómetro visto en esta sesión. Los incrementos se miden
    /// contra él, no contra la última muestra: 350 → 340 → 360 suma 10, no 20.
    @ObservationIgnored private var highestCumulativeSteps = 0
    /// Consumo de `motion.updates(from:)`. Expuesto para que los tests esperen su final.
    @ObservationIgnored private(set) var stepCounting: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.walktracker.app", category: "SessionStore")

    init(clock: any ClockPort, motion: any MotionPort, strideM: Double) {
        self.clock = clock
        self.motion = motion
        self.strideM = strideM
    }

    /// Tiempo transcurrido **leído del reloj** en cada lectura. El tick de 1 Hz de la
    /// vista solo provoca la relectura: nunca acumula ni es fuente de verdad.
    var elapsedS: TimeInterval {
        elapsedS(notBefore: .distantPast)
    }

    /// Tiempo transcurrido en `max(instant, clock.now)`. Para el `TimelineView`, que puede
    /// evaluar una entrada un instante antes de su fecha: sin el suelo, el truncado
    /// mostraría k−1 y después saltaría un segundo. El reloj sigue mandando: la fecha
    /// de la entrada solo impide quedarse por detrás de ella.
    func elapsedS(notBefore instant: Date) -> TimeInterval {
        session?.elapsedS(at: max(instant, clock.now)) ?? 0
    }

    // MARK: - Intenciones

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

    // MARK: - Sesión y conteo

    private func openSession() {
        do {
            let session = try Session.start(at: clock.now, strideM: strideM)
            self.session = session
            hasSession = true
            countSteps(from: session.startedAt)
        } catch {
            startFailure = .invalidSession(error)
        }
    }

    /// Consume las muestras **acumuladas desde el inicio** del coprocesador (AD-21). Lo
    /// dado en background entra en la primera muestra al volver, sin estimación.
    private func countSteps(from start: Date) {
        highestCumulativeSteps = 0
        isCountingSteps = true
        let updates = motion.updates(from: start)
        stepCounting = Task { [weak self] in
            for await sample in updates {
                guard let self else { return }
                self.record(sample)
            }
            self?.stepCountingEnded()
        }
    }

    private func record(_ sample: PedometerSample) {
        guard sample.steps > highestCumulativeSteps else { return }
        let increment = sample.steps - highestCumulativeSteps
        highestCumulativeSteps = sample.steps
        do {
            try session?.addMeasuredSteps(increment)
        } catch {
            // Inalcanzable en la 1.2: la sesión siempre está activa y el incremento es > 0.
            log.error("Muestra del podómetro rechazada: \(String(describing: error), privacy: .public)")
        }
    }

    /// El stream terminó sin que nadie lo cancelara: el sistema detuvo el podómetro.
    /// La sesión sigue y conserva sus pasos (AD-11 solo bloquea al iniciar).
    private func stepCountingEnded() {
        isCountingSteps = false
        guard !Task.isCancelled else { return }
        log.error("El sistema terminó las actualizaciones del podómetro; la sesión sigue con \(self.session?.stepsMeasured ?? 0, privacy: .public) pasos")
    }
}
