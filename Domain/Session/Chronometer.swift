import Foundation

/// Cronómetro wall-clock (domain-model.md §3, `domain.js:69`).
///
/// ```
/// elapsedS = (now − startedAt) − totalPausesS
/// ```
///
/// `now` llega siempre de `ClockPort`: ningún timer es fuente de verdad, los timers
/// solo repintan. Por eso el tiempo que la app pasa en background o cerrada cuenta
/// sin hacer nada: la resta se rehace desde `startedAt`.
public enum Chronometer {

    /// Segundos transcurridos en movimiento. **Nunca negativo**: si el reloj del
    /// sistema va hacia atrás (`now < startedAt`) o las pausas superan el total, da 0.
    ///
    /// Diverge a propósito de `domain.js`, que devuelve el negativo: un tiempo
    /// negativo no es una magnitud que la UI pueda mostrar (AD-22).
    public static func elapsedS(startedAt: Date, totalPausesS: TimeInterval, now: Date) -> TimeInterval {
        let elapsed = now.timeIntervalSince(startedAt) - totalPausesS
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        return elapsed
    }
}
