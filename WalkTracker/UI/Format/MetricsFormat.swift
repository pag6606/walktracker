import Foundation

// Conversión de las métricas del dominio (metros, s/km, spm) a texto. El dominio no
// sabe de kilómetros ni de `m:ss`: el formato vive aquí, en `UI/Format/` (AD-22). Cada
// magnitud tiene su texto en pantalla y su forma hablada completa para VoiceOver.

/// Distancia en kilómetros con 2 decimales.
enum DistanceFormat {

    /// "3,26" en español, sin unidad: la vista la pinta aparte. Trunca al centésimo de
    /// kilómetro, como el cronómetro al segundo: no muestra una distancia aún no
    /// recorrida, y "0,10" aparece a la vez que el ritmo.
    static func kilometers(_ meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        truncatedKilometers(meters).formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    /// La magnitud completa para VoiceOver: "3,26 kilómetros", no "3,26".
    static func spoken(_ meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: truncatedKilometers(meters), unit: UnitLength.kilometers).formatted(
            .measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)))
                .locale(locale)
        )
    }

    private static func truncatedKilometers(_ meters: Double) -> Double {
        guard meters.isFinite, meters > 0 else { return 0 }
        return (meters / 10).rounded(.down) / 100
    }
}

/// Ritmo en minutos por kilómetro.
enum PaceFormat {

    /// Lo que se pinta sin ritmo (AD-22): por debajo de 100 m el dominio no lo produce.
    static let absent = "—"

    /// `m:ss` ("19:00"), con los minutos sin tope; "—" si no hay ritmo.
    static func text(_ secPerKm: Int?) -> String {
        guard let seconds = validSeconds(secPerKm) else { return absent }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "19 minutos por kilómetro" para VoiceOver; sin ritmo, lo dice en vez de leer "—".
    static func spoken(_ secPerKm: Int?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let seconds = validSeconds(secPerKm) else {
            return String(localized: "Sin ritmo hasta los 100 metros", locale: locale, comment: "Lectura de VoiceOver del ritmo cuando aún no existe: por debajo de 100 m.")
        }
        let duration = Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale)
        )
        return String(localized: "\(duration) por kilómetro", locale: locale, comment: "Lectura de VoiceOver del ritmo: una duración (\"19 minutos y 5 segundos\") por kilómetro.")
    }

    private static func validSeconds(_ secPerKm: Int?) -> Int? {
        guard let secPerKm, secPerKm > 0 else { return nil }
        return secPerKm
    }
}

/// Cadencia en pasos por minuto, entera en pantalla (el dominio conserva el decimal).
enum CadenceFormat {

    /// "80" para 80,3 spm, sin unidad: la vista la pinta aparte.
    static func text(_ spm: Double, locale: Locale = .autoupdatingCurrent) -> String {
        wholeSpm(spm).formatted(.number.locale(locale))
    }

    /// "80 pasos por minuto" para VoiceOver, no "80 spm".
    static func spoken(_ spm: Double, locale: Locale = .autoupdatingCurrent) -> String {
        String(localized: "\(wholeSpm(spm)) pasos por minuto", locale: locale, comment: "Lectura de VoiceOver de la cadencia en la pantalla de sesión: la magnitud completa.")
    }

    private static func wholeSpm(_ spm: Double) -> Int {
        guard spm.isFinite, spm > 0 else { return 0 }
        let whole = spm.rounded(.toNearestOrAwayFromZero)
        return whole < Double(Int.max) ? Int(whole) : Int.max
    }
}
