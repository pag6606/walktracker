import Domain
import Foundation
import Testing

/// El `GoalEngine` (3.1): la ventana de la semana, la suma en metros y la clave de semana.
///
/// **Lo que los 15 vectores ya fijan no se repite aquí.** `weeklyProgress.json` cubre el
/// contrato con la referencia —los límites de lunes y domingo, la semana que cruza el año, la
/// meta exacta, los 9 995 m que no cumplen y las tres divergencias de hora local— y lo ejecuta
/// `DomainVectorTests`. Esto cubre lo que un vector no puede: lo que **no** está en la
/// referencia (una meta ≤ 0, el cambio de hora, la clave de semana) y las piezas que el motor
/// expone para que la aplicación no las vuelva a razonar.
@Suite("GoalEngine · la semana, en hora local")
struct GoalEngineTests {

    // MARK: - Soporte

    /// El `AppCalendar` de AD-19 en la zona que pida el test: ISO-8601 y lunes primero. Es el
    /// mismo que construyen `SystemClock` y `ClockStub`; ningún test se inventa otro.
    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// Una caminata cerrada con lo único que el motor lee: cuándo empezó y cuánto midió.
    private static func record(_ startedAt: String, _ distanceM: Double, recovered: Bool = false) throws -> SessionRecord {
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
            recovered: recovered
        )
    }

    // MARK: - La ventana

    @Test("La semana es semiabierta: el lunes 00:00 entra y el lunes siguiente ya no")
    func weekIsHalfOpen() {
        let calendar = Self.calendar("Europe/Madrid")
        let week = GoalEngine.week(containing: Self.instant("2026-07-08T12:00:00+02:00"), calendar: calendar)

        #expect(week.lowerBound == Self.instant("2026-07-06T00:00:00+02:00"))
        #expect(week.upperBound == Self.instant("2026-07-13T00:00:00+02:00"))
        #expect(week.contains(Self.instant("2026-07-06T00:00:00+02:00")), "el lunes a las 00:00 entra")
        #expect(week.contains(Self.instant("2026-07-12T23:59:59+02:00")), "el último segundo del domingo también")
        #expect(!week.contains(Self.instant("2026-07-13T00:00:00+02:00")), "y el lunes siguiente abre otra semana")
        #expect(!week.contains(Self.instant("2026-07-05T23:59:59+02:00")), "el domingo anterior se quedó fuera")
    }

    @Test("En la semana del cambio de hora, el lunes siguiente sigue cayendo a las 00:00 locales")
    func daylightSavingKeepsTheLocalMidnight() {
        // El 25 de octubre de 2026 España atrasa los relojes: esa semana dura 169 horas. Sumar
        // 7 × 24 h al lunes dejaría el final a las 23:00 del domingo, y una caminata del domingo
        // por la noche se saldría de su propia semana.
        let calendar = Self.calendar("Europe/Madrid")
        let week = GoalEngine.week(containing: Self.instant("2026-10-21T12:00:00+02:00"), calendar: calendar)

        #expect(week.lowerBound == Self.instant("2026-10-19T00:00:00+02:00"))
        #expect(week.upperBound == Self.instant("2026-10-26T00:00:00+01:00"))
        #expect(
            week.upperBound.timeIntervalSince(week.lowerBound) == 7 * 24 * 3600 + 3600,
            "siete días naturales, que esa semana son 169 horas"
        )
        #expect(week.contains(Self.instant("2026-10-25T23:30:00+01:00")), "el domingo por la noche sigue en su semana")
    }

    // MARK: - La suma

    @Test("Sin sesiones no hay progreso, y no hay división por cero en ningún sitio")
    func emptyHistoryIsZero() {
        let progress = GoalEngine.weeklyProgress(
            records: [], goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(progress.completedKm == 0)
        #expect(progress.percentage == 0)
        #expect(progress.isComplete == false)
        #expect(progress.fraction == 0)
    }

    @Test("Una caminata recuperada SÍ suma en el anillo, aunque no cuente para logros")
    func orphanWalksCountTowardsTheRing() throws {
        // Son dos preguntas distintas y el código ya las separó en la 5.1: `countsForAchievements`
        // es `false` porque un logro premia una caminata que Paul hizo deliberadamente; el anillo
        // mide distancia recorrida, y la recorrió igual — la contó el coprocesador.
        let orphan = try Self.record("2026-07-06T10:00:00Z", 6000, recovered: true)
        #expect(orphan.countsForAchievements == false)

        let progress = GoalEngine.weeklyProgress(
            records: [orphan], goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(progress.completedKm == 6)
        #expect(progress.percentage == 60)
    }

    @Test("Se suma en metros: 10 000 m repartidos en seis caminatas cumplen la meta exacta")
    func metresAreSummedNotKilometres() throws {
        // Sumar kilómetros fraccionarios daba 9,999999… y la meta exacta no se cumplía. Tiene
        // vector propio; aquí se comprueba además que el sumatorio es exactamente 10 km.
        let records = try [
            Self.record("2026-07-06T08:00:00Z", 8806),
            Self.record("2026-07-06T19:00:00Z", 603),
            Self.record("2026-07-07T08:00:00Z", 456),
            Self.record("2026-07-07T19:00:00Z", 1),
            Self.record("2026-07-08T08:00:00Z", 68),
            Self.record("2026-07-08T10:00:00Z", 66),
        ]

        let progress = GoalEngine.weeklyProgress(
            records: records, goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(progress.completedKm == 10)
        #expect(progress.isComplete, "10 000 m exactos cumplen una meta de 10 km")
    }

    @Test("9 995 m NO cumplen una meta de 10 km, y la cifra que se ve no los redondea hacia arriba")
    func almostCompleteIsNotComplete() throws {
        // Decisión de Paul (8.7): `isComplete` mira los metros SIN redondear.
        //
        // La cifra que se ve **no** sale 10,00, y el vector lo había previsto: su nota dice que
        // solo fija `isComplete` porque "completedKm y percentage dependen de cómo redondee cada
        // runtime". 9 995 / 1000 no es 9,995 en coma flotante binaria, sino 9,99499999…, así que
        // el `toFixed(2)` de la referencia da **9,99** — y este dominio da lo mismo, que es lo
        // que se quiere: el anillo y su cifra dicen la misma verdad, en vez de enseñar "10,00"
        // junto a un anillo que no se cierra.
        let records = try [
            Self.record("2026-07-06T10:00:00Z", 5000),
            Self.record("2026-07-07T10:00:00Z", 4995),
        ]

        let progress = GoalEngine.weeklyProgress(
            records: records, goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(progress.isComplete == false, "9 995 m no son 10 000")
        #expect(progress.completedKm == 9.99)
        #expect(progress.percentage == 99.9)
    }

    @Test("La cifra redondeada llega a 10,00, la meta SIGUE sin cumplirse y el ANILLO NO SE CIERRA")
    func roundingUpDoesNotCompleteTheGoal() throws {
        // El caso que hace comprobable la decisión de la 8.7, y que ningún vector trae: con
        // 9 999,6 m el redondeo a dos decimales **sí** da 10,00 km. Si `isComplete` mirara la
        // cifra redondeada, ésta sería la caminata que desbloquea `weekly_goal` sin haber
        // llegado. Con 9 995 m el mutante no se ve: su cifra redondeada también se queda corta.
        let progress = GoalEngine.weeklyProgress(
            records: try [Self.record("2026-07-06T10:00:00Z", 9999.6)],
            goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(progress.completedKm == 10, "la cifra que se ve sí redondea a 10,00")
        #expect(progress.isComplete == false, "pero faltan 40 cm")
        // **El anillo no puede contradecir a la celebración.** `percentage` sale de los km ya
        // redondeados —lo fija el vector— y aquí vale 100; un arco derivado de él se pintaría
        // **entero** mientras `isComplete` es `false`: lleno y sin celebrar. `fraction` sale de
        // la magnitud cruda, así que se queda un pelo por debajo.
        #expect(progress.percentage == 100, "el porcentaje de la referencia sí llega a 100")
        #expect(progress.fraction < 1)
        #expect(progress.fraction > 0.999, "casi lleno, que es la verdad")
    }

    @Test("El anillo solo se cierra cuando la meta está cumplida")
    func theRingIsFullOnlyWhenComplete() throws {
        let exact = GoalEngine.weeklyProgress(
            records: try [Self.record("2026-07-06T10:00:00Z", 10_000)],
            goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )
        let over = GoalEngine.weeklyProgress(
            records: try [Self.record("2026-07-06T10:00:00Z", 30_000)],
            goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )
        let half = GoalEngine.weeklyProgress(
            records: try [Self.record("2026-07-06T10:00:00Z", 5000)],
            goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(exact.fraction == 1 && exact.isComplete)
        #expect(over.fraction == 1 && over.isComplete, "pasarse no pinta vuelta y media")
        #expect(half.fraction == 0.5 && !half.isComplete)
    }

    @Test("El porcentaje se acota a 100 y la fracción del anillo, a 1")
    func percentageIsCapped() throws {
        let progress = GoalEngine.weeklyProgress(
            records: try [Self.record("2026-07-06T10:00:00Z", 30_000)],
            goalKm: 10, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(progress.percentage == 100, "300 % pintarían un anillo de tres vueltas")
        #expect(progress.fraction == 1)
        #expect(progress.completedKm == 30, "pero los kilómetros de verdad se siguen diciendo")
    }

    @Test("Una meta que no es meta: porcentaje 0, sin división por cero y sin celebrar", arguments: [0.0, -3.0])
    func nonPositiveGoalIsTolerated(goalKm: Double) throws {
        // `settings.json` manipulado a mano: la frontera de escritura ya rechaza el 0 y la puerta
        // tolerante lo lee como "sin configurar", así que esto es la segunda puerta. La
        // referencia JS daría `isComplete: true` (`0 >= 0`) y celebraría por no tener meta.
        let progress = GoalEngine.weeklyProgress(
            records: try [Self.record("2026-07-06T10:00:00Z", 5000)],
            goalKm: goalKm, now: Self.instant("2026-07-08T12:00:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(progress.percentage == 0)
        #expect(progress.percentage.isFinite, "una división por cero habría dado infinito o NaN")
        #expect(progress.isComplete == false)
    }

    @Test("La caminata cuenta en la semana en que EMPEZÓ, aunque termine en la siguiente")
    func theWeekIsDecidedByTheStart() throws {
        var record = try Self.record("2026-07-12T23:30:00Z", 4000)
        record = try SessionRecord(
            id: record.id, startedAt: record.startedAt,
            endedAt: Self.instant("2026-07-13T00:30:00Z"),
            stepsMeasured: 0, stepsEstimated: 0, strideM: 0.655, distanceM: 4000,
            durationS: 3600, pausesS: 0, paceSecPerKm: nil, cadenceSpm: 0
        )

        let oldWeek = GoalEngine.weeklyProgress(
            records: [record], goalKm: 10, now: Self.instant("2026-07-12T23:59:00Z"), calendar: Self.calendar("UTC")
        )
        let newWeek = GoalEngine.weeklyProgress(
            records: [record], goalKm: 10, now: Self.instant("2026-07-13T00:30:00Z"), calendar: Self.calendar("UTC")
        )

        #expect(oldWeek.completedKm == 4, "el domingo que la empezó")
        #expect(newWeek.completedKm == 0, "y el lunes que la terminó ya no")
    }

    @Test("Sin ventana no se suma nada, y eso es mejor que sumar la semana equivocada")
    func anEmptyWindowSumsNothing() {
        // La rama que el calendario ISO-8601 no produce, ejecutada de verdad: con la ventana
        // fuera, `week(from:containing:)` es lo único que decide, y un 0 % silencioso deja de ser
        // una suposición escrita en un comentario.
        let now = Self.instant("2026-07-08T12:00:00Z")
        let interval = Self.calendar("UTC").dateInterval(of: .weekOfYear, for: now)

        #expect(GoalEngine.week(from: nil, containing: now) == now..<now)
        #expect(GoalEngine.week(from: DateInterval(start: now, duration: 0), containing: now) == now..<now)
        #expect(GoalEngine.week(from: interval, containing: now).contains(Self.instant("2026-07-06T00:00:00Z")))
    }

    // MARK: - El valor no se puede construir mal

    @Test("Un progreso imposible se normaliza en vez de existir", arguments: [
        (-5000.0, 10.0), (Double.nan, 10.0), (.infinity, 10.0), (5000, 0), (5000, -3), (5000, .nan),
    ])
    func impossibleProgressIsNormalised(completedM: Double, goalKm: Double) {
        // El init anterior recibía los cuatro derivados por separado y admitía
        // `(completedKm: -5, goalKm: 0, percentage: 900, isComplete: true)`.
        let progress = WeeklyProgress(completedM: completedM, goalKm: goalKm)

        #expect(progress.completedKm >= 0 && progress.completedKm.isFinite)
        #expect(progress.goalKm >= 0 && progress.goalKm.isFinite)
        #expect((0...100).contains(progress.percentage))
        #expect((0...1).contains(progress.fraction))
        #expect(progress.isComplete == false, "sin meta o sin metros no se cumple nada")
    }

    // MARK: - La clave de la semana (AD-25)

    @Test("La clave de semana es la ISO local, con el año DE LA SEMANA")
    func weekKeyUsesTheWeekYear() {
        let calendar = Self.calendar("UTC")

        #expect(GoalEngine.weekKey(for: Self.instant("2026-07-08T12:00:00Z"), calendar: calendar) == "2026-W28")
        // El jueves 1 de enero de 2026 pertenece a la semana que empieza el lunes 29 de
        // diciembre de 2025: con el año del DÍA, esa semana tendría dos claves y la celebración
        // se dispararía dos veces en la misma semana.
        #expect(GoalEngine.weekKey(for: Self.instant("2025-12-29T00:00:00Z"), calendar: calendar) == "2026-W01")
        #expect(GoalEngine.weekKey(for: Self.instant("2026-01-01T12:00:00Z"), calendar: calendar) == "2026-W01")
    }

    @Test("La clave es la misma para todos los instantes de la semana, y cambia el lunes")
    func weekKeyIsStableWithinTheWeek() {
        let calendar = Self.calendar("America/Guayaquil")
        let monday = GoalEngine.weekKey(for: Self.instant("2026-07-06T00:00:00-05:00"), calendar: calendar)
        let sunday = GoalEngine.weekKey(for: Self.instant("2026-07-12T23:59:59-05:00"), calendar: calendar)
        let next = GoalEngine.weekKey(for: Self.instant("2026-07-13T00:00:00-05:00"), calendar: calendar)

        #expect(monday == sunday, "refrescar la pantalla el domingo no abre una semana nueva")
        #expect(monday != next)
    }

    @Test("La clave se calcula en hora LOCAL: el domingo por la noche aquí ya es lunes en UTC")
    func weekKeyIsLocal() {
        // La misma divergencia declarada de AD-6 que la ventana, vista desde la celebración: con
        // el calendario en UTC, celebrar el domingo a las 21:00 de Guayaquil marcaría la semana
        // SIGUIENTE como celebrada y la de verdad se quedaría sin celebrar.
        let instant = Self.instant("2026-07-12T21:00:00-05:00")

        #expect(GoalEngine.weekKey(for: instant, calendar: Self.calendar("America/Guayaquil")) == "2026-W28")
        #expect(GoalEngine.weekKey(for: instant, calendar: Self.calendar("UTC")) == "2026-W29")
    }
}
