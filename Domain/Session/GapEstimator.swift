import Foundation

/// Degradación excepcional de la reconstrucción del background (CAP-3, domain-model.md §4,
/// `domain.js:508` `estimateSteps`).
///
/// Los pasos de un gap salen **primero** de la consulta por rango al coprocesador: la
/// respuesta del sistema manda y cualquier muestra no nula cuenta como dato (R1). Solo sin
/// respuesta —`nil`, error o timeout— se estiman por cadencia:
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

    /// Por qué no se estimó nada para un gap. Cada caso es una defensa concreta, y su
    /// `rawValue` es el que sale en el registro `WTM1` (`MeasurementLog.EstimateSkip`).
    public enum Skip: String, Sendable, CaseIterable {
        /// La sesión no está `active`: pausada, finalizada o aún sin empezar.
        case notActive
        /// Los pasos medidos crecieron desde el inicio del gap: el stream ya los trajo.
        case streamAdvanced
        /// Menos de `minPriorSampleS` de sesión en el inicio del gap: la cadencia medida
        /// todavía no es representativa.
        case noPriorSample
        /// El gap supera `maxEstimableGapS`.
        case gapAboveCap
        /// La estimación no da ni un paso: sin pasos medidos al abrir el gap (cadencia 0), con
        /// un gap no positivo —el reloj fue hacia atrás— o con un valor no representable.
        case noCadence
    }

    /// Lo que decide la estimación de un gap: los pasos, o la defensa que la suprimió.
    public enum Outcome: Sendable, Equatable {
        case estimated(Int)
        case skipped(Skip)
    }

    /// Pasos estimados para el gap `[gapStart, gapEnd]` de `session`, o la razón por la que no
    /// se estima.
    ///
    /// Se comprueban en este orden las cinco razones de `Skip`: la sesión no está `active`
    /// (`.notActive`); los pasos medidos crecieron desde el inicio del gap (`.streamAdvanced`);
    /// hay menos de `minPriorSampleS` de sesión en `gapStart` (`.noPriorSample`); el gap supera
    /// `maxEstimableGapS` (`.gapAboveCap`); y no sale cadencia con la que estimar —incluido un
    /// gap negativo porque el reloj fue hacia atrás— (`.noCadence`).
    ///
    /// **Pasos ya contados (R1).** `measuredAtGapStart` es el acumulado medido al abrir el gap;
    /// si `session.stepsMeasured` es mayor, el stream ya entregó los pasos de ese rato y
    /// estimarlos los contaría dos veces. La comprobación vive aquí, y no en quien llama, para
    /// que los dos argumentos no puedan contradecirse sin que nadie lo mire.
    ///
    /// **Cadencia del inicio del gap (R1).** Se calcula con `measuredAtGapStart` sobre el
    /// tiempo de sesión en ese mismo instante, nunca con los pasos de ahora: mezclar los pasos
    /// de ahora con el tiempo de entonces dobla la cadencia y estima pasos que el stream ya
    /// trajo. Solo cuenta pasos medidos: nunca se estima sobre lo estimado.
    ///
    /// **Tope de gap (R1).** Por encima de `maxEstimableGapS` no se estima nada: la cadencia
    /// de hace tanto ya no dice gran cosa del rato sin datos.
    ///
    /// - Parameters:
    ///   - measuredAtGapStart: `session.stepsMeasured` en `gapStart`, no el de ahora.
    ///   - maxEstimableGapS: gap máximo estimable (`formulas.json`).
    public static func outcome(
        for session: Session,
        measuredAtGapStart: Int,
        gapStart: Date,
        gapEnd: Date,
        maxEstimableGapS: TimeInterval
    ) -> Outcome {
        guard session.status == .active else { return .skipped(.notActive) }
        guard session.stepsMeasured <= measuredAtGapStart else { return .skipped(.streamAdvanced) }
        guard session.elapsedS(at: gapStart) >= minPriorSampleS else { return .skipped(.noPriorSample) }
        let gapS = gapEnd.timeIntervalSince(gapStart)
        guard gapS <= maxEstimableGapS else { return .skipped(.gapAboveCap) }
        do {
            let cadence = try MetricsCalculator.cadenceSpm(
                stepsMeasured: measuredAtGapStart,
                activeSeconds: session.elapsedS(at: gapStart)
            )
            let steps = try estimateSteps(cadenceSpm: cadence, gapS: gapS)
            return steps > 0 ? .estimated(steps) : .skipped(.noCadence)
        } catch {
            // Inalcanzable en la práctica: los pasos medidos no son negativos, el tiempo del
            // cronómetro es finito y los `Date` dan un intervalo finito. Sin un valor
            // representable no se estima.
            return .skipped(.noCadence)
        }
    }
}
