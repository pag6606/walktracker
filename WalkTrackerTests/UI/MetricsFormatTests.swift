import Foundation
import Testing

@testable import WalkTracker

@Suite("Formato de las métricas")
struct MetricsFormatTests {

    private static let es = Locale(identifier: "es_ES")

    // MARK: - Distancia

    @Test("Distancia: km con 2 decimales y coma en español, truncando al centésimo")
    func distanceText() {
        #expect(DistanceFormat.kilometers(0, locale: Self.es) == "0,00")
        #expect(DistanceFormat.kilometers(3261.9, locale: Self.es) == "3,26")
        #expect(DistanceFormat.kilometers(3400, locale: Self.es) == "3,40")
        #expect(DistanceFormat.kilometers(99.99, locale: Self.es) == "0,09")
        #expect(DistanceFormat.kilometers(100, locale: Self.es) == "0,10")
        #expect(DistanceFormat.kilometers(12_345.6, locale: Self.es) == "12,34")
    }

    @Test("Distancia: negativa o no finita se muestra como 0", arguments: [-5, Double.nan, .infinity])
    func distanceInvalid(meters: Double) {
        #expect(DistanceFormat.kilometers(meters, locale: Self.es) == "0,00")
    }

    @Test("Distancia: VoiceOver lee la magnitud completa")
    func distanceSpoken() {
        #expect(DistanceFormat.spoken(3240, locale: Self.es) == "3,24 kilómetros")
        #expect(DistanceFormat.spoken(3249, locale: Self.es) == "3,24 kilómetros", "trunca, como en pantalla")
    }

    // MARK: - Ritmo

    @Test("Ritmo: m:ss, con minutos sin tope, y — sin ritmo")
    func paceText() {
        #expect(PaceFormat.text(nil) == "—")
        #expect(PaceFormat.text(1140) == "19:00")
        #expect(PaceFormat.text(1094) == "18:14")
        #expect(PaceFormat.text(599) == "9:59")
        #expect(PaceFormat.text(5) == "0:05")
        #expect(PaceFormat.text(4530) == "75:30")
        #expect(PaceFormat.text(0) == "—")
        #expect(PaceFormat.text(-1) == "—")
    }

    @Test("Ritmo: VoiceOver lee la duración por kilómetro, y lo dice cuando aún no hay")
    func paceSpoken() {
        #expect(PaceFormat.spoken(1094, locale: Self.es) == "18 minutos y 14 segundos por kilómetro")
        #expect(PaceFormat.spoken(nil, locale: Self.es) == "Sin ritmo hasta los 100 metros")
        #expect(!PaceFormat.spoken(nil, locale: Self.es).contains("—"))
    }

    // MARK: - Cadencia

    @Test("Cadencia: spm entero en pantalla")
    func cadenceText() {
        #expect(CadenceFormat.text(0, locale: Self.es) == "0")
        #expect(CadenceFormat.text(80.3, locale: Self.es) == "80")
        #expect(CadenceFormat.text(84.5, locale: Self.es) == "85")
        #expect(CadenceFormat.text(-3, locale: Self.es) == "0")
        #expect(CadenceFormat.text(.nan, locale: Self.es) == "0")
    }

    @Test("Cadencia: VoiceOver lee pasos por minuto")
    func cadenceSpoken() {
        #expect(CadenceFormat.spoken(80.3, locale: Self.es) == "80 pasos por minuto")
        #expect(CadenceFormat.spoken(1, locale: Self.es) == "1 paso por minuto")
    }
}

/// El desglose de pasos estimados de la celda (1.5): nunca se suman a los medidos.
@MainActor
@Suite("Celda de pasos · desglose de estimados")
struct MetricCellStepsTests {

    @Test("Con estimados: el valor son solo los medidos y el desglose, \"~236\"")
    func withEstimated() {
        let cell = MetricCell.steps(4100, estimated: 236)
        #expect(cell.value == 4100.formatted(.number))
        #expect(cell.estimate == "~236")
    }

    @Test("Sin estimados (o tras descartarlos) no hay desglose, ni \"~0\"")
    func withoutEstimated() {
        #expect(MetricCell.steps(4100).estimate == nil)
        #expect(MetricCell.steps(4100, estimated: 0).estimate == nil)
        #expect(MetricCell.steps(4100, estimated: 0).value == 4100.formatted(.number))
    }
}
