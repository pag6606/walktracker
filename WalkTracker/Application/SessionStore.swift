import Domain
import Foundation
import Observation
import OSLog

/// Único escritor de la sesión (AD-7). Las vistas leen su estado y llaman a sus
/// intenciones; nunca escriben una propiedad. Adapters y timers solo le publican
/// eventos.
///
/// La 1.1 cubre iniciar y el cronómetro; la 1.2, el permiso de Motion & Fitness y el
/// conteo de pasos del coprocesador; la 1.3, las métricas derivadas; la 1.4, pausar,
/// reanudar, finalizar y el resumen. La sesión no se persiste (1.6, 5.1): cerrar la app
/// la descarta, y la finalizada se descarta al salir del resumen.
///
/// La pausa es solo explícita (CAP-1): pasar a segundo plano o bloquear la pantalla no
/// llega aquí como intención y nunca pausa.
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
    ///
    /// Sigue en `true` con la sesión finalizada, mientras se muestra su resumen dentro
    /// del mismo modo; pasa a `false` al salir del resumen.
    private(set) var hasSession = false
    /// "Finalizar" pidió confirmación y el diálogo está en pantalla (AD-20).
    private(set) var isConfirmingFinish = false
    private(set) var startFlow: StartFlow = .idle
    /// Motivo del último inicio fallido, hasta que Inicio lo reconoce.
    private(set) var startFailure: StartFailure?
    /// Distancia, ritmo y cadencia de la sesión, o `nil` sin sesión. Se fijan al abrirla y
    /// se recalculan con **cada muestra** del coprocesador, no con el tick de 1 Hz
    /// (AD-21): con el teléfono quieto no llegan muestras y se quedan en su último valor.
    private(set) var metrics: SessionMetrics?
    /// El stream del podómetro sigue abierto. Pasa a `false` si el sistema lo termina.
    private(set) var isCountingSteps = false

    @ObservationIgnored private let clock: any ClockPort
    @ObservationIgnored private let motion: any MotionPort
    /// Zancada con la que nace cada sesión. Hoy es la de `formulas.json`; el perfil de
    /// calibración la sustituirá.
    @ObservationIgnored private let strideM: Double
    /// Mayor acumulado del podómetro visto en el tramo en curso. Los incrementos se miden
    /// contra él, no contra la última muestra: 350 → 340 → 360 suma 10, no 20.
    @ObservationIgnored private var highestCumulativeSteps = 0
    /// Distancia del sistema acumulada al abrir el tramo en curso. Cada stream da la
    /// distancia desde su propio inicio, así que la de la sesión es esta base más la del
    /// tramo: sigue siendo acumulada desde el inicio y nunca baja.
    @ObservationIgnored private var distanceBaseM: Double = 0
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

    /// "Pausar": congela el tiempo y detiene el podómetro (AD-21, energía). Solo con la
    /// sesión `active`; en otro estado no hace nada.
    func pause() {
        guard var session, session.status == .active else { return }
        let now = clock.now
        do {
            try session.pause(at: now)
        } catch {
            log.error("Pausar rechazado: \(String(describing: error), privacy: .public)")
            return
        }
        stopCountingSteps()
        self.session = session
        metrics = session.metrics(at: now)
    }

    /// "Reanudar": el tiempo sigue y se abre un stream nuevo desde el instante de
    /// reanudación. Sus muestras acumuladas empiezan de cero, así que los pasos dados
    /// durante la pausa quedan fuera por construcción. Solo con la sesión `paused`.
    func resume() {
        guard var session, session.status == .paused else { return }
        let now = clock.now
        do {
            try session.resume(at: now)
        } catch {
            log.error("Reanudar rechazado: \(String(describing: error), privacy: .public)")
            return
        }
        self.session = session
        metrics = session.metrics(at: now)
        countSteps(from: now)
    }

    /// "Finalizar": pide confirmación explícita antes de cerrar (AD-20). Solo con la
    /// sesión `active` o `paused`.
    func requestFinish() {
        guard let status = session?.status, status != .finished else { return }
        isConfirmingFinish = true
    }

    /// "Cancelar" (o cerrar) el diálogo de confirmación: la sesión sigue en su estado.
    func cancelFinish() {
        isConfirmingFinish = false
    }

    /// "Finalizar caminata" en la confirmación: cierra la sesión y detiene el podómetro.
    /// La sesión finalizada se queda en `session` para el resumen y `hasSession` sigue en
    /// `true`. No exige que `isConfirmingFinish` siga en `true`: el diálogo puede
    /// cerrarse (y cancelar) antes de ejecutar la acción del botón.
    func confirmFinish() {
        isConfirmingFinish = false
        guard var session, session.status != .finished else { return }
        let now = clock.now
        do {
            try session.finish(at: now)
        } catch {
            log.error("Finalizar rechazado: \(String(describing: error), privacy: .public)")
            return
        }
        stopCountingSteps()
        self.session = session
        metrics = session.metrics(at: now)
    }

    /// "Volver a Inicio" en el resumen: descarta la sesión finalizada (aún no hay
    /// persistencia) y cierra el modo de sesión. Solo con la sesión `finished`.
    func leaveSummary() {
        guard session?.status == .finished else { return }
        session = nil
        metrics = nil
        isConfirmingFinish = false
        hasSession = false
    }

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
            metrics = session.metrics(at: clock.now)
            hasSession = true
            countSteps(from: session.startedAt)
        } catch {
            startFailure = .invalidSession(error)
        }
    }

    /// Consume las muestras **acumuladas desde `start`** del coprocesador (AD-21): el
    /// inicio de la sesión o el de la reanudación. Lo dado en background entra en la
    /// primera muestra al volver, sin estimación.
    private func countSteps(from start: Date) {
        highestCumulativeSteps = 0
        distanceBaseM = session?.systemDistanceM ?? 0
        isCountingSteps = true
        let updates = motion.updates(from: start)
        stepCounting = Task { [weak self] in
            for await sample in updates {
                // Una muestra ya encolada cuando se canceló el tramo es de ese tramo: no
                // se aplica, ni a la sesión pausada ni al acumulado del tramo siguiente.
                guard !Task.isCancelled, let self else { return }
                self.record(sample)
            }
            self?.stepCountingEnded()
        }
    }

    /// Cancela el stream del tramo en curso. Cancelar la iteración detiene el podómetro
    /// en el adapter.
    private func stopCountingSteps() {
        stepCounting?.cancel()
        isCountingSteps = false
    }

    /// Aplica pasos y distancia de la muestra y recalcula las métricas en `clock.now`.
    /// Un fallo de una parte no impide la otra: una distancia inválida se registra y el
    /// conteo sigue.
    private func record(_ sample: PedometerSample) {
        guard session?.status == .active else { return }
        if sample.steps > highestCumulativeSteps {
            let increment = sample.steps - highestCumulativeSteps
            highestCumulativeSteps = sample.steps
            do {
                try session?.addMeasuredSteps(increment)
            } catch {
                // Inalcanzable: la sesión está activa y el incremento es > 0.
                log.error("Pasos de la muestra rechazados: \(String(describing: error), privacy: .public)")
            }
        }
        if let distance = sample.distance {
            do {
                try session?.recordSystemDistance(distanceBaseM + distance)
            } catch {
                log.error("Distancia de la muestra rechazada: \(String(describing: error), privacy: .public)")
            }
        }
        metrics = session?.metrics(at: clock.now)
    }

    /// El stream terminó sin que nadie lo cancelara: el sistema detuvo el podómetro.
    /// La sesión sigue y conserva sus pasos (AD-11 solo bloquea al iniciar).
    /// Si lo canceló el store (pausar o finalizar), no hace nada: `isCountingSteps` ya se
    /// actualizó al cancelar, y quizá otro tramo ya está contando.
    private func stepCountingEnded() {
        guard !Task.isCancelled else { return }
        isCountingSteps = false
        log.error("El sistema terminó las actualizaciones del podómetro; la sesión sigue con \(self.session?.stepsMeasured ?? 0, privacy: .public) pasos")
    }
}
