import Foundation

/// Una caminata **cerrada**, tal y como se guarda en `sessions.json` (5.1, CAP-9, FR-9;
/// domain-model.md §8 `sessions`) — AD-9, AD-16.
///
/// Es el registro **inmutable** que sobrevive al cierre de la app, y el DTO de frontera del
/// historial: todos sus campos son `let`, se construye validando en la frontera (el molde de
/// `WorkoutRecord`) y nada lo muta después. Recalibrar la zancada no reescribe historial: por eso
/// `strideM` viaja **dentro** del registro y no se vuelve a leer de los ajustes.
///
/// **Las derivadas vienen materializadas, no se recalculan.** `distanceM`, `paceSecPerKm` y
/// `cadenceSpm` salen de `Session.metrics(at:)` en el instante del cierre y se congelan aquí; un
/// historial que las recalculara al leer daría números distintos en cuanto cambiara una constante
/// de `formulas.json`.
///
/// **Dos columnas que no están en el agregado y sin las cuales el registro mentiría:**
///
/// - `recovered` — la sesión la cerró la app al arrancar, no Paul (AD-18). Entra en el historial
///   con su marca: sus pasos son reales y **suman** distancia y anillo, pero **no disparan
///   logros** (`countsForAchievements`).
/// - `degraded` — las métricas de este registro son la degradación de `metrics(at:)`, no una
///   medida (B-3). Sin la marca, el `distanceM: 0` de un cálculo que no cuadró es indistinguible
///   en disco de una caminata sin pasos, y el registro es inmutable: no hay una segunda
///   oportunidad de decirlo.
///
/// `source` es `"ios"` para todo lo que produce la v1 (arranque limpio, OQ-3).
public struct SessionRecord: Equatable, Sendable, Identifiable {

    /// Identidad estable del registro, generada fuera del dominio (AD-3: aquí no hay azar ni
    /// reloj). Es la clave de idempotencia del import de la 5.3 y del borrado de la 5.4.
    public let id: UUID
    /// Inicio de la caminata. Es además la **clave natural** de una sesión: no puede haber dos
    /// caminatas que empiecen en el mismo instante, y por eso sirve para reconocer en el
    /// historial la que un snapshot huérfano querría archivar por segunda vez (ver
    /// `SessionStore.restoreOnLaunch()`).
    public let startedAt: Date
    /// Instante del cierre. **No es estrictamente posterior a `startedAt`**, a diferencia de
    /// `WorkoutRecord.end`: una huérfana sin ninguna muestra del coprocesador se cierra en su
    /// propio `startedAt` (AD-18), y ese registro es legítimo.
    public let endedAt: Date
    /// Pasos del coprocesador. No negativos.
    public let stepsMeasured: Int
    /// Pasos de la degradación del `GapEstimator`. No negativos y **siempre desglosados**:
    /// medidos y estimados nunca se suman en disco.
    public let stepsEstimated: Int
    /// Zancada con la que se calculó esta caminata, en metros. **Congelada**: recalibrar después
    /// no la cambia. Pasa por `Session.validateStride`, la misma puerta que el agregado.
    public let strideM: Double
    /// Distancia en metros, materializada al cerrar. No negativa y finita.
    public let distanceM: Double
    /// Segundos netos de la caminata, ya redondeados por el agregado. No negativos.
    public let durationS: Int
    /// Segundos acumulados en pausas, ya redondeados por el agregado. No negativos.
    public let pausesS: Int
    /// Segundos por kilómetro, o `nil` por debajo de `MetricsCalculator.minPaceDistanceM`. Una
    /// magnitud ausente se guarda ausente, nunca como `0` (AD-22).
    public let paceSecPerKm: Int?
    /// Pasos por minuto sobre los medidos. No negativa y finita.
    public let cadenceSpm: Double
    /// Clima congelado al inicio (2.1), o `nil` sin clima.
    public let weather: WeatherSnapshot?
    /// `id` de la frase mostrada al iniciar (2.2), o `nil` sin frase.
    public let quoteId: Int?
    /// Procedencia. `ios` para todo lo de la v1.
    public let source: SessionSource
    /// La cerró la app al arrancar, no Paul (AD-18).
    public let recovered: Bool
    /// Las métricas de este registro son una degradación, no una medida (B-3).
    public let degraded: Bool

    /// - Throws: `DomainError.invalidValue` con el campo que no cruza la frontera:
    ///   `endedAt` (anterior a `startedAt`), `stepsMeasured` / `stepsEstimated` (< 0), `strideM`
    ///   (≤ 0, no finita o no representable), `distanceM` (< 0 o no finita), `durationS` /
    ///   `pausesS` (< 0), `paceSecPerKm` (≤ 0) o `cadenceSpm` (< 0 o no finita).
    public init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        stepsMeasured: Int,
        stepsEstimated: Int,
        strideM: Double,
        distanceM: Double,
        durationS: Int,
        pausesS: Int,
        paceSecPerKm: Int?,
        cadenceSpm: Double,
        weather: WeatherSnapshot? = nil,
        quoteId: Int? = nil,
        source: SessionSource = .ios,
        recovered: Bool = false,
        degraded: Bool = false
    ) throws(DomainError) {
        guard endedAt >= startedAt else { throw .invalidValue(field: "endedAt") }
        guard stepsMeasured >= 0 else { throw .invalidValue(field: "stepsMeasured") }
        guard stepsEstimated >= 0 else { throw .invalidValue(field: "stepsEstimated") }
        try Session.validateStride(strideM)
        guard distanceM.isFinite, distanceM >= 0 else { throw .invalidValue(field: "distanceM") }
        guard durationS >= 0 else { throw .invalidValue(field: "durationS") }
        guard pausesS >= 0 else { throw .invalidValue(field: "pausesS") }
        if let paceSecPerKm {
            guard paceSecPerKm > 0 else { throw .invalidValue(field: "paceSecPerKm") }
        }
        guard cadenceSpm.isFinite, cadenceSpm >= 0 else { throw .invalidValue(field: "cadenceSpm") }

        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stepsMeasured = stepsMeasured
        self.stepsEstimated = stepsEstimated
        self.strideM = strideM
        self.distanceM = distanceM
        self.durationS = durationS
        self.pausesS = pausesS
        self.paceSecPerKm = paceSecPerKm
        self.cadenceSpm = cadenceSpm
        self.weather = weather
        self.quoteId = quoteId
        self.source = source
        self.recovered = recovered
        self.degraded = degraded
    }

    /// Pasos totales de la caminata. Los dos sumandos siguen guardados aparte: esto es una
    /// lectura, no lo que hay en disco.
    public var stepsTotal: Int { stepsMeasured + stepsEstimated }

    /// Esta caminata puede **desbloquear logros**.
    ///
    /// **Es el punto donde se enchufa la 3.2, y existe ya porque AD-18 se decide aquí**: una
    /// sesión huérfana se archiva y **no dispara celebración**, así que el evaluador de logros
    /// tiene que poder distinguirla sin volver a razonar sobre `recovered` en cada llamada. Lo
    /// que AD-18 prohíbe es la celebración, **no la existencia**: la distancia de una huérfana es
    /// real —la contó el coprocesador— y suma en el anillo semanal (3.1) y en los totales (5.2).
    public var countsForAchievements: Bool { !recovered }
}
