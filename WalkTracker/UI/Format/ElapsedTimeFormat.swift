import Foundation

/// Conversión de segundos del dominio a texto de cronómetro. El dominio trabaja en
/// segundos; el formato vive aquí, en `UI/Format/`.
enum ElapsedTimeFormat {

    /// `m:ss` por debajo de una hora y `h:mm:ss` a partir de ella. Trunca al segundo:
    /// el cronómetro no muestra un segundo que aún no ha pasado.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// La magnitud completa para VoiceOver ("5 minutos y 3 segundos"), no "5:03".
    /// Trunca al segundo, como `clock`.
    static func spoken(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        return Duration.seconds(total).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale)
        )
    }
}
