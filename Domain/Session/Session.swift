import Foundation

/// Aggregate root de una caminata (domain-model.md §2, `domain.js:271` `createV3Session`).
///
/// Siempre válido: solo se materializa por `start(at:strideM:)`, que valida la zancada
/// en la frontera. Sus campos no se escriben desde fuera; las mutaciones (pasos,
/// pausas, cierre) entran como operaciones del agregado: pasos en la 1.2, pausas y
/// cierre en la 1.4.
///
/// `distanceM`, `paceSecPerKm` y `cadenceSpm` son derivadas y llegan con su cálculo en
/// la 1.3 (AD-22: una métrica nueva exige antes su cálculo en el dominio).
public struct Session: Equatable, Sendable {

    public let startedAt: Date
    /// Solo al finalizar (1.4).
    public private(set) var endedAt: Date?
    public private(set) var status: SessionStatus
    /// Pasos del coprocesador. Entero ≥ 0 que nunca baja.
    public private(set) var stepsMeasured: Int
    /// Pasos de la degradación del `GapEstimator`. Entero ≥ 0, siempre desglosado.
    public private(set) var stepsEstimated: Int
    /// Zancada en metros, > 0 y finita. Congelada: recalibrar nunca reescribe una sesión.
    public let strideM: Double
    /// Segundos acumulados en pausas cerradas (`pausesS` en el snapshot).
    public private(set) var totalPausesS: TimeInterval
    public let source: SessionSource

    private init(startedAt: Date, strideM: Double) {
        self.startedAt = startedAt
        self.endedAt = nil
        self.status = .active
        self.stepsMeasured = 0
        self.stepsEstimated = 0
        self.strideM = strideM
        self.totalPausesS = 0
        self.source = .ios
    }

    /// Crea una sesión `active` que empieza en `now`.
    ///
    /// - Throws: `DomainError.invalidValue(field: "strideM")` si la zancada es ≤ 0 o no
    ///   finita. Se rechaza **antes** de crear el agregado.
    public static func start(at now: Date, strideM: Double) throws(DomainError) -> Session {
        try validateStride(strideM)
        return Session(startedAt: now, strideM: strideM)
    }

    /// La regla de la zancada, única para el agregado y para las constantes de
    /// `formulas.json`: > 0 y finita.
    public static func validateStride(_ strideM: Double) throws(DomainError) {
        guard strideM.isFinite, strideM > 0 else {
            throw .invalidValue(field: "strideM")
        }
    }

    /// Suma pasos medidos por el coprocesador (`domain.js:316` `addSteps`).
    ///
    /// Recibe un **incremento**, no el acumulado del podómetro: convertir muestras
    /// acumuladas en incrementos es de quien las consume (`SessionStore`). `0` no cambia
    /// nada. La distancia que recalcula el JS no se porta aquí: llega con su cálculo en
    /// la 1.3 (AD-22).
    ///
    /// - Throws: `DomainError.invalidTransition` si la sesión no está `active` (una
    ///   pausada o finalizada no cuenta pasos); `DomainError.invalidValue(field: "steps")`
    ///   si `count` es negativo o desbordaría el contador. En ambos casos no muta.
    public mutating func addMeasuredSteps(_ count: Int) throws(DomainError) {
        guard status == .active else {
            throw .invalidTransition(from: status.rawValue, to: "addMeasuredSteps")
        }
        guard count >= 0 else { throw .invalidValue(field: "steps") }
        guard count > 0 else { return }
        let (total, overflow) = stepsMeasured.addingReportingOverflow(count)
        guard !overflow else { throw .invalidValue(field: "steps") }
        stepsMeasured = total
    }

    /// Tiempo transcurrido en `now`, que el llamante lee de `ClockPort`.
    public func elapsedS(at now: Date) -> TimeInterval {
        Chronometer.elapsedS(startedAt: startedAt, totalPausesS: totalPausesS, now: now)
    }
}
