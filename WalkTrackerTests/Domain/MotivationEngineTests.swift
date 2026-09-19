import Domain
import Foundation
import Testing

@testable import WalkTracker

/// La selección de frase del arranque (2.2, CAP-6, domain-model.md §5): la matriz de la
/// historia sobre el motor puro. El azar entra por `RandomPort`, así que aquí no hay suerte
/// que valga: cada caso fija el índice que se elige.
@Suite("MotivationEngine · selección de frase")
struct MotivationEngineTests {

    /// Un banco de `count` frases con ids 1…`count`. Ids únicos y textos no vacíos: la
    /// validación del `init` no puede fallar.
    private static func bank(_ count: Int) -> QuoteBank {
        try! QuoteBank(quotes: (0..<count).map { Quote(id: $0 + 1, text: "Frase \($0 + 1)") })
    }

    /// El azar fijo de estos tests. `RandomStub` recuerda además el tamaño del conjunto de
    /// cada llamada: es lo que demuestra que el filtro se aplicó ANTES de elegir, y no después.
    private static func random(index: Int = 0) -> RandomStub {
        RandomStub(.fixed(index))
    }

    // MARK: - Matriz de la historia

    @Test("Caso normal: banco de 100 con 20 recientes → se elige de las 80 restantes")
    func normalCase() throws {
        let random = Self.random()
        let recent = Array(1...20)

        let selection = try #require(MotivationEngine.selectQuote(from: Self.bank(100), recentQuoteIds: recent, random: random))

        #expect(random.counts == [80], "el filtro se aplica ANTES de elegir: 100 − 20")
        #expect(!recent.contains(selection.quote.id))
        #expect(selection.quote.id == 21, "la primera de las disponibles, con el índice 0")
        #expect(!selection.ignoredRecentWindow)
    }

    @Test("Ventana vacía: se elige de las 100")
    func emptyWindow() throws {
        let random = Self.random()

        let selection = try #require(MotivationEngine.selectQuote(from: Self.bank(100), recentQuoteIds: [], random: random))

        #expect(random.counts == [100])
        #expect(selection.quote.id == 1)
        #expect(!selection.ignoredRecentWindow)
    }

    @Test("Todas excluidas: se ignora el filtro y se elige del banco entero, señalándolo")
    func allExcluded() throws {
        let random = Self.random(index: 2)

        let selection = try #require(MotivationEngine.selectQuote(from: Self.bank(3), recentQuoteIds: [1, 2, 3], random: random))

        #expect(random.counts == [3], "el conjunto vuelve a ser el banco entero")
        #expect(selection.quote.id == 3)
        #expect(selection.ignoredRecentWindow, "quien llama tiene que poder registrarlo: el fallback no es silencioso")
    }

    @Test("Banco vacío: no hay frase, y ni siquiera se pide un índice")
    func emptyBank() {
        let random = Self.random()

        #expect(MotivationEngine.selectQuote(from: .empty, recentQuoteIds: [], random: random) == nil)
        #expect(random.counts.isEmpty)
    }

    @Test("Ventana con ids fantasma: se ignoran y no estrechan el conjunto")
    func phantomIds() throws {
        let random = Self.random()

        let selection = try #require(
            MotivationEngine.selectQuote(from: Self.bank(5), recentQuoteIds: [900, 901, 902], random: random)
        )

