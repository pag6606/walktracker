import Domain
import Foundation
import Testing

/// El `AchievementEngine` (3.2): la tabla métrica → dato, la comparación y la racha local.
///
/// **Lo que los 65 vectores ya fijan no se repite aquí.** `evaluateAchievements.json` (51),
/// `checkStreak.json` (8), `checkTimeOfDay.json` (5) y `achievementCatalog.json` (1) cubren el
/// contrato con la referencia —los 14 logros en los dos sentidos, los umbrales exactos, los
/// códigos WMO, las franjas horarias y las 15 divergencias declaradas (12 de hora local y las 3
/// de `wmoCategory`)— y los ejecuta
/// `DomainVectorTests`. Esto cubre lo que un vector **no puede**: la huérfana (que el vector no
/// modela, porque `{startedAt, distanceM}` no tiene columna para ella), el cambio de hora, las
/// nueve ramas del `switch` una por una, la guarda inferior de `speed_walker` y la divergencia
/// `wmoCategory` mirada desde el texto de la v3.
@Suite("AchievementEngine · los logros del cierre")
struct AchievementEngineTests {

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

    /// Una caminata cerrada con lo único que el motor lee.
    private static func record(
        _ startedAt: String,
        distanceM: Double = 500,
        paceSecPerKm: Int? = nil,
        wmoCode: Int? = nil,
        tempC: Double = 18,
        recovered: Bool = false
    ) throws -> SessionRecord {
        let weather = try wmoCode.map { code in
            try WeatherSnapshot(
                tempC: tempC, feelsLikeC: tempC, wmoCode: code,
                humidityPct: 50, uvIndex: 0, windKmh: 0, capturedAt: instant(startedAt)
            )
        }
        return try SessionRecord(
            id: UUID(),
            startedAt: instant(startedAt),
            endedAt: instant(startedAt),
            stepsMeasured: 0,
            stepsEstimated: 0,
            strideM: 0.655,
            distanceM: distanceM,
            durationS: 0,
            pausesS: 0,
            paceSecPerKm: paceSecPerKm,
            cadenceSpm: 0,
            weather: weather,
            recovered: recovered
        )
    }

    private static func unlocked(_ keys: String...) throws -> [AchievementUnlock] {
        try keys.map { try AchievementUnlock(key: $0, unlockedAt: instant("2026-01-01T00:00:00Z"), progress: 1) }
    }

    private static var catalog: AchievementCatalog { AchievementCatalogFixture.bundled }

    private static func keys(
        closing record: SessionRecord,
        history: [SessionRecord] = [],
        alreadyUnlocked: [AchievementUnlock] = [],
        zone: String = "UTC"
    ) -> [String] {
        AchievementEngine.newlyUnlocked(
            closing: record,
            history: history,
            alreadyUnlocked: alreadyUnlocked,
            catalog: catalog,
            calendar: calendar(zone)
        ).map(\.key)
    }

    // MARK: - La huérfana: lo que ningún vector puede modelar

