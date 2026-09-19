import Domain
import Foundation

/// `RandomPort` sobre el generador del sistema (AD-10).
///
/// `SystemRandomNumberGenerator` es criptográficamente seguro y no tiene semilla: es lo que
/// hace que la elección de frase sea de verdad aleatoria entre lanzamientos. Por eso el azar
/// entra por un puerto — el dominio no puede depender de algo así y seguir siendo
/// vectorizable.
struct SystemRandom: RandomPort {

    func index(below count: Int) -> Int? {
        guard count > 0 else { return nil }
        return Int.random(in: 0..<count)
    }
}