        #expect(random.counts == [5], "un id que no está en el banco no excluye nada")
        #expect(selection.quote.id == 1)
        #expect(!selection.ignoredRecentWindow)
    }

    @Test("Solo cuentan las últimas 20 de la ventana, como el slice(-20) de la v3")
    func onlyTheLastTwentyExclude() throws {
        // Una ventana más larga de lo debido (un fichero de otra versión) no puede excluir de
        // más: las 5 primeras vuelven a estar disponibles.
        let random = Self.random()
        let tooLong = Array(1...25)

        let selection = try #require(MotivationEngine.selectQuote(from: Self.bank(30), recentQuoteIds: tooLong, random: random))

        #expect(random.counts == [10], "30 − las 20 últimas (6…25)")
        #expect(selection.quote.id == 1, "la 1 salió de la ventana al pasar de 20")
    }

    @Test("Un puerto de azar que no elige no inventa frase")
    func randomWithoutIndex() {
        #expect(MotivationEngine.selectQuote(from: Self.bank(10), recentQuoteIds: [], random: RandomStub(.none)) == nil)
    }

    @Test("Un índice fuera de rango no revienta ni devuelve otra frase: no hay frase")
    func outOfRangeIndex() {
        #expect(MotivationEngine.selectQuote(from: Self.bank(10), recentQuoteIds: [], random: RandomStub(.outOfRange)) == nil)
    }

    // MARK: - 20 seguidas sin repetir

    @Test("20 selecciones consecutivas sobre un banco de 100: ninguna frase repetida")
    func twentyConsecutiveWithoutRepeats() throws {
        // El azar más adverso posible: siempre el índice 0. Sin la ventana, las 20 serían la
        // misma frase; con ella, la 0 del conjunto disponible cambia en cada vuelta.
        let random = Self.random()
        let bank = Self.bank(100)
        var recent: [Int] = []
        var shown: [Int] = []

        for _ in 0..<20 {
            let selection = try #require(MotivationEngine.selectQuote(from: bank, recentQuoteIds: recent, random: random))
            #expect(!selection.ignoredRecentWindow)
            shown.append(selection.quote.id)
            recent = MotivationEngine.updateRecentIds(recent, selectedId: selection.quote.id)
        }

        #expect(shown.count == 20)
        #expect(Set(shown).count == 20, "ninguna repetida en la secuencia: \(shown)")
        #expect(random.counts == (0..<20).map { 100 - $0 }, "el conjunto se estrecha una frase por vuelta")
    }

    @Test("Con un banco de justo 20, la vuelta 21 ya no puede evitar repetir, y lo dice")
    func theTwentyFirstOnASmallBank() throws {
        let random = Self.random()
        let bank = Self.bank(20)
        var recent: [Int] = []

        for _ in 0..<20 {
            let selection = try #require(MotivationEngine.selectQuote(from: bank, recentQuoteIds: recent, random: random))
            #expect(!selection.ignoredRecentWindow)
            recent = MotivationEngine.updateRecentIds(recent, selectedId: selection.quote.id)
        }

        let twentyFirst = try #require(MotivationEngine.selectQuote(from: bank, recentQuoteIds: recent, random: random))
        #expect(twentyFirst.ignoredRecentWindow, "el fallback se dispara, y con señal")
    }

    // MARK: - Ventana de recientes

    @Test("updateRecentIds: FIFO con tope de 20")
    func windowIsFIFOCappedAtTwenty() {
        var recent: [Int] = []
        for id in 1...25 {
            recent = MotivationEngine.updateRecentIds(recent, selectedId: id)
        }

        #expect(recent.count == MotivationEngine.recentWindow)
        #expect(recent == Array(6...25), "entra por el final, sale por el principio")
    }

    @Test("updateRecentIds: una ventana más larga de lo debido se recorta al tope")
    func overlongWindowIsTrimmed() {
        let updated = MotivationEngine.updateRecentIds(Array(1...100), selectedId: 101)

        #expect(updated.count == MotivationEngine.recentWindow)
        #expect(updated.last == 101)
        #expect(updated.first == 82)
    }

    @Test("updateRecentIds no deduplica: reproduce la v3 tal cual")
    func windowDoesNotDeduplicate() {
        #expect(MotivationEngine.updateRecentIds([7, 8], selectedId: 7) == [7, 8, 7])
    }

    @Test("La ventana son 20: el valor que fija la regla del épico")
    func windowSize() {
        #expect(MotivationEngine.recentWindow == 20)
    }
}
