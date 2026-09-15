import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Formato de la tarjeta de clima (2.1): magnitudes redondeadas, sin "-0", y la condición en
/// español desde el código WMO (tabla de `climate.js:22-37`).
@Suite("WeatherFormat · tarjeta de clima")
struct WeatherFormatTests {

    @Test("Temperatura, humedad, UV y viento redondeados al entero")
    func magnitudes() {
        #expect(WeatherFormat.temperature(18.2) == "18 °C")
        #expect(WeatherFormat.temperature(18.5) == "19 °C")
        #expect(WeatherFormat.temperature(-3.6) == "-4 °C")
        #expect(WeatherFormat.temperature(-0.4) == "0 °C", "nunca -0")
        #expect(WeatherFormat.humidity(82) == "82 %")
        #expect(WeatherFormat.uv(1.55) == "UV 2")
        #expect(WeatherFormat.wind(12.4) == "12 km/h")
    }

    @Test("La condición en español sale del código WMO, con la tabla de la v3")
    func conditions() {
        let expected: [Int: String] = [
            0: "Despejado", 1: "Mayormente despejado", 2: "Parcialmente nublado", 3: "Nublado",
            45: "Niebla", 48: "Niebla con escarcha",
            51: "Llovizna ligera", 53: "Llovizna moderada", 55: "Llovizna densa",
            56: "Llovizna helada ligera", 57: "Llovizna helada densa",
            61: "Lluvia ligera", 63: "Lluvia moderada", 65: "Lluvia intensa",
            66: "Lluvia helada ligera", 67: "Lluvia helada intensa",
            71: "Nevada ligera", 73: "Nevada moderada", 75: "Nevada intensa", 77: "Granos de nieve",
            80: "Chubascos ligeros", 81: "Chubascos moderados", 82: "Chubascos intensos",
            85: "Chubascos de nieve ligeros", 86: "Chubascos de nieve intensos",
            95: "Tormenta", 96: "Tormenta con granizo ligero", 99: "Tormenta con granizo intenso",
        ]
        for (code, text) in expected {
            #expect(String(localized: WeatherFormat.condition(wmoCode: code)) == text, "WMO \(code)")
        }
        #expect(String(localized: WeatherFormat.condition(wmoCode: 4)) == "Condición desconocida")
    }

    @Test("Lectura de VoiceOver: condición, temperatura, humedad, UV y viento, redondeados")
    func spoken() throws {
        let weather = try WeatherSnapshot(
            tempC: 18, feelsLikeC: 17.5, wmoCode: 61, humidityPct: 82, uvIndex: 1.5, windKmh: 12.4,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(WeatherFormat.spoken(weather) == "Lluvia ligera, 18 °C, humedad 82 %, UV 2, viento 12 km/h")
    }

    @Test("Cada código con texto tiene un SF Symbol de clima; uno desconocido, el termómetro")
    func symbols() {
        #expect(WeatherFormat.symbolName(wmoCode: 61) == "cloud.rain.fill")
        #expect(WeatherFormat.symbolName(wmoCode: 0) == "sun.max.fill")
        #expect(WeatherFormat.symbolName(wmoCode: 95) == "cloud.bolt.rain.fill")
        #expect(WeatherFormat.symbolName(wmoCode: 42) == "thermometer.medium")
    }
}
