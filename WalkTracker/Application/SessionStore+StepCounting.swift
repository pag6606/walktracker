import Domain
import Foundation
import OSLog

/// Conteo de pasos (1.2, 1.3, AD-21): el stream acumulado del coprocesador por tramos, la
/// aplicación de cada muestra (`record`), el autosave por muestras y el tope de
/// `lastSampleAt` tras un gap (R4).
///
/// Escribe `segmentStart`, `highestCumulativeSteps`, `distanceBaseM`, `lastSampleAt`,
/// `lastSampleAtCap`, `isCountingSteps`, `stepCounting` y `lastKilometerDistanceM`; con cada
/// muestra, `session` y `metrics`. La consulta de la reconciliación también entra por
/// `record(_:fromQuery:)`.
///
/// Aquí vive además **el único disparo de `.kilometer`** del producto (4.1): ver
/// `noteKilometerCrossing(upTo:live:)`.
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
        noteKilometerCrossing(upTo: metrics?.distanceM ?? 0, live: !fromQuery)
        if let lastSavedAt, clock.now.timeIntervalSince(lastSavedAt) < Self.autosaveIntervalS { return }
        persist()
    }

    /// Dispara `.kilometer` si la distancia acaba de cruzar un múltiplo de 1.000 m, y deja la
    /// marca puesta para la muestra siguiente (4.1, CAP-12).
    ///
    /// **Solo en vivo** (decisión D2). `live` es `!fromQuery`: la consulta de la reconciliación
    /// reconstruye un hueco de background y puede sumar varios kilómetros andados hace media
    /// hora; vibrar ahí sería un buzz al desbloquear el móvil. El evento de kilómetro es una
    /// travesía en vivo, y una reconstrucción no lo es. Por eso este es **el único** de los doce
    /// sitios que reasignan `metrics` donde el disparo está enganchado.
    ///
    /// **Pero la marca se mueve igual, se dispare o no**, y es lo que hace verdadera la fila
    /// "la reconciliación suma 3 km → ningún evento": si la consulta no la moviera, la primera
    /// muestra en vivo posterior compararía con la distancia de antes del hueco y vibraría por
    /// los kilómetros que la reconciliación acaba de reconstruir.
    ///
    /// **Un evento por lote** (D3): `KilometerCrossing.didCross` responde `Bool`, así que saltar
    /// de 800 a 4.200 m vibra una vez y no tres. La decisión no se vuelve a tomar aquí.
    ///
    /// La distancia es la de las métricas —la que Paul está viendo—, así que la vibración cae en
    /// el mismo instante en que el cuentakilómetros de la pantalla marca el kilómetro.
    ///
    /// **Y la marca NUNCA baja** (`max`), que es lo que la protege de una métrica degradada.
    /// `Session.metrics(at:)` devuelve `distanceM: 0` con `degraded: true` cuando un cálculo no
    /// cuadra (B-3), y ese `catch` **no es inalcanzable**: `MetricsScenarios` lo alcanza, y darlo
    /// por imposible ya costó un crash en cada caminata. Si la marca siguiera esa caída a cero,
    /// el cálculo bueno siguiente volvería a cruzar **todos** los kilómetros ya cruzados y
    /// vibraría una vez por cada uno: la ráfaga que D3 existe para impedir, justo en el momento
    /// en que algo ya ha ido mal.
    ///
    /// Es un paso interno con acceso de módulo, como `record`, `countSteps` o `persist`: lo
    /// llaman este fichero y los tests, y la sección 6 del gate impide que lo alcance una vista.
    /// Sin esa costura, sustituir el `max` por una asignación directa deja la suite entera en
    /// verde — comprobado.
    func noteKilometerCrossing(upTo distanceM: Double, live: Bool) {
        if live, let previousM = lastKilometerDistanceM, KilometerCrossing.didCross(from: previousM, to: distanceM) {
            // Sin `try` y sin comprobar nada: el puerto promete que no falla hacia fuera, y un
            // feedback perdido no puede costar una muestra. `soundEnabled: false` es la decisión
            // D1 — la preferencia de sonido es de la 4.2 y todavía no existe.
            feedback.fire(.kilometer, soundEnabled: false)
        }
        lastKilometerDistanceM = max(lastKilometerDistanceM ?? 0, distanceM)
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
