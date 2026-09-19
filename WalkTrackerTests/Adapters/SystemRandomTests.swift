import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El azar de producción (2.2, AD-10). Es el **único** `RandomPort` real: decide qué frase ve
/// Paul en cada caminata, y todos los demás tests de motivación corren sobre `RandomStub`, así
/// que sin esta suite el adapter no lo fija nadie.
///
/// No se comprueba la distribución —`SystemRandomNumberGenerator` no tiene semilla y eso es
/// justo lo que se quiere de él—, sino su **contrato**: el `nil` de "no hay nada que elegir" y
/// que el índice cae siempre dentro de `0..<count`, extremos incluidos. Un rango cerrado
/// (`0...count`) devolvería a veces un índice de una frase que no existe.
@Suite("SystemRandom · el azar de producción")
struct SystemRandomTests {

    /// Cuántas tiradas por caso. Suficientes para que los dos extremos de un conjunto pequeño
    /// salgan con una probabilidad abrumadora, y para que un índice fuera de rango asome.
    private static let rolls = 500

    @Test("Sin nada que elegir no hay índice", arguments: [0, -1, -7, Int.min])
    func noIndexWithoutACollection(count: Int) {
        #expect(SystemRandom().index(below: count) == nil, "quien llama trata el nil como \"no hay nada que elegir\"")
    }

    @Test("Un conjunto de uno siempre da el 0")
    func singleElement() {
        let random = SystemRandom()

        for _ in 0..<Self.rolls {
            #expect(random.index(below: 1) == 0)
        }
    }

    @Test("En unos cientos de tiradas el índice nunca se sale de 0..<count", arguments: [2, 3, 10, 100])
    func alwaysInsideTheHalfOpenRange(count: Int) throws {
        let random = SystemRandom()
        var seen = Set<Int>()

        for _ in 0..<Self.rolls {
            let index = try #require(random.index(below: count), "con count > 0 siempre hay índice")
            #expect(index >= 0, "índice negativo: \(index)")
            #expect(index < count, "índice \(index) fuera de 0..<\(count): un 0...count elegiría una frase que no existe")
            seen.insert(index)
        }

        // Y alcanza los dos extremos: un generador que devolviera siempre lo mismo, o que
        // nunca llegara al último, pasaría el rango pero no serviría para elegir frase.
        #expect(seen.contains(0), "nunca salió el primer elemento en \(Self.rolls) tiradas")
        #expect(seen.contains(count - 1), "nunca salió el último elemento en \(Self.rolls) tiradas")
    }

    @Test("El banco de las 100: cada tirada es un índice válido y no siempre el mismo")
    func coversTheRealBank() throws {
        let random = SystemRandom()
        var seen = Set<Int>()

        for _ in 0..<Self.rolls {
            seen.insert(try #require(random.index(below: 100)))
        }

        #expect(seen.allSatisfy { (0..<100).contains($0) })
        #expect(seen.count > 1, "un azar que devolviera siempre el mismo índice repetiría la frase cada caminata")
    }
}
