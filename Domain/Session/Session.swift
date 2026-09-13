import Foundation

/// Aggregate root de una caminata (domain-model.md §2, `domain.js:271` `createV3Session`).
///
/// Siempre válido: solo se materializa por `start(at:strideM:)`, que valida la zancada
/// en la frontera. Sus campos no se escriben desde fuera; las mutaciones (pasos,
/// pausas, cierre) entran como operaciones del agregado en las historias 1.2–1.4.
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

    /// Tiempo transcurrido en `now`, que el llamante lee de `ClockPort`.
    public func elapsedS(at now: Date) -> TimeInterval {
        Chronometer.elapsedS(startedAt: startedAt, totalPausesS: totalPausesS, now: now)
    }
}
