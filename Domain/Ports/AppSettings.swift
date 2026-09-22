import Foundation

/// Ajustes persistentes de la app, `settings.json` (domain-model.md §8 `config`).
///
/// Su **único** dueño en la aplicación es `SettingsStore`, igual que `SessionStore` lo es del
/// snapshot de la sesión viva (AD-16). Nadie más lee ni escribe el fichero.
///
/// La 2.2 lo estrenó con la ventana de frases recientes, la 2.3 añadió la zancada
/// configurada (`strideM`) y la 3.1 la meta semanal (`weeklyGoalKm`) con la semana en que
/// se celebró por última vez (`lastGoalCelebratedWeek`); los toggles entran en la historia
/// que los estrene (4.2). Un campo que aún no existe en el fichero se lee con su valor por
/// omisión: un `settings.json` de hoy sigue siendo legible mañana, y uno escrito por la 2.2
/// —sin `strideM`, esquema 1— se lee hoy sin apartarse.
///
/// **Ningún campo se puede construir mal.** El `init` es la única entrada y **normaliza**, así
/// que no existe un `AppSettings` que viole su invariante: ni recién leído de un fichero
/// manipulado, ni recién escrito por un store.
///
/// **Dos puertas distintas para lo que Paul teclea, y la diferencia es el punto de la 2.3**
/// (ver `strideM` y `setStrideM(_:)`, y desde la 3.1 `weeklyGoalKm` y `setWeeklyGoalKm(_:)`):
/// leer del fichero **tolera** —un valor corrupto cae a "sin configurar" y no cuesta la ventana
/// de frases— y escribir desde la UI **rechaza** con error, porque normalizar en silencio lo que
/// Paul acaba de teclear es perderle el valor sin decírselo.
public struct AppSettings: Equatable, Sendable {

    /// Los ajustes de la primera vez: sin fichero, se parte de aquí. También es el punto de
    /// partida cuando el fichero está corrupto — se aparta y no se pierde la sesión.
    public static let defaults = AppSettings()

    /// Ids de las frases mostradas recientemente, la **más reciente al final**.
    ///
    /// **Invariante, garantizado por construcción:** sin repetidos y como mucho
    /// `MotivationEngine.recentWindow`. Solo se escribe por `setRecentQuoteIds(_:)`, que
    /// normaliza; quien calcula el valor nuevo usa `updateRecentIds(_:selectedId:)`.
    ///
    /// No vive en `activeSession.json`: no es estado de una sesión viva, sino del producto.
    public private(set) var recentQuoteIds: [Int]

    /// Zancada recalibrada por Paul, en metros, o `nil` si **nunca la tocó** (2.3, CAP-7).
    ///
    /// **Es un override opcional, no un campo con valor.** Sin configurar, la sesión nace con
    /// `formulas.defaultStrideM`, que queda como el único sitio donde vive el 0,655. Diverge a
    /// propósito de `domain-model.md:95`, que modela `config.strideM` con el default dentro:
    /// duplicarlo en dos ficheros los deja divergir sin que nadie lo note, y quien nunca tocó
    /// el ajuste no se beneficiaría de mejorarlo.
    ///
    /// **Invariante, garantizado por construcción:** o es `nil`, o es > 0, finita y
    /// representable en la fórmula de la distancia (`Session.validateStride`). El `init` es la
    /// puerta **tolerante** —lo que no valida se lee como "sin configurar", incluida una
    /// zancada guardada antes de B-3 que hoy ya no cabría—; `setStrideM(_:)` es la que
    /// **rechaza**.
    public private(set) var strideM: Double?

    /// Meta semanal de Paul, en kilómetros, o `nil` si **nunca la tocó** (3.1, CAP-7).
    ///
    /// **Es un override opcional, como la zancada, y por la misma razón**: sin configurar, el
    /// anillo usa `defaultWeeklyGoalKm`. Lo que diverge es dónde vive el valor por omisión: el
    /// de la zancada está en `formulas.json` porque es una **calibración medible** y el de la
    /// meta está aquí porque es un **default de producto**, y `formulas.json` no es su sitio
    /// (decisión del Epic 3, `epic-3-context.md`).
    ///
    /// **Invariante, garantizado por construcción:** o es `nil`, o es finita y **≥
    /// `minimumWeeklyGoalKm`**. El `init` es la puerta **tolerante** —un `0`, un `-3`, un `0,01`
    /// o un `NaN` de un fichero manipulado se leen como "sin configurar" y no cuestan ni la
    /// zancada ni la ventana de frases—; `setWeeklyGoalKm(_:)` es la que **rechaza**.
    public private(set) var weeklyGoalKm: Double?

