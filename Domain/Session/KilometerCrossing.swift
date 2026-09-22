import Foundation

/// ¿La caminata acaba de cruzar un kilómetro? (CAP-12, 4.1)
///
/// Una función pura sobre dos distancias acumuladas —la anterior y la nueva—, sin store,
/// sin sesión y sin reloj. Existe porque **no había nada parecido**: la aplicación reasigna
/// las métricas en doce sitios y en ninguno compara la distancia de antes con la de ahora.
///
/// **Responde `Bool`, no un número, y eso es la decisión D3 hecha tipo.** Saltar de 800 a
/// 4.200 m cruza tres múltiplos y produce **un** evento, no tres: una confirmación discreta,
/// no una ráfaga. Devolver "cuántos se cruzaron" habría dejado esa decisión suelta en cada
/// punto de llamada.
public enum KilometerCrossing {

    /// El múltiplo que se celebra, en metros. Un kilómetro, y no es un número de formato:
    /// es **la unidad del evento** `FeedbackEvent.kilometer`.
    public static let stepM: Double = 1_000

    /// `true` si entre `previousM` y `currentM` se cruzó al menos un múltiplo de ``stepM``.
    ///
    /// Cruzar es **alcanzarlo**, no pasarlo: de 999 a 1.000 m exactos se ha cruzado el primer
    /// kilómetro. De 1.100 a 1.900 no se cruza ninguno, porque los dos están dentro del mismo.
    ///
    /// Una distancia que no avanza —igual o menor que la anterior, que es lo que produce una
    /// métrica degradada (`SessionMetrics.degraded` devuelve ceros)— **no cruza nada**: no se
    /// celebra hacia atrás.
    ///
    /// - Parameters:
    ///   - previousM: distancia acumulada con la que se evaluó la última vez, en metros.
    ///   - currentM: distancia acumulada de ahora, en metros.
    /// - Returns: `false` ante cualquier entrada que no sea un par de metros finitos y no
    ///   negativos que avanza. Un feedback perdido no es un fallo de sesión (`FeedbackPort`),
    ///   así que la frontera no lanza: se calla.
    public static func didCross(from previousM: Double, to currentM: Double) -> Bool {
        guard previousM.isFinite, currentM.isFinite else { return false }
        guard previousM >= 0, currentM > previousM else { return false }
        return (currentM / stepM).rounded(.down) > (previousM / stepM).rounded(.down)
    }
}
