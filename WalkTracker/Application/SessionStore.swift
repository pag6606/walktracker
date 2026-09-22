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
/// reanudar, finalizar y el resumen; la 1.5, la reconstrucción del background por consulta
/// al sistema y el descarte de pasos estimados; la 1.6, la recuperación tras un force-quit; la
/// 2.1, el clima del inicio; la 2.2, la frase motivacional del arranque; la 5.1, el registro
/// inmutable de la caminata cerrada en el historial.
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
///
/// **Recuperación (1.6, AD-9, AD-18).** Es el único escritor de `activeSession.json`: guarda
/// un snapshot al iniciar, pausar, reanudar, pasar a background y reconciliar, y con la
/// muestra que llega al menos `autosaveIntervalS` después del último guardado; lo borra al
/// finalizar. Nunca con un temporizador (AD-21): quieto no hay muestras ni escrituras.
/// `restoreOnLaunch()` lo lee al arrancar: restaura y reconcilia la sesión antes de
/// presentarla, o cierra la huérfana en su último dato real.
///
/// **Organización (retro del Epic 1, A-1).** Un solo tipo repartido en extensiones, cada una
/// en su fichero y con su responsabilidad:
/// - este fichero: estado, intenciones de la sesión, fases de la escena y el reset de sesión;
/// - `SessionStore+StartFlow.swift`: "Iniciar caminata" y el permiso de Motion & Fitness;
/// - `SessionStore+StepCounting.swift`: el stream del podómetro, `record` y el tope de R4;
/// - `SessionStore+Reconciliation.swift`: la reconciliación atómica y su carrera con el timeout;
/// - `SessionStore+Recovery.swift`: restaurar al arrancar, la huérfana y el snapshot;
/// - `SessionStore+Weather.swift`: la pre-pantalla de ubicación y la captura del clima del inicio;
/// - `SessionStore+Motivation.swift`: la elección de la frase del arranque y su overlay;
/// - `SessionStore+History.swift`: el registro de la caminata cerrada y su entrega a `HistoryStore`.
///
/// Las propiedades que escriben varias extensiones tienen acceso de módulo (Swift no deja a
/// una extensión de otro fichero ver lo `private`). **Invariante:** solo los ficheros
/// `SessionStore*.swift` las escriben; vistas, adapters y tests solo las leen. El compilador
/// ya no lo impide: lo comprueba `Scripts/check-project-shape.sh` (sección 6) en cada build,
/// que falla si `WalkTracker/UI` o `WalkTracker/App` asignan una propiedad del store, llaman a
/// sus pasos internos (`persist`, `record`, `reconcile`…) o tocan sus puertos.
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

    /// Pre-pantalla de ubicación sobre la sesión ya abierta (2.1, AD-11).
    enum LocationPrompt: Equatable, Sendable {
        /// "¿Añadir el clima a tus caminatas?" con "Permitir" y "Ahora no".
        case offering
        /// El diálogo del sistema está en pantalla. Un segundo toque no hace nada.
        case requesting
    }

    /// Por qué el último intento de iniciar no abrió sesión, para la alerta de Inicio.
    enum StartFailure: Equatable, Sendable {
        /// El dominio rechazó crear la sesión.
        case invalidSession(DomainError)
        /// Tras pedirlo, el permiso sigue sin decidir (fallo transitorio): se reintenta
        /// con el siguiente toque.
        case permissionUnresolved
    }

    /// Fase de la escena, sin depender de SwiftUI: la vista traduce la suya.
    enum ScenePhase: Equatable, Sendable {
        case active
        /// Centro de control, el diálogo del sistema: no es un gap, el podómetro sigue.
        case inactive
        case background
    }

    // MARK: - Estado observable
    //
    // Todo con escritura de módulo: lo escriben las extensiones de `SessionStore*.swift` y
    // nadie más.

    /// La sesión en curso, o `nil` antes de iniciar ("idle"). La escriben las intenciones,
    /// el conteo, la reconciliación y la recuperación.
    var session: Session?
    /// Hay una sesión abierta y la UI la presenta como modo a pantalla completa (AD-14).
    /// Guardado aparte de `session` a propósito: cada muestra del podómetro muta la
    /// sesión, y quien solo necesita saber si hay una no debe redibujarse por ello.
    ///
    /// Sigue en `true` con la sesión finalizada, mientras se muestra su resumen dentro
    /// del mismo modo; pasa a `false` al salir del resumen. **Invariante:** en `true` solo
    /// cuando la sesión ya está presentable (abierta, restaurada y reconciliada, o huérfana
    /// cerrada); nunca a mitad de `restoreOnLaunch()`.
    var hasSession = false
    /// "Finalizar" pidió confirmación y el diálogo está en pantalla (AD-20). Lo cierran
    /// también la reconciliación y el reset.
    var isConfirmingFinish = false
    /// Paso del flujo de inicio (`SessionStore+StartFlow.swift`).
    var startFlow: StartFlow = .idle
    /// Motivo del último inicio fallido, hasta que Inicio lo reconoce.
    var startFailure: StartFailure?
    /// Distancia, ritmo y cadencia de la sesión, o `nil` sin sesión. Se fijan al abrirla y
    /// se recalculan con **cada muestra** del coprocesador, no con el tick de 1 Hz
    /// (AD-21): con el teléfono quieto no llegan muestras y se quedan en su último valor.
    /// **Invariante:** se reasigna junto con cada escritura de `session`.
    var metrics: SessionMetrics?
    /// El stream del podómetro sigue abierto. Pasa a `false` si el sistema lo termina.
    var isCountingSteps = false
    /// Reconciliación atómica en curso (AD-8): las intenciones de comando no hacen nada y la
    /// UI deshabilita los controles. **Invariante:** solo `reconcile(until:)` lo pone en
    /// `true`, y lo devuelve a `false` al salir.
    var isReconciling = false
    /// "Descartar" pidió confirmación y el diálogo está en pantalla (AD-20).
    var isConfirmingDiscard = false
    /// La sesión se acaba de restaurar al relanzar la app: la vista muestra "Sesión
    /// recuperada" 3 s y después llama a `dismissRecoveredNotice()`. Volver de background
    /// nunca lo enciende.
    var showsRecoveredNotice = false
    /// La captura del clima de la sesión está en curso: la tarjeta de clima espera sin mostrar
    /// ceros. Lo escribe `SessionStore+Weather.swift`.
    var isCapturingWeather = false
    /// Pre-pantalla de ubicación en pantalla, o `nil`. No bloquea el conteo ni los controles.
    var locationPrompt: LocationPrompt?
    /// La frase del arranque **mientras su overlay está en pantalla**, o `nil` (2.2).
    ///
    /// **No es `session.quoteId`, y la diferencia importa.** `quoteId` es del agregado y viaja
    /// en el snapshot, así que una sesión recuperada tras un force-quit vuelve con él; esto
    /// solo lo enciende `openSession()`, así que esa sesión recuperada **no** vuelve a ver el
    /// overlay. "Ya mostrada" y "hay quoteId" no son lo mismo.
    ///
    /// Lo apaga `dismissQuote()`: el tap y los 3 s son la misma intención.
    var quote: Quote?
    /// La caminata que se acaba de cerrar **no se ha podido guardar en el historial** (5.1): el
    /// resumen lo dice antes de dejar salir, y el snapshot NO se ha borrado, así que la caminata
    /// se recupera al relanzar la app.
    ///
    /// Es estado observable del store y no de la vista (sección 6 del gate). Lo escriben
    /// `SessionStore+History.swift` y el reset; la pantalla solo lo pinta.
    var finishedWalkNotPersisted = false
    /// Los logros que **el cierre de esta caminata** ha desbloqueado y que ya están escritos en
    /// `achievements.json` (3.2). Vacío mientras no se haya evaluado nada, y en toda sesión que
    /// no cuente para logros (una huérfana, AD-18).
    ///
    /// **Es la señal, no la celebración.** Esta historia produce el desbloqueo y esto; la
    /// celebración visible es de la 3.4 y la sección de logros del resumen, de la 3.5. Lleva las
    /// definiciones del catálogo —nombre y emoji incluidos— para que quien pinte no vuelva a
    /// buscarlas.
    ///
    /// **`weekly_goal` nunca aparece aquí** (AD-25): no lo evalúa este camino y no produce
    /// celebración propia; quien celebra la meta es el anillo, una vez por semana.
    ///
    /// Lo escriben `SessionStore+History.swift` y el reset; la pantalla solo lo lee.
    var unlockedAchievements: [AchievementDefinition] = []

    // MARK: - Dependencias

    @ObservationIgnored let clock: any ClockPort
    @ObservationIgnored let motion: any MotionPort
    /// Zancada **por omisión**, la de `formulas.json`. Es el valor de quien nunca recalibró:
    /// el único sitio del producto donde vive el 0,655.
    ///
    /// **No es la zancada de la sesión, y el nombre lo dice a propósito** (2.3). La de cada
    /// sesión se resuelve al abrirla, contra el override de `settings`, en `openSession()`:
    /// leerla aquí —en el init del store— haría que una recalibración solo surtiera efecto
    /// tras relanzar la app, sin que fallara ningún test.
    @ObservationIgnored let defaultStrideM: Double
    /// Tope de la reconciliación (AD-8), de `formulas.json`. Fijado en la 8.4.
    @ObservationIgnored let reconciliationTimeoutS: TimeInterval
    /// Snapshot de la sesión viva (AD-9). Este store es su único escritor (AD-16).
    @ObservationIgnored let storage: any StoragePort
    /// Umbral de la sesión huérfana (AD-18), de `formulas.json`. Valor decidido, fijado en la 8.4.
    @ObservationIgnored let orphanSessionThresholdS: TimeInterval
    /// Gap máximo estimable (R1), de `formulas.json`. Por encima no se estima nada.
    @ObservationIgnored let maxEstimableGapS: TimeInterval
    /// Ubicación aproximada para el clima (2.1). El adapter posee el permiso (AD-11).
    @ObservationIgnored let location: any LocationPort
    /// Clima actual de Open-Meteo (2.1): la única llamada de red.
    @ObservationIgnored let weather: any WeatherPort
    /// Tope de cada paso de la captura del clima: la lectura de ubicación y la petición a
    /// Open-Meteo tienen 3 s cada una (AR-12).
    @ObservationIgnored let weatherStepTimeoutS: TimeInterval
    /// El banco de frases del bundle (2.2). Vacío si `quotes.json` falta o no valida: sin
    /// frase, la caminata sigue igual (decisión de Paul, a diferencia de AD-5).
    @ObservationIgnored let quotes: QuoteBank
    /// Azar inyectado para elegir la frase (AD-3, AD-10): el dominio no lo genera.
    @ObservationIgnored let random: any RandomPort
    /// Dueño de `settings.json` (AD-16). Este store le pide la ventana de frases recientes y
    /// le comunica la mostrada; nunca toca el fichero.
    @ObservationIgnored let settings: SettingsStore
    /// Dueño de `sessions.json` (AD-16, 5.1). Este store le entrega la caminata cerrada y le
    /// pregunta si una sesión ya está guardada; nunca toca el fichero. Como con `settings`, la
    /// sección 9b del gate impide asignarle estado o llamar a su `save()` desde aquí.
    @ObservationIgnored let history: HistoryStore
    /// Dueño de `achievements.json` **del sandbox** (AD-16, 5.1). Este store le entrega los
    /// logros que el motor da por cumplidos al cerrar (3.2); nunca toca el fichero. Como con
    /// `settings` y `history`, la sección 9b del gate impide asignarle estado o llamar a su
    /// `save()` desde aquí.
    ///
    /// **Obligatorio, y sin valor por omisión**, por la misma razón que los tres colaboradores de
    /// `SettingsStore` desde la 3.1: un fichero, un dueño, **y una sola instancia**. Un segundo
    /// `AchievementsStore` sobre el mismo almacenamiento sería un segundo lector, y el desbloqueo
    /// escrito por uno no lo vería el otro.
    @ObservationIgnored let achievements: AchievementsStore
    /// El catálogo congelado de los 14 logros, ya validado (AD-5). Lo carga `CompositionRoot` del
    /// bundle y llega aquí para dárselo al motor: la evaluación es Swift, pero **qué** se evalúa
    /// es dato, y en este fichero no hay ni una clave de logro escrita.
    @ObservationIgnored let achievementCatalog: AchievementCatalog
    @ObservationIgnored let log = Logger(subsystem: "com.walktracker.app", category: "SessionStore")
    /// Destino de las líneas de medición de la 8.4 (`MeasurementLog`). Solo observa: nada
    /// del comportamiento depende de él. Los tests lo sustituyen para leer las líneas.
    @ObservationIgnored let measure: @Sendable (String) -> Void

    // MARK: - Estado compartido entre las extensiones (lección L3 de la retro)
    //
    // Sin observar: no se pinta. Cada uno con quién lo escribe y su invariante. Todos, salvo
    // `didAttemptRestore`, vuelven a su valor inicial en `resetSessionState()`.

    /// Inicio del tramo en curso: el de la sesión o el de la última reanudación. La
    /// consulta de la reconciliación cubre `[segmentStart, ahora]`, con la misma semántica
    /// acumulada que el stream. Lo fijan `countSteps(from:restoring:)` y la restauración.
    @ObservationIgnored var segmentStart: Date?
    /// Instante en que la app pasó a segundo plano con la sesión activa: el inicio del gap
    /// pendiente de reconciliar. Se fija en `appDidEnterBackground()` (y con `savedAt` al
    /// restaurar) y se limpia al terminar la reconciliación, al finalizar y en el reset.
    @ObservationIgnored var backgroundedAt: Date?
    /// `session.stepsMeasured` en el instante en que se abrió el gap pendiente
    /// (`backgroundedAt`). Es la base de las dos primeras defensas de la estimación (R1): si
    /// los medidos crecieron desde entonces, el stream ya trajo los pasos del gap y no se
    /// estima; y la cadencia del `GapEstimator` sale de estos pasos, no de los de ahora.
    /// Se fija y se limpia siempre junto a `backgroundedAt`.
    @ObservationIgnored var stepsMeasuredAtGapStart: Int?
    /// Mayor acumulado del podómetro visto en el tramo en curso, que suben la consulta y el
    /// stream (`record`). Los incrementos se miden contra él, no contra la última muestra:
    /// 350 → 340 → 360 suma 10, no 20. Vuelve a 0 (o al del snapshot) al abrir un tramo.
    @ObservationIgnored var highestCumulativeSteps = 0
    /// Distancia del sistema acumulada al abrir el tramo en curso. Cada stream da la
    /// distancia desde su propio inicio, así que la de la sesión es esta base más la del
    /// tramo: sigue siendo acumulada desde el inicio y nunca baja. La fija
    /// `countSteps(from:restoring:)` (o la restauración).
    @ObservationIgnored var distanceBaseM: Double = 0
    /// Último dato real del coprocesador, que recorta una sesión huérfana (AD-18): el `end` de
    /// la última muestra **del stream** que sumó pasos. La consulta nunca lo mueve. Tras un gap
    /// puede quedarse en su inicio en vez de en el `end` de la muestra (`lastSampleAtCap`).
    @ObservationIgnored var lastSampleAt: Date?
    /// Tope de `lastSampleAt` tras un gap (R4): su inicio. Se fija al pasar a background con la
    /// sesión activa (`backgroundedAt`) y al restaurar una activa (`savedAt`); con uno ya
    /// pendiente se conserva el más temprano. La primera muestra del stream con `end` posterior
    /// al tope trae el acumulado del gap con `end ≈ ahora`, que no es el último paso real: lo
    /// libera, sume pasos o no. Una con `end` anterior (ya encolada antes del gap) no lo libera.
    /// Pausar, finalizar y salir del resumen también lo liberan.
    @ObservationIgnored var lastSampleAtCap: Date?
    /// Instante del último snapshot guardado, para espaciar el autosave por muestras. Solo lo
    /// escribe `persist()` cuando el guardado sale bien.
    @ObservationIgnored var lastSavedAt: Date?
    /// El registro de la caminata cerrada que **no se pudo escribir** en el historial (5.1), para
    /// reintentarlo al salir del resumen. `nil` cuando no hay nada pendiente.
    ///
    /// **Existe porque el snapshot no es una copia eterna.** Mientras esté sin guardar, el
    /// snapshot de esa caminata sigue en disco y relanzar la recupera; pero si Paul empieza otra
    /// caminata en esta misma ejecución, el primer `persist()` de la nueva lo sobrescribe. El
    /// reintento de `leaveSummary()` acota la pérdida a "el disco falló dos veces".
    /// Lo escriben `SessionStore+History.swift` y el reset.
    @ObservationIgnored var unsavedFinishedRecord: SessionRecord?
    /// `restoreOnLaunch()` ya corrió: relanzar la tarea de la escena no restaura dos veces. Es
    /// del arranque, no de una sesión: el reset no lo toca.
    @ObservationIgnored var didAttemptRestore = false
    /// Consumo de `motion.updates(from:)`. Expuesto para que los tests esperen su final. Lo
    /// abre `countSteps(from:restoring:)` y lo cancela `stopCountingSteps()`.
    @ObservationIgnored var stepCounting: Task<Void, Never>?
    /// La captura del clima en curso. La abre `SessionStore+Weather.swift` y la cancela
    /// `cancelWeatherCapture()`, al finalizar y en el reset.
    @ObservationIgnored var weatherCapture: Task<Void, Never>?
    /// Paul dijo "Ahora no" en la pre-pantalla de ubicación: no vuelve a salir al iniciar
    /// mientras la app siga abierta. Es de la ejecución, no de una sesión: el reset no lo toca.
    /// Recordarlo entre lanzamientos es de la 2.3, junto con ofrecer el permiso desde Ajustes:
    /// la 2.2 dejó `settings.json` y `SettingsStore`, que era la pieza que faltaba, pero la
    /// otra mitad del diferido necesita la pantalla de Ajustes (ver `deferred-work.md`).
    @ObservationIgnored var declinedLocationPromptThisLaunch = false

    // MARK: - Estado de la escena (privado de este fichero)

    /// La escena pasó por `.background` (p. ej. un viaje a Ajustes) desde el último `.active`.
    /// Solo lo escribe `scenePhaseDidChange(to:)`. Es de la app, no de una sesión: el reset no
    /// lo toca.
    @ObservationIgnored private var returnedFromBackground = false

    /// Espacio mínimo entre dos guardados por muestras (AD-9, domain-model.md §8: "autosave
    /// del snapshot cada 10 s").
    static let autosaveIntervalS: TimeInterval = 10
    /// Tope de cada paso de la captura del clima: 3 s (AR-12, v3 AD-14).
    static let weatherStepTimeoutS: TimeInterval = 3

    init(
        clock: any ClockPort,
        motion: any MotionPort,
        storage: any StoragePort,
        defaultStrideM: Double,
        reconciliationTimeoutS: TimeInterval,
        orphanSessionThresholdS: TimeInterval,
        maxEstimableGapS: TimeInterval,
        location: any LocationPort,
        weather: any WeatherPort,
        settings: SettingsStore,
        history: HistoryStore,
        achievements: AchievementsStore,
        achievementCatalog: AchievementCatalog,
        quotes: QuoteBank = .empty,
        random: any RandomPort = SystemRandom(),
        weatherStepTimeoutS: TimeInterval = SessionStore.weatherStepTimeoutS,
        measure: @escaping @Sendable (String) -> Void = MeasurementLog.record
    ) {
        self.clock = clock
        self.motion = motion
        self.storage = storage
        self.defaultStrideM = defaultStrideM
        self.reconciliationTimeoutS = reconciliationTimeoutS
        self.orphanSessionThresholdS = orphanSessionThresholdS
        self.maxEstimableGapS = maxEstimableGapS
        self.location = location
        self.weather = weather
        self.settings = settings
        self.history = history
        self.achievements = achievements
        self.achievementCatalog = achievementCatalog
        self.quotes = quotes
        self.random = random
        self.weatherStepTimeoutS = weatherStepTimeoutS
        self.measure = measure
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

    // MARK: - Intenciones de la sesión

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
        measureTransition(.pause, session, at: now)
        persist()
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
        measureTransition(.resume, session, at: now)
        persist()
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
    ///
    /// **Y guarda la caminata** (5.1). Entre materializar las métricas y borrar el snapshot está
    /// el único instante en que coexisten la sesión finalizada y sus métricas congeladas: ese es
    /// el punto de escritura del historial, y el mismo desde el que se evalúan los logros (3.2,
    /// AD-17), **después** de un guardado con éxito (decisión D1). El orden es **guardar primero y
    /// borrar el snapshot solo si el guardado fue bien**: si falla, el snapshot sigue ahí y la
    /// caminata se recupera al relanzar, con el resumen diciéndolo antes de dejar salir.
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
        cancelWeatherCapture()
        // El overlay de la frase tampoco sobrevive al final de la caminata: lo que viene es el
        // resumen. El `quoteId` sigue en el agregado; esto solo apaga la presentación.
        quote = nil
        isConfirmingDiscard = false
        backgroundedAt = nil
        stepsMeasuredAtGapStart = nil
        self.session = session
        let finalMetrics = session.metrics(at: now)
        metrics = finalMetrics
        measureTransition(.finish, session, at: now)
        // Guardar ANTES de borrar: el snapshot es la única otra copia de esta caminata.
        if saveFinishedWalk(session, metrics: finalMetrics) {
            clearSnapshot()
        }
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
        measureTransition(.discardEstimated, session, at: clock.now)
        persist()
    }

    /// "Sesión recuperada" ya estuvo en pantalla sus 3 s.
    func dismissRecoveredNotice() {
        showsRecoveredNotice = false
    }

    /// "Volver a Inicio" en el resumen: descarta la sesión finalizada —también la huérfana
    /// cerrada al arrancar— y cierra el modo de sesión. Solo con la sesión `finished`.
    ///
    /// Desde la 5.1 la caminata ya no se pierde al salir: vive en `sessions.json`. Lo único que
    /// se descarta aquí es el estado en memoria de la sesión.
    ///
    /// **Último reintento del guardado.** Si el historial falló al cerrar, se intenta otra vez
    /// antes de soltar la sesión: es el último instante en que el registro sigue a mano. Si
    /// también falla, el snapshot sigue en disco y la caminata vuelve al relanzar.
    /// **Los logros que desbloquee el reintento se escriben, pero NO se anuncian.** El reintento
    /// puede evaluar (D1b) y `unlockedAchievements` se llena un instante antes de que
    /// `resetSessionState()` lo vacíe. **Se deja morir a propósito, y no es un olvido:** el único
    /// destino de esta intención es Inicio, así que el resumen ya no está en pantalla y no hay
    /// dónde celebrar; inventar una celebración que aparezca fuera del resumen sería decidir por
    /// la 3.4, que es su dueña. El desbloqueo, que es lo irrevocable, sí queda en
    /// `achievements.json` y lo enseña el grid de la 3.3. Lo fija
    /// `SessionStoreAchievementsTests`, "El reintento escribe los logros pero NO los anuncia".
    func leaveSummary() {
        guard !isReconciling, session?.status == .finished else { return }
        retrySavingFinishedWalk()
        resetSessionState()
    }

    /// Devuelve a su valor inicial **todo** el estado de una sesión cerrada. Es el único punto
    /// de reset: un campo nuevo de sesión se añade aquí, y no en cada salida.
    ///
    /// Fuera, a propósito: las dependencias; `startFlow` y `startFailure`, que son del flujo de
    /// inicio y solo cambian sin sesión; `isReconciling`, que solo vive dentro de
    /// `reconcile(until:)`; y `didAttemptRestore`, `returnedFromBackground` y
    /// `declinedLocationPromptThisLaunch`, que son del arranque, de la escena y de la ejecución,
    /// no de una sesión.
    private func resetSessionState() {
        session = nil
        metrics = nil
        hasSession = false
        isConfirmingFinish = false
        isConfirmingDiscard = false
        showsRecoveredNotice = false
        isCountingSteps = false
        // Cancelar antes de soltarla: un stream vivo no puede seguir entregando a la sesión siguiente.
        stepCounting?.cancel()
        stepCounting = nil
        segmentStart = nil
        backgroundedAt = nil
        stepsMeasuredAtGapStart = nil
        highestCumulativeSteps = 0
        distanceBaseM = 0
        lastSampleAt = nil
        lastSampleAtCap = nil
        lastSavedAt = nil
        quote = nil
        finishedWalkNotPersisted = false
        unsavedFinishedRecord = nil
        // La señal de logros es de ESTE cierre: la caminata siguiente no hereda la celebración de
        // la anterior. El desbloqueo, en cambio, ya está en `achievements.json` y es de por vida.
        unlockedAchievements = []
        // La captura del clima y la pre-pantalla: un clima tardío no llega a la sesión siguiente.
        cancelWeatherCapture()
    }

    // MARK: - Fases de la escena

    /// Único punto de entrada de las fases de la escena: la vista raíz pasa cada cambio y el
    /// store decide.
    ///
    /// - **`.background`:** abre el gap (`appDidEnterBackground()`) y recuerda que la app
    ///   salió, para releer el permiso a la vuelta.
    /// - **`.active`:** si antes pasó por `.background` (p. ej. un viaje a Ajustes), relee el
    ///   permiso de la pantalla bloqueante (`motionStatusMayHaveChanged()`). Solo entonces:
    ///   cerrar el diálogo del sistema es `inactive → active`, y en ese instante el permiso aún
    ///   puede leerse `.notDetermined`. Después lanza la reconciliación del gap pendiente
    ///   (`appDidBecomeActive()`), que no hace nada sin gap.
    /// - **`.inactive`:** nada. No es un gap: el podómetro sigue entregando.
    ///
    /// Ninguna fase pausa (CAP-1).
    ///
    /// - Returns: la tarea de la reconciliación lanzada con `.active`, para quien necesite
    ///   esperarla (los tests); la vista la ignora.
    @discardableResult
    func scenePhaseDidChange(to phase: ScenePhase) -> Task<Void, Never>? {
        switch phase {
        case .background:
            returnedFromBackground = true
            appDidEnterBackground()
            return nil
        case .active:
            if returnedFromBackground {
                returnedFromBackground = false
                motionStatusMayHaveChanged()
            }
            return Task { await appDidBecomeActive() }
        case .inactive:
            return nil
        }
    }

    /// La app pasó a segundo plano: guarda el snapshot y, con la sesión activa, abre el gap
    /// pendiente de reconciliar y topa `lastSampleAt` en su inicio. Nunca pausa (CAP-1). Si ya
    /// hay un gap pendiente (la app volvió a salir mientras reconciliaba), lo conserva.
    ///
    /// Paso de `scenePhaseDidChange(to:)`; la UI no lo llama directamente.
    func appDidEnterBackground() {
        guard let status = session?.status, status != .finished else { return }
        if status == .active {
            let gapStart = backgroundedAt ?? clock.now
            backgroundedAt = gapStart
            // Los pasos del inicio del gap se conservan con él: si ya había uno pendiente,
            // siguen siendo los de entonces (R1).
            stepsMeasuredAtGapStart = stepsMeasuredAtGapStart ?? session?.stepsMeasured
            // Ya aquí, no al volver: la muestra de puesta al día puede llegar antes que la
            // vuelta a primer plano.
            capLastSampleAt(at: gapStart)
        }
        if let session { measureTransition(.background, session, at: clock.now) }
        persist()
    }

    /// La app vuelve a primer plano: con un gap pendiente y la sesión activa, reconcilia
    /// antes de soltar los comandos (AD-8). Volver mientras ya reconcilia no abre otra; en
    /// pausa no consulta ni estima.
    ///
    /// Paso de `scenePhaseDidChange(to:)`; la UI no lo llama directamente.
    func appDidBecomeActive() async {
        guard !isReconciling, backgroundedAt != nil else { return }
        if session?.status == .active {
            await reconcile(until: clock.now)
        }
        backgroundedAt = nil
        stepsMeasuredAtGapStart = nil
        if let session { measureTransition(.active, session, at: clock.now) }
        persist()
    }

    // MARK: - Medición

    /// Línea de medición de una transición de la sesión (8.4).
    func measureTransition(_ transition: MeasurementLog.Transition, _ session: Session, at instant: Date) {
        measure(MeasurementLog.sessionLine(transition: transition, session: session, at: instant))
    }
}
