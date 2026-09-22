import Domain
import Foundation

/// La intención que escribe los logros que desbloquea un cierre de sesión (3.2) — AD-16, AD-17.
///
/// **Quién hace qué, y por qué están separados.** El motor (`AchievementEngine`, en `Domain/`)
/// **decide** qué logros se desbloquean: es puro, recibe el calendario por parámetro y lo
/// ejecutan los vectores de AD-6. Este fichero **escribe**: `achievements.json` tiene un solo
/// escritor (AD-16) y sus intenciones viven en `AchievementsStore+*.swift`, exentas por la regla
/// de forma de las secciones 9 y 9b del gate. Ni el motor sabe de ficheros ni esto sabe de
/// umbrales.
///
/// Es hermana de `AchievementsStore+Goal.swift`, que escribe el **único** logro que este camino
/// no evalúa: `weekly_goal` (AD-25).
extension AchievementsStore {

    /// Desbloquea los logros de `definitions` y los escribe, en **una sola** escritura.
    ///
    /// **Idempotente, como `unlockWeeklyGoal(at:)` y por la misma razón** (AD-17, CAP-15): un
    /// logro ya desbloqueado no se re-dispara, su `unlockedAt` no se mueve y **no se revoca
    /// nunca**, ni al borrar la caminata que lo desbloqueó. Eso es lo que permite llamar aquí en
    /// los dos caminos de persistencia —el cierre y el reintento del resumen (D1b)— sin llevar la
    /// cuenta fuera: si la primera escritura entró, la segunda no hace nada.
    ///
    /// **Una sola escritura para todos.** Una caminata puede desbloquear varios logros a la vez
    /// (la primera de 1,2 km desbloquea `first_session` y `first_km`), y escribir el fichero una
    /// vez por logro multiplicaría las ventanas en las que un corte deja el estado a medias.
    ///
    /// `progress` es `1` en todos, igual que en `unlockWeeklyGoal(at:)`: un logro **conseguido**
    /// no tiene barra que pintar. La unidad de la métrica —metros para `marathon_42km`, sesiones
    /// para `consistency_30`— solo importa en la fila de un logro **en curso**, y quien escribe
    /// esas filas es la 3.3, que es la dueña del grid. Dos intenciones escribiendo `progress` con
    /// criterios distintos sería la incoherencia de verdad.
    ///
    /// - Parameters:
    ///   - definitions: los logros que el motor acaba de dar por cumplidos.
    ///   - instant: el instante del desbloqueo. Quien llama pasa el **cierre de la caminata**
    ///     (`SessionRecord.endedAt`) y no "ahora": es cuando Paul se lo ganó, y así el reintento
    ///     del resumen no fecha el logro cuando Paul pulsa un botón.
    /// - Returns: los logros que **esta** llamada desbloqueó y que quedaron escritos en
    ///   `achievements.json`. Vacío si no había ninguno nuevo o si no se pudo escribir —con el
    ///   fichero ilegible no se escribe encima (B-1), y entonces el logro **no se anuncia**: un
    ///   logro celebrado que no está en disco volvería a desbloquearse en el cierre siguiente.
    @discardableResult
    func unlock(_ definitions: [AchievementDefinition], at instant: Date) -> [AchievementDefinition] {
        let pending = definitions.filter { unlock(forKey: $0.key)?.isUnlocked != true }
        guard !pending.isEmpty else { return [] }

        var rows: [AchievementUnlock] = []
        var unlocked: [AchievementDefinition] = []
        for definition in pending {
            guard let row = try? AchievementUnlock(key: definition.key, unlockedAt: instant, progress: 1) else {
                // No puede ocurrir —la clave viene del catálogo validado y el progreso es 1— pero
                // un `try!` aquí mataría la app por un logro, que es exactamente lo que AD-22 no
                // quiere. Se pierde ese logro y los demás siguen.
                log.error("No se pudo construir el desbloqueo de '\(definition.key, privacy: .public)'; ese logro no se escribe")
                continue
            }
            rows.append(row)
            unlocked.append(definition)
        }
        guard !rows.isEmpty else { return [] }

        // **Qué se escribió de verdad se decide DENTRO del closure**, no aquí: `save(applying:)`
        // puede releer el fichero antes de aplicar el cambio, y esa relectura puede revelar filas
        // ya desbloqueadas que el estado en memoria no tenía. `upsert(_:into:)` las respeta.
        var writtenKeys = Set<String>()
        guard save(applying: { stored in
            writtenKeys = []
            for row in rows {
                if self.upsert(row, into: &stored) { writtenKeys.insert(row.key) }
            }
        }) else {
            log.error("No se pudieron guardar \(rows.count, privacy: .public) desbloqueo(s); no se anuncia ninguno")
            return []
        }

        // Solo se anuncia lo que esta llamada desbloqueó. Un logro que la relectura destapó como
        // ya conseguido no se re-celebra, y su `unlockedAt` sigue siendo el suyo.
        let announced = unlocked.filter { writtenKeys.contains($0.key) }
        guard !announced.isEmpty else { return [] }

        log.info("Logros desbloqueados al cerrar: \(announced.map(\.key).joined(separator: ", "), privacy: .public)")
        return announced
    }
}
