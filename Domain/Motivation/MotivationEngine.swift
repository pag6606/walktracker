import Foundation

/// Selección de la frase del arranque (CAP-6, domain-model.md §5, `motivation.js:28`
/// `selectQuote` y `:48` `updateRecentIds`).
///
/// **Puro y vectorizable (AD-6).** No lee el reloj ni llama a un generador aleatorio: el azar
/// entra por `RandomPort` (AD-3, AD-10). Con un doble determinista, la secuencia de frases de
/// veinte caminatas seguidas es comprobable en un test.
///
/// **La regla heredada, con su señal.** Se excluyen las últimas `recentWindow` frases
/// mostradas; si eso vacía el banco, se ignora el filtro y se elige de todo. Con 100 frases y
/// una ventana de 20 ese fallback es inalcanzable, pero si el banco encoge o la ventana se
/// corrompe se dispararía **y la promesa de "20 sin repetir" se rompería en silencio**: la v3
/// no lo registraba, así que la selección lo devuelve en `ignoredRecentWindow` y quien llama
/// lo anota (`log.info`).
public enum MotivationEngine {

    /// Cuántas frases recientes se excluyen, y tope de la ventana persistida
    /// (domain-model.md §5: "máximo 20 ids").
    public static let recentWindow = 20

    /// Lo que devuelve una selección: la frase y si hubo que ignorar el filtro.
    public struct Selection: Equatable, Sendable {

        public let quote: Quote
        /// Todas las frases del banco estaban en la ventana y se eligió de todo el banco
        /// (regla heredada). Quien llama lo registra: el fallback nunca es silencioso.
        public let ignoredRecentWindow: Bool

        public init(quote: Quote, ignoredRecentWindow: Bool) {
            self.quote = quote
            self.ignoredRecentWindow = ignoredRecentWindow
        }
    }

    /// Elige una frase del banco excluyendo las últimas `recentWindow` de `recentQuoteIds`.
    ///
    /// - Banco vacío → `nil`: no hay frase y la caminata sigue.
    /// - Ventana vacía → se elige de todo el banco.
    /// - Ids de la ventana que no están en el banco → se ignoran, no estrechan nada.
    /// - Todas excluidas → se elige de todo el banco, con `ignoredRecentWindow` en `true`.
    ///
    /// Solo cuentan los **últimos** `recentWindow` ids, como el `slice(-20)` de la v3: una
    /// ventana más larga de lo debido no excluye de más.
    ///
    /// - Returns: la selección, o `nil` con el banco vacío (o si el puerto de azar devuelve un
    ///   índice imposible, que nunca se fuerza).
    public static func selectQuote(
        from bank: QuoteBank,
        recentQuoteIds: [Int],
        random: any RandomPort
    ) -> Selection? {
        guard !bank.quotes.isEmpty else { return nil }
        let excluded = Set(recentQuoteIds.suffix(recentWindow))
        let available = bank.quotes.filter { !excluded.contains($0.id) }
        let ignoredRecentWindow = available.isEmpty
        let pool = ignoredRecentWindow ? bank.quotes : available
        guard let index = random.index(below: pool.count), pool.indices.contains(index) else { return nil }
        return Selection(quote: pool[index], ignoredRecentWindow: ignoredRecentWindow)
    }

    /// Añade `selectedId` al final de la ventana y la recorta a `recentWindow`
    /// (`motivation.js:48`: `[...recent, id].slice(-20)`).
    ///
    /// FIFO: el más antiguo sale por delante. Una ventana más larga de lo debido se recorta al
    /// tope en la primera actualización. No deduplica: reproduce la v3 tal cual.
    public static func updateRecentIds(_ recentQuoteIds: [Int], selectedId: Int) -> [Int] {
        Array((recentQuoteIds + [selectedId]).suffix(recentWindow))
    }
}