    /// La semana ISO **local** en la que el anillo celebró por última vez la meta cumplida
    /// (`GoalEngine.weekKey(for:calendar:)`, p. ej. `"2026-W28"`), o `nil` si nunca celebró.
    ///
    /// **Es otro evento distinto del logro, y ésa es la decisión D1 de la 3.1.** `weekly_goal`
    /// es un desbloqueo **de por vida e irrevocable** (AD-5 congela el catálogo, AD-17 lo hace
    /// irrevocable) y por eso no puede ser también el estado de "ya celebré esta semana": la
    /// segunda semana que Paul cumpliera la meta no habría nada que celebrar. La celebración es
    /// semanal, tiene estado propio y **solo la dispara el anillo** — `weekly_goal` no produce
    /// celebración aparte, que es lo que impide que la primera semana celebre dos veces. La
    /// regla la heredan la 3.2 y la 3.4 y está escrita como **AD-25** en `ARCHITECTURE-SPINE.md`.
    ///
    /// **Invariante:** o es `nil`, o es una cadena no vacía. No se valida su forma: una clave que
    /// no case con ninguna semana solo hace que la celebración vuelva a dispararse una vez, que
    /// es el lado inofensivo del error.
    public private(set) var lastGoalCelebratedWeek: String?

    public init(
        recentQuoteIds: [Int] = [],
        strideM: Double? = nil,
        weeklyGoalKm: Double? = nil,
        lastGoalCelebratedWeek: String? = nil
    ) {
        self.recentQuoteIds = Self.normalized(recentQuoteIds)
        self.strideM = Self.tolerated(strideM)
        self.weeklyGoalKm = Self.toleratedGoal(weeklyGoalKm)
        self.lastGoalCelebratedWeek = Self.toleratedWeek(lastGoalCelebratedWeek)
    }

    /// Sustituye la ventana de recientes, normalizada.
    public mutating func setRecentQuoteIds(_ ids: [Int]) {
        recentQuoteIds = Self.normalized(ids)
    }

    /// Recalibra la zancada. **Rechaza y no muta**: a diferencia de la ventana de recientes,
    /// aquí no se normaliza en silencio, porque quien escribe es Paul en un campo de texto y
    /// corregirle el valor sin decírselo es peor que no guardarlo.
    ///
    /// - Throws: `DomainError.invalidValue(field: "strideM")` si es ≤ 0, no finita o mayor que
    ///   `MetricsCalculator.maxRepresentableStrideM`: la misma regla del agregado
    ///   (`Session.validateStride`), no una copia suya. Quien pinta el rechazo distingue antes
    ///   "no cabe" con `isRepresentableStride(_:)`, porque los dos motivos no se corrigen igual.
    public mutating func setStrideM(_ meters: Double) throws(DomainError) {
        try Session.validateStride(meters)
        strideM = meters
    }

    /// Quita el override y vuelve al default de `formulas.json` (decisión de Paul, 2026-09-19).
    ///
    /// **Es la única salida de vuelta.** Vaciar el campo de texto **no** sirve: la matriz dice
    /// que el campo vacío se rechaza, así que un dedazo guardado (0,067) dejaría a Paul sin
    /// manera de recuperar el valor bueno salvo reinstalando. Por eso es una acción explícita y
    /// aparte, y no un caso más del "Guardar".
    ///
    /// No puede fallar: volver a "sin configurar" es siempre un estado válido.
    public mutating func clearStrideM() {
        strideM = nil
    }

    /// La zancada con la que nace una sesión: la configurada si la hay, y si no el default de
    /// `formulas.json`, que se pasa desde fuera porque el dominio no lee ficheros.
    public func resolvedStrideM(default defaultStrideM: Double) -> Double {
        strideM ?? defaultStrideM
    }

    // MARK: - Meta semanal (3.1)

    /// La meta semanal de quien nunca la tocó: **10 km**.
    ///
    /// Vive aquí y **no en `formulas.json`**: ese fichero es para calibraciones medibles —la
    /// zancada de 0,655 m sale de medir pasos contra distancia— y un default de producto no lo
    /// es. Es la diferencia con `strideM`, cuyo valor por omisión sí se inyecta desde fuera.
    public static let defaultWeeklyGoalKm: Double = 10

