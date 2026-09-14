import Foundation

/// Aggregate root de una caminata (domain-model.md §2, `domain.js:271` `createV3Session`).
///
/// Siempre válido: solo se materializa por `start(at:strideM:)`, que valida la zancada
/// en la frontera. Sus campos no se escriben desde fuera; las mutaciones (pasos,
/// distancia del sistema, pausas, cierre) entran como operaciones del agregado.
///
/// Ciclo de estados (domain-model.md §2): `active → paused → active → finished`. Pausar
/// solo desde `active`, reanudar solo desde `paused` y finalizar desde `active` o
/// `paused`; cualquier otra transición lanza `invalidTransition` y no muta. Una sesión
/// finalizada es **inmutable**: toda mutación lanza.
///
/// Distancia, ritmo y cadencia son derivadas: no se guardan, se calculan con
/// `metrics(at:)` y `MetricsCalculator` (AD-22).
public struct Session: Equatable, Sendable {

    public let startedAt: Date
    /// Instante del cierre; `nil` hasta finalizar.
    public private(set) var endedAt: Date?
    public private(set) var status: SessionStatus
    /// Pasos del coprocesador. Entero ≥ 0 que nunca baja.
    public private(set) var stepsMeasured: Int
    /// Pasos de la degradación del `GapEstimator`. Entero ≥ 0, siempre desglosado.
    public private(set) var stepsEstimated: Int
    /// Zancada en metros, > 0 y finita. Congelada: recalibrar nunca reescribe una sesión.
    public let strideM: Double
    /// Última distancia acumulada del sistema en metros, o `nil` si no la ha dado. Nunca
    /// baja. Cuando existe, sustituye a la derivada de los pasos medidos (CAP-4).
    public private(set) var systemDistanceM: Double?
    /// Segundos acumulados en pausas cerradas. Al finalizar desde pausa incluye la que
    /// estaba abierta.
    public private(set) var totalPausesS: TimeInterval
    /// Inicio de la pausa en curso: solo existe en `paused`.
    public private(set) var pausedAt: Date?
    /// Segundos netos de la sesión, redondeados al entero. Solo al finalizar: congela el
    /// cronómetro y es el denominador de ritmo y cadencia finales.
    public private(set) var durationS: Int?
    /// `totalPausesS` redondeado al entero (`pausesS` en el snapshot). Solo al finalizar.
    public private(set) var pausesS: Int?
    public let source: SessionSource

    private init(startedAt: Date, strideM: Double) {
        self.startedAt = startedAt
        self.endedAt = nil
        self.status = .active
        self.stepsMeasured = 0
        self.stepsEstimated = 0
        self.systemDistanceM = nil
        self.strideM = strideM
        self.totalPausesS = 0
        self.pausedAt = nil
        self.durationS = nil
        self.pausesS = nil
        self.source = .ios
    }

    /// Crea una sesión `active` que empieza en `now`.
    ///
    /// - Throws: `DomainError.invalidValue(field: "strideM")` si la zancada es ≤ 0 o no
    ///   finita. Se rechaza **antes** de crear el agregado.
    public static func start(at now: Date, strideM: Double) throws(DomainError) -> Session {
        try validateStride(strideM)
        return Session(startedAt: now, strideM: strideM)
    }

    /// La regla de la zancada, única para el agregado y para las constantes de
    /// `formulas.json`: > 0 y finita.
    public static func validateStride(_ strideM: Double) throws(DomainError) {
        guard strideM.isFinite, strideM > 0 else {
            throw .invalidValue(field: "strideM")
        }
    }

