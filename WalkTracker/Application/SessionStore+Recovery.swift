import Domain
import Foundation
import OSLog

/// Recuperación y persistencia (1.6, AD-9, AD-16, AD-18): restaurar al arrancar, cerrar la
/// sesión huérfana y guardar o borrar el snapshot de la sesión viva.
///
/// `persist()` y `clearSnapshot()` son las únicas llamadas de escritura a `StoragePort` de la
/// app. `restoreOnLaunch()` escribe `didAttemptRestore` y, al restaurar, `session`, `metrics`,
/// `hasSession`, `showsRecoveredNotice` y el tramo (`segmentStart`, `highestCumulativeSteps`,
/// `distanceBaseM`, `lastSampleAt`, `backgroundedAt`, `stepsMeasuredAtGapStart`).
extension SessionStore {

    /// Al arrancar la app: restaura en silencio la sesión del snapshot, si lo hay.
    ///
    /// Orden: leer → validar → huérfana o restaurar → reconciliar (solo activa) → presentar.
    /// La sesión aparece ya consolidada, sin pantalla de carga: la espera la acota el timeout
    /// de la reconciliación.
    ///
    /// - **Ilegible o inválido:** no se restaura; el snapshot se aparta (nunca se borra), se
    ///   registra un `fault` e Inicio queda normal.
    /// - **Ya guardada** (5.1): el snapshot es de una caminata que ya está en el historial —la
    ///   app murió entre guardarla y borrar su snapshot—. No se restaura ni se archiva otra vez:
    ///   se termina de borrar el snapshot y se sigue.
    /// - **Huérfana** (`now − startedAt` > `orphanSessionThresholdS`): se cierra en el último
    ///   dato real (`lastSampleAt`, o `startedAt` sin ninguno), nunca antes de la última
    ///   reanudación (`segmentStart`), marcada `recovered`, sin consultar ni estimar. Queda en
    ///   `session` para su resumen, **entra en el historial con su marca** y el snapshot se borra
    ///   si el guardado fue bien.
    /// - **Pausada:** vuelve pausada, con el tiempo congelado en `pausedAt`, sin consulta.
    /// - **Activa:** reabre el tramo y reconcilia `[segmentStart, now]` con el gap pendiente
    ///   desde `savedAt`, como la vuelta de background de la 1.5.
    ///
    /// El clima guardado vuelve con la sesión. Una restaurada sin clima no lo captura ni pide
    /// permiso: el snapshot sería de otro instante que el inicio (2.1).
    ///
    /// La frase guardada también vuelve con la sesión, pero **su overlay no** (2.2): `quote`
    /// se queda en `nil`, porque solo lo enciende `openSession()`. Volver del force-quit no es
    /// empezar a caminar.
    ///
    /// Solo corre una vez, y no hace nada si ya hay una sesión.
    func restoreOnLaunch() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard session == nil else { return }

        let snapshot: ActiveSessionSnapshot
        do {
            guard let loaded = try storage.loadActiveSession() else { return }
            snapshot = loaded
        } catch .failed(let operation) {
            log.fault("No se pudo leer el snapshot de la sesión (\(operation, privacy: .public)); sigue en su sitio")
            return
        } catch {
            log.fault("Snapshot de la sesión ilegible, apartado: \(String(describing: error), privacy: .public)")
            return
        }

        // La ventana de duplicado del cierre (5.1): entre guardar la caminata y borrar su
        // snapshot hay un instante en que existe en los dos ficheros. Si la app murió ahí, esto
        // es lo que impide archivarla por segunda vez —o presentarla como viva—: ya está a salvo,
        // así que lo único que queda es terminar de borrar el snapshot.
        if history.contains(startedAt: snapshot.startedAt) {
            log.info("El snapshot es de una caminata que YA está en el historial: se borra en vez de restaurarla o archivarla otra vez")
            clearSnapshot()
            return
        }

        let restored: Session
        do {
            guard snapshot.segmentSteps >= 0 else { throw DomainError.invalidValue(field: "segmentSteps") }
            guard snapshot.distanceBaseM.isFinite, snapshot.distanceBaseM >= 0 else {
                throw DomainError.invalidValue(field: "distanceBaseM")
            }
            restored = try Session.restore(
                startedAt: snapshot.startedAt,
                stepsMeasured: snapshot.stepsMeasured,
                stepsEstimated: snapshot.stepsEstimated,
                totalPausesS: snapshot.totalPausesS,
                paused: snapshot.paused,
                pausedAt: snapshot.pausedAt,
                strideM: snapshot.strideM,
                systemDistanceM: snapshot.systemDistanceM,
                weather: snapshot.weather,
                quoteId: snapshot.quoteId
            )
        } catch {
            log.fault("Snapshot de la sesión rechazado en la frontera: \(String(describing: error), privacy: .public)")
            do {
                try storage.setAsideActiveSession()
            } catch {
                log.error("No se pudo apartar el snapshot rechazado: \(String(describing: error), privacy: .public)")
            }
            return
        }