    /// La meta semanal más pequeña que se admite: **1 km** (decisión de Paul, 2026-09-21).
    ///
    /// **No es cosmética, y ésa es la razón de que sea un rechazo y no un aviso.** Con la regla
    /// anterior —"finita y > 0"— una meta de 0,01 km se aceptaba, así que caminar diez metros la
    /// cumplía y **desbloqueaba `weekly_goal`**, que es un logro **de por vida e irrevocable**
    /// (AD-5 congela el catálogo, AD-25 y AD-17 lo hacen irrevocable). Una meta de broma ensucia
    /// para siempre el grid de logros de la 3.3 y no hay manera de deshacerlo: por eso ésta es la
    /// única regla de producto de esta historia que **bloquea** en vez de avisar, al revés que el
    /// rango humano de la zancada, que se puede rehacer guardando otro valor.
    ///
    /// El mínimo es **inclusivo**: 1 km exacto se acepta.
    public static let minimumWeeklyGoalKm: Double = 1

    /// Fija la meta semanal. **Rechaza y no muta**, como la zancada y por la misma razón:
    /// quien escribe es Paul en un campo de texto, y corregirle el valor sin decírselo es peor
    /// que no guardarlo.
    ///
    /// - Throws: `DomainError.invalidValue(field: "weeklyGoalKm")` si no es finita, es ≤ 0 o se
    ///   queda por debajo de `minimumWeeklyGoalKm`. Quien pinta el rechazo distingue los tres
    ///   motivos antes de llamar —`isRepresentableGoalKm(_:)` y `isTooSmallGoalKm(_:)`—, porque
    ///   "eso no cabe", "tiene que ser mayor que cero" y "el mínimo es 1 km" no se corrigen igual.
    public mutating func setWeeklyGoalKm(_ kilometers: Double) throws(DomainError) {
        try Self.validateWeeklyGoalKm(kilometers)
        weeklyGoalKm = kilometers
    }

    /// Quita la meta configurada y vuelve a `defaultWeeklyGoalKm`. No puede fallar: "sin
    /// configurar" siempre es un estado válido.
    public mutating func clearWeeklyGoalKm() {
        weeklyGoalKm = nil
    }

    /// La meta con la que se pinta el anillo: la configurada si la hay, y si no los 10 km.
    public var resolvedWeeklyGoalKm: Double { weeklyGoalKm ?? Self.defaultWeeklyGoalKm }

    /// La regla de la meta semanal, en un solo sitio: **finita y ≥ `minimumWeeklyGoalKm`**.
    ///
    /// No hay tope superior "razonable": igual que el rango humano de la zancada avisa y no
    /// bloquea, una meta absurda **por arriba** es asunto de Paul — 80 km son suyos, y no
    /// desbloquean nada que no se haya caminado. Por abajo sí hay suelo, y por qué está en
    /// `minimumWeeklyGoalKm`.
    public static func validateWeeklyGoalKm(_ kilometers: Double) throws(DomainError) {
        guard kilometers.isFinite, kilometers >= minimumWeeklyGoalKm else {
            throw .invalidValue(field: "weeklyGoalKm")
        }
    }

    /// El número es un positivo por debajo del mínimo: `0,01`, no `0` ni `-3`.
    ///
    /// Existe para que el motivo del rechazo sea el verdadero, como `isRepresentableGoalKm(_:)`:
    /// sin él, `0,5` leería "la meta tiene que ser mayor que cero", que es falso y manda a
    /// corregir lo que no está mal. Cero y los negativos **no** caen aquí: su mensaje es el otro.
    public static func isTooSmallGoalKm(_ kilometers: Double) -> Bool {
        kilometers.isFinite && kilometers > 0 && kilometers < minimumWeeklyGoalKm
    }

    /// El número **es finito**: los cientos de dígitos que desbordan a `inf` al parsear no lo
    /// son. Existe para que el motivo del rechazo sea el verdadero, igual que
    /// `isRepresentableStride(_:)`: con una sola causa, `inf` leía "la meta tiene que ser mayor
    /// que cero", que manda a Paul a corregir lo que no está mal.
    ///
    /// Cero y los negativos **sí** son representables: su problema es otro y su mensaje también.
    public static func isRepresentableGoalKm(_ kilometers: Double) -> Bool { kilometers.isFinite }

    /// Registra en qué semana ISO local celebró el anillo por última vez. Una cadena vacía es
    /// "nunca".
    public mutating func setLastGoalCelebratedWeek(_ week: String?) {
        lastGoalCelebratedWeek = Self.toleratedWeek(week)
    }