    /// Suma pasos medidos por el coprocesador (`domain.js:316` `addSteps`).
    ///
    /// Recibe un **incremento**, no el acumulado del podómetro: convertir muestras
    /// acumuladas en incrementos es de quien las consume (`SessionStore`). `0` no cambia
    /// nada. La distancia que recalcula el JS no se guarda aquí: se deriva en
    /// `metrics(at:)` (AD-22).
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión no está `active` (una
    ///   pausada o finalizada no cuenta pasos); `DomainError.invalidValue(field: "steps")`
    ///   si `count` es negativo o desbordaría el contador. En ambos casos no muta.
    public mutating func addMeasuredSteps(_ count: Int) throws(DomainError) {
        guard status == .active else {
            throw .invalidTransition(from: status.rawValue, to: "addMeasuredSteps")
        }
        guard count >= 0 else { throw .invalidValue(field: "steps") }
        guard count > 0 else { return }
        let (total, overflow) = stepsMeasured.addingReportingOverflow(count)
        guard !overflow else { throw .invalidValue(field: "steps") }
        stepsMeasured = total
    }

    /// Suma pasos estimados por el `GapEstimator` (`domain.js:330` `addEstimatedSteps`).
    ///
    /// Solo es la degradación de la reconstrucción del background: quien llama ya consultó
    /// al sistema sin dato (CAP-3). Se guardan aparte de `stepsMeasured`, siempre
    /// desglosados. `0` no cambia nada.
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión no está `active` (no se estima
    ///   en pausa ni sobre una finalizada); `DomainError.invalidValue(field: "steps")` si
    ///   `count` es negativo o desbordaría el contador. En ambos casos no muta.
    public mutating func addEstimatedSteps(_ count: Int) throws(DomainError) {
        guard status == .active else {
            throw .invalidTransition(from: status.rawValue, to: "addEstimatedSteps")
        }
        guard count >= 0 else { throw .invalidValue(field: "steps") }
        guard count > 0 else { return }
        let (total, overflow) = stepsEstimated.addingReportingOverflow(count)
        guard !overflow else { throw .invalidValue(field: "steps") }
        stepsEstimated = total
    }

    /// Descarta todos los pasos estimados: `stepsEstimated` vuelve a 0 y distancia y ritmo,
    /// que se derivan en `metrics(at:)`, se recalculan sin ellos. Irreversible: la
    /// confirmación es de la UI (AD-20).
    ///
    /// Se permite en `active` y en `paused`, porque el Estimated Banner también se ve en
    /// pausa (diverge a propósito de la v3, cuyo `addEstimatedSteps(-n)` lanzaba en pausa).
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión está `finished`. No muta.
    public mutating func discardEstimatedSteps() throws(DomainError) {
        guard status != .finished else {
            throw .invalidTransition(from: status.rawValue, to: "discardEstimatedSteps")
        }
        stepsEstimated = 0
    }

    /// Registra la distancia **acumulada desde el inicio** que da el sistema, en metros.
    ///
    /// Como los pasos, nunca baja: una muestra menor que la guardada no resta (3400 →
    /// 3390 sigue en 3400).
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión no está `active`;
    ///   `DomainError.invalidValue(field: "distanceM")` si `meters` es negativo o no
    ///   finito. En ambos casos no muta.
    public mutating func recordSystemDistance(_ meters: Double) throws(DomainError) {
        guard status == .active else {
            throw .invalidTransition(from: status.rawValue, to: "recordSystemDistance")
        }
        guard meters.isFinite, meters >= 0 else { throw .invalidValue(field: "distanceM") }
        if let current = systemDistanceM, meters <= current { return }
        systemDistanceM = meters
    }

    /// Pausa la sesión en `now` (`domain.js:176` `pause`): el cronómetro se congela.
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión no está `active`. Pausar una
    ///   sesión ya pausada **lanza**: diverge a propósito de la v3, que reescribía
    ///   `pausedAtMs` y perdía la pausa en curso (domain-model.md §2). No muta.
    public mutating func pause(at now: Date) throws(DomainError) {
        guard status == .active else {
            throw .invalidTransition(from: status.rawValue, to: SessionStatus.paused.rawValue)
        }
        status = .paused
        pausedAt = now
    }

    /// Reanuda la sesión en `now` (`domain.js:187` `resume`): la pausa se acumula en
    /// `totalPausesS` y el cronómetro sigue desde donde se detuvo.
    ///
    /// Una pausa negativa (el reloj del sistema fue hacia atrás) cuenta como 0: nunca
    /// devuelve tiempo en movimiento que no pasó.
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión no está `paused`. No muta.
    public mutating func resume(at now: Date) throws(DomainError) {
        guard status == .paused, let pausedAt else {
            throw .invalidTransition(from: status.rawValue, to: SessionStatus.active.rawValue)
        }
        totalPausesS += Self.pauseS(from: pausedAt, to: now)
        self.pausedAt = nil
        status = .active
    }

    /// Finaliza la sesión en `now` (`domain.js:344` `finishV3`).
    ///
    /// Desde pausa, primero acumula la pausa abierta y después cierra (domain-model.md §2).
    /// `durationS` es el tiempo neto redondeado y `pausesS`, las pausas redondeadas; ritmo
    /// y cadencia finales salen de `durationS` sin volver a restar las pausas (`:351-358`).
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión ya está `finished`. No muta.
    public mutating func finish(at now: Date) throws(DomainError) {
        guard status != .finished else {
            throw .invalidTransition(from: status.rawValue, to: SessionStatus.finished.rawValue)
        }
        if let pausedAt {
            totalPausesS += Self.pauseS(from: pausedAt, to: now)
            self.pausedAt = nil
        }
        let elapsed = Chronometer.elapsedS(startedAt: startedAt, totalPausesS: totalPausesS, now: now)
        durationS = Self.roundedSeconds(elapsed)
        pausesS = Self.roundedSeconds(totalPausesS)
        endedAt = now
        status = .finished
    }

    /// Tiempo transcurrido en `now`, que el llamante lee de `ClockPort`.
    ///
    /// - `active`: `(now − startedAt) − totalPausesS`.
    /// - `paused`: congelado en el inicio de la pausa, sea cual sea `now`. Se mide en
    ///   `pausedAt` en vez de restar la pausa abierta porque así no depende de la guarda
    ///   `pausedAt > startedAt` del cronómetro: una pausa en el mismo instante del inicio
    ///   también congela.
    /// - `finished`: `durationS`.
    public func elapsedS(at now: Date) -> TimeInterval {
        switch status {
        case .active:
            Chronometer.elapsedS(startedAt: startedAt, totalPausesS: totalPausesS, now: now)
        case .paused:
            Chronometer.elapsedS(startedAt: startedAt, totalPausesS: totalPausesS, now: pausedAt ?? now)
        case .finished:
            TimeInterval(durationS ?? 0)
        }
    }

    private static func pauseS(from pausedAt: Date, to now: Date) -> TimeInterval {
        let seconds = now.timeIntervalSince(pausedAt)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    /// `Math.round` de la v3 para segundos ≥ 0: la mitad sube.
    private static func roundedSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let rounded = seconds.rounded(.toNearestOrAwayFromZero)
        return rounded < Double(Int.max) ? Int(rounded) : Int.max
    }

    /// Distancia, ritmo y cadencia en `now`, que el llamante lee de `ClockPort` (CAP-4).
    ///
    /// - **Distancia:** la del sistema más los estimados × zancada si el sistema la dio;
    ///   si no, `(stepsMeasured + stepsEstimated) × strideM`.
    /// - **Ritmo:** solo con `distanceM ≥ minPaceDistanceM`; si no, `nil`.
    /// - **Cadencia:** solo `stepsMeasured`, sobre el tiempo neto transcurrido (la v3 y su
    ///   regresión `session-v3-tests.js:183`).
    ///
    /// El tiempo es el de `elapsedS(at:)`: en pausa no avanza y en una sesión finalizada
    /// es `durationS`, así que las métricas finales quedan congeladas.
    public func metrics(at now: Date) -> SessionMetrics {
        let elapsed = elapsedS(at: now)
        do {
            let distance: Double
            if let systemDistanceM {
                let estimated = try MetricsCalculator.distanceM(stepsMeasured: 0, stepsEstimated: stepsEstimated, strideM: strideM)
                distance = systemDistanceM + estimated
            } else {
                distance = try MetricsCalculator.distanceM(stepsMeasured: stepsMeasured, stepsEstimated: stepsEstimated, strideM: strideM)
            }
            let pace = distance >= MetricsCalculator.minPaceDistanceM
                ? try MetricsCalculator.paceSecPerKm(movingS: elapsed, distanceM: distance)
                : nil
            let cadence = try MetricsCalculator.cadenceSpm(stepsMeasured: stepsMeasured, activeSeconds: elapsed)
            return SessionMetrics(distanceM: distance, paceSecPerKm: pace, cadenceSpm: cadence)
        } catch {
            // Inalcanzable: el agregado garantiza pasos ≥ 0, zancada > 0 y finita, distancia
            // del sistema ≥ 0 y finita, y `Chronometer` un tiempo ≥ 0 y finito.
            preconditionFailure("Session viola sus invariantes al calcular métricas: \(error)")
        }
    }
}
