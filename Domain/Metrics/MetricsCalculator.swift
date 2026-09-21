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
    /// Estas métricas son una **degradación**, no una medida: algo no se pudo calcular y
    /// `Session.metrics(at:)` devolvió lo poco que sí sabía en vez de matar el proceso (B-3).
    ///
    /// Es lo único que el dominio puede "registrar" sin un logger —`Domain/` solo importa
    /// `Foundation` (AD-3)—, y es lo que distingue una degradación de una caminata sin pasos,
    /// que tiene exactamente los mismos ceros. Quien lo pinte o lo escriba en `OSLog` es de
    /// fuera; hoy nadie lo hace y queda en `deferred-work.md`.
    public let degraded: Bool

    public init(distanceM: Double, paceSecPerKm: Int?, cadenceSpm: Double, degraded: Bool = false) {
        self.distanceM = distanceM
        self.paceSecPerKm = paceSecPerKm
        self.cadenceSpm = cadenceSpm
        self.degraded = degraded
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

    /// Decimales a los que se redondea la distancia: el `toFixed(2)` de la v3 (AD-6).
    ///
    /// No es un detalle de formato. El redondeo **multiplica por 10² antes de dividir**, así
    /// que este 2 es el factor que decide dónde desborda la fórmula, y por eso
    /// `maxRepresentableStrideM` lo lee de aquí en vez de repetir un 100 a mano.
    public static let distanceFractionDigits = 2

    /// El mayor número de pasos que puede haber en la fórmula: `stepsMeasured + stepsEstimated`
    /// con los dos en su tope.
    ///
    /// Los dos son `Int` que **nunca desbordan** —`Session.addMeasuredSteps` y
    /// `addEstimatedSteps` lanzan `invalidValue(field: "steps")` antes de pasarse—, así que
    /// ninguno supera `Int.max`. `Double(Int.max)` redondea a 2⁶³ (el `Double` más cercano),
    /// de modo que este tope es exactamente 2⁶⁴ ≈ 1,84e19.
    public static let maxSteps: Double = Double(Int.max) + Double(Int.max)

    /// La zancada más larga con la que la fórmula de la distancia **sigue dando un número**,
    /// en metros: ≈ 9,75e286.
    ///
    /// **Derivada, no elegida.** No es una regla de producto ni un "máximo razonable": el
    /// rango humano (0,3–1,2 m) **avisa y no bloquea** y eso no cambia (decisión de Paul,
    /// 2026-09-19). Lo único que hay aquí es aritmética, y sale de tres factores:
    ///
    /// 1. **`Double.greatestFiniteMagnitude`** ≈ 1,798e308 — el mayor finito que existe. Por
    ///    encima, la operación no produce un número: produce `inf`.
    /// 2. **`pow(10, distanceFractionDigits)`** = 100 — `rounded(_:fractionDigits:)` hace
    ///    `(value × 100).rounded() / 100`, así que el ×100 desborda **antes** que el propio
    ///    producto: el techo del producto no es el mayor finito, sino su centésima parte.
    /// 3. **`maxSteps`** = 2⁶⁴ — el mayor número de pasos que el agregado puede contener.
    ///
    /// ```
    /// maxRepresentableStrideM = (greatestFiniteMagnitude / 100) / 2⁶⁴ ≈ 9,745e286
    /// ```
    ///
    /// Es el borde **exacto**, no una aproximación con holgura: con esta zancada y 2⁶⁴ pasos
    /// la distancia sale finita, y con el `Double` siguiente (`.nextUp`) ya no. Lo fija un test
    /// (`MetricsScenarios`), porque la propiedad —no el número— es lo que importa.
    ///
    /// La comprueban las dos fronteras que pueden dejar entrar una zancada: la de escritura
    /// (`AppSettings.isRepresentableStride`, que además sabe decir "no cabe" en vez de "no es
    /// mayor que cero") y la del agregado (`Session.validateStride`).
    public static let maxRepresentableStrideM: Double =
        (Double.greatestFiniteMagnitude / pow(10, Double(distanceFractionDigits))) / maxSteps

    /// `(stepsMeasured + stepsEstimated) × strideM`, redondeada a 2 decimales como el
    /// `toFixed(2)` de la v3.
    ///
    /// **Valida su propio resultado, no solo sus entradas** (B-3). Tres entradas válidas —pasos
    /// ≥ 0 y una zancada > 0 y finita— podían dar `inf`, y un calculador que devuelve `inf` le
    /// pasa el problema al siguiente: `paceSecPerKm` lanzaba y quien la llamaba se caía. Es lo
    /// mismo que hace `GapEstimator.estimateSteps` cuando el producto no cabe en `Int`, con el
    /// campo del valor que no cabe.
    ///
    /// - Throws: `DomainError.invalidValue` con `stepsMeasured` o `stepsEstimated` si son
    ///   negativos, con `strideM` si la zancada es ≤ 0 o no finita, y con `distanceM` si el
    ///   producto redondeado no es representable.
    public static func distanceM(stepsMeasured: Int, stepsEstimated: Int, strideM: Double) throws(DomainError) -> Double {
        guard stepsMeasured >= 0 else { throw .invalidValue(field: "stepsMeasured") }
        guard stepsEstimated >= 0 else { throw .invalidValue(field: "stepsEstimated") }
        guard strideM.isFinite, strideM > 0 else { throw .invalidValue(field: "strideM") }
        // En `Double` y no en `Int`: la suma no puede desbordar.
        let steps = Double(stepsMeasured) + Double(stepsEstimated)
        let distance = rounded(steps * strideM, fractionDigits: distanceFractionDigits)
        guard distance.isFinite else { throw .invalidValue(field: "distanceM") }
        return distance
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
