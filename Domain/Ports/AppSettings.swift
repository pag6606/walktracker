import Foundation

/// Ajustes persistentes de la app, `settings.json` (domain-model.md §8 `config`).
///
/// Su **único** dueño en la aplicación es `SettingsStore`, igual que `SessionStore` lo es del
/// snapshot de la sesión viva (AD-16). Nadie más lee ni escribe el fichero.
///
/// La 2.2 lo estrena con la ventana de frases recientes; la zancada configurada
/// (`strideM`), la meta semanal y los toggles entran en las historias que los estrenen (2.3,
/// Epic 3, 4.2). Un campo que aún no existe en el fichero se lee con su valor por omisión: un
/// `settings.json` de hoy sigue siendo legible mañana.
///
/// **Ningún campo se puede construir mal.** El `init` es la única entrada y **normaliza**, así
/// que no existe un `AppSettings` que viole su invariante: ni recién leído de un fichero
/// manipulado, ni recién escrito por un store. La 2.3 añade `strideM` ("> 0 y finita") por la
/// misma puerta, y el tope de la ventana deja de vivir por convención en cada frontera.
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

    public init(recentQuoteIds: [Int] = []) {
        self.recentQuoteIds = Self.normalized(recentQuoteIds)
    }

    /// Sustituye la ventana de recientes, normalizada.
    public mutating func setRecentQuoteIds(_ ids: [Int]) {
        recentQuoteIds = Self.normalized(ids)
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
