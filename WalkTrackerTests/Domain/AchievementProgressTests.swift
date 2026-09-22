import Domain
import Foundation
import Testing

/// El progreso que pinta el grid de Logros (3.3): `AchievementEngine.accumulated(towards:…)` y
/// `progressFraction(towards:…)`.
///
/// **Ningún vector cubre esto y no puede cubrirlo**: los 65 de AD-6 ejecutan `evaluateAchievements`,
/// `checkStreak`, `checkTimeOfDay` y `achievementCatalog`, y la referencia **no tiene** progreso de
/// logros en curso — `motivation.js` responde si un logro se gana, no cuánto falta. Es una magnitud
/// de esta app, como `WeeklyProgress.fraction`, y por eso vive aquí entera.
///
/// Lo que se fija: que la barra mida **lo mismo que decide el desbloqueo**, que `nil` y `0` no se
/// confundan nunca, y que llegar al 100 % **no** desbloquee (AD-17).
@Suite("AchievementEngine · el progreso del grid")
struct AchievementProgressTests {

    // MARK: - Soporte

    /// El `AppCalendar` de AD-19 en la zona que pida el test: ISO-8601 y lunes primero. El mismo
    /// que construyen `SystemClock` y `ClockStub`; ningún test se inventa otro.
    private static func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private static func record(
        _ startedAt: String,
        distanceM: Double = 1_000,
        recovered: Bool = false
    ) throws -> SessionRecord {
        try SessionRecord(
            id: UUID(),
            startedAt: instant(startedAt),
            endedAt: instant(startedAt),
            stepsMeasured: 0,
            stepsEstimated: 0,
            strideM: 0.655,
            distanceM: distanceM,
            durationS: 0,
            pausesS: 0,
            paceSecPerKm: nil,
            cadenceSpm: 0,
            weather: nil,
            recovered: recovered
        )
    }

    private static var catalog: AchievementCatalog { AchievementCatalogFixture.bundled }

    /// El `!` es seguro y no es desidia: `AchievementCatalog.validate()` exige las 14 claves de
    /// `requiredKeys` al arrancar, así que una clave que falte aquí es un catálogo que la app no
    /// habría podido cargar — y eso ya lo dice `AchievementCatalogTests`.
    private static func definition(_ key: String) -> AchievementDefinition {
        catalog.definition(for: key)!
    }

    private static func fraction(_ key: String, _ sessions: [SessionRecord], zone: String = "UTC") -> Double? {
        AchievementEngine.progressFraction(
            towards: definition(key),
            sessions: sessions,
            calendar: calendar(zone)
        )
    }

    private static func accumulated(_ key: String, _ sessions: [SessionRecord], zone: String = "UTC") -> Double? {
        AchievementEngine.accumulated(
            towards: definition(key),
            sessions: sessions,
            calendar: calendar(zone)
        )
    }

    // MARK: - Los que llevan barra

    @Test("El acumulado de maratón es la suma del historial, y la barra su fracción del umbral")
    func marathonAddsUpTheHistory() throws {
        let sessions = try [
            Self.record("2026-09-01T08:00:00Z", distanceM: 12_000),
            Self.record("2026-09-02T08:00:00Z", distanceM: 8_000),
        ]

        #expect(Self.accumulated("marathon_42km", sessions) == 20_000)
        let fraction = try #require(Self.fraction("marathon_42km", sessions))
        #expect(abs(fraction - 20_000 / 42_000) < 0.000_001)
    }

    @Test("Un logro de sesión mide la caminata MÁS LARGA, no la suma: tres de 3 km no son 9")
    func sessionDistanceIsTheLongestWalk() throws {
        // `first_5km` se decide sobre **una** sesión (`sessionDistanceM`), así que lo que acerca a
        // conseguirlo es el mejor día de Paul. Sumar aquí pintaría la barra llena de un logro que
        // no se puede desbloquear con esas tres caminatas.
        let sessions = try [
            Self.record("2026-09-01T08:00:00Z", distanceM: 3_000),
            Self.record("2026-09-02T08:00:00Z", distanceM: 3_000),
            Self.record("2026-09-03T08:00:00Z", distanceM: 3_000),
        ]

        #expect(Self.accumulated("first_5km", sessions) == 3_000)
        #expect(Self.fraction("first_5km", sessions) == 0.6)
    }

    @Test("Las sesiones se cuentan: 3 de 30 para la constancia, y la primera caminata va de 0 a 1")
    func sessionCountIsCounted() throws {
        let sessions = try (1...3).map { try Self.record("2026-09-0\($0)T08:00:00Z") }

        #expect(Self.accumulated("consistency_30", sessions) == 3)
        #expect(Self.fraction("consistency_30", sessions) == 0.1)
        #expect(Self.fraction("first_session", []) == 0)
        #expect(Self.fraction("first_session", sessions) == 1)
    }

    @Test("La racha del grid es la misma magnitud que desbloquea: la tirada más larga de días locales")
    func streakIsTheLongestRun() throws {
        // Cuatro días seguidos, un hueco y dos más: la tirada más larga es 4, no 6.
        let sessions = try [
            "2026-09-01T08:00:00Z", "2026-09-02T08:00:00Z", "2026-09-03T08:00:00Z",
            "2026-09-04T08:00:00Z", "2026-09-06T08:00:00Z", "2026-09-07T08:00:00Z",
        ].map { try Self.record($0) }

        #expect(Self.accumulated("7_days_streak", sessions) == 4)
        let fraction = try #require(Self.fraction("7_days_streak", sessions))
        #expect(abs(fraction - 4.0 / 7.0) < 0.000_001)
    }

