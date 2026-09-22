import Foundation

/// El progreso de la semana hacia la meta: lo que el anillo pinta y lo que la celebración
/// consulta (3.1, CAP-7, FR-10).
///
/// Las cuatro magnitudes que cruzan a la vista son exactamente las que fijan los 15 vectores de
/// `weeklyProgress.json` (AD-6), con los nombres de la referencia. `fraction` es la quinta y **no
/// la fija ningún vector**: es el arco que se dibuja, una magnitud de esta app que la v3 no tenía.
///
/// **Ningún `WeeklyProgress` se puede construir mal**, como `AppSettings` y por la misma razón: el
/// `init` es la **única** entrada y recibe lo crudo —los metros de la semana sin redondear y la
/// meta—, así que los cuatro derivados no pueden contradecirse entre ellos. El init anterior
/// recibía los cuatro por separado y admitía `(completedKm: -5, goalKm: 0, percentage: 900,
/// isComplete: true)`.
public struct WeeklyProgress: Equatable, Sendable {

    /// Kilómetros de la semana, redondeados a dos decimales. **No es lo que decide
    /// `isComplete`**, que mira los metros: 9 999,6 m se redondean a `10,00` y no cumplen una
    /// meta de 10 km.
    public let completedKm: Double
    /// La meta con la que se calculó, en kilómetros. Una meta que no es meta —no finita o ≤ 0,
    /// solo alcanzable con un fichero manipulado— se representa como `0`.
    public let goalKm: Double
    /// Porcentaje hacia la meta, con un decimal y **acotado a 100**: pasarse de la meta no
    /// pinta un anillo de vuelta y media.
    ///
    /// Sale de `completedKm`, ya redondeado, porque es lo que fija el vector. **Por eso puede
    /// decir `100` sin que la meta esté cumplida** (9 999,6 m), y por eso el arco NO se deriva de
    /// aquí: ver `fraction`.
    public let percentage: Double
    /// La meta está cumplida. Se decide sobre los **metros sin redondear**.
    public let isComplete: Bool

    /// La fracción del anillo que se dibuja, `0…1`, **sin redondear**.
    ///
    /// **No sale de `percentage`, y ésa es toda la razón de que exista.** `percentage` se redondea
    /// a un decimal sobre unos kilómetros ya redondeados a dos, así que con 9 999,6 m vale `100`:
    /// un anillo derivado de él se pintaría **entero** mientras `isComplete` es `false`, es decir,
    /// lleno y sin celebrar. Aquí se divide la magnitud cruda, de modo que
    /// **`fraction == 1` si y solo si `isComplete`**.
    public let fraction: Double

    /// Única entrada: los metros de la semana **sin redondear** y la meta en kilómetros.
    ///
    /// Normaliza en vez de lanzar, como `AppSettings`: esto no es una frontera de escritura —nadie
    /// teclea un progreso— sino el resultado de un cálculo, y un progreso imposible significa que
    /// los datos de entrada ya estaban mal, no que Paul se haya equivocado.
    public init(completedM: Double, goalKm: Double) {
        let meters = completedM.isFinite && completedM > 0 ? completedM : 0
        let goal = goalKm.isFinite && goalKm > 0 ? goalKm : 0

        self.goalKm = goal
        // **Se suma en METROS y se redondea una sola vez, aquí.** Sumar kilómetros fraccionarios
        // acumula error de coma flotante: 10 000 m repartidos en seis caminatas daban 9,999999… km
        // y una meta exacta no se cumplía. Está en el JS de referencia con su comentario, y tiene
        // vector propio (`diez-km-exactos-en-seis-sesiones`).
        completedKm = Self.rounded(meters / 1000, decimals: 2)
        // El porcentaje sale de los kilómetros **ya redondeados**, como la referencia.
        percentage = goal > 0 ? min(100, Self.rounded(completedKm / goal * 100, decimals: 1)) : 0
        // **Sobre los metros SIN redondear** (decisión de Paul, 8.7, con su vector). Con una meta
        // que no es meta no se cumple nada: la referencia diría que sí (`0 >= 0`), y celebrar por
        // no tener meta sería el peor de los dos errores. No hay vector que lo fije porque la
        // frontera de escritura ya rechaza el 0; esto es la segunda puerta.
        isComplete = goal > 0 && meters >= goal * 1000
        fraction = goal > 0 ? min(1, meters / (goal * 1000)) : 0
    }

    /// El `toFixed(n)` de la referencia: redondeo a `n` decimales, medio hacia arriba en valor
    /// absoluto. Vive aquí y no en la vista porque los vectores fijan el número redondeado.
    private static func rounded(_ value: Double, decimals: Int) -> Double {
        guard value.isFinite else { return 0 }
        let factor = pow(10.0, Double(decimals))
        let scaled = (value * factor).rounded(.toNearestOrAwayFromZero)
        return scaled.isFinite ? scaled / factor : value
    }
}

