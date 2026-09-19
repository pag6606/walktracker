import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El banco de frases en el borde (2.2, CAP-6): `quotes.json` decodifica y valida, y el
/// fichero real del bundle sigue siendo el contenido congelado de la v3.
@Suite("QuoteBank · las 100 frases del bundle")
struct QuoteBankTests {

    // MARK: - Formato

    @Test("Un array de { id, text } decodifica en orden")
    func decodesArray() throws {
        let data = Data(#"[{"id":1,"text":"Uno"},{"id":2,"text":"Dos"}]"#.utf8)

        let bank = try QuoteBank.decode(from: data)

        #expect(bank.quotes == [Quote(id: 1, text: "Uno"), Quote(id: 2, text: "Dos")])
        #expect(bank.quote(id: 2) == Quote(id: 2, text: "Dos"))
        #expect(bank.quote(id: 99) == nil)
    }

    @Test("Un banco vacío es válido: no hay frase, y no es un error")
    func emptyBankIsValid() throws {
        let bank = try QuoteBank.decode(from: Data("[]".utf8))

        #expect(bank.isEmpty)
        #expect(bank == .empty)
    }

    @Test("JSON roto, con otra forma o con un campo de otro tipo: malformed", arguments: [
        "",
        "[",
        #"{"quotes":[]}"#,
        #"[{"id":"1","text":"Uno"}]"#,
        #"[{"id":1}]"#,
        #"[{"text":"Uno"}]"#,
    ])
    func malformed(json: String) {
        #expect {
            try QuoteBank.decode(from: Data(json.utf8))
        } throws: { error in
            guard case QuoteBankError.malformed = error else { return false }
            return true
        }
    }

    @Test("Dos frases con el mismo id: duplicateId, porque la ventana dejaría de excluir lo que dice")
    func duplicateId() {
        let json = #"[{"id":1,"text":"Uno"},{"id":1,"text":"Otra"}]"#
        #expect(throws: QuoteBankError.duplicateId(1)) {
            try QuoteBank.decode(from: Data(json.utf8))
        }
    }

    @Test("Una frase sin texto: emptyText, porque el overlay saldría en blanco", arguments: ["", "   ", "\n", "\t"])
    func emptyText(text: String) throws {
        // El JSON se construye, no se interpola: un salto de línea crudo dentro de una cadena
        // no es JSON válido y el caso saldría por `malformed`, que no es lo que se prueba.
        let json = try JSONSerialization.data(withJSONObject: [
            ["id": 1, "text": "Uno"],
            ["id": 7, "text": text],
        ])

        #expect(throws: QuoteBankError.emptyText(id: 7)) {
            try QuoteBank.decode(from: json)
        }
    }

    // MARK: - El fichero real

    @Test("quotes.json del bundle: 100 frases, ids únicos y ninguna vacía")
    func bundledBank() throws {
        // `Bundle.main` es el de la app, que es quien lleva `Resources/quotes.json`, igual
        // que en `AchievementCatalogTests`.
        let bank = try CompositionRoot.loadQuoteBank(from: .main)

        #expect(bank.quotes.count == 100, "el banco congelado de la v3 son 100 frases")
        #expect(Set(bank.quotes.map(\.id)).count == 100)
        #expect(bank.quotes.allSatisfy { !$0.text.isEmpty })
        #expect(Set(bank.quotes.map(\.id)) == Set(1...100), "los ids van de 1 a 100, sin huecos")
    }

    @Test("Sin quotes.json en el bundle: malformed que lo nombra, y nadie termina el proceso")
    func missingFromBundle() {
        #expect {
            // El bundle de tests no lleva `quotes.json`: es del target de la app.
            try CompositionRoot.loadQuoteBank(from: Bundle(for: QuoteBundleToken.self))
        } throws: { error in
            guard case QuoteBankError.malformed(let reason) = error else { return false }
            return reason.contains("quotes.json")
        }
    }

    @Test("Sin quotes.json, el banco del composition root degrada a vacío en vez de terminar el proceso")
    func compositionRootDegradesToEmpty() {
        // El camino real de AD-5 **invertido** (decisión de Paul, 2026-09-19): el catálogo de
        // logros termina el arranque; el banco de frases NO. Se llama a la misma función que
        // usa el `init` del root, sobre el bundle de tests —que no lleva `quotes.json`—, para
        // que sea el `catch` el que quede fijado: con un `fatalError` ahí, esto no volvería.
        let bank = CompositionRoot.bundledQuoteBankOrEmpty(from: Bundle(for: QuoteBundleToken.self))

        #expect(bank == .empty)
        #expect(bank.isEmpty)
    }

    @Test("Con el banco vacío la caminata arranca igual, sin frase y sin overlay")
    @MainActor
    func emptyBankStillStartsAWalk() async {
        let fixture = SessionStoreFixture(quotes: .empty)

        await fixture.store.start()

        #expect(fixture.store.session != nil, "la caminata arranca sin frase")
        #expect(fixture.store.session?.quoteId == nil)
        #expect(fixture.store.quote == nil, "no hay overlay que mostrar")
    }

    // MARK: - No hay banco sin validar

    @Test("El init valida: un banco con ids repetidos no llega a existir")
    func initRejectsDuplicateIds() {
        #expect(throws: QuoteBankError.duplicateId(1)) {
            try QuoteBank(quotes: [Quote(id: 1, text: "Uno"), Quote(id: 1, text: "Otra")])
        }
    }

    @Test("El init valida también el texto vacío")
    func initRejectsEmptyText() {
        #expect(throws: QuoteBankError.emptyText(id: 2)) {
            try QuoteBank(quotes: [Quote(id: 1, text: "Uno"), Quote(id: 2, text: "  ")])
        }
    }

    @Test("Un banco coherente sí se construye, y conserva el orden")
    func initAcceptsACoherentBank() throws {
        let bank = try QuoteBank(quotes: [Quote(id: 9, text: "Nueve"), Quote(id: 4, text: "Cuatro")])

        #expect(bank.quotes.map(\.id) == [9, 4])
    }
}

/// Token para alcanzar el bundle de tests, como en `AchievementCatalogTests`.
private final class QuoteBundleToken {}