    /// Texto tecleado → kilómetros, o `nil` si eso no es un número.
    ///
    /// Misma puerta que `strideMeters(fromText:)` y **el mismo parser**, no una copia: acepta
    /// coma y punto y nada más, y puede devolver un valor no finito a propósito (400 dígitos
    /// son dígitos: se parsean y desbordan). Parsear y validar son dos pasos distintos, y quien
    /// sabe decir por qué se rechaza es la frontera.
    public static func weeklyGoalKm(fromText text: String) -> Double? {
        decimalNumber(fromText: text)
    }

    /// Rango razonable de una zancada humana, en metros (decisión de Paul, 2026-09-19).
    ///
    /// **Avisa, no bloquea.** Es una regla de **producto**, no del dominio: el agregado acepta
    /// 0,001 m y 50 m, y los dos falsean toda distancia futura en silencio, pero bloquear aquí
    /// inventaría un límite que el modelo no tiene y le quitaría a Paul el control de su propia
    /// app. Avisar cubre el dedazo real —0,067 por 0,67— sin rechazar nada. En el borde exacto
    /// (0,3 y 1,2) **no** hay aviso: el rango es cerrado.
    public static let humanStrideRangeM: ClosedRange<Double> = 0.3...1.2

    /// La zancada cae dentro del rango humano. `false` no impide guardar: solo enciende el aviso.
    public static func isHumanStride(_ meters: Double) -> Bool {
        meters.isFinite && humanStrideRangeM.contains(meters)
    }

    /// El número **cabe en la fórmula de la distancia**: es finito y no pasa de
    /// `MetricsCalculator.maxRepresentableStrideM`.
    ///
    /// Existe para que el motivo del rechazo sea el verdadero. `Session.validateStride` rechaza
    /// lo que no cabe con la misma causa que el cero y los negativos, y el mensaje que le toca a
    /// esa causa es "la zancada tiene que ser mayor que cero": para un número de 400 dígitos,
    /// que no es ni cero ni negativo, eso manda a Paul a corregir lo que no está mal.
    ///
    /// **Comprobar que es finito no bastaba** (B-3, hallazgo D3 de la retro del Epic 2). Esto
    /// se escribió para atajar el desbordamiento del **parseo** —400 dígitos dan `inf`—, no el
    /// del **cálculo**: `1e307` tiene 308 dígitos, es finito, entraba, y hacía que
    /// `pasos × zancada` dejara de ser un número en cada caminata posterior. El tope nuevo sale
    /// de la aritmética y está derivado factor a factor en `maxRepresentableStrideM`.
    ///
    /// **No es un máximo "razonable" de producto**, que renegociaría la decisión de Paul de
    /// 2026-09-19: fuera de `humanStrideRangeM` se **avisa y se guarda**. Una zancada absurda
    /// pero representable —50 m— se sigue guardando con su aviso; lo único que se rechaza es lo
    /// que no cabe.
    ///
    /// Cero y los negativos **sí caben**: su problema es otro y su mensaje también.
    public static func isRepresentableStride(_ meters: Double) -> Bool {
        meters.isFinite && meters <= MetricsCalculator.maxRepresentableStrideM
    }

    /// Texto tecleado → metros, o `nil` si eso no es un número.
    ///
    /// Vive aquí, y no en la vista, porque es **la frontera de escritura**: lo que decide si un
    /// campo vacío, `abc` o `,` se rechazan es parte de la misma regla que el "> 0 y finita",
    /// y así se prueba sin renderizar una pantalla (A-4 sigue abierto).
    ///
    /// Acepta **coma y punto** como separador decimal —el teclado en español da coma— y nada
    /// más: ni separadores de millar, ni notación científica, ni los literales hexadecimales
    /// (`0x10` → 16) y las palabras `inf`/`nan` que `Double(_:)` sí acepta y que aquí serían
    /// una sorpresa. El signo, si aparece, va delante; un `-0,5` se parsea y lo rechaza después
    /// `setStrideM(_:)`, que es quien sabe decir por qué.
    ///
    /// **Puede devolver un valor no finito, y eso es a propósito.** 400 dígitos son dígitos: se
    /// parsean y desbordan a `inf`. No se convierte aquí en "esto no es un número" porque no lo
    /// es —lo que pasa es que no cabe—, y quien pinta el mensaje distingue los dos motivos:
    /// `AppSettings.isRepresentableStride(_:)` separa "no cabe" de "no es mayor que cero", que
    /// son dos erratas que no se corrigen igual.
    public static func strideMeters(fromText text: String) -> Double? {
        decimalNumber(fromText: text)
    }

