import Domain
import Foundation
import Observation
import OSLog
import Synchronization

/// Único escritor de la sesión (AD-7). Las vistas leen su estado y llaman a sus
/// intenciones; nunca escriben una propiedad. Adapters y timers solo le publican
/// eventos.
///
/// La 1.1 cubre iniciar y el cronómetro; la 1.2, el permiso de Motion & Fitness y el
/// conteo de pasos del coprocesador; la 1.3, las métricas derivadas; la 1.4, pausar,
/// reanudar, finalizar y el resumen; la 1.5, la reconstrucción del background por consulta
/// al sistema y el descarte de pasos estimados. La sesión no se persiste (1.6, 5.1): cerrar
/// la app la descarta, y la finalizada se descarta al salir del resumen.
///
/// La pausa es solo explícita (CAP-1): pasar a segundo plano o bloquear la pantalla llega
/// aquí solo para reconciliar los pasos del gap, y nunca pausa.
///
/// **Reconciliación atómica (AD-8).** Al volver a primer plano con la sesión activa, y al
/// finalizar desde activa, el store consulta al coprocesador el acumulado del tramo en
/// curso. Mientras dura, `isReconciling` está en `true`: toda intención de comando sale
/// sin hacer nada y la UI deshabilita los controles; `SessionStatus` no cambia. La consulta
/// está acotada por `reconciliationTimeoutS`: al agotarse, cuenta como sin dato y libera los
/// comandos. Sin dato, y solo con un gap de background pendiente, estima con el
/// `GapEstimator`.
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
    /// Reconciliación atómica en curso (AD-8): las intenciones de comando no hacen nada y la
    /// UI deshabilita los controles.
    private(set) var isReconciling = false
    /// "Descartar" pidió confirmación y el diálogo está en pantalla (AD-20).
    private(set) var isConfirmingDiscard = false

    @ObservationIgnored private let clock: any ClockPort
    @ObservationIgnored private let motion: any MotionPort
    /// Zancada con la que nace cada sesión. Hoy es la de `formulas.json`; el perfil de
    /// calibración la sustituirá.
    @ObservationIgnored private let strideM: Double
    /// Tope de la reconciliación (AD-8), de `formulas.json`. Provisional hasta la 8.4.
    @ObservationIgnored private let reconciliationTimeoutS: TimeInterval
    /// Inicio del tramo en curso: el de la sesión o el de la última reanudación. La
    /// consulta de la reconciliación cubre `[segmentStart, ahora]`, con la misma semántica
    /// acumulada que el stream.
    @ObservationIgnored private var segmentStart: Date?
    /// Instante en que la app pasó a segundo plano con la sesión activa: el inicio del gap
    /// pendiente de reconciliar. Se limpia al terminar la reconciliación.
    @ObservationIgnored private var backgroundedAt: Date?
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

    init(clock: any ClockPort, motion: any MotionPort, strideM: Double, reconciliationTimeoutS: TimeInterval) {
        self.clock = clock
        self.motion = motion
        self.strideM = strideM
        self.reconciliationTimeoutS = reconciliationTimeoutS
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
        guard !isReconciling, var session, session.status == .active else { return }
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
        guard !isReconciling, var session, session.status == .paused else { return }
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
        guard !isReconciling, let status = session?.status, status != .finished else { return }
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
    ///
    /// Desde activa, antes de cerrar reconcilia hasta el instante del toque, para que el
    /// resumen incluya los pasos que el podómetro aún no había entregado; y cierra en ese
    /// instante. Sin dato no estima, salvo que haya un gap de background pendiente. Desde
    /// pausa no consulta: el tramo ya se cerró al pausar.
    func confirmFinish() async {
        isConfirmingFinish = false
        guard !isReconciling, let status = session?.status, status != .finished else { return }
        let now = clock.now
        if status == .active {
            await reconcile(until: now)
        }
        guard var session, session.status != .finished else { return }
        do {
            try session.finish(at: now)
        } catch {
            log.error("Finalizar rechazado: \(String(describing: error), privacy: .public)")
            return
        }
        stopCountingSteps()
        isConfirmingDiscard = false
        backgroundedAt = nil
        self.session = session
        metrics = session.metrics(at: now)
    }

    /// "Descartar" en el Estimated Banner: pide confirmación explícita (AD-20). Solo con
    /// pasos estimados en una sesión `active` o `paused`.
    func requestDiscardEstimated() {
        guard !isReconciling, let session, session.status != .finished, session.stepsEstimated > 0 else { return }
        isConfirmingDiscard = true
    }

    /// "Cancelar" (o cerrar) el diálogo de descarte: los estimados siguen.
    func cancelDiscardEstimated() {
        isConfirmingDiscard = false
    }

    /// "Descartar pasos estimados" en la confirmación: `stepsEstimated` vuelve a 0 y
    /// distancia y ritmo se recalculan sin ellos. Irreversible. Como `confirmFinish()`, no
    /// exige que el diálogo siga abierto.
    func confirmDiscardEstimated() {
        isConfirmingDiscard = false
        guard !isReconciling, var session, session.status != .finished, session.stepsEstimated > 0 else { return }
        do {
            try session.discardEstimatedSteps()
        } catch {
            log.error("Descartar estimados rechazado: \(String(describing: error), privacy: .public)")
            return
        }
        self.session = session
        metrics = session.metrics(at: clock.now)
    }

    /// La app pasó a segundo plano: con la sesión activa, abre el gap pendiente de
    /// reconciliar. Nunca pausa (CAP-1). Si ya hay uno pendiente (la app volvió a salir
    /// mientras reconciliaba), lo conserva.
    func appDidEnterBackground() {
        guard session?.status == .active, backgroundedAt == nil else { return }
        backgroundedAt = clock.now
    }

    /// La app vuelve a primer plano: con un gap pendiente y la sesión activa, reconcilia
    /// antes de soltar los comandos (AD-8). Volver mientras ya reconcilia no abre otra; en
    /// pausa no consulta ni estima.
    func appDidBecomeActive() async {
        guard !isReconciling, backgroundedAt != nil else { return }
        if session?.status == .active {
            await reconcile(until: clock.now)
        }
        backgroundedAt = nil
    }

    /// "Volver a Inicio" en el resumen: descarta la sesión finalizada (aún no hay
    /// persistencia) y cierra el modo de sesión. Solo con la sesión `finished`.
    func leaveSummary() {
        guard !isReconciling, session?.status == .finished else { return }
        session = nil
        metrics = nil
        isConfirmingFinish = false
        isConfirmingDiscard = false
        segmentStart = nil
        backgroundedAt = nil
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
    /// inicio de la sesión o el de la reanudación. Lo dado en background entra al volver
    /// por la reconciliación (`appDidBecomeActive()`), sin esperar a la siguiente muestra.
    private func countSteps(from start: Date) {
        segmentStart = start
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

    // MARK: - Reconciliación (AD-8)

    /// El sistema solo guarda 7 días de podómetro, y fuera de ese rango devuelve datos
    /// parciales sin avisar: un tramo más antiguo no se consulta (AD-8).
    private static let queryableHistoryS: TimeInterval = 7 * 24 * 60 * 60

    /// Reconciliación atómica hasta `end`, con la sesión `active`.
    ///
    /// Consulta el tramo, no el gap: `[segmentStart, end]` da el acumulado del tramo y
    /// entra por `record(_:)`, así que el máximo de `highestCumulativeSteps` evita contar dos
    /// veces lo que el stream entregue después. Un resultado menor que lo visto al empezar
    /// es incoherente y cuenta como sin dato. Sin dato, y solo con un gap de background
    /// pendiente, suma los pasos del `GapEstimator` para `[backgroundedAt, end]`.
    private func reconcile(until end: Date) async {
        guard session?.status == .active, let start = segmentStart else { return }
        isReconciling = true
        defer { isReconciling = false }
        // Un diálogo abierto antes de reconciliar se cierra: su confirmación se perdería en
        // silencio, y la de descartar podría borrar estimados que aún no había visto.
        isConfirmingFinish = false
        isConfirmingDiscard = false

        let seen = highestCumulativeSteps
        var sample: PedometerSample?
        if end.timeIntervalSince(start) <= Self.queryableHistoryS {
            sample = await queryWithinTimeout(from: start, to: end)
        } else {
            log.info("Tramo de más de 7 días: no se consulta y se estima")
        }

        // Nada muta entre `await` y aquí salvo las muestras del stream, que no cambian el
        // estado: los comandos están rechazados mientras reconcilia.
        guard var session, session.status == .active else { return }
        if let sample, sample.steps >= seen {
            record(sample)
            return
        }
        // Si el stream avanzó durante la consulta, su acumulado ya cubre el gap: el sistema sí
        // tenía el dato, y estimar lo contaría dos veces con una cadencia inflada.
        guard let gapStart = backgroundedAt, highestCumulativeSteps == seen else { return }
        let estimated = GapEstimator.steps(for: session, gapStart: gapStart, gapEnd: end)
        guard estimated > 0 else { return }
        do {
            try session.addEstimatedSteps(estimated)
        } catch {
            log.error("Pasos estimados rechazados: \(String(describing: error), privacy: .public)")
            return
        }
        log.info("Gap sin dato del sistema: \(estimated, privacy: .public) pasos estimados")
        self.session = session
        metrics = session.metrics(at: clock.now)
    }

    /// `motion.query` acotada por `reconciliationTimeoutS`. Un error o el timeout dan `nil`.
    ///
    /// Sin `withTaskGroup` a propósito: el grupo espera a sus hijos al salir y la consulta de
    /// CoreMotion no se puede cancelar, así que una consulta colgada bloquearía. La consulta y
    /// el temporizador compiten en tareas no estructuradas sobre una continuación que resuelve
    /// el primero; el resultado tardío se ignora.
    private func queryWithinTimeout(from start: Date, to end: Date) async -> PedometerSample? {
        let motion = self.motion
        let timeout = reconciliationTimeoutS
        let log = self.log
        let race = FirstResult<PedometerSample?>()
        Task.detached {
            do {
                race.resolve(try await motion.query(from: start, to: end))
            } catch {
                log.error("Consulta del podómetro fallida: \(String(describing: error), privacy: .public)")
                race.resolve(nil)
            }
        }
        let timer = Task.detached {
            try? await Task.sleep(for: .seconds(timeout))
            if race.resolve(nil) {
                log.error("La consulta del podómetro agotó el timeout de \(timeout, privacy: .public) s")
            }
        }
        let result = await race.value()
        timer.cancel()
        return result
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

/// El primer resultado de una carrera entre tareas no estructuradas. `resolve` gana solo la
/// primera vez; `value()` lo espera, aunque se llame después de resolverse.
private final class FirstResult<Value: Sendable>: Sendable {

    private enum State {
        case waiting(CheckedContinuation<Value, Never>?)
        case resolved(Value)
    }

    private let state = Mutex(State.waiting(nil))

    /// `true` si este resultado es el que gana.
    @discardableResult
    func resolve(_ value: Value) -> Bool {
        let waiter: CheckedContinuation<Value, Never>?? = state.withLock { state in
            guard case .waiting(let continuation) = state else { return .none }
            state = .resolved(value)
            return .some(continuation)
        }
        guard let waiter else { return false }
        waiter?.resume(returning: value)
        return true
    }

    func value() async -> Value {
        await withCheckedContinuation { continuation in
            let resolved: Value? = state.withLock { state in
                switch state {
                case .resolved(let value):
                    return value
                case .waiting:
                    state = .waiting(continuation)
                    return nil
                }
            }
            if let resolved { continuation.resume(returning: resolved) }
        }
    }
}
