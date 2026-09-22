import Domain
import Foundation

/// El único logro que esta historia toca: `weekly_goal` (3.1).
///
/// **No es el `AchievementEngine`**, que es de la 3.2 y evalúa los 14 al cerrar la sesión dentro
/// de la misma transacción que la persiste (AD-17). `weekly_goal` es la **excepción declarada**
/// del spine: lo evalúa `GoalEngine` al cumplirse la meta, no el cierre de sesión, y por eso
/// entra aquí con la historia del anillo y no con la del evaluador.
extension AchievementsStore {

    /// La clave de `weekly_goal` en el catálogo congelado (AD-5, entrada #5).
    ///
    /// **Es la clave, no la definición.** El umbral (`1`), la comparación (`eq`), la métrica
    /// (`weeklyGoalMet`), el nombre, el texto y el emoji siguen viviendo **solo** en
    /// `WalkTracker/Resources/achievements.json`, que es contenido congelado y no se declara en
    /// Swift. Las 14 claves ya están duplicadas a propósito en `AchievementCatalog.requiredKeys`
    /// —un fichero de datos no puede validarse contra sí mismo— y esto es el mismo trato para
    /// una de ellas. `AchievementsStoreGoalTests` lo ata al catálogo del bundle: si la entrada
    /// dejara de existir o dejara de ser la de `weeklyGoalMet`, la suite lo dice.
    static let weeklyGoalKey = "weekly_goal"

    /// Desbloquea `weekly_goal`. **De por vida e irrevocable** (AD-17): una vez conseguido no se
    /// re-dispara ni vuelve a bloquearse, ni siquiera si se borra la caminata que lo desbloqueó.
    ///
    /// Es **idempotente**: si ya estaba desbloqueado no escribe nada y devuelve `false`. Eso es
    /// lo que permite llamarlo cada vez que el anillo llega al 100 %, sin llevar la cuenta fuera.
    ///
    /// `progress` es `1` porque su umbral es `eq 1` sobre `weeklyGoalMet`: la métrica es "la meta
    /// se cumplió", y no hay medio logro.
    ///
    /// - Returns: `true` si **esta** llamada lo desbloqueó y quedó escrito en disco.
    @discardableResult
    func unlockWeeklyGoal(at instant: Date) -> Bool {
        guard unlock(forKey: Self.weeklyGoalKey)?.isUnlocked != true else { return false }

        guard let unlocked = try? AchievementUnlock(key: Self.weeklyGoalKey, unlockedAt: instant, progress: 1) else {
            // No puede ocurrir —la clave no está vacía y el progreso es 1— pero un `try!` aquí
            // mataría la app por un logro, y eso es exactamente lo que AD-22 no quiere.
            log.error("No se pudo construir el desbloqueo de la meta semanal; no se escribe nada")
            return false
        }

        // La guarda de "ya desbloqueado" vive dentro de `upsert(_:into:)` y no en el `guard` de
        // arriba, porque `save(applying:)` puede releer el fichero antes de aplicar: sin ella, una
        // fila que la relectura destapa como conseguida se reescribiría con otro instante.
        var wrote = false
        let saved = save { unlocks in
            wrote = self.upsert(unlocked, into: &unlocks)
        }
        return saved && wrote
    }
}