    @Test("La racha se agrupa en hora LOCAL, como el desbloqueo: dos instantes, un día en Guayaquil")
    func streakGroupsByLocalDay() throws {
        // 2026-09-02T02:00Z son las 21:00 del día 1 en Guayaquil (UTC-5): en UTC son dos días
        // consecutivos y en local es **uno**. Es la divergencia `localTime` de AD-6, mirada desde
        // la barra en vez de desde el desbloqueo.
        let sessions = try [
            Self.record("2026-09-01T20:00:00Z"),
            Self.record("2026-09-02T02:00:00Z"),
        ]

        #expect(Self.accumulated("7_days_streak", sessions, zone: "UTC") == 2)
        #expect(Self.accumulated("7_days_streak", sessions, zone: "America/Guayaquil") == 1)
    }

    // MARK: - Ni 0 ni 100 de más

    @Test("Sin historial la barra está a 0 y NO es 'sin dato': el logro existe y se puede conseguir")
    func emptyHistoryIsZeroAndNotAbsent() throws {
        for key in ["first_km", "first_5km", "first_10km", "first_session", "7_days_streak", "marathon_42km", "consistency_30"] {
            #expect(Self.fraction(key, []) == 0, "'\(key)' sin historial debería estar a 0")
            #expect(Self.accumulated(key, []) == 0, "'\(key)' sin historial debería acumular 0")
        }
    }

    @Test("La barra se capa en 1: pasarse de 42 km no pinta un 120 %")
    func fractionIsCapped() throws {
        let sessions = try [Self.record("2026-09-01T08:00:00Z", distanceM: 50_000)]

        #expect(Self.fraction("marathon_42km", sessions) == 1)
        // Y el acumulado NO se capa: la cifra dice lo que Paul ha caminado de verdad.
        #expect(Self.accumulated("marathon_42km", sessions) == 50_000)
    }

    @Test("Con el umbral cumplido y sin fila escrita, la barra llega al 100 % y el logro SIGUE bloqueado")
    func fullBarDoesNotUnlock() throws {
        // AD-17: se desbloquea en el cierre siguiente, no al mirar la pantalla. Aquí se comprueba
        // la mitad que es de este motor — la barra llena **sin** que exista fila —, y que la
        // función de progreso no produce ningún desbloqueo.
        let sessions = try [Self.record("2026-09-01T08:00:00Z", distanceM: 42_000)]

        #expect(Self.fraction("marathon_42km", sessions) == 1)
        #expect(
            AchievementEngine.newlyUnlocked(
                closing: sessions[0],
                history: [],
                alreadyUnlocked: [],
                catalog: Self.catalog,
                calendar: Self.calendar()
            ).contains { $0.key == "marathon_42km" }
        )
        // …y ese desbloqueo lo produce **cerrar**, no pintar: la barra por sí sola no escribe
        // nada, y quien la pinta no llama a `newlyUnlocked`.
    }

    @Test("Una huérfana no cuenta para el progreso, igual que no cuenta para desbloquear")
    func orphansDoNotCount() throws {
        let sessions = try [
            Self.record("2026-09-01T08:00:00Z", distanceM: 12_000),
            Self.record("2026-09-02T08:00:00Z", distanceM: 30_000, recovered: true),
        ]

        // Sin el filtro, esto sumaría 42 000 y la barra saldría llena.
        #expect(Self.accumulated("marathon_42km", sessions) == 12_000)
        #expect(Self.accumulated("consistency_30", sessions) == 1)
        #expect(Self.accumulated("first_5km", sessions) == 12_000)
    }

    // MARK: - Los que NO llevan barra

    @Test("Sin barra: la meta semanal, el clima, la franja horaria, la temperatura y el ritmo")
    func theOnesWithoutABar() throws {
        let sessions = try [Self.record("2026-09-01T06:00:00Z", distanceM: 9_000)]

        for key in ["weekly_goal", "rain_walker", "early_bird", "night_walker", "hot_walker", "cold_walker", "speed_walker"] {
            #expect(Self.fraction(key, sessions) == nil, "'\(key)' no puede tener barra")
            #expect(Self.accumulated(key, sessions) == nil, "'\(key)' no puede tener cifra de progreso")
        }
    }

    @Test("Los 14 se reparten en dos grupos y no hay un tercero: o barra con cifra, o ninguna de las dos")
    func everyAchievementIsInOneOfTheTwoGroups() throws {
        let sessions = try [Self.record("2026-09-01T08:00:00Z", distanceM: 2_000)]
        var withBar: [String] = []

        for definition in Self.catalog.achievements {
            let fraction = AchievementEngine.progressFraction(towards: definition, sessions: sessions, calendar: Self.calendar())
            let accumulated = AchievementEngine.accumulated(towards: definition, sessions: sessions, calendar: Self.calendar())
            // Las dos funciones tienen que ausentarse **a la vez**: una cifra sin barra o una
            // barra sin cifra dejaría media insignia sin pintar.
            #expect((fraction == nil) == (accumulated == nil), "'\(definition.key)' contradice a su pareja")
            if fraction != nil { withBar.append(definition.key) }
        }

        #expect(withBar == ["first_km", "first_5km", "first_10km", "first_session", "7_days_streak", "marathon_42km", "consistency_30"])
    }
}
