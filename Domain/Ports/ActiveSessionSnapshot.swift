import Foundation

/// Snapshot de la sesión viva para recuperarla tras un force-quit o una purga del sistema
/// (CAP-1, AD-9, domain-model.md §8 `activeSession`).
///
/// Va en **segundos y `Date`**, como el dominio: los milisegundos del fichero son del
/// adapter de persistencia. El clima (2.1) viaja con la sesión; la frase (§8) llega con la 2.2.
///
/// Además de los campos de la sesión lleva el tramo del podómetro en curso
/// (`segmentStart`, `segmentSteps`, `distanceBaseM`): al restaurar, el stream se reabre
/// desde `segmentStart` con ese máximo visto, y así sus acumulados, que incluyen lo andado
/// con la app cerrada, solo suman lo nuevo.
public struct ActiveSessionSnapshot: Equatable, Sendable {
    public let startedAt: Date
    public let stepsMeasured: Int
    public let stepsEstimated: Int
    /// Segundos acumulados en pausas cerradas.
    public let totalPausesS: TimeInterval
    public let paused: Bool
    /// Inicio de la pausa en curso: solo si `paused`.
    public let pausedAt: Date?
    public let strideM: Double
    /// Última distancia acumulada del sistema en metros, o `nil` si no la dio.
    public let systemDistanceM: Double?
    /// Instante del guardado: el inicio del gap que queda por reconciliar al restaurar.
    public let savedAt: Date
    /// `end` de la última muestra del coprocesador que sumó pasos, o `nil` sin ninguna.
    /// Es el recorte de una sesión huérfana (AD-18).
    public let lastSampleAt: Date?
    /// Inicio del tramo del podómetro en curso: el de la sesión o el de la última reanudación.
    public let segmentStart: Date
    /// Mayor acumulado del podómetro visto en el tramo en curso.
    public let segmentSteps: Int
    /// Distancia del sistema acumulada al abrir el tramo en curso, en metros.
    public let distanceBaseM: Double
    /// Clima capturado al inicio, o `nil` sin clima. Se conserva al restaurar (2.1).
    public let weather: WeatherSnapshot?

    public init(
        startedAt: Date,
        stepsMeasured: Int,
        stepsEstimated: Int,
        totalPausesS: TimeInterval,
        paused: Bool,
        pausedAt: Date?,
        strideM: Double,
        systemDistanceM: Double?,
        savedAt: Date,
        lastSampleAt: Date?,
        segmentStart: Date,
        segmentSteps: Int,
        distanceBaseM: Double,
        weather: WeatherSnapshot? = nil
    ) {
        self.startedAt = startedAt
        self.stepsMeasured = stepsMeasured
        self.stepsEstimated = stepsEstimated
        self.totalPausesS = totalPausesS
        self.paused = paused
        self.pausedAt = pausedAt
        self.strideM = strideM
        self.systemDistanceM = systemDistanceM
        self.savedAt = savedAt
        self.lastSampleAt = lastSampleAt
        self.segmentStart = segmentStart
        self.segmentSteps = segmentSteps
        self.distanceBaseM = distanceBaseM
        self.weather = weather
    }
}
