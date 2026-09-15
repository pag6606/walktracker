import Domain
import Foundation
import Testing

/// `WeatherSnapshot` y `WeatherCondition` (2.1): la tabla WMO → categoría interna, la
/// validación en la frontera y el clima en el agregado `Session` (una vez, nunca en una
/// finalizada, conservado al restaurar).
@Suite("WeatherSnapshot · clima del inicio")
struct WeatherSnapshotTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func snapshot(
        tempC: Double = 18,
        feelsLikeC: Double = 17.5,
        wmoCode: Int = 61,
        humidityPct: Double = 82,
        uvIndex: Double = 1.5,
        windKmh: Double = 12.4
    ) throws -> WeatherSnapshot {
        try WeatherSnapshot(
            tempC: tempC, feelsLikeC: feelsLikeC, wmoCode: wmoCode, humidityPct: humidityPct,
            uvIndex: uvIndex, windKmh: windKmh, capturedAt: t0
        )
    }

    // MARK: - Tabla WMO

    /// Los códigos de lluvia de AD-6 (divergencia `wmoCategory`): 51–67, 80–82 y 95–99.
    private static let rainCodes = Set(51...67).union(80...82).union(95...99)

    @Test("Tabla WMO: rain exactamente en 51–67, 80–82 y 95–99; other en el resto de 0–99", arguments: 0...99)
    func wmoTable(code: Int) {
        let expected: WeatherCondition = Self.rainCodes.contains(code) ? .rain : .other
        #expect(WeatherCondition(wmoCode: code) == expected)
    }

    @Test("Los casos de lluvia de evaluateAchievements.json (51, 61, 67, 95, 99) son rain; nieve, niebla y nublado no")
    func vectorRainCodes() {
        for code in [51, 61, 67, 95, 99, 56, 80, 82] {
            #expect(WeatherCondition(wmoCode: code) == .rain, "WMO \(code)")
        }
        for code in [0, 3, 45, 50, 68, 71, 77, 79, 83, 85, 94] {
            #expect(WeatherCondition(wmoCode: code) == .other, "WMO \(code)")
        }
    }

    // MARK: - Frontera

    @Test("Snapshot válido: conserva el código WMO, deriva la condición y fija capturedAt")
    func validSnapshot() throws {
        let rain = try Self.snapshot()
        #expect(rain.wmoCode == 61)
        #expect(rain.condition == .rain)
        #expect(rain.tempC == 18)
        #expect(rain.capturedAt == Self.t0)

        let cloudy = try Self.snapshot(wmoCode: 3)
        #expect(cloudy.wmoCode == 3)
        #expect(cloudy.condition == .other)
    }

    @Test("Los extremos del rango valen: humedad 0 y 100, UV 0, viento 0, WMO 0 y 99, temperaturas bajo cero")
    func boundaries() throws {
        _ = try Self.snapshot(tempC: -40, feelsLikeC: -48, wmoCode: 0, humidityPct: 0, uvIndex: 0, windKmh: 0)
        _ = try Self.snapshot(wmoCode: 99, humidityPct: 100, uvIndex: 14)
    }

    @Test("Fuera de rango o no finito: invalidValue con su campo")
    func invalid() {
        let cases: [(field: String, make: () throws -> WeatherSnapshot)] = [
            ("tempC", { try Self.snapshot(tempC: .nan) }),
            ("tempC", { try Self.snapshot(tempC: .infinity) }),
            ("feelsLikeC", { try Self.snapshot(feelsLikeC: -.infinity) }),
            ("wmoCode", { try Self.snapshot(wmoCode: -1) }),
            ("wmoCode", { try Self.snapshot(wmoCode: 100) }),
            ("humidityPct", { try Self.snapshot(humidityPct: -0.1) }),
            ("humidityPct", { try Self.snapshot(humidityPct: 100.1) }),
            ("humidityPct", { try Self.snapshot(humidityPct: .nan) }),
            ("uvIndex", { try Self.snapshot(uvIndex: -1) }),
            ("uvIndex", { try Self.snapshot(uvIndex: .nan) }),
            ("windKmh", { try Self.snapshot(windKmh: -0.5) }),
            ("windKmh", { try Self.snapshot(windKmh: .infinity) }),
        ]
        for (field, make) in cases {
            #expect(throws: DomainError.invalidValue(field: field)) {
                _ = try make()
            }
        }
    }

    // MARK: - En el agregado

    @Test("Una sesión nueva no tiene clima; se adjunta activa o pausada")
    func attachActiveOrPaused() throws {
        var active = try Session.start(at: Self.t0, strideM: 0.655)
        #expect(active.weather == nil)
        try active.attachWeather(Self.snapshot())
        #expect(active.weather == (try Self.snapshot()))

        var paused = try Session.start(at: Self.t0, strideM: 0.655)
        try paused.pause(at: Self.t0.addingTimeInterval(10))
        try paused.attachWeather(Self.snapshot(wmoCode: 3))
        #expect(paused.weather?.wmoCode == 3)
    }

    @Test("Congelado: un segundo clima lanza y no sustituye al primero")
    func attachOnlyOnce() throws {
        var session = try Session.start(at: Self.t0, strideM: 0.655)
        try session.attachWeather(Self.snapshot(wmoCode: 61))
        #expect(throws: DomainError.invalidTransition(from: "active", to: "replaceWeather")) {
            try session.attachWeather(Self.snapshot(wmoCode: 3))
        }
        #expect(session.weather?.wmoCode == 61)

        try session.pause(at: Self.t0.addingTimeInterval(10))
        #expect(throws: DomainError.invalidTransition(from: "paused", to: "replaceWeather")) {
            try session.attachWeather(Self.snapshot(wmoCode: 3))
        }
    }

    @Test("Una sesión finalizada no recibe clima")
    func noWeatherAfterFinish() throws {
        var session = try Session.start(at: Self.t0, strideM: 0.655)
        try session.finish(at: Self.t0.addingTimeInterval(60))
        #expect(throws: DomainError.invalidTransition(from: "finished", to: "attachWeather")) {
            try session.attachWeather(Self.snapshot())
        }
        #expect(session.weather == nil)
    }

    @Test("restore conserva el clima; sin él, la sesión restaurada no tiene")
    func restoreKeepsWeather() throws {
        let weather = try Self.snapshot()
        let restored = try Session.restore(
            startedAt: Self.t0, stepsMeasured: 10, stepsEstimated: 0, totalPausesS: 0, paused: false,
            pausedAt: nil, strideM: 0.655, systemDistanceM: nil, weather: weather
        )
        #expect(restored.weather == weather)

        let withoutWeather = try Session.restore(
            startedAt: Self.t0, stepsMeasured: 10, stepsEstimated: 0, totalPausesS: 0, paused: false,
            pausedAt: nil, strideM: 0.655, systemDistanceM: nil
        )
        #expect(withoutWeather.weather == nil)
    }
}