        let now = clock.now
        if now.timeIntervalSince(snapshot.startedAt) > orphanSessionThresholdS {
            // Nunca antes de la última reanudación: toda pausa cerrada queda antes del recorte,
            // y restar `totalPausesS` no se come tiempo andado antes del último dato.
            closeOrphan(restored, at: max(snapshot.lastSampleAt ?? snapshot.startedAt, snapshot.segmentStart))
            return
        }

        session = restored
        metrics = restored.metrics(at: now)
        lastSampleAt = snapshot.lastSampleAt
        segmentStart = snapshot.segmentStart
        highestCumulativeSteps = snapshot.segmentSteps
        distanceBaseM = snapshot.distanceBaseM
        if restored.status == .active {
            capLastSampleAt(at: snapshot.savedAt)
            countSteps(from: snapshot.segmentStart, restoring: (snapshot.segmentSteps, snapshot.distanceBaseM))
            backgroundedAt = snapshot.savedAt
            stepsMeasuredAtGapStart = snapshot.stepsMeasured
            await reconcile(until: now)
            backgroundedAt = nil
            stepsMeasuredAtGapStart = nil
        }
        guard let current = session, current.status != .finished else { return }
        metrics = current.metrics(at: clock.now)
        log.info("Sesión recuperada: \(current.status.rawValue, privacy: .public)")
        measureTransition(.restore, current, at: clock.now)
        showsRecoveredNotice = true
        hasSession = true
        persist()
    }

    /// Cierra la huérfana en `end`, **la guarda en el historial** y la deja en `session` para su
    /// resumen.
    ///
    /// **El segundo sitio que cierra una sesión, y el fácil de olvidar** (5.1). Entra en el
    /// historial con su marca `recovered`: sus pasos son reales —los contó el coprocesador— así
    /// que suma distancia y anillo, pero **no dispara logros** (AD-18), y eso lo dice el propio
    /// registro con `countsForAchievements`.
    ///
    /// El snapshot se borra **solo si el guardado fue bien**, igual que al finalizar: si falla,
    /// sigue en disco y la huérfana vuelve a intentarse al relanzar.
    private func closeOrphan(_ orphan: Session, at end: Date) {
        var closed = orphan
        do {
            try closed.closeOrphan(at: end)
        } catch {
            // Inalcanzable: `restore` solo da sesiones activas o pausadas.
            log.fault("No se pudo cerrar la sesión huérfana: \(String(describing: error), privacy: .public)")
            return
        }
        log.info("Sesión huérfana cerrada en su último dato real")
        session = closed
        let closedMetrics = closed.metrics(at: end)
        metrics = closedMetrics
        measureTransition(.orphan, closed, at: end)
        hasSession = true
        if saveFinishedWalk(closed, metrics: closedMetrics) {
            clearSnapshot()
        }
    }

    /// Guarda el snapshot de la sesión viva. Nunca a mitad de una reconciliación, que aún no
    /// ha consolidado los pasos del gap: al terminar se guarda. Un fallo se registra y el
    /// siguiente evento lo reintenta.
    func persist() {
        guard !isReconciling, let session, session.status != .finished else { return }
        let now = clock.now
        let snapshot = ActiveSessionSnapshot(
            startedAt: session.startedAt,
            stepsMeasured: session.stepsMeasured,
            stepsEstimated: session.stepsEstimated,
            totalPausesS: session.totalPausesS,
            paused: session.status == .paused,
            pausedAt: session.pausedAt,
            strideM: session.strideM,
            systemDistanceM: session.systemDistanceM,
            savedAt: now,
            lastSampleAt: lastSampleAt,
            segmentStart: segmentStart ?? session.startedAt,
            segmentSteps: highestCumulativeSteps,
            distanceBaseM: distanceBaseM,
            weather: session.weather,
            quoteId: session.quoteId
        )
        do {
            try storage.saveActiveSession(snapshot)
            lastSavedAt = now
        } catch {
            log.error("No se pudo guardar el snapshot de la sesión: \(String(describing: error), privacy: .public)")
        }
    }

    /// Borra el snapshot al cerrar la sesión: relanzar ya no la restaura.
    func clearSnapshot() {
        do {
            try storage.clearActiveSession()
        } catch {
            log.error("No se pudo borrar el snapshot de la sesión: \(String(describing: error), privacy: .public)")
        }
    }
}
