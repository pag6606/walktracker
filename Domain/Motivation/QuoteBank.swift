import Foundation

/// Una frase del banco de motivación (`quotes.json`, CAP-6).
///
/// El `id` es la identidad estable que viaja en la sesión (`Session.quoteId`) y en la ventana
/// de recientes: nunca se renumera. El texto es contenido congelado de la v3.
public struct Quote: Equatable, Sendable, Codable {

    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// Por qué el banco de frases no vale.
///
/// A diferencia del catálogo de logros (AD-5), ninguno mata el arranque: con el banco
/// ausente o inválido la caminata sigue **sin frase** (decisión de Paul, 2026-09-19). Quien
/// lo lee lo registra; nadie lo convierte en un fallo visible.
public enum QuoteBankError: Error, Equatable, Sendable {
    /// El JSON no se puede leer o no tiene la forma del esquema.
    case malformed(String)
    /// Dos frases con el mismo `id`: la ventana de recientes dejaría de excluir lo que dice.
    case duplicateId(Int)
    /// Una frase sin texto: no hay nada que mostrar, y el overlay saldría en blanco.
    case emptyText(id: Int)
}

/// El banco de las 100 frases de `Resources/quotes.json` (CAP-6, domain-model.md §5).
///
/// **El único recurso empaquetado sin `schemaVersion`, y a propósito.** `achievements.json`,
/// `formulas.json` y `settings.json` llevan versión porque su forma es nuestra y va a cambiar:
/// el Epic 3 añade logros, la 2.3 añade `strideM`. `quotes.json` es el fichero de la v3 **tal
/// cual**, y la Intent congelada de la 2.2 lo declara contenido congelado: un array desnudo de
/// `{ id, text }` que no se reescribe ni se renumera. Versionar lo que no cambia sería
/// inventar una migración que nunca va a existir, y además obligaría a tocar el contenido
/// congelado para escribirle la versión. Si algún día el banco cambiara de forma, la versión
/// entraría **entonces**, con la migración que la justifique; hasta ahí, la asimetría es la
/// decisión, no un descuido.
///
/// Un banco **vacío es válido**: no hay frase y la sesión sigue. Lo que no vale es un banco
/// incoherente (ids repetidos, texto vacío), porque ahí la regla de "20 sin repetir" mentiría:
/// por eso **no se puede construir uno sin validar** — el único `init` público lanza.
public struct QuoteBank: Equatable, Sendable {

    /// El banco sin frases: lo que queda cuando `quotes.json` falta o no valida.
    public static let empty = QuoteBank(unchecked: [])

    /// Las frases, en el orden del fichero.
    public let quotes: [Quote]

    /// Valida al construir: un banco incoherente no llega a existir.
    ///
    /// No hay forma de esquivar la validación —ni un init por miembros, ni un `validate()`
    /// que alguien pueda olvidarse de llamar—, porque un banco con ids repetidos dejaría un
    /// gemelo seleccionable y la ventana de recientes excluiría solo a uno de los dos.
    ///
    /// - Throws: `duplicateId` con un `id` repetido; `emptyText` con una frase sin texto.
    public init(quotes: [Quote]) throws(QuoteBankError) {
        self.quotes = quotes
        try validate()
    }

    /// El único camino sin validar, y solo para `empty`: un array vacío no puede tener ids
    /// repetidos ni textos en blanco.
    private init(unchecked quotes: [Quote]) {
        self.quotes = quotes
    }

    public var isEmpty: Bool { quotes.isEmpty }

    /// La frase de un `id`, si está en el banco.
    ///
    /// **Hoy no tiene llamador de producción:** el overlay recibe el texto de la frase recién
    /// elegida (`SessionStore.quote`), no un id que resolver. Existe para el sentido inverso
    /// —de `Session.quoteId` a su texto—, que es lo que necesitarán el historial persistido y
    /// el export (Epic 5) al mostrar una caminata ya cerrada; hasta entonces solo lo ejercitan
    /// los tests. Devuelve `nil` sin drama con un id que el banco ya no tenga, porque el
    /// fichero puede cambiar entre lanzamientos y una sesión vieja no deja de ser válida.
    public func quote(id: Int) -> Quote? {
        quotes.first { $0.id == id }
    }

    /// Decodifica y valida. Único punto de entrada desde datos.
    ///
    /// - Throws: `malformed` si no es un array de `{ id, text }`; `duplicateId` con un `id`
    ///   repetido; `emptyText` con una frase sin texto.
    public static func decode(from data: Data) throws(QuoteBankError) -> QuoteBank {
        let quotes: [Quote]
        do {
            quotes = try JSONDecoder().decode([Quote].self, from: data)
        } catch {
            throw .malformed(String(describing: error))
        }
        return try QuoteBank(quotes: quotes)
    }

    /// Lanza la primera causa encontrada: `id` repetido, después texto vacío. Privada: la
    /// llama el `init`, y no hay ningún banco que no haya pasado por ella.
    private func validate() throws(QuoteBankError) {
        var seen = Set<Int>()
        for quote in quotes where !seen.insert(quote.id).inserted {
            throw .duplicateId(quote.id)
        }
        for quote in quotes where quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .emptyText(id: quote.id)
        }
    }
}
