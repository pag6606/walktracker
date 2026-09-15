import Domain
import SwiftUI

/// Tarjeta de clima de la sesión (2.1), bajo las métricas. Estática: pinta el snapshot
/// congelado al inicio y nunca se refresca.
///
/// Tres estados, nunca un error ni un cero (AD-22, "celebrar, nunca culpar"):
/// - **con clima:** SF Symbol de la condición, temperatura, condición en español desde el
///   código WMO y una fila con humedad, UV y viento, más la atribución "Datos: Open-Meteo" como
///   enlace a open-meteo.com (CC-BY 4.0 y términos de Open-Meteo, AD-24);
/// - **capturando:** un indicador de espera, sin números;
/// - **sin clima:** "Sin clima", en calma.
///
/// VoiceOver lee el clima como un solo elemento y la atribución aparte, como enlace.
struct WeatherCard: View {

    let weather: WeatherSnapshot?
    let isCapturing: Bool

    var body: some View {
        Group {
            if let weather {
                content(weather)
            } else if isCapturing {
                placeholder {
                    ProgressView()
                        .accessibilityHidden(true)
                    Text("Buscando el clima…")
                }
            } else {
                placeholder {
                    Image(systemName: "cloud.slash")
                        .accessibilityHidden(true)
                    Text("Sin clima")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }

    /// Destino de la atribución (CC-BY 4.0).
    static let attributionURL = URL(string: "https://open-meteo.com/")!

    private func content(_ weather: WeatherSnapshot) -> some View {
        VStack(spacing: 0) {
            summary(weather)
            Link(destination: Self.attributionURL) {
                Text("Datos: Open-Meteo")
                    .font(.caption2)
                    .underline()
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func summary(_ weather: WeatherSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: WeatherFormat.symbolName(wmoCode: weather.wmoCode))
                    .symbolRenderingMode(.multicolor)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: WeatherFormat.temperature(weather.tempC))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(WeatherFormat.condition(wmoCode: weather.wmoCode))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { details(weather) }
                VStack(alignment: .leading, spacing: 4) { details(weather) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Clima"))
        .accessibilityValue(Text(WeatherFormat.spoken(weather)))
    }

    @ViewBuilder
    private func details(_ weather: WeatherSnapshot) -> some View {
        Label {
            Text(verbatim: WeatherFormat.humidity(weather.humidityPct))
        } icon: {
            Image(systemName: "humidity")
        }
        Label {
            Text(verbatim: WeatherFormat.uv(weather.uvIndex))
        } icon: {
            Image(systemName: "sun.max")
        }
        Label {
            Text(verbatim: WeatherFormat.wind(weather.windKmh))
        } icon: {
            Image(systemName: "wind")
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Formato del clima para la tarjeta: textos en español desde el código WMO (tabla de
/// `climate.js:22-37`, salvo el 77, que son granos de nieve y no granizo) y magnitudes redondeadas al entero. Nunca sale de un texto: la categoría
/// interna (`WeatherCondition`) es del dominio.
enum WeatherFormat {

    /// "18 °C". Nunca "-0 °C".
    static func temperature(_ celsius: Double) -> String {
        "\(rounded(celsius)) °C"
    }

    /// "82 %".
    static func humidity(_ percent: Double) -> String {
        "\(rounded(percent)) %"
    }

    /// "UV 2".
    static func uv(_ index: Double) -> String {
        "UV \(rounded(index))"
    }

    /// "12 km/h".
    static func wind(_ kmh: Double) -> String {
        "\(rounded(kmh)) km/h"
    }

    /// Lectura completa de VoiceOver: "Lluvia ligera, 18 °C, humedad 82 %, UV 2, viento 12 km/h".
    static func spoken(_ weather: WeatherSnapshot) -> String {
        String(
            localized: "\(String(localized: condition(wmoCode: weather.wmoCode))), \(temperature(weather.tempC)), humedad \(humidity(weather.humidityPct)), \(uv(weather.uvIndex)), viento \(wind(weather.windKmh))",
            comment: "Lectura de VoiceOver de la tarjeta de clima de la sesión: condición, temperatura, humedad, índice UV y viento. Ejemplo: \"Lluvia ligera, 18 °C, humedad 82 %, UV 2, viento 12 km/h\"."
        )
    }

    /// Entero más cercano, con la mitad lejos de cero; `-0` sale como `0`.
    private static func rounded(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        guard rounded > Double(Int.min), rounded < Double(Int.max) else { return 0 }
        return Int(rounded)
    }

    /// La condición en español de un código WMO 4677, o "Condición desconocida".
    static func condition(wmoCode: Int) -> LocalizedStringResource {
        switch wmoCode {
        case 0: LocalizedStringResource("Despejado", comment: "Condición del clima, código WMO 0, en la tarjeta de clima de la sesión.")
        case 1: LocalizedStringResource("Mayormente despejado", comment: "Condición del clima, código WMO 1, en la tarjeta de clima de la sesión.")
        case 2: LocalizedStringResource("Parcialmente nublado", comment: "Condición del clima, código WMO 2, en la tarjeta de clima de la sesión.")
        case 3: LocalizedStringResource("Nublado", comment: "Condición del clima, código WMO 3, en la tarjeta de clima de la sesión.")
        case 45: LocalizedStringResource("Niebla", comment: "Condición del clima, código WMO 45, en la tarjeta de clima de la sesión.")
        case 48: LocalizedStringResource("Niebla con escarcha", comment: "Condición del clima, código WMO 48, en la tarjeta de clima de la sesión.")
        case 51: LocalizedStringResource("Llovizna ligera", comment: "Condición del clima, código WMO 51, en la tarjeta de clima de la sesión.")
        case 53: LocalizedStringResource("Llovizna moderada", comment: "Condición del clima, código WMO 53, en la tarjeta de clima de la sesión.")
        case 55: LocalizedStringResource("Llovizna densa", comment: "Condición del clima, código WMO 55, en la tarjeta de clima de la sesión.")
        case 56: LocalizedStringResource("Llovizna helada ligera", comment: "Condición del clima, código WMO 56, en la tarjeta de clima de la sesión.")
        case 57: LocalizedStringResource("Llovizna helada densa", comment: "Condición del clima, código WMO 57, en la tarjeta de clima de la sesión.")
        case 61: LocalizedStringResource("Lluvia ligera", comment: "Condición del clima, código WMO 61, en la tarjeta de clima de la sesión.")
        case 63: LocalizedStringResource("Lluvia moderada", comment: "Condición del clima, código WMO 63, en la tarjeta de clima de la sesión.")
        case 65: LocalizedStringResource("Lluvia intensa", comment: "Condición del clima, código WMO 65, en la tarjeta de clima de la sesión.")
        case 66: LocalizedStringResource("Lluvia helada ligera", comment: "Condición del clima, código WMO 66, en la tarjeta de clima de la sesión.")
        case 67: LocalizedStringResource("Lluvia helada intensa", comment: "Condición del clima, código WMO 67, en la tarjeta de clima de la sesión.")
        case 71: LocalizedStringResource("Nevada ligera", comment: "Condición del clima, código WMO 71, en la tarjeta de clima de la sesión.")
        case 73: LocalizedStringResource("Nevada moderada", comment: "Condición del clima, código WMO 73, en la tarjeta de clima de la sesión.")
        case 75: LocalizedStringResource("Nevada intensa", comment: "Condición del clima, código WMO 75, en la tarjeta de clima de la sesión.")
        case 77: LocalizedStringResource("Granos de nieve", comment: "Condición del clima, código WMO 77 (granos de nieve, no granizo), en la tarjeta de clima de la sesión.")
        case 80: LocalizedStringResource("Chubascos ligeros", comment: "Condición del clima, código WMO 80, en la tarjeta de clima de la sesión.")
        case 81: LocalizedStringResource("Chubascos moderados", comment: "Condición del clima, código WMO 81, en la tarjeta de clima de la sesión.")
        case 82: LocalizedStringResource("Chubascos intensos", comment: "Condición del clima, código WMO 82, en la tarjeta de clima de la sesión.")
        case 85: LocalizedStringResource("Chubascos de nieve ligeros", comment: "Condición del clima, código WMO 85, en la tarjeta de clima de la sesión.")
        case 86: LocalizedStringResource("Chubascos de nieve intensos", comment: "Condición del clima, código WMO 86, en la tarjeta de clima de la sesión.")
        case 95: LocalizedStringResource("Tormenta", comment: "Condición del clima, código WMO 95, en la tarjeta de clima de la sesión.")
        case 96: LocalizedStringResource("Tormenta con granizo ligero", comment: "Condición del clima, código WMO 96, en la tarjeta de clima de la sesión.")
        case 99: LocalizedStringResource("Tormenta con granizo intenso", comment: "Condición del clima, código WMO 99, en la tarjeta de clima de la sesión.")
        default: LocalizedStringResource("Condición desconocida", comment: "Condición del clima para un código WMO sin texto propio, en la tarjeta de clima de la sesión.")
        }
    }

    /// SF Symbol de un código WMO 4677. El emoji queda para las insignias de logro.
    static func symbolName(wmoCode: Int) -> String {
        switch wmoCode {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...65: "cloud.rain.fill"
        case 66, 67: "cloud.sleet.fill"
        case 71...77: "cloud.snow.fill"
        case 80...82: "cloud.heavyrain.fill"
        case 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "thermometer.medium"
        }
    }
}
