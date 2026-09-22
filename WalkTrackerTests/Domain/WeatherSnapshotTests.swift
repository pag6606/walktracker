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

    /// **Los códigos salen del propio `evaluateAchievements.json`, no de una lista escrita a
    /// mano** (diferido de la 2.1, cerrado en la 3.2). La lista anterior nombraba el fichero en su
    /// título y traía ocho códigos que el fichero no tiene (56, 45, 50, 68, 77, 79, 83, 94): decía
    /// estar atada al contrato y no lo estaba. Ahora cada vector con clima se contrasta con lo que
    /// su propio `expected` dice de `rain_walker`.
    ///
    /// Es la mitad de `WeatherCondition`; la del puente a `WeatherCategory` la cubre
    /// `AchievementEngineTests`, sobre el mismo fichero y por la misma razón.
    @Test("Los códigos WMO de los vectores de clima cuadran con WeatherCondition")
    func vectorRainCodes() throws {
        var seen = 0
        for (wmoCode, unlocksRain) in try Self.weatherCasesFromVectors() {
            seen += 1
            #expect(
                WeatherCondition(wmoCode: wmoCode) == (unlocksRain ? .rain : .other),
                "WMO \(wmoCode): el vector y `WeatherCondition` no dicen lo mismo"
            )
        }
        #expect(seen >= 9, "los vectores de clima siguen ahí; si bajan de nueve, este test tiene que verlo")
    }

    /// `(wmoCode, ¿su vector desbloquea rain_walker?)` de cada vector de `evaluateAchievements`
    /// con clima.
    private static func weatherCasesFromVectors() throws -> [(Int, Bool)] {
        let file = try JSONSerialization.jsonObject(with: try VectorBundle.data(for: "evaluateAchievements"))
        let vectors = try #require((file as? [String: Any])?["vectors"] as? [[String: Any]])
        return vectors.compactMap { vector in
            guard let input = vector["input"] as? [String: Any],
                  let session = input["session"] as? [String: Any],
                  let weather = session["weather"] as? [String: Any],
                  let wmoCode = weather["wmoCode"] as? Int,
                  let expected = (vector["expected"] as? [String: Any])?["newlyUnlocked"] as? [String]
            else { return nil }
            return (wmoCode, expected.contains("rain_walker"))
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
