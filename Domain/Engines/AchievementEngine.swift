import Foundation

/// El valor de una métrica del catálogo, ya leído de la sesión que cierra y de su historial.
///
/// Son dos formas porque el catálogo compara dos cosas distintas: magnitudes (metros, sesiones,
/// días, horas, grados, segundos por kilómetro) y **una** categoría de clima. Un tercer caso
/// exigiría un comparador nuevo en `AchievementComparison`, y el catálogo está congelado (AD-5).
///
/// **La ausencia se representa con `nil`, no con un caso propio.** Una métrica que no se puede
/// medir —no hay clima, no hay ritmo por debajo de 100 m (AD-4), la meta semanal no la evalúa
/// este motor— hace que el logro **no se evalúe**: ni se cumple ni se incumple. Un `.absent`
/// dentro del enum obligaría a decidir en cada comparación qué hacer con él, que es justo el
/// tipo de rama que se olvida.
///
/// **`internal`, no `public`:** no aparece en ninguna firma que salga de `Domain`. La API pública
/// del motor habla de logros (`AchievementDefinition`) y de números (`consecutiveDays`,
/// `paceMetric`, `startHourLocal`); esto es cómo los mide por dentro.
enum AchievementMeasurement: Equatable, Sendable {
    case number(Double)
    case category(WeatherCategory)
}

/// El motor de logros (`AchievementEngine`, `motivation.js:86`) — AD-3, AD-5, AD-6, AD-17, AD-19.
///
/// **Es un cálculo puro y vive en `Domain/`**, con el molde exacto de `GoalEngine`: un `enum` sin
/// casos, todo `static func`, y el **calendario por parámetro** (AD-3: aquí no hay reloj ni
/// `Calendar.current`). Las dos razones se refuerzan, como allí: AD-3 lo pide, y los 65 vectores
/// de `evaluateAchievements.json`, `checkStreak.json`, `checkTimeOfDay.json` y
/// `achievementCatalog.json` ejecutan **esto**, y los vectores no pueden importar `WalkTracker`.
///
/// **La evaluación es Swift; el catálogo es dato** (AD-5). Este motor no sabe qué logros existen:
/// recibe el `AchievementCatalog` y, para cada entrada, lee la métrica que la entrada nombra y la
/// compara con su umbral por el comparador que la entrada declara. Cambiar un umbral es cambiar
/// `Resources/achievements.json`, no este fichero — y por eso no hay ni una clave de logro
/// escrita aquí.
///
/// **El `switch` sobre `AchievementMetric` es exhaustivo y sin `default`, y eso es una decisión.**
/// La doc de `AchievementMetric` promete que una métrica nueva sin rama **no compila**. Un
/// `default: return nil` convertiría ese error de compilación en un logro que no se desbloquea
/// nunca y del que nadie se enteraría. El catálogo está congelado, así que el día que se amplíe
/// será por una decisión deliberada que merece romper el build. Lo mismo vale para el `switch` de
/// la comparación: no tiene `default`, así que un comparador nuevo también rompe.
///
/// **Las dos divergencias declaradas de AD-6, y las dos pasan por aquí.**
/// - `localTime`: las horas de inicio y las rachas se calculan en **hora local**, con el
///   `AppCalendar` de AD-19, y no en UTC como `motivation.js` (`getUTCHours`, `getUTCDate`). Los
///   vectores divergentes llevan el valor de Swift en `expected` y **tienen que pasar aquí**; es
///   `domain.js` quien los falla a propósito.
/// - `wmoCategory`: la categoría de clima se deriva del **código WMO** (`WeatherCategory`), no de
///   un regex sobre el texto localizado (`motivation.js:116`). De ahí que los tres chubascos
///   80/81/82 sean lluvia aquí y no allí.
///
/// **`weekly_goal` es la excepción declarada** (AD-25): este motor **no lo evalúa** y **no emite
/// celebración** por él. Lo desbloquea `GoalEngine` a través de `AchievementsStore.unlockWeeklyGoal(at:)`
/// cuando la meta se cumple, y quien celebra es el anillo, una vez por semana.
public enum AchievementEngine {

