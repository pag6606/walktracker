import Foundation

/// Contrato de datos de la Live Activity (AD-15). Viaja por `request`/`update` con
/// tope de 4 KB; **no** hay App Group ni disco de por medio: compartir el tipo es
/// pertenencia a target.
///
/// Solo `Foundation`. La conformidad a `ActivityAttributes` exige `ActivityKit` y por
/// eso vive aparte, en `WalkTrackerActivityAttributes.swift`: el contrato de datos no
/// arrastra el framework.
///
/// Lleva **valores ya formateados** más `timerStart`, para que la extensión solo
/// renderice (AD-15) y anime el cronómetro con `Text(timerInterval:)` — el único
/// cálculo que se le permite, y el que mantiene el coste de actualizaciones a cero
/// (AD-21).
public struct ActivitySnapshot: Codable, Hashable, Sendable {

    /// Instante desde el que la extensión cuenta el cronómetro.
    ///
    /// **Ya viene ajustado por las pausas**: es `startedAt` desplazado hacia adelante
    /// por todo el tiempo acumulado en pausa, no el `startedAt` crudo. Por eso
    /// reanudar no cuenta el tiempo pausado, sin que la extensión sepa nada de pausas.
    public let timerStart: Date

    /// Segundos transcurridos, congelados, mientras la sesión está en pausa.
    /// `nil` mientras la sesión corre: entonces manda `timerStart`.
    public let frozenElapsed: TimeInterval?

    /// Pasos, ya formateados por el contenedor (AD-15).
    public let stepsText: String

    /// Distancia, ya formateada por el contenedor (AD-15).
    public let distanceText: String

    /// Ritmo en **segundos por kilómetro**. `nil` cuando el dominio no lo produce
    /// —por debajo de 100 m no hay ritmo (AD-4)—, nunca `0` ni `-1`.
    public let pace: Int?

    public init(
        timerStart: Date,
        frozenElapsed: TimeInterval? = nil,
        stepsText: String,
        distanceText: String,
        pace: Int? = nil
    ) {
        self.timerStart = timerStart
        self.frozenElapsed = frozenElapsed
        self.stepsText = stepsText
        self.distanceText = distanceText
        self.pace = pace
    }
}

// MARK: - Formateo que la extensión necesita (AD-15)
//
// `UI/Format/` no es importable desde la extensión, así que el poco formateo que la
// Live Activity requiere vive aquí. Es también el consumidor real de `pace`.

public extension ActivitySnapshot {

    /// La sesión está en pausa exactamente cuando hay un transcurrido congelado.
    var isPaused: Bool { frozenElapsed != nil }

    /// Ritmo en `m:ss /km`, o `—` cuando el dominio no lo produce (AD-22: una
    /// métrica ausente se representa como tal).
    var paceText: String {
        guard let pace, pace > 0 else { return "—" }
        return String(format: "%d:%02d /km", pace / 60, pace % 60)
    }

    /// Cronómetro congelado en `m:ss` (o `h:mm:ss`) para el estado en pausa, donde
    /// `Text(timerInterval:)` no sirve porque no debe avanzar.
    var frozenElapsedText: String {
        guard let frozenElapsed else { return "—" }
        let total = Int(frozenElapsed.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
