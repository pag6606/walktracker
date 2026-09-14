import Foundation

/// Degradación excepcional de la reconstrucción del background (CAP-3, domain-model.md §4,
/// `domain.js:508` `estimateSteps`).
///
/// Los pasos de un gap salen **primero** de la consulta por rango al coprocesador; solo si
/// el sistema no tiene el dato (nil, vacío, error o timeout) se estiman por cadencia:
///
/// ```
/// stepsEstimated += round(cadenceSpm × gapS / 60)
/// ```
///
/// Lo estimado es siempre `stepsEstimated`, desglosado y descartable; nunca se mezcla con
/// `stepsMeasured`.
public enum GapEstimator {

    /// Muestra previa mínima, en segundos de sesión, para que la cadencia medida sea
    /// representativa: por debajo, el gap es 0 (domain-model.md §4).
    public static let minPriorSampleS: TimeInterval = 120

    /// `round(cadenceSpm × gapS / 60)` (`domain.js:508`).
    ///
    /// `0` si la cadencia o el gap son ≤ 0. El redondeo es el `Math.round` de la v3 para
    /// valores ≥ 0.
    ///
    /// - Throws: `DomainError.invalidValue` con `cadenceSpm` o `gapS` si son `NaN` (el
    ///   `TypeError` de la v3). Diverge a propósito de `domain.js`, que devuelve `Infinity`
    ///   con una entrada infinita: un conteo de pasos infinito no existe, así que una
    ///   entrada infinita (> 0) lanza con su campo, y un producto que no cabe en `Int`
    ///   lanza con `steps`.
    public static func estimateSteps(cadenceSpm: Double, gapS: TimeInterval) throws(DomainError) -> Int {
        guard !cadenceSpm.isNaN else { throw .invalidValue(field: "cadenceSpm") }
        guard !gapS.isNaN else { throw .invalidValue(field: "gapS") }
        guard cadenceSpm > 0, gapS > 0 else { return 0 }
        guard cadenceSpm.isFinite else { throw .invalidValue(field: "cadenceSpm") }
        guard gapS.isFinite else { throw .invalidValue(field: "gapS") }
        let steps = (cadenceSpm * (gapS / 60)).rounded(.toNearestOrAwayFromZero)
        guard steps.isFinite, steps < Double(Int.max) else { throw .invalidValue(field: "steps") }
        return Int(steps)
    }

    /// Pasos estimados para el gap `[gapStart, gapEnd]` de `session`.
    ///
    /// Devuelve `0` salvo con la sesión `active` y al menos `minPriorSampleS` de sesión en
    /// `gapStart`. La cadencia es la de `session.metrics(at: gapStart)`, que solo cuenta
    /// pasos medidos: nunca se estima sobre lo estimado. Un gap negativo (el reloj fue hacia
    /// atrás) es 0.
    public static func steps(for session: Session, gapStart: Date, gapEnd: Date) -> Int {
        guard session.status == .active,
              session.elapsedS(at: gapStart) >= minPriorSampleS
        else { return 0 }
        let cadence = session.metrics(at: gapStart).cadenceSpm
        do {
            return try estimateSteps(cadenceSpm: cadence, gapS: gapEnd.timeIntervalSince(gapStart))
        } catch {
            // Inalcanzable en la práctica: la cadencia del agregado es finita y los `Date`
            // dan un intervalo finito. Sin un valor representable no se estima.
            return 0
        }
    }
}