    /// Los logros que **se desbloquean ahora**, al cerrar `record`.
    ///
    /// - Parameters:
    ///   - record: la caminata que acaba de cerrarse. Si **no cuenta para logros** —una huérfana,
    ///     `SessionRecord.countsForAchievements == false`, AD-18— no se evalúa **nada**: se
    ///     devuelve la lista vacía sin mirar el catálogo. Ojo: es la pregunta contraria a la del
    ///     anillo, donde una huérfana **sí** suma kilómetros (3.1).
    ///   - history: el historial. **Da igual si `record` ya está dentro** —lo normal después de un
    ///     `append` con éxito, que es el orden que fija D1— o si no: cuenta **una vez**. La clave
    ///     es `startedAt`, la misma clave natural que usa `HistoryStore.contains(startedAt:)`: no
    ///     puede haber dos caminatas que empiecen en el mismo instante.
    ///   - alreadyUnlocked: el estado de los logros tal y como está en `achievements.json`. Solo
    ///     cuentan como desbloqueados los que llevan `unlockedAt`: una fila con progreso y sin
    ///     instante es un logro **en curso**, y ése sí puede desbloquearse ahora.
    ///   - catalog: el catálogo congelado, ya validado (AD-5).
    ///   - calendar: el `AppCalendar` de AD-19, de `ClockPort.calendar`.
    /// - Returns: las definiciones de los logros nuevos, **en el orden del catálogo** (el mismo
    ///   que recorre `motivation.js`). Se devuelven las definiciones y no las claves porque quien
    ///   celebra (3.4) y quien pinta (3.3, 3.5) necesitan el nombre y el emoji, que son dato del
    ///   catálogo y no se vuelven a buscar.
    public static func newlyUnlocked(
        closing record: SessionRecord,
        history: [SessionRecord],
        alreadyUnlocked: [AchievementUnlock],
        catalog: AchievementCatalog,
        calendar: Calendar
    ) -> [AchievementDefinition] {
        guard record.countsForAchievements else { return [] }

        let sessions = history.contains(where: { $0.startedAt == record.startedAt })
            ? history
            : history + [record]
        let unlocked = Set(alreadyUnlocked.filter(\.isUnlocked).map(\.key))

        return catalog.achievements.filter { definition in
            !unlocked.contains(definition.key)
                && isEarned(definition, closing: record, sessions: sessions, calendar: calendar)
        }
    }