/// El motor de la meta semanal (`GoalEngine`, `motivation.js:195`) — AD-3, AD-6, AD-19.
///
/// **Es un cálculo puro y vive en `Domain/` por dos razones que se refuerzan.** La primera es
/// AD-3: aquí no hay reloj, ni calendario del sistema, ni ficheros — el instante y el calendario
/// entran como parámetros, desde `ClockPort`. La segunda es AD-6: los 15 vectores de
/// `weeklyProgress.json` ejecutan **esto**, y los vectores no pueden importar `WalkTracker`. Lo
/// que no es cálculo —leer el historial, leer la meta y decidir si toca celebrar— se queda en el
/// store.
///
/// **La divergencia declarada, y por qué.** La referencia calcula la semana ISO en **UTC**
/// (`getUTCDay`, `Date.UTC`); esto la calcula en **hora local** con el `AppCalendar` de AD-19,
/// que es un solo calendario para el anillo, las rachas y la agrupación del historial. Es la
/// primera fila de la tabla de divergencias de AD-6 y tiene tres vectores que la fijan, cada uno
/// con su `expected` (el nuestro) y su `expectedJs` (el de la v3): ejecutar un divergente contra
/// `expectedJs` **tiene que fallar**, o la divergencia habría dejado de existir.
public enum GoalEngine {

    /// El progreso de la semana que contiene `now`.
    ///
    /// - Parameters:
    ///   - records: el historial entero. Se filtra por `startedAt`, no por `endedAt`: una
    ///     caminata que cruza la medianoche del domingo cuenta en la semana en que **empezó**.
    ///     Una caminata recuperada u huérfana **suma** (`SessionRecord.countsForAchievements`
    ///     responde a otra pregunta): sus pasos los contó el coprocesador y la distancia es real.
    ///   - goalKm: la meta, ya resuelta (`AppSettings.resolvedWeeklyGoalKm`).
    ///   - now: el instante de referencia, de `ClockPort.now`.
    ///   - calendar: el `AppCalendar` de AD-19, de `ClockPort.calendar`.
    public static func weeklyProgress(
        records: [SessionRecord],
        goalKm: Double,
        now: Date,
        calendar: Calendar
    ) -> WeeklyProgress {
        // El motor decide QUÉ metros entran —la ventana de la semana— y el valor decide cómo se
        // leen. Que el redondeo viva en `WeeklyProgress.init` es lo que impide que el arco y la
        // cifra salgan de dos criterios distintos.
        WeeklyProgress(
            completedM: completedMeters(records: records, week: week(containing: now, calendar: calendar)),
            goalKm: goalKm
        )
    }

    /// La ventana **semiabierta** de la semana que contiene `now`:
    /// `[lunes 00:00 local, lunes siguiente 00:00 local)`.
    ///
    /// El domingo a las 23:59:59 entra en la semana vieja y el lunes a las 00:00:00 abre la
    /// nueva — las dos puntas tienen vector. El final se calcula **con el calendario** y no
    /// sumando 7 × 24 h: en la semana de un cambio de hora, siete días naturales no son 168
    /// horas, y el lunes siguiente tiene que caer a las 00:00 locales igual.
    public static func week(containing now: Date, calendar: Calendar) -> Range<Date> {
        week(from: calendar.dateInterval(of: .weekOfYear, for: now), containing: now)
    }

    /// El intervalo del calendario como ventana semiabierta, con su suelo para el caso en que el
    /// calendario no sepa responder.
    ///
    /// **Existe separada para poder probar ese suelo**, que el calendario ISO-8601 no produce: con
    /// la rama escondida dentro de `week(containing:calendar:)` no había forma de ejecutarla, y
    /// una rama sin ejecutar que devuelve un 0 % silencioso no es un suelo, es una suposición.
    /// Sin ventana no hay nada que sumar, y un anillo a 0 es preferible a uno que sume la semana
    /// equivocada.
    public static func week(from interval: DateInterval?, containing now: Date) -> Range<Date> {
        guard let interval, interval.end > interval.start else { return now..<now }
        return interval.start..<interval.end
    }

    /// La semana ISO local como clave estable, `"2026-W28"`.
    ///
    /// Es lo que `settings.json` guarda en `lastGoalCelebratedWeek` para que la celebración sea
    /// **una por semana** (AD-25). Se usa el año **de la semana** (`yearForWeekOfYear`) y no el
    /// del día: el jueves 1 de enero de 2026 pertenece a la semana que empieza el lunes 29 de
    /// diciembre de 2025, y con el año del día esa semana tendría dos claves.
    public static func weekKey(for instant: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: instant)
        guard let year = components.yearForWeekOfYear, let week = components.weekOfYear else {
            return ""
        }
        return String(format: "%04d-W%02d", year, week)
    }

    /// Los metros de las caminatas que empezaron dentro de la ventana.
    private static func completedMeters(records: [SessionRecord], week: Range<Date>) -> Double {
        records.reduce(0) { total, record in
            week.contains(record.startedAt) ? total + record.distanceM : total
        }
    }
}
