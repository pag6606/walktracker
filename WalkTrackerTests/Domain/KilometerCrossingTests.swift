import Domain
import Foundation
import Testing

/// El cruce de kilómetro (4.1): la única pieza de lógica que la historia del canal de feedback
/// tenía que inventar, porque no existía en ninguna parte.
///
/// Se prueba **sin store y sin vista**: es una función pura de dos distancias. Las filas de la
/// matriz que hablan de kilómetros se ejecutan aquí; que el disparo esté cableado donde toca lo
/// fijan los tests de `SessionStore`.
@Suite("Cruce de kilómetro")
struct KilometerCrossingTests {

    @Test("El primer kilómetro: de 980 a 1.020 m se cruza")
    func crossesTheFirstKilometer() {
        #expect(KilometerCrossing.didCross(from: 980, to: 1_020))
    }

    @Test("Dentro del mismo kilómetro no se cruza nada: de 1.100 a 1.900 m")
    func staysInsideTheSameKilometer() {
        #expect(!KilometerCrossing.didCross(from: 1_100, to: 1_900))
    }

    /// Cruzar es **alcanzar** el múltiplo, no pasarlo: con un `>` en vez de un `>=` dentro de la
    /// división, los 1.000 m exactos no sonarían y el primer kilómetro llegaría tarde.
    @Test("Justo en el múltiplo: de 999 a 1.000 m exactos SÍ se cruza")
    func exactMultipleCrosses() {
        #expect(KilometerCrossing.didCross(from: 999, to: 1_000))
        #expect(KilometerCrossing.didCross(from: 3_999.99, to: 4_000))
    }

    /// D3 hecha tipo: la respuesta es `Bool`, así que tres múltiplos de golpe **no se pueden**
    /// contar por separado. Si esto devolviera un número, el punto de llamada tendría que
    /// volver a decidir, y ahí es donde nace la ráfaga.
    @Test("Varios kilómetros de golpe son UN cruce: de 800 a 4.200 m")
    func severalKilometersAtOnceAreOneCrossing() {
        #expect(KilometerCrossing.didCross(from: 800, to: 4_200))
    }

    @Test("Una distancia que no avanza no cruza: igual, menor o desde cero")
    func noProgressNeverCrosses() {
        #expect(!KilometerCrossing.didCross(from: 1_000, to: 1_000))
        #expect(!KilometerCrossing.didCross(from: 4_200, to: 0), "una métrica degradada da ceros: no se celebra hacia atrás")
        #expect(!KilometerCrossing.didCross(from: 0, to: 0))
        #expect(!KilometerCrossing.didCross(from: 0, to: 999.99))
    }

    /// La frontera **no lanza**: el puerto promete que un feedback perdido no es un fallo de
    /// sesión, así que una entrada imposible se calla en vez de abortar un cierre.
    @Test("Una entrada que no es un par de metros no cruza, y no lanza")
    func invalidInputNeverCrosses() {
        #expect(!KilometerCrossing.didCross(from: .nan, to: 2_000))
        #expect(!KilometerCrossing.didCross(from: 800, to: .nan))
        #expect(!KilometerCrossing.didCross(from: 800, to: .infinity))
        #expect(!KilometerCrossing.didCross(from: -1_500, to: 500))
    }

    @Test("Los kilómetros siguientes cuentan igual que el primero")
    func laterKilometersBehaveTheSame() {
        #expect(KilometerCrossing.didCross(from: 1_980, to: 2_020))
        #expect(KilometerCrossing.didCross(from: 41_999, to: 42_000))
        #expect(!KilometerCrossing.didCross(from: 42_001, to: 42_999))
    }

    @Test("El múltiplo del evento es el kilómetro, y es la unidad del canal")
    func theStepIsOneKilometer() {
        #expect(KilometerCrossing.stepM == 1_000)
    }
}