    /// El parser de los dos campos de texto del producto —la zancada (2.3) y la meta semanal
    /// (3.1)—, escrito una sola vez.
    ///
    /// Lo comparten porque la regla es la misma: **dígitos ASCII y un único separador decimal,
    /// coma o punto**, con el signo delante si aparece. Lo que cambia entre los dos campos es la
    /// validación, no la lectura, y ésa sí vive en cada frontera (`setStrideM`, `setWeeklyGoalKm`).
    private static func decimalNumber(fromText text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = 0
        var separators = 0
        for (offset, character) in trimmed.enumerated() {
            if character.isASCII, character.isNumber {
                digits += 1
            } else if character == "," || character == "." {
                separators += 1
            } else if character == "+" || character == "-" {
                guard offset == 0 else { return nil }
            } else {
                return nil
            }
        }
        guard digits > 0, separators <= 1 else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// La puerta **tolerante** de la zancada: lo que no cumple la regla del agregado se lee
    /// como "sin configurar".
    ///
    /// Un `settings.json` manipulado con `strideM: -1` no puede costar la ventana de frases ni
    /// impedir el arranque: se ignora ese campo y el resto del fichero se conserva.
    ///
    /// Es también la puerta por la que entra —sin apartar nada— una zancada **guardada antes de
    /// B-3** que hoy ya no cabe en la fórmula: se lee como "sin configurar" y la caminata usa el
    /// default de `formulas.json`. Que el tope viva en `Session.validateStride` y no solo en la
    /// frontera de escritura es lo que hace que ese fichero entre por aquí y no por la puerta
    /// que rechaza.
    private static func tolerated(_ strideM: Double?) -> Double? {
        guard let strideM else { return nil }
        do {
            try Session.validateStride(strideM)
        } catch {
            return nil
        }
        return strideM
    }

    /// La puerta **tolerante** de la meta semanal: lo que no cumple la regla se lee como "sin
    /// configurar", y el anillo usa los 10 km.
    ///
    /// Un `settings.json` manipulado con `weeklyGoalKm: 0` —o con un `0,01` guardado por un build
    /// anterior al mínimo de 1 km— no puede costar la zancada ni la ventana de frases, y tampoco
    /// puede llegar al cálculo: con la meta en 0 el porcentaje sería una división por cero, y
    /// `GoalEngine` la tolera devolviendo 0 precisamente porque esta puerta no puede ser la única
    /// defensa. Que el mínimo viva en `validateWeeklyGoalKm` y no solo en la frontera de
    /// escritura es lo que hace que ese fichero entre por aquí y no por la puerta que rechaza.
    private static func toleratedGoal(_ weeklyGoalKm: Double?) -> Double? {
        guard let weeklyGoalKm else { return nil }
        do {
            try validateWeeklyGoalKm(weeklyGoalKm)
        } catch {
            return nil
        }
        return weeklyGoalKm
    }

    /// La puerta tolerante de la semana celebrada: una cadena vacía o de solo espacios es
    /// "nunca celebró". No se valida su forma a propósito (ver `lastGoalCelebratedWeek`).
    private static func toleratedWeek(_ week: String?) -> String? {
        guard let week else { return nil }
        let trimmed = week.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// La ventana tal y como puede guardarse: **sin repetidos**, conservando el orden y
    /// quedándose con la aparición **más reciente** de cada id, y recortada a las últimas
    /// `MotivationEngine.recentWindow`.
    ///
    /// Deduplicar es lo que cierra el hueco de unos ajustes manipulados: una ventana de 20 ids
    /// repetidos (`[5, 5, 5, …]`) pasaría todos los topes y dejaría la exclusión real en **una**
    /// frase, sin que `selectQuote` lo notara ni disparara `ignoredRecentWindow`. Aquí, y no en
    /// `MotivationEngine.updateRecentIds`: que el motor no deduplique es paridad deliberada con
    /// la v3 y está en el bloque congelado de la 2.2.
    private static func normalized(_ ids: [Int]) -> [Int] {
        var seen = Set<Int>()
        var newestFirst: [Int] = []
        for id in ids.reversed() where seen.insert(id).inserted {
            newestFirst.append(id)
        }
        return Array(newestFirst.reversed().suffix(MotivationEngine.recentWindow))
    }
}