    /// ¿`definition` se cumple con esta caminata?
    ///
    /// Es la decisión de **un** logro, sin mirar si ya estaba desbloqueado ni si la caminata
    /// cuenta: eso lo decide `newlyUnlocked(closing:history:alreadyUnlocked:catalog:calendar:)`.
    /// Está expuesta —como `GoalEngine.week(from:containing:)`— porque hay vectores que ejercitan
    /// exactamente esto: los 5 de `checkTimeOfDay` son una franja horaria contra una hora local, y
    /// pasar por aquí es lo que les hace ejecutar la comparación **de verdad** en vez de una copia.
    ///
    /// - Parameter sessions: el historial **con la que cierra dentro**, que es lo que miden los
    ///   acumulados (`totalDistanceM`, `sessionCount`) y la racha.
    public static func isEarned(
        _ definition: AchievementDefinition,
        closing record: SessionRecord,
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> Bool {
        guard let measurement = measurement(
            of: definition.metric,
            closing: record,
            sessions: sessions,
            calendar: calendar
        ) else {
            // Métrica ausente: el logro **no se evalúa**. Sin clima no hay `rain_walker` ni
            // `hot_walker` ni `cold_walker`; sin ritmo no hay `speed_walker`; y `weekly_goal` no
            // es de este motor (AD-25).
            return false
        }
        return satisfies(measurement, definition.comparison, definition.threshold)
    }

    /// Días **locales** consecutivos con al menos una caminata — la métrica `consecutiveDays`.
    ///
    /// Es la racha más larga del conjunto, que es exactamente lo que decide `checkStreak` en la
    /// referencia: allí se agrupan las sesiones por día, se deduplican, se ordenan y se cuentan
    /// las diferencias de un día, devolviendo `true` en cuanto una tirada llega a `days`. Comparar
    /// la tirada más larga con el umbral (`7_days_streak` es `consecutiveDays gte 7`) da la misma
    /// respuesta y además **es una magnitud**, que es lo que el catálogo sabe comparar. Las dos
    /// guardas de la referencia (`sessions.length < days`, `dates.length < days`) quedan
    /// implicadas: una tirada de `n` días necesita `n` días distintos y al menos `n` sesiones.
    ///
    /// **La divergencia `localTime` vive aquí.** La referencia agrupa con `getUTCFullYear/Month/Date`;
    /// esto agrupa por **día local** del `AppCalendar` (AD-19), el mismo que usa el anillo. Y el
    /// día siguiente se calcula **con el calendario** (`date(byAdding: .day, value: 1,)`), no
    /// sumando 86 400 s: en la noche de un cambio de hora un día no tiene 24 h y la racha se
    /// rompería sola.
    ///
    /// Sin caminatas la racha es **0**, no 1: `motivation.js` arranca su contador en 1 y lo
    /// protege con las dos guardas, y aquí el suelo es la lista vacía.
    public static func consecutiveDays(startedAts: [Date], calendar: Calendar) -> Int {
        let days = Set(startedAts.map { calendar.startOfDay(for: $0) }).sorted()
        guard var previous = days.first else { return 0 }

        var longest = 1
        var current = 1
        for day in days.dropFirst() {
            guard let next = calendar.date(byAdding: .day, value: 1, to: previous) else {
                // **No es un hueco: es que el calendario no sabe responder.** Reiniciar el
                // contador aquí afirmaría que Paul no caminó ese día, que es justo lo que nadie
                // sabe (AD-22). Se corta el recuento y se devuelve lo contado hasta aquí, que es
                // lo único que se sabe de verdad. El `AppCalendar` ISO-8601 no produce este caso.
                return longest
            }
            if calendar.isDate(next, inSameDayAs: day) {
                current += 1
            } else {
                // Aquí sí: hay un hueco de días locales y la tirada se rompe.
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }

    /// El ritmo como métrica de logro, o `nil` si no hay ritmo que comparar.
    ///
    /// **Aquí vive la mitad de la regla de `speed_walker` que el catálogo no puede expresar.**
    /// `achievements.md` la especifica como *"`paceSecPerKm` > 0 y < 480"* y el esquema de AD-5
    /// solo llega a la mitad de arriba (`{ "metric": "paceSecPerKm", "threshold": 480,
    /// "comparison": "lt" }`). De las tres salidas que el diferido dejaba escritas —tratarlo en el
    /// evaluador, estrechar el umbral a `between [1, 479]` o una rama del `switch`— se toma la
    /// primera: el catálogo **no se toca** (AD-5 lo congela y esta historia lo tiene como "Never"),
    /// y un `between` cambiaría la regla de un logro cuyos desbloqueos son irrevocables por una
    /// limitación de esquema.
    ///
    /// Un ritmo **ausente** es lo que da el dominio por debajo de 100 m (AD-4), no un `0`: una
    /// caminata de 50 m no es infinitamente rápida. Un ritmo **no positivo** no puede existir en un
    /// `SessionRecord` —su frontera lo rechaza— y la guarda se queda igual: es la regla de la
    /// referencia, y apoyarla en un invariante que vive en otro fichero sería dejarla a merced de
    /// que ese otro fichero cambie. Existe expuesta para poder ejercitar las dos ramas, que desde
    /// un `SessionRecord` son inalcanzables.
    public static func paceMetric(_ paceSecPerKm: Int?) -> Double? {
        guard let paceSecPerKm, paceSecPerKm > 0 else { return nil }
        return Double(paceSecPerKm)
    }

    /// La hora **local** entera en que empezó la caminata (0–23) — la métrica `startHourLocal`.
    ///
    /// Expuesta porque es la mitad divergente de `checkTimeOfDay`: la referencia lee `getUTCHours`
    /// y esto lee la hora del `AppCalendar` (AD-19, divergencia `localTime` de AD-6).
    public static func startHourLocal(of instant: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: instant)
    }

    // MARK: - El progreso del grid (3.3)

    /// Lo que Paul lleva acumulado hacia `definition`, en la unidad de su métrica, o `nil` si
    /// ese logro **no tiene progreso que medir**.
    ///
    /// **Calcular una barra no es evaluar** (AD-17, decisión D1 de la 3.3). Esta función no
    /// desbloquea nada, no mira el estado de `achievements.json` y no tiene efectos: devuelve una
    /// magnitud derivada del historial, que es lo que el grid pinta cada vez que se abre. Por eso
    /// el progreso de los logros en curso **no se guarda**: guardado sería una caché que habría
    /// que invalidar al borrar una sesión (CAP-15), y una caché que miente es peor que un cálculo.
    ///
    /// **`nil` no es 0, y la diferencia es la honestidad de la pantalla** (AD-22). Un logro sin
    /// fracción se pinta **sin barra**, no con un 0 % falso. Son tres familias:
    /// - **`weekly_goal`**, cuyo progreso no está en el historial: lo posee `GoalEngine`, contra
    ///   la meta y la semana en curso (AD-25). Derivarlo aquí sería una segunda fuente de verdad
    ///   para el mismo número, y la que se quedara atrás lo haría en silencio.
    /// - **Las métricas que no se acumulan**: una categoría de clima no tiene fracción, y una
    ///   hora de inicio, una temperatura o un ritmo tampoco — caminar a 20 °C no es "avanzar
    ///   hacia" los 30 °C de `hot_walker`, y con `cold_walker` (`lt 5`) la fracción saldría del
    ///   revés.
    /// - **Los umbrales que no se alcanzan subiendo**: solo `gte` y `gt` sobre un número positivo
    ///   describen una cuenta atrás hacia una meta. `lt`, `lte`, `eq` y `between` no.
    ///
    /// **Una huérfana no cuenta, igual que no cuenta para desbloquear** (AD-18): el filtro es
    /// `SessionRecord.countsForAchievements`. Ojo, es la pregunta contraria a la del anillo, donde
    /// una huérfana **sí** suma kilómetros (3.1).
    ///
    /// - Parameters:
    ///   - definition: el logro del catálogo. Ni su clave ni sus umbrales se escriben aquí: se
    ///     leen, como en el resto del motor (AD-5).
    ///   - sessions: el historial. **Sin caminata que cierre**: el grid no cierra nada.
    ///   - calendar: el `AppCalendar` de AD-19, para la racha.
    public static func accumulated(
        towards definition: AchievementDefinition,
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> Double? {
        // Un umbral que no es un número positivo no describe una meta que se alcance subiendo:
        // sin él no hay fracción que calcular ni cifra que enseñar frente a nada.
        guard case .number(let threshold) = definition.threshold, threshold > 0 else { return nil }
        // **Sin `default`**, como los otros dos `switch` del motor: un comparador nuevo obliga a
        // decidir si su logro lleva barra, en vez de heredar un `nil` mudo.
        switch definition.comparison {
        case .gte, .gt: break
        case .lte, .lt, .eq, .between: return nil
        }
        return accumulation(
            of: definition.metric,
            sessions: sessions.filter(\.countsForAchievements),
            calendar: calendar
        )
    }

    /// La fracción `0…1` de `definition` sobre el historial, o `nil` si el logro no tiene barra.
    ///
    /// **Se capa en 1 y el logro sigue bloqueado.** Con 42 km caminados y sin fila en
    /// `achievements.json`, la barra está llena y `marathon_42km` **no** se desbloquea: eso ocurre
    /// en el cierre siguiente, porque AD-17 fija un único disparador y el grid no es uno. Parece
    /// un defecto y no lo es; hay caso en la matriz de la 3.3 para que nadie lo "arregle".
    ///
    /// Es exactamente `accumulated(towards:sessions:calendar:)` dividido por el umbral del
    /// catálogo, **incluida su regla de ausencia**: las dos devuelven `nil` en los mismos casos,
    /// porque la segunda se define sobre la primera. Así la pantalla no puede enseñar una cifra
    /// sin barra ni una barra sin cifra.
    public static func progressFraction(
        towards definition: AchievementDefinition,
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> Double? {
        guard
            case .number(let threshold) = definition.threshold,
            let value = accumulated(towards: definition, sessions: sessions, calendar: calendar)
        else { return nil }
        return Swift.min(1, Swift.max(0, value / threshold))
    }

    /// El acumulado de una métrica sobre el historial, o `nil` si esa métrica no se acumula.
    ///
    /// **Exhaustivo y sin `default`**, como la tabla del cierre: una métrica nueva obliga a
    /// decidir si tiene barra. Cada rama mide **lo mismo que decide el desbloqueo**, para que la
    /// barra y el logro no cuenten cosas distintas:
    /// - `sessionDistanceM` es la **caminata más larga**, no la suma: `first_5km` se decide sobre
    ///   una sola sesión, así que lo que acerca a conseguirlo es el mejor día de Paul. Con el
    ///   historial vacío es **0**, que es lo que la matriz pide (barra a 0, no "sin dato").
    /// - `consecutiveDays` es **la tirada más larga**, la misma magnitud que compara el catálogo.
    private static func accumulation(
        of metric: AchievementMetric,
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> Double? {
        switch metric {
        case .sessionDistanceM:
            return sessions.map(\.distanceM).max() ?? 0
        case .totalDistanceM:
            return sessions.reduce(0) { $0 + $1.distanceM }
        case .sessionCount:
            return Double(sessions.count)
        case .consecutiveDays:
            return Double(consecutiveDays(startedAts: sessions.map(\.startedAt), calendar: calendar))
        case .startHourLocal, .weatherCategory, .tempC, .paceSecPerKm, .weeklyGoalMet:
            // Ninguna se acumula: una hora, una temperatura, un ritmo y una categoría de clima
            // son estados de **una** caminata, no una cuenta que suba con el historial. Y la meta
            // semanal la posee `GoalEngine` (AD-25). Ver la nota de `accumulated`.
            return nil
        }
    }

    // MARK: - La tabla métrica → dato

    /// El valor de `metric`, o `nil` si no se puede medir.
    ///
    /// **Exhaustivo y sin `default`**: ver la nota del tipo. Cada rama dice de dónde sale el dato,
    /// que es lo que documenta `AchievementMetric` caso a caso.
    private static func measurement(
        of metric: AchievementMetric,
        closing record: SessionRecord,
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> AchievementMeasurement? {
        switch metric {
        case .sessionDistanceM:
            // Solo la que cierra: 9 km en tres caminatas de 3 km **no** desbloquean `first_5km`.
            return .number(record.distanceM)
        case .totalDistanceM:
            return .number(sessions.reduce(0) { $0 + $1.distanceM })
        case .sessionCount:
            return .number(Double(sessions.count))
        case .consecutiveDays:
            return .number(Double(consecutiveDays(startedAts: sessions.map(\.startedAt), calendar: calendar)))
        case .startHourLocal:
            return .number(Double(startHourLocal(of: record.startedAt, calendar: calendar)))
        case .weatherCategory:
            // Sin clima, `nil`; con un clima que no es lluvia, `nil` también: el catálogo solo
            // sabe comparar categorías que existen, y las dos respuestas son "no se evalúa".
            return record.weather
                .flatMap { WeatherCategory($0.condition) }
                .map { AchievementMeasurement.category($0) }
        case .tempC:
            return record.weather.map { AchievementMeasurement.number($0.tempC) }
        case .paceSecPerKm:
            return paceMetric(record.paceSecPerKm).map { AchievementMeasurement.number($0) }
        case .weeklyGoalMet:
            // **La excepción declarada** (AD-25, AD-17): la meta semanal no se evalúa al cerrar la
            // sesión. La desbloquea `GoalEngine` al cumplirse la meta, y no produce celebración
            // propia — celebra el anillo, una vez por semana. Devolver `nil` es lo que hace que el
            // vector `weekly-goal-no-se-evalua-al-cierre` pase con 22 km de semana cumplida.
            return nil
        }
    }

    /// La comparación del catálogo.
    ///
    /// **Es un `switch` paralelo al de `AchievementDefinition.hasCoherentThreshold`** (privado, en
    /// `AchievementCatalog.swift`): aquel decide qué formas admite el catálogo al arrancar y éste
    /// qué formas sabe decidir. Nada del compilador los ata, así que lo ata un test —
    /// `AchievementEngineTests`, "Lo que el catálogo admite es exactamente lo que el motor sabe
    /// decidir"—, que recorre `AchievementComparison.allCases` × las tres formas de umbral y
    /// compara las dos respuestas a través de la API pública (`validate()` e `isEarned`).
    ///
    /// **`between` es inclusiva en los dos extremos**, como en la v3: `[5, 7]` sobre una hora
    /// local entera es 05:00–07:59, y `[21, 23]` es 21:00–23:59. Es la conducta de la referencia,
    /// no una divergencia nueva.
    ///
    /// Las combinaciones incoherentes (una categoría comparada con `gte`, un `between` sin
    /// intervalo) devuelven `false` en vez de acertar por casualidad: el catálogo ya no puede
    /// traerlas —`validate()` las rechaza al arrancar y la app no arranca— así que esto es la
    /// segunda puerta. **Sin `default`**: un comparador nuevo en `AchievementComparison` rompe la
    /// compilación, igual que una métrica nueva.
    private static func satisfies(
        _ measurement: AchievementMeasurement,
        _ comparison: AchievementComparison,
        _ threshold: AchievementThreshold
    ) -> Bool {
        switch (measurement, comparison, threshold) {
        case (.category(let category), .eq, .category(let raw)):
            return category.rawValue == raw
        case (.category, _, _), (_, _, .category):
            return false
        case (.number(let value), .between, .range(let min, let max)):
            return value >= min && value <= max
        case (.number, .between, _), (_, _, .range):
            return false
        case (.number(let value), .gte, .number(let threshold)):
            return value >= threshold
        case (.number(let value), .lte, .number(let threshold)):
            return value <= threshold
        case (.number(let value), .eq, .number(let threshold)):
            return value == threshold
        case (.number(let value), .gt, .number(let threshold)):
            return value > threshold
        case (.number(let value), .lt, .number(let threshold)):
            return value < threshold
        }
    }
}
