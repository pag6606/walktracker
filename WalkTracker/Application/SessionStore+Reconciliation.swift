import Domain
import Foundation
import OSLog

/// Reconciliación atómica (1.5, AD-8): la consulta del tramo en curso al coprocesador,
/// acotada por `reconciliationTimeoutS`, y la degradación al `GapEstimator` sin dato.
///
/// Escribe `isReconciling` (solo aquí), cierra los diálogos de confirmación y, con estimados,
/// `session` y `metrics`. Lo que da la consulta entra por `record(_:fromQuery:)`. Llaman a
/// `reconcile(until:)` la vuelta a primer plano, finalizar desde activa y la restauración.
extension SessionStore {

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
    func reconcile(until end: Date) async {
        guard session?.status == .active, let start = segmentStart else { return }
        isReconciling = true
        defer { isReconciling = false }
        // Un diálogo abierto antes de reconciliar se cierra: su confirmación se perdería en
        // silencio, y la de descartar podría borrar estimados que aún no había visto.
        isConfirmingFinish = false
        isConfirmingDiscard = false

        let seen = highestCumulativeSteps
        let sessionStartedAt = session?.startedAt
        var sample: PedometerSample?
        if end.timeIntervalSince(start) <= Self.queryableHistoryS {
            let answer = await queryWithinTimeout(from: start, to: end, seen: seen, sessionStartedAt: sessionStartedAt)
            sample = answer.race.sample
            if let sessionStartedAt {
                measure(MeasurementLog.queryLine(
                    sessionStartedAt: sessionStartedAt,
                    start: start,
                    end: end,
                    result: answer.race.sample,
                    seen: seen,
                    durationMs: answer.durationMs,
                    outcome: answer.race.outcome(seen: seen)
                ))
            }
        } else {
            log.info("Tramo de más de 7 días: no se consulta y se estima")
        }

        // Durante la espera los comandos están rechazados, pero la sesión sí puede cambiar: las
        // muestras del stream suman pasos y el clima del inicio (2.1) puede adjuntarse. Por eso
        // se vuelve a leer aquí, y lo que llegó se conserva.
        guard var session, session.status == .active else { return }
        if let sample, sample.steps >= seen {
            record(sample, fromQuery: true)
            return
        }
        // Si el stream avanzó durante la consulta, su acumulado ya cubre el gap: el sistema sí
        // tenía el dato, y estimar lo contaría dos veces con una cadencia inflada.
        guard let gapStart = backgroundedAt else { return }
        guard highestCumulativeSteps == seen else {
            measure(MeasurementLog.estimateLine(
                sessionStartedAt: session.startedAt, gapStart: gapStart, gapEnd: end, steps: 0, skipped: .streamAdvanced
            ))
            return
        }
        let estimated = GapEstimator.steps(for: session, gapStart: gapStart, gapEnd: end)
        measure(MeasurementLog.estimateLine(sessionStartedAt: session.startedAt, gapStart: gapStart, gapEnd: end, steps: estimated))
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

    /// Resultado de `queryWithinTimeout`: quién ganó la carrera y, para la medición de la 8.4,
    /// cuánto tardó en resolverse, medido en la tarea que la ganó.
    private struct QueryAnswer {
        let race: QueryRace
        let durationMs: Int
    }

    /// `motion.query` acotada por `reconciliationTimeoutS`. Un error o el timeout dan `nil`.
    ///
    /// Sin `withTaskGroup` a propósito: el grupo espera a sus hijos al salir y la consulta de
    /// CoreMotion no se puede cancelar, así que una consulta colgada bloquearía. La consulta y
    /// el temporizador compiten en tareas no estructuradas sobre una continuación que resuelve
    /// el primero; el resultado tardío se ignora.
    ///
    /// La duración es la espera real (`ContinuousClock`), no la de `ClockPort`, como el propio
    /// timeout, y se toma en la tarea que gana: no incluye la vuelta al hilo principal. Una
    /// respuesta que llega tras el timeout se descarta, pero deja su línea `queryLate` con la
    /// duración real: es lo que la 8.4 mide para fijar `reconciliationTimeoutS`.
    private func queryWithinTimeout(from start: Date, to end: Date, seen: Int, sessionStartedAt: Date?) async -> QueryAnswer {
        let motion = self.motion
        let timeout = reconciliationTimeoutS
        let log = self.log
        let measure = self.measure
        let race = FirstResult<QueryResolution>()
        let startedAt = ContinuousClock.now
        Task.detached {
            let answer: QueryRace
            do {
                answer = .answered(try await motion.query(from: start, to: end))
            } catch {
                log.error("Consulta del podómetro fallida: \(String(describing: error), privacy: .public)")
                answer = .failed
            }
            let answeredAt = ContinuousClock.now
            guard !race.resolve(QueryResolution(race: answer, at: answeredAt)), let sessionStartedAt else { return }
            measure(MeasurementLog.lateQueryLine(
                sessionStartedAt: sessionStartedAt,
                start: start,
                end: end,
                result: answer.sample,
                seen: seen,
                durationMs: MeasurementLog.milliseconds(startedAt.duration(to: answeredAt)),
                outcome: answer.outcome(seen: seen)
            ))
        }
        let timer = Task.detached {
            try? await Task.sleep(for: .seconds(timeout))
            if race.resolve(QueryResolution(race: .timedOut, at: ContinuousClock.now)) {
                log.error("La consulta del podómetro agotó el timeout de \(timeout, privacy: .public) s")
            }
        }
        let resolution = await race.value()
        timer.cancel()
        return QueryAnswer(race: resolution.race, durationMs: MeasurementLog.milliseconds(startedAt.duration(to: resolution.at)))
    }
}

/// Quién ganó la carrera de `queryWithinTimeout`.
private enum QueryRace: Sendable {
    case answered(PedometerSample?)
    case failed
    case timedOut

    /// La muestra que decide: `nil` con error o timeout.
    var sample: PedometerSample? {
        if case .answered(let sample) = self { return sample }
        return nil
    }

    func outcome(seen: Int) -> MeasurementLog.QueryOutcome {
        switch self {
        case .answered(let sample): MeasurementLog.outcome(of: sample, seen: seen)
        case .failed: .error
        case .timedOut: .timeout
        }
    }
}

/// Resultado de la carrera con el instante en que lo resolvió la tarea que la ganó.
private struct QueryResolution: Sendable {
    let race: QueryRace
    let at: ContinuousClock.Instant
}
