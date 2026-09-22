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
/// **Aquí se evalúan los logros, y es el único sitio donde se evalúan** (AD-17, 3.2). No al abrir
/// el historial, no al pintar el grid, no al borrar.
///
/// **Sesión primero, logros después** (decisión D1 de Paul, 2026-09-21). La 5.1 marcó el hueco
/// **antes** del `append`, suponiendo el orden contrario, y no era una desviación: era una
/// pregunta que la 5.1 no podía responder y dejó señalada. La respuesta es que la prioridad de la
/// 5.1 no se renegocia —perder el historial es perder meses de caminatas irreconstruibles;
/// perder un logro es perder un reconocimiento que se puede volver a ganar—, así que la
/// evaluación va **después de un `append` con éxito**. Si la app muere en la ventana entre las dos
/// escrituras, los 4 logros acumulados (`first_session`, `7_days_streak`, `marathon_42km`,
/// `consistency_30`) **se curan solos** en el cierre siguiente —el historial ya trae la caminata
/// anterior y la evaluación es determinista— y los 9 de sesión se pierden. Se acepta a sabiendas:
/// la alternativa era un logro fantasma **irrevocable**, y un logro que miente es peor que uno que
/// falta.
///
/// **Y por eso evalúan los dos caminos** (D1b). Con sesión primero, si el `append` falló la
/// evaluación **no ocurrió**, así que `retrySavingFinishedWalk()` —el de `leaveSummary()`— también
/// tiene que evaluar. Para que "un único punto" sea verdad y no una frase, la evaluación está
/// extraída a `evaluateAchievements(for:)`, al que llaman los dos, en vez de copiada en ambos.
/// `HistoryStore.append` es idempotente por `startedAt` y devuelve `true` si el registro ya
/// estaba, así que el reintento no duplica nada — y `AchievementsStore.unlock(_:at:)` es
/// idempotente por clave, así que tampoco re-dispara.
///
/// **AD-17 no se enmienda, y conviene decir por qué** (D1c). Su letra dice "dentro de la misma
/// transacción que la persiste", y **esa transacción conjunta no existe**: AD-9 hace la escritura
/// atómica por fichero y AD-16 les da dueños distintos. Lo que AD-17 previene —que un logro se
/// evalúe al abrir el historial, al pintar el grid o al borrar, y se dispare dos veces— se cumple
/// íntegro: hay un único punto, en el cierre. La imposibilidad de atomicidad conjunta sigue
/// registrada en `deferred-work.md` como lo que es: un límite conocido, no un pendiente.
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
        guard history.append(record) else {
            unsavedFinishedRecord = record
            finishedWalkNotPersisted = true
            return false
        }
        unsavedFinishedRecord = nil
        finishedWalkNotPersisted = false
        log.info("Caminata guardada en el historial")
        // ↓ AD-17, D1: la caminata ya está a salvo, y solo entonces se evalúan los logros.
        evaluateAchievements(for: record)
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
        // D1b: si el `append` del cierre falló, la evaluación no ocurrió. Este camino es el otro
        // que la puede hacer ocurrir, y llama al mismo sitio.
        evaluateAchievements(for: record)
        clearSnapshot()
    }

    /// **El único punto donde se evalúan los logros** (AD-17). Lo llaman los dos caminos de
    /// persistencia, siempre **después** de un `append` con éxito (D1, D1b).
    ///
    /// El motor es puro y vive en `Domain/`: recibe el registro que cierra, el historial —que ya
    /// trae ese registro dentro, y el motor lo cuenta una sola vez—, el estado actual de los
    /// logros y el catálogo congelado, y devuelve **qué se desbloquea ahora**. Aquí no se decide
    /// ningún umbral.
    ///
    /// El calendario es el `AppCalendar` de AD-19, el mismo que usa el anillo semanal: las horas
    /// de `early_bird`/`night_walker` y la racha de `7_days_streak` se calculan en **hora local**,
    /// que es la divergencia declarada de AD-6.
    ///
    /// Una caminata que no cuenta para logros —una huérfana (AD-18)— no llega a evaluarse: lo
    /// decide el propio motor con `SessionRecord.countsForAchievements`, así que este camino no
    /// vuelve a razonarlo.
    ///
    /// **Un fallo no cuesta la caminata.** El registro ya está en `sessions.json`; si
    /// `achievements.json` no se puede escribir, la lista de desbloqueos queda vacía y no se
    /// anuncia nada (ver `AchievementsStore.unlock(_:at:)`).
    ///
    /// **Y con el estado de los logros ilegible no se evalúa NADA.** Es la misma doctrina de B-1
    /// un paso antes de la escritura: con `readOutcome == .unreadable` los `unlocks` en memoria
    /// están vacíos —no porque no haya logros, sino porque no se pudieron leer—, así que el motor
    /// recibiría `alreadyUnlocked` vacío y daría por **nuevos los catorce**, reescribiéndolos con
    /// otro instante y anunciándolos otra vez. Un logro no se evalúa contra un estado que no se
    /// pudo leer.
    private func evaluateAchievements(for record: SessionRecord) {
        guard !achievements.readOutcome.isUnreadable else {
            log.error("El estado de los logros no se pudo leer: NO se evalúa nada. Con la lista de desbloqueados vacía se darían por nuevos los catorce logros")
            return
        }
        let newlyUnlocked = AchievementEngine.newlyUnlocked(
            closing: record,
            history: history.records,
            alreadyUnlocked: achievements.unlocks,
            catalog: achievementCatalog,
            calendar: clock.calendar
        )
        guard !newlyUnlocked.isEmpty else { return }

        // El instante del desbloqueo es el **cierre de la caminata**, no "ahora": es cuando Paul
        // se lo ganó, y así el reintento del resumen no fecha el logro cuando pulsa un botón.
        let written = achievements.unlock(newlyUnlocked, at: record.endedAt)
        guard !written.isEmpty else { return }

        // La señal para la 3.4 y la 3.5: solo lo que quedó ESCRITO.
        //
        // **Se asigna, no se acumula, y una caminata pasa por aquí una sola vez.** El reintento
        // solo corre con `unsavedFinishedRecord != nil`, y eso solo ocurre cuando el `append` del
        // cierre falló —en cuyo caso no se evaluó nada—. Aquí había un filtro de deduplicación
        // "por si los dos caminos evalúan la misma caminata": ese estado no existe, y el filtro
        // afirmaba una concurrencia inventada.
        unlockedAchievements = written
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
