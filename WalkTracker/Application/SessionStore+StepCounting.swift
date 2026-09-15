import Domain
import Foundation
import OSLog

/// Conteo de pasos (1.2, 1.3, AD-21): el stream acumulado del coprocesador por tramos, la
/// aplicación de cada muestra (`record`), el autosave por muestras y el tope de
/// `lastSampleAt` tras un gap (R4).
///
/// Escribe `segmentStart`, `highestCumulativeSteps`, `distanceBaseM`, `lastSampleAt`,
/// `lastSampleAtCap`, `isCountingSteps` y `stepCounting`; con cada muestra, `session` y
/// `metrics`. La consulta de la reconciliación también entra por `record(_:fromQuery:)`.
extension SessionStore {

    /// Consume las muestras **acumuladas desde `start`** del coprocesador (AD-21): el
    /// inicio de la sesión o el de la reanudación. Lo dado en background entra al volver
    /// por la reconciliación (`appDidBecomeActive()`), sin esperar a la siguiente muestra.
    ///
    /// Un tramo nuevo empieza sin pasos vistos y con la distancia de la sesión como base. Uno
    /// restaurado (`restoring`) conserva el máximo visto y la base del snapshot: el stream
    /// reabierto desde su inicio da acumulados que ya incluyen lo contado, y solo suma lo nuevo.
    func countSteps(from start: Date, restoring segment: (steps: Int, distanceBaseM: Double)? = nil) {
        segmentStart = start
        highestCumulativeSteps = segment?.steps ?? 0
        distanceBaseM = segment?.distanceBaseM ?? session?.systemDistanceM ?? 0
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
    func stopCountingSteps() {
        stepCounting?.cancel()
        isCountingSteps = false
        // El tope era para la muestra de este stream: el tramo siguiente trae `end` reales.
        lastSampleAtCap = nil
    }

    /// Topa `lastSampleAt` en `gapStart` hasta la siguiente muestra del stream. Con un tope ya
    /// pendiente (no llegó ninguna muestra entre medias) conserva el más temprano: esa muestra
    /// puede traer también el gap anterior.
    func capLastSampleAt(at gapStart: Date) {
        lastSampleAtCap = min(lastSampleAtCap ?? gapStart, gapStart)
    }

    /// Aplica pasos y distancia de la muestra y recalcula las métricas en `clock.now`.
    /// Un fallo de una parte no impide la otra: una distancia inválida se registra y el
    /// conteo sigue.
    ///
    /// Solo una muestra del stream mueve `lastSampleAt`: la de la consulta (`fromQuery`)
    /// termina en el instante pedido (volver o relanzar), no en el último paso real, y
    /// recortar ahí una huérfana contaría como caminadas las horas quietas. Por lo mismo, la
    /// primera del stream con `end` posterior al inicio del gap no lo lleva más allá de él, y
    /// libera el tope sume pasos o no. Una con `end` anterior es un dato previo al gap: lo mueve
    /// como siempre y el tope sigue pendiente. La consulta no lo libera.
    func record(_ sample: PedometerSample, fromQuery: Bool = false) {
        if !fromQuery, let startedAt = session?.startedAt {
            measure(MeasurementLog.sampleLine(sessionStartedAt: startedAt, sample: sample))
        }
        let cap = fromQuery ? nil : lastSampleAtCap.flatMap { sample.end > $0 ? $0 : nil }
        if cap != nil { lastSampleAtCap = nil }
        guard session?.status == .active else { return }
        if sample.steps > highestCumulativeSteps {
            let increment = sample.steps - highestCumulativeSteps
            highestCumulativeSteps = sample.steps
            if !fromQuery { moveLastSampleAt(to: sample.end, cap: cap) }
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
        if let lastSavedAt, clock.now.timeIntervalSince(lastSavedAt) < Self.autosaveIntervalS { return }
        persist()
    }

    /// `lastSampleAt` tras una muestra del stream que sumó pasos y terminó en `end`. Con un tope
    /// (`cap`, R4) no pasa del inicio del gap ni retrocede; sin él, es `end`.
    private func moveLastSampleAt(to end: Date, cap: Date?) {
        guard let cap else {
            lastSampleAt = end
            return
        }
        let capped = min(end, cap)
        lastSampleAt = lastSampleAt.map { max($0, capped) } ?? capped
    }

    /// El stream terminó sin que nadie lo cancelara: el sistema detuvo el podómetro.
    /// La sesión sigue y conserva sus pasos (AD-11 solo bloquea al iniciar).
    /// Si lo canceló el store (pausar o finalizar), no hace nada: `isCountingSteps` ya se
    /// actualizó al cancelar, y quizá otro tramo ya está contando.
    private func stepCountingEnded() {
        guard !Task.isCancelled else { return }
        isCountingSteps = false
        if let session { measureTransition(.streamEnded, session, at: clock.now) }
        log.error("El sistema terminó las actualizaciones del podómetro; la sesión sigue con \(self.session?.stepsMeasured ?? 0, privacy: .public) pasos")
    }
}
