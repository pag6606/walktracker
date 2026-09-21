import Domain
import Foundation

/// El registro de la caminata cerrada (5.1, CAP-9, FR-9) — AD-16, AD-17, AD-18, AD-22.
///
/// Los **dos** sitios que cierran una sesión pasan por aquí: `confirmFinish()`, cuando Paul
/// finaliza, y `closeOrphan(_:at:)`, cuando la app archiva una huérfana al arrancar. Tener un
/// solo punto es lo que impide que el segundo se olvide, que es exactamente lo que pasaba antes:
/// los dos acababan en `clearSnapshot()` y ninguno guardaba nada.
///
/// **El orden, y por qué es ese.** Se materializa el registro → se guarda → y **solo si el
/// guardado fue bien** se borra el snapshot. Al revés, un fallo de disco perdería la caminata
/// entera; así, lo peor que pasa es que quede un instante en los dos ficheros, y esa ventana la
/// cierra `HistoryStore.contains(startedAt:)` en el arranque siguiente.
///
/// **Aquí se enchufará la 3.2** (AD-17): la evaluación de logros va en esta misma transacción,
/// entre materializar el registro y darlo por guardado, porque es el único instante donde
/// coexisten la sesión cerrada y sus métricas congeladas. Lo que ya está decidido para entonces:
/// una huérfana **no** dispara logros y el registro lo dice solo
/// (`SessionRecord.countsForAchievements`), y la atomicidad conjunta entre `sessions.json` y
/// `achievements.json` **no existe** —la escritura de AD-9 es por fichero y AD-16 les da dueños
/// distintos—, lo que está registrado en `deferred-work.md` en vez de dejarlo para descubrirlo.
extension SessionStore {

    /// Materializa la caminata cerrada y la entrega a su dueño.
    ///
    /// - Returns: `true` si quedó escrita en `sessions.json`. Solo entonces puede borrarse el
    ///   snapshot.
    @discardableResult
    func saveFinishedWalk(_ session: Session, metrics: SessionMetrics) -> Bool {
        guard let record = finishedRecord(session, metrics: metrics) else {
            // Sin registro no hay nada que reintentar, pero el snapshot tampoco se borra: la
            // caminata vuelve al relanzar y alguien podrá mirar por qué no se pudo materializar.
            unsavedFinishedRecord = nil
            finishedWalkNotPersisted = true
            return false
        }
        // ↓ AD-17: la evaluación de logros de la 3.2 va aquí, sobre `record`, antes de dar la
        //   transacción por cerrada. `record.countsForAchievements` ya sabe que una huérfana no.
        guard history.append(record) else {
            unsavedFinishedRecord = record
            finishedWalkNotPersisted = true
            return false
        }
        unsavedFinishedRecord = nil
        finishedWalkNotPersisted = false
        log.info("Caminata guardada en el historial")
        return true
    }

    /// Último intento de guardar la caminata que falló al cerrar, al salir del resumen.
    ///
    /// Sin nada pendiente no hace nada. Si esta vez entra, el snapshot ya se puede borrar: la
    /// caminata está en su sitio definitivo.
    func retrySavingFinishedWalk() {
        guard let record = unsavedFinishedRecord else { return }
        guard history.append(record) else {
            log.fault("La caminata sigue sin poder guardarse al salir del resumen; el snapshot NO se borra y vuelve al relanzar")
            return
        }
        unsavedFinishedRecord = nil
        finishedWalkNotPersisted = false
        log.info("Caminata guardada en el historial al reintentar desde el resumen")
        clearSnapshot()
    }

    /// El registro inmutable de `session`, con las derivadas ya materializadas.
    ///
    /// **Las derivadas se congelan, no se recalculan al leer** (AD-22): `distanceM`,
    /// `paceSecPerKm` y `cadenceSpm` salen de las `metrics` del instante del cierre. La zancada
    /// viaja con el registro, así que recalibrar después no reescribe historial.
    ///
    /// **Una métrica degradada viaja marcada, no corregida.** Con `metrics.degraded` el
    /// `distanceM: 0` no es una caminata sin pasos: es un cálculo que no cuadró (B-3). El
    /// registro es inmutable y no hay segunda oportunidad de decirlo, así que la marca va dentro,
    /// por la misma razón que `recovered`.
    ///
    /// - Returns: `nil` si la sesión no está cerrada o el dominio rechaza el registro en la
    ///   frontera. Lo segundo es inalcanzable con una sesión que `finish(at:)` acaba de cerrar
    ///   —los invariantes del agregado son más estrictos— y por eso se registra como `fault`.
    func finishedRecord(_ session: Session, metrics: SessionMetrics) -> SessionRecord? {
        guard let endedAt = session.endedAt, let durationS = session.durationS, let pausesS = session.pausesS else {
            log.fault("Se intentó registrar una caminata que no está cerrada")
            return nil
        }
        do {
            return try SessionRecord(
                id: UUID(),
                startedAt: session.startedAt,
                endedAt: endedAt,
                stepsMeasured: session.stepsMeasured,
                stepsEstimated: session.stepsEstimated,
                strideM: session.strideM,
                distanceM: metrics.distanceM,
                durationS: durationS,
                pausesS: pausesS,
                paceSecPerKm: metrics.paceSecPerKm,
                cadenceSpm: metrics.cadenceSpm,
                weather: session.weather,
                quoteId: session.quoteId,
                source: session.source,
                recovered: session.recovered,
                degraded: metrics.degraded
            )
        } catch {
            log.fault("La caminata cerrada no cruza la frontera del registro: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
