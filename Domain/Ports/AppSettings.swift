import Foundation

/// Ajustes persistentes de la app, `settings.json` (domain-model.md §8 `config`).
///
/// Su **único** dueño en la aplicación es `SettingsStore`, igual que `SessionStore` lo es del
/// snapshot de la sesión viva (AD-16). Nadie más lee ni escribe el fichero.
///
/// La 2.2 lo estrenó con la ventana de frases recientes y la 2.3 añade la zancada
/// configurada (`strideM`); la meta semanal y los toggles entran en las historias que los
/// estrenen (Epic 3, 4.2). Un campo que aún no existe en el fichero se lee con su valor por
/// omisión: un `settings.json` de hoy sigue siendo legible mañana, y uno escrito por la 2.2
/// —sin `strideM`, esquema 1— se lee hoy sin apartarse.
///
/// **Ningún campo se puede construir mal.** El `init` es la única entrada y **normaliza**, así
/// que no existe un `AppSettings` que viole su invariante: ni recién leído de un fichero
/// manipulado, ni recién escrito por un store.
///
/// **Dos puertas distintas para `strideM`, y la diferencia es el punto de la 2.3** (ver
/// `strideM` y `setStrideM(_:)`): leer del fichero **tolera** —un valor corrupto cae a "sin
/// configurar" y no cuesta la ventana de frases— y escribir desde la UI **rechaza** con error,
/// porque normalizar en silencio lo que Paul acaba de teclear es perderle el valor sin
/// decírselo.
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
    /// **Invariante, garantizado por construcción:** o es `nil`, o es > 0 y finita
    /// (`Session.validateStride`). El `init` es la puerta **tolerante** —lo que no valida se
    /// lee como "sin configurar"—; `setStrideM(_:)` es la que **rechaza**.
    public private(set) var strideM: Double?

    public init(recentQuoteIds: [Int] = [], strideM: Double? = nil) {
        self.recentQuoteIds = Self.normalized(recentQuoteIds)
        self.strideM = Self.tolerated(strideM)
    }

    /// Sustituye la ventana de recientes, normalizada.
    public mutating func setRecentQuoteIds(_ ids: [Int]) {
        recentQuoteIds = Self.normalized(ids)
    }

    /// Recalibra la zancada. **Rechaza y no muta**: a diferencia de la ventana de recientes,
    /// aquí no se normaliza en silencio, porque quien escribe es Paul en un campo de texto y
    /// corregirle el valor sin decírselo es peor que no guardarlo.
    ///
    /// - Throws: `DomainError.invalidValue(field: "strideM")` si es ≤ 0 o no finita, la misma
    ///   regla del agregado (`Session.validateStride`), no una copia suya.
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

    /// El número **cabe**: es finito. Un texto de 400 dígitos se parsea —son dígitos— y
    /// desborda a `inf`.
    ///
    /// Existe para que el motivo del rechazo sea el verdadero. `Session.validateStride` rechaza
    /// lo no finito con la misma causa que el cero y los negativos, y el mensaje que le toca a
    /// esa causa es "la zancada tiene que ser mayor que cero": para un número de 400 dígitos,
    /// que no es ni cero ni negativo, eso manda a Paul a corregir lo que no está mal.
    public static func isRepresentableStride(_ meters: Double) -> Bool {
        meters.isFinite
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
    private static func tolerated(_ strideM: Double?) -> Double? {
        guard let strideM else { return nil }
        do {
            try Session.validateStride(strideM)
        } catch {
            return nil
        }
        return strideM
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
