import Foundation

/// Métricas derivadas de una sesión en un instante (CAP-4). Solo existen si las produce
/// el dominio (AD-22): la vista las formatea, nunca las calcula.
public struct SessionMetrics: Equatable, Sendable {
    /// Metros recorridos. De la fuente que haya: la UI no la distingue.
    public let distanceM: Double
    /// Segundos por kilómetro, o `nil` por debajo de `MetricsCalculator.minPaceDistanceM`.
    public let paceSecPerKm: Int?
    /// Pasos por minuto, **solo** sobre pasos medidos; con un decimal.
    public let cadenceSpm: Double

    public init(distanceM: Double, paceSecPerKm: Int?, cadenceSpm: Double) {
        self.distanceM = distanceM
        self.paceSecPerKm = paceSecPerKm
        self.cadenceSpm = cadenceSpm
    }
}

/// Cálculo de distancia, ritmo y cadencia (domain-model.md §4, `domain.js:299`
/// `v3distance`, `:105` `pace` y `:525` `calculateCadence`). Funciones puras con vectores
/// (AD-6); los redondeos son los de la v3.
public enum MetricsCalculator {

    /// Distancia mínima para que exista ritmo (CAP-4). Es una regla de producto, no una
    /// calibración provisional: por eso vive aquí y no en `formulas.json`. La aplica
    /// quien pide el ritmo (`domain.js:355`), no `paceSecPerKm`.
    public static let minPaceDistanceM: Double = 100

    /// `(stepsMeasured + stepsEstimated) × strideM`, redondeada a 2 decimales como el
    /// `toFixed(2)` de la v3.
    ///
    /// - Throws: `DomainError.invalidValue` con `stepsMeasured` o `stepsEstimated` si son
    ///   negativos, o con `strideM` si la zancada es ≤ 0 o no finita.
    public static func distanceM(stepsMeasured: Int, stepsEstimated: Int, strideM: Double) throws(DomainError) -> Double {
        guard stepsMeasured >= 0 else { throw .invalidValue(field: "stepsMeasured") }
        guard stepsEstimated >= 0 else { throw .invalidValue(field: "stepsEstimated") }
        guard strideM.isFinite, strideM > 0 else { throw .invalidValue(field: "strideM") }
        // En `Double` y no en `Int`: la suma no puede desbordar.
        let steps = Double(stepsMeasured) + Double(stepsEstimated)
        return rounded(steps * strideM, fractionDigits: 2)
    }

    /// Segundos por kilómetro: `round(movingS / km)`.
    ///
    /// `nil` sin movimiento (distancia o tiempo ≤ 0), donde la v3 devuelve `Infinity`: una
    /// métrica ausente es ausente (AD-4). También `nil` si el ritmo no cabe en un entero.
    /// El umbral de `minPaceDistanceM` **no** se aplica aquí.
    ///
    /// - Throws: `DomainError.invalidValue` con `movingS` o `distanceM` si no son finitos.
    public static func paceSecPerKm(movingS: TimeInterval, distanceM: Double) throws(DomainError) -> Int? {
        guard movingS.isFinite else { throw .invalidValue(field: "movingS") }
        guard distanceM.isFinite else { throw .invalidValue(field: "distanceM") }
        guard distanceM > 0, movingS > 0 else { return nil }
        let pace = (movingS / (distanceM / 1000)).rounded(.toNearestOrAwayFromZero)
        guard pace.isFinite, pace < Double(Int.max) else { return nil }
        return Int(pace)
    }

    /// Pasos por minuto sobre tramos medidos, con 1 decimal. `0` si no hay pasos o no hay
    /// tiempo. Nunca recibe pasos estimados (domain-model.md §4).
    ///
    /// - Throws: `DomainError.invalidValue` con `stepsMeasured` si es negativo, o con
    ///   `activeSeconds` si es negativo o no finito.
    public static func cadenceSpm(stepsMeasured: Int, activeSeconds: TimeInterval) throws(DomainError) -> Double {
        guard stepsMeasured >= 0 else { throw .invalidValue(field: "stepsMeasured") }
        guard activeSeconds.isFinite, activeSeconds >= 0 else { throw .invalidValue(field: "activeSeconds") }
        guard stepsMeasured > 0, activeSeconds > 0 else { return 0 }
        return rounded(Double(stepsMeasured) / (activeSeconds / 60), fractionDigits: 1)
    }

    private static func rounded(_ value: Double, fractionDigits: Int) -> Double {
        let scale = pow(10, Double(fractionDigits))
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }
}