    /// AD-18, y la mutación obligatoria de esta historia: dejar que la huérfana dispare logros.
    /// El vector no puede cazarla porque su sesión es `{startedAt, distanceM, paceSecPerKm,
    /// weather}` y no tiene columna para `recovered`.
    @Test("Una huérfana no desbloquea NADA, ni el que desbloquearía de sobra")
    func anOrphanUnlocksNothing() throws {
        let huerfana = try Self.record("2026-07-08T06:30:00Z", distanceM: 12_000, paceSecPerKm: 400, wmoCode: 61, recovered: true)

        #expect(Self.keys(closing: huerfana).isEmpty)

        // La misma caminata cerrada por Paul sí desbloquea, y de sobra: es lo que hace que el
        // test de arriba no pase por casualidad.
        let suya = try Self.record("2026-07-08T06:30:00Z", distanceM: 12_000, paceSecPerKm: 400, wmoCode: 61)
        #expect(Self.keys(closing: suya).sorted() == [
            "early_bird", "first_10km", "first_5km", "first_km", "first_session", "rain_walker", "speed_walker",
        ])
    }

    /// Y al revés de la pregunta del anillo: una huérfana **en el historial** sí cuenta para los
    /// acumulados, porque sus pasos los contó el coprocesador. Lo que AD-18 prohíbe es premiar la
    /// sesión que nadie cerró, no que exista.
    @Test("Una huérfana del historial SÍ suma en los acumulados de la que cierra")
    func anOrphanInTheHistoryStillCounts() throws {
        let huerfanas = try (0..<5).map { index in
            try Self.record("2026-07-0\(index + 1)T10:00:00Z", distanceM: 8_200, recovered: true)
        }
        let cierre = try Self.record("2026-07-11T10:00:00Z", distanceM: 1_000)

        let keys = Self.keys(closing: cierre, history: huerfanas, alreadyUnlocked: try Self.unlocked("first_session", "first_km"))

        #expect(keys.contains("marathon_42km"), "5 × 8 200 m + 1 000 m = 42 km justos")
    }

    // MARK: - El único punto: idempotencia y la que cierra, una sola vez

    /// El historial que ve el store **ya trae** la caminata que cierra, porque la evaluación va
    /// después de un `append` con éxito (D1). Contarla dos veces adelantaría `consistency_30` y
    /// `marathon_42km` una sesión entera.
    @Test("La que cierra cuenta UNA vez, esté o no ya en el historial")
    func theClosingWalkIsCountedOnce() throws {
        let previas = try (1...28).map { try Self.record("2026-06-\(String(format: "%02d", $0))T10:00:00Z") }
        let cierre = try Self.record("2026-07-08T10:00:00Z")
        let yaDesbloqueados = try Self.unlocked("first_session")

        // 28 + 1 = 29: todavía no.
        #expect(!Self.keys(closing: cierre, history: previas, alreadyUnlocked: yaDesbloqueados).contains("consistency_30"))
        // Y con la que cierra ya dentro del historial sigue siendo 29, no 30.
        #expect(!Self.keys(closing: cierre, history: previas + [cierre], alreadyUnlocked: yaDesbloqueados).contains("consistency_30"))

        let unaMas = try Self.record("2026-06-29T10:00:00Z")
        #expect(Self.keys(closing: cierre, history: previas + [unaMas] + [cierre], alreadyUnlocked: yaDesbloqueados).contains("consistency_30"))
    }

    @Test("Un logro ya desbloqueado no se re-dispara; uno con progreso y sin instante, sí")
    func anUnlockedAchievementIsNotRetriggered() throws {
        let cierre = try Self.record("2026-07-08T10:00:00Z", distanceM: 2_000)

        #expect(Self.keys(closing: cierre, alreadyUnlocked: try Self.unlocked("first_km", "first_session")).isEmpty)

        // Una fila con progreso y **sin** `unlockedAt` es un logro EN CURSO: ése sí se desbloquea.
        let enCurso = try AchievementUnlock(key: "first_km", unlockedAt: nil, progress: 800)
        #expect(Self.keys(closing: cierre, alreadyUnlocked: [enCurso] + (try Self.unlocked("first_session"))) == ["first_km"])
    }

    // MARK: - Las nueve métricas, una por una

    /// **La prueba de que no hay ninguna rama muerta.** Si se añadiera una métrica al enum, el
    /// motor no compilaría (el `switch` es exhaustivo y sin `default`); esto comprueba la otra
    /// mitad: que las nueve que hay **se miden**, y que la única que devuelve "no se evalúa" es
    /// `weeklyGoalMet`, que es la excepción declarada de AD-25.
    @Test("Las nueve métricas tienen rama, y solo weeklyGoalMet no se evalúa", arguments: AchievementMetric.allCases)
    func everyMetricHasABranch(metric: AchievementMetric) throws {
        // Una caminata que satisface cualquier umbral laxo: 12 km, ritmo 400, lluvia, 18 °C, a
        // las 06:30 locales, con seis días previos seguidos.
        let cierre = try Self.record("2026-07-08T06:30:00Z", distanceM: 12_000, paceSecPerKm: 400, wmoCode: 61)
        let previas = try (2...7).map { try Self.record("2026-07-0\($0)T10:00:00Z") }

        let lax = Self.laxRule(for: metric)
        let probe = AchievementDefinition(
            key: "probe",
            name: "",
            description: "",
            icon: "",
            metric: metric,
            threshold: lax.threshold,
            comparison: lax.comparison
        )
        let earned = AchievementEngine.isEarned(
            probe,
            closing: cierre,
            sessions: previas + [cierre],
            calendar: Self.calendar()
        )

        if metric == .weeklyGoalMet {
            #expect(!earned, "AD-25: la meta semanal no la evalúa este motor, ni para bien ni para mal")
        } else {
            #expect(earned, "la métrica \(metric.rawValue) no se midió")
        }
    }

    /// Un umbral que cualquier caminata razonable supera, en la forma que la métrica admite, con
    /// el comparador que le corresponde.
    private static func laxRule(
        for metric: AchievementMetric
    ) -> (threshold: AchievementThreshold, comparison: AchievementComparison) {
        switch metric {
        case .startHourLocal: (.range(min: 0, max: 23), .between)
        case .weatherCategory: (.category("rain"), .eq)
        case .tempC: (.number(-100), .gte)
        case .paceSecPerKm: (.number(0), .gte)
        case .sessionDistanceM, .totalDistanceM, .sessionCount, .consecutiveDays, .weeklyGoalMet:
            (.number(1), .gte)
        }
    }

    // MARK: - `weekly_goal`, la excepción declarada (AD-25)

    @Test("weekly_goal no se desbloquea al cerrar, ni con la semana cumplida de sobra")
    func theWeeklyGoalIsNotEvaluatedOnFinish() throws {
        // 22 km en la misma semana ISO: el anillo estaría al 100 % con cualquier meta razonable.
        let previas = [
            try Self.record("2026-07-06T10:00:00Z", distanceM: 5_000),
            try Self.record("2026-07-07T10:00:00Z", distanceM: 5_000),
        ]
        let cierre = try Self.record("2026-07-08T10:00:00Z", distanceM: 12_000)

        let keys = Self.keys(
            closing: cierre,
            history: previas,
            alreadyUnlocked: try Self.unlocked("first_session", "first_km", "first_5km", "first_10km")
        )

        #expect(keys.isEmpty, "lo desbloquea GoalEngine al cumplirse la meta, no el cierre de sesión")
    }

    // MARK: - `speed_walker`: la mitad de la regla que el catálogo no expresa

    /// La decisión de esta historia: la guarda inferior de *"ritmo > 0 y < 480"* vive en el
    /// evaluador, no en el catálogo (que está congelado, AD-5). Las dos ramas son inalcanzables
    /// desde un `SessionRecord` —su frontera rechaza un ritmo ≤ 0— y por eso se ejercitan aquí.
    @Test("El ritmo como métrica: ausente y no positivo son 'no se evalúa', no un 0 rapidísimo")
    func paceMetricGuardsTheLowerBound() {
        let cases: [(pace: Int?, metric: Double?)] = [
            (nil, nil),
            (0, nil),
            (-1, nil),
            (1, 1),
            (479, 479),
        ]
        for (pace, metric) in cases {
            #expect(AchievementEngine.paceMetric(pace) == metric, "ritmo \(String(describing: pace))")
        }
    }

    @Test("Sin ritmo no hay speed_walker, aunque el umbral sea `lt 480`")
    func anAbsentPaceDoesNotUnlockSpeedWalker() throws {
        let sinRitmo = try Self.record("2026-07-08T10:00:00Z", distanceM: 90, paceSecPerKm: nil)
        #expect(!Self.keys(closing: sinRitmo, alreadyUnlocked: try Self.unlocked("first_session")).contains("speed_walker"))

        let conRitmo = try Self.record("2026-07-08T10:00:00Z", distanceM: 1_000, paceSecPerKm: 479)
        #expect(Self.keys(closing: conRitmo, alreadyUnlocked: try Self.unlocked("first_session")).contains("speed_walker"))
    }

    // MARK: - Clima: el puente por código, no por texto

    @Test("Sin clima no se cumple ninguno de los tres climáticos, y tampoco se incumple: no se evalúan")
    func withoutWeatherNoWeatherAchievement() throws {
        let sinClima = try Self.record("2026-07-08T10:00:00Z")
        let keys = Self.keys(closing: sinClima, alreadyUnlocked: try Self.unlocked("first_session"))

        #expect(!keys.contains("rain_walker"))
        #expect(!keys.contains("hot_walker"))
        #expect(!keys.contains("cold_walker"))
    }

    /// **El puente, y la única lista de códigos de lluvia.** Los códigos salen del propio
    /// `evaluateAchievements.json` —que es quien fija el contrato— en vez de una lista escrita a
    /// mano, que es lo que el diferido de la 2.1 pedía cerrar aquí.
    @Test("Los códigos WMO de los vectores de clima van al puente, y el puente coincide con ellos")
    func theBridgeAgreesWithTheVectors() throws {
        let file = try JSONSerialization.jsonObject(with: try VectorBundle.data(for: "evaluateAchievements"))
        let vectors = try #require((file as? [String: Any])?["vectors"] as? [[String: Any]])

        var seen = 0
        for vector in vectors {
            guard let input = vector["input"] as? [String: Any],
                  let session = input["session"] as? [String: Any],
                  let weather = session["weather"] as? [String: Any],
                  let wmoCode = weather["wmoCode"] as? Int,
                  let expected = (vector["expected"] as? [String: Any])?["newlyUnlocked"] as? [String]
            else { continue }
            seen += 1
            let esLluvia = expected.contains("rain_walker")
            #expect(
                (WeatherCategory(wmoCode: wmoCode) == .rain) == esLluvia,
                "WMO \(wmoCode) (vector \(vector["id"] as? String ?? "?")): el puente y el vector no dicen lo mismo"
            )
        }
        #expect(seen >= 9, "los vectores de clima siguen ahí; si bajan de nueve, este test tiene que verlo")
    }

    /// **La divergencia `wmoCategory` de AD-6, mirada desde el otro lado.** La v3 decide la lluvia
    /// con un regex sobre el **texto localizado** (`motivation.js:116`,
    /// `/lluv|llovi|torment/i` sobre `climate.js`), y por eso los tres chubascos —80, 81 y 82— no
    /// son lluvia allí: "Chubascos ligeros" no contiene ninguna de las tres raíces. Aquí lo son,
    /// porque la categoría sale del **código**. Si el motor se implementara contra el texto, esos
    /// tres vectores divergentes fallarían: eso es exactamente lo que la divergencia declara.
    @Test("wmoCategory: los chubascos 80–82 son lluvia por código y NO lo serían por texto")
    func theWmoCategoryDivergenceIsReal() {
        // Los textos de la referencia (`climate.js` WMO_CONDITIONS) para los códigos que los
        // vectores usan. Van escritos porque son el valor de la v3, no una conducta de esta app.
        let v3Text: [Int: String] = [
            51: "Llovizna ligera", 61: "Lluvia ligera", 67: "Lluvia helada intensa",
            95: "Tormenta", 99: "Tormenta con granizo intenso",
            80: "Chubascos ligeros", 81: "Chubascos moderados", 82: "Chubascos intensos",
            3: "Nublado", 71: "Nevada ligera", 85: "Chubascos de nieve ligeros",
        ]
        let v3SaysRain: (String) -> Bool = { text in
            text.range(of: "lluv|llovi|torment", options: [.regularExpression, .caseInsensitive]) != nil
        }

        // Donde los dos runtimes coinciden.
        for code in [51, 61, 67, 95, 99] {
            #expect(WeatherCategory(wmoCode: code) == .rain, "WMO \(code)")
            #expect(v3SaysRain(v3Text[code]!), "WMO \(code): la v3 también lo ve")
        }
        for code in [3, 71, 85] {
            #expect(WeatherCategory(wmoCode: code) == nil, "WMO \(code)")
            #expect(!v3SaysRain(v3Text[code]!), "WMO \(code): tampoco para la v3")
        }
        // Y los tres que divergen, que son los tres vectores marcados `wmoCategory`.
        for code in [80, 81, 82] {
            #expect(WeatherCategory(wmoCode: code) == .rain, "WMO \(code) es lluvia por código")
            #expect(!v3SaysRain(v3Text[code]!), "WMO \(code): el texto de la v3 no lo es, y ahí está la divergencia")
        }
    }

    @Test("Un clima que no es lluvia no tiene categoría: no hay `case other` que inventar")
    func aNonRainConditionHasNoCategory() {
        #expect(WeatherCategory(.rain) == .rain)
        #expect(WeatherCategory(.other) == nil)
        #expect(WeatherCategory.allCases == [.rain])
    }

    // MARK: - La racha, en días locales

    @Test("La racha es la tirada más larga de días locales, no el número de sesiones")
    func theStreakIsTheLongestRunOfLocalDays() {
        let calendar = Self.calendar()
        let dias = ["2026-09-25", "2026-09-26", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"]
            .map { Self.instant("\($0)T10:00:00Z") }

        #expect(AchievementEngine.consecutiveDays(startedAts: dias, calendar: calendar) == 5, "tras el hueco del 27")
        #expect(AchievementEngine.consecutiveDays(startedAts: [], calendar: calendar) == 0, "sin caminatas la racha es 0, no 1")

        // Varias sesiones el mismo día son **un** día: el conjunto se deduplica.
        let mismoDia = (0..<7).map { Self.instant("2026-09-25T0\($0):00:00Z") }
        #expect(AchievementEngine.consecutiveDays(startedAts: mismoDia, calendar: calendar) == 1)
    }

    /// **El día siguiente se calcula con el calendario, no sumando 86 400 s.** En la noche del
    /// cambio de hora un día local tiene 23 o 25 horas, y una racha que sume segundos se rompe
    /// sola. Es el mismo argumento por el que `GoalEngine` no suma 7 × 24 h para cerrar la semana.
    @Test("La racha aguanta el cambio de hora: 25 y 23 de octubre en Madrid siguen siendo días seguidos")
    func theStreakSurvivesADaylightSavingChange() {
        // En `Europe/Madrid` el domingo 25 de octubre de 2026 tiene 25 horas (atrasa a las 03:00).
        let calendar = Self.calendar("Europe/Madrid")
        let dias = [
            Self.instant("2026-10-24T12:00:00+02:00"),
            Self.instant("2026-10-25T12:00:00+01:00"),
            Self.instant("2026-10-26T12:00:00+01:00"),
        ]

        #expect(AchievementEngine.consecutiveDays(startedAts: dias, calendar: calendar) == 3)
    }

    /// La divergencia `localTime` en su forma más corta: los mismos instantes, dos calendarios,
    /// dos rachas. Los vectores la fijan con `America/Guayaquil`; esto la deja dicha sin JSON.
    @Test("Los mismos instantes dan una racha en local y otra en UTC")
    func theSameInstantsGiveDifferentStreaksPerCalendar() {
        let instantes = [
            "2026-07-01T23:59:59Z", "2026-07-02T00:00:00Z", "2026-07-03T23:59:59Z",
            "2026-07-04T00:00:00Z", "2026-07-05T23:59:59Z", "2026-07-06T00:00:00Z",
            "2026-07-07T23:59:59Z",
        ].map { Self.instant($0) }

        #expect(AchievementEngine.consecutiveDays(startedAts: instantes, calendar: Self.calendar()) == 7)
        #expect(
            AchievementEngine.consecutiveDays(startedAts: instantes, calendar: Self.calendar("America/Guayaquil")) == 1,
            "en Guayaquil caen de dos en dos en los días 1, 3, 5 y 7: no hay racha"
        )
    }

    // MARK: - Las horas, en hora local

    @Test("La hora de inicio es la LOCAL del calendario que se le pase")
    func theStartHourIsLocal() {
        let seisTreinta = Self.instant("2026-07-08T06:30:00-05:00")

        #expect(AchievementEngine.startHourLocal(of: seisTreinta, calendar: Self.calendar("America/Guayaquil")) == 6)
        #expect(AchievementEngine.startHourLocal(of: seisTreinta, calendar: Self.calendar()) == 11, "en UTC son las 11:30")
    }

    /// `between` es inclusiva en los **dos** extremos, y por eso `early_bird` llega a las 07:59:59.
    /// Es la conducta de la v3, y es la razón por la que su `description` dice "antes de las 8:00"
    /// con su divergencia de texto declarada (AD-6).
    @Test("early_bird llega a las 07:59:59 locales y se corta a las 08:00:00")
    func earlyBirdIsInclusiveAtBothEnds() throws {
        let cases: [(startedAt: String, unlocks: Bool)] = [
            ("2026-07-08T04:59:59-05:00", false),
            ("2026-07-08T05:00:00-05:00", true),
            ("2026-07-08T07:59:59-05:00", true),
            ("2026-07-08T08:00:00-05:00", false),
        ]
        for (startedAt, unlocks) in cases {
            let keys = Self.keys(
                closing: try Self.record(startedAt),
                alreadyUnlocked: try Self.unlocked("first_session"),
                zone: "America/Guayaquil"
            )
            #expect(keys.contains("early_bird") == unlocks, "\(startedAt)")
        }
    }

    /// El otro extremo del catálogo, y el más interesante de los dos: el borde de arriba de
    /// `night_walker` (`[21, 23]`) **cruza el cambio de día local**. Las 23:59:59 son la última
    /// hora de la franja y las 00:00:00 ya son otro día, no una hora 24 — que es exactamente el
    /// caso que un `hourEnd` tratado como exclusivo o como "menor que 24" no distingue.
    @Test("night_walker llega a las 23:59:59 locales y se corta al cambiar de día")
    func nightWalkerIsInclusiveUpToTheDayChange() throws {
        let cases: [(startedAt: String, unlocks: Bool)] = [
            ("2026-07-08T20:59:59-05:00", false),
            ("2026-07-08T21:00:00-05:00", true),
            ("2026-07-08T23:59:59-05:00", true),
            ("2026-07-09T00:00:00-05:00", false),
        ]
        for (startedAt, unlocks) in cases {
            let keys = Self.keys(
                closing: try Self.record(startedAt),
                alreadyUnlocked: try Self.unlocked("first_session"),
                zone: "America/Guayaquil"
            )
            #expect(keys.contains("night_walker") == unlocks, "\(startedAt)")
        }
    }

    // MARK: - Los dos `switch` paralelos, atados

    /// **`AchievementEngine.satisfies` y `AchievementDefinition.hasCoherentThreshold` conmutan
    /// sobre el mismo espacio y nada del compilador los ata.** Uno decide qué formas admite el
    /// catálogo al arrancar; el otro, qué formas sabe decidir el motor. Si se separan, una entrada
    /// que el catálogo acepta se evaluaría siempre a `false` —un logro que no se desbloquea
    /// nunca— o al revés.
    ///
    /// Se comprueba a través de la **API pública**, sin abrir nada: `AchievementCatalog.validate()`
    /// dice si el catálogo admite la forma, y `isEarned` si el motor la sabe decidir. El umbral de
    /// cada comparación se elige para que una forma coherente **siempre** se cumpla, de modo que
    /// las dos respuestas tengan que coincidir exactamente.
    @Test("Lo que el catálogo admite es exactamente lo que el motor sabe decidir", arguments: AchievementComparison.allCases)
    func theCatalogAndTheEngineAgreeOnShapes(comparison: AchievementComparison) throws {
        let cierre = try Self.record("2026-07-08T10:00:00Z", distanceM: 1_000, wmoCode: 61)

        for metric in [AchievementMetric.sessionDistanceM, .weatherCategory] {
            for threshold in Self.thresholdForms(for: comparison) {
                let probe = AchievementDefinition(
                    key: AchievementCatalog.requiredKeys[0],
                    name: "", description: "", icon: "",
                    metric: metric, threshold: threshold, comparison: comparison
                )
                let admitido = Self.catalogAccepts(probe)
                let decidido = AchievementEngine.isEarned(
                    probe, closing: cierre, sessions: [cierre], calendar: Self.calendar()
                )
                #expect(
                    admitido == decidido,
                    "\(metric.rawValue) · \(comparison.rawValue) · \(threshold): el catálogo dice \(admitido) y el motor \(decidido)"
                )
            }
        }
    }

    /// Las tres formas de umbral, con valores que una caminata de 1 000 m y lluvia **cumple** si
    /// la forma es coherente. Así "coherente" y "se cumple" son la misma respuesta.
    private static func thresholdForms(for comparison: AchievementComparison) -> [AchievementThreshold] {
        let number: Double
        switch comparison {
        case .gte, .gt: number = 500
        case .lte, .lt: number = 2_000
        case .eq: number = 1_000
        case .between: number = 1_000
        }
        return [.number(number), .range(min: 0, max: 2_000), .category("rain")]
    }

    /// ¿El catálogo admite esta entrada? Se monta un catálogo real de 14 con la sonda en la
    /// primera posición y se le pide que valide: `invalidThreshold` es la única causa que puede
    /// salir, porque el resto (claves, recuento, duplicados) está bien por construcción.
    private static func catalogAccepts(_ probe: AchievementDefinition) -> Bool {
        let rest = AchievementCatalog.requiredKeys.dropFirst().map {
            AchievementDefinition(
                key: $0, name: "", description: "", icon: "",
                metric: .sessionDistanceM, threshold: .number(1), comparison: .gte
            )
        }
        let catalog = AchievementCatalog(schemaVersion: 1, achievements: [probe] + rest)
        do {
            try catalog.validate()
            return true
        } catch {
            return false
        }
    }
}
