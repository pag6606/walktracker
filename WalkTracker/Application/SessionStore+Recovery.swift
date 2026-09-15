import Domain
import Foundation
import OSLog

/// Recuperación y persistencia (1.6, AD-9, AD-16, AD-18): restaurar al arrancar, cerrar la
/// sesión huérfana y guardar o borrar el snapshot de la sesión viva.
///
/// `persist()` y `clearSnapshot()` son las únicas llamadas de escritura a `StoragePort` de la
/// app. `restoreOnLaunch()` escribe `didAttemptRestore` y, al restaurar, `session`, `metrics`,
/// `hasSession`, `showsRecoveredNotice` y el tramo (`segmentStart`, `highestCumulativeSteps`,
/// `distanceBaseM`, `lastSampleAt`, `backgroundedAt`).
extension SessionStore {

    /// Al arrancar la app: restaura en silencio la sesión del snapshot, si lo hay.
    ///
    /// Orden: leer → validar → huérfana o restaurar → reconciliar (solo activa) → presentar.
    /// La sesión aparece ya consolidada, sin pantalla de carga: la espera la acota el timeout
    /// de la reconciliación.
    ///
    /// - **Ilegible o inválido:** no se restaura; el snapshot se aparta (nunca se borra), se
    ///   registra un `fault` e Inicio queda normal.
    /// - **Huérfana** (`now − startedAt` > `orphanSessionThresholdS`): se cierra en el último
    ///   dato real (`lastSampleAt`, o `startedAt` sin ninguno), nunca antes de la última
    ///   reanudación (`segmentStart`), marcada `recovered`, sin
    ///   consultar ni estimar. Queda en `session` para su resumen y el snapshot se borra.
    /// - **Pausada:** vuelve pausada, con el tiempo congelado en `pausedAt`, sin consulta.
    /// - **Activa:** reabre el tramo y reconcilia `[segmentStart, now]` con el gap pendiente
    ///   desde `savedAt`, como la vuelta de background de la 1.5.
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
                systemDistanceM: snapshot.systemDistanceM
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
            await reconcile(until: now)
            backgroundedAt = nil
        }
        guard let current = session, current.status != .finished else { return }
        metrics = current.metrics(at: clock.now)
        log.info("Sesión recuperada: \(current.status.rawValue, privacy: .public)")
        measureTransition(.restore, current, at: clock.now)
        showsRecoveredNotice = true
        hasSession = true
        persist()
    }

    /// Cierra la huérfana en `end` y la deja en `session` para su resumen. El snapshot se
    /// borra: como la finalizada, se descarta al salir del resumen.
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
        metrics = closed.metrics(at: end)
        measureTransition(.orphan, closed, at: end)
        hasSession = true
        clearSnapshot()
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
            distanceBaseM: distanceBaseM
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
