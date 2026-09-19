import Domain
import Foundation
import Synchronization

/// `RandomPort` de test: el azar lo fija el test. Es lo que hace comprobable "20 caminatas
/// seguidas sin frase repetida" sin depender de la suerte.
///
/// Por omisión recorre `0, 1, 2, …` sobre el conjunto disponible de cada llamada, que es la
/// secuencia más exigente para la ventana de recientes: sin exclusión, repetiría la primera
/// frase una y otra vez.
final class RandomStub: RandomPort {

    /// Qué índice devuelve cada llamada. **Es la única forma de azar de test que hay**: los
    /// casos "no hay índice" y "el índice no vale" son estrategias, no tipos aparte.
    enum Strategy: Sendable {
        /// Siempre el mismo índice, acotado al conjunto.
        case fixed(Int)
        /// `0, 1, 2, …` según el número de llamada, acotado al conjunto.
        case increasing
        /// Los índices de la lista, en orden; al agotarse vuelve al principio.
        case sequence([Int])
        /// Nunca hay índice: el puerto dice que no hay nada que elegir.
        case none
        /// Un índice imposible, fuera de `0..<count`: el camino que nunca se fuerza.
        case outOfRange
    }

    private struct State {
        var strategy: Strategy
        var callCount = 0
        /// El `count` de cada llamada, en orden: el tamaño del conjunto del que se eligió.
        var counts: [Int] = []
    }

    private let state: Mutex<State>

    init(_ strategy: Strategy = .increasing) {
        state = Mutex(State(strategy: strategy))
    }

    // MARK: - RandomPort

    func index(below count: Int) -> Int? {
        state.withLock { state in
            state.counts.append(count)
            let call = state.callCount
            state.callCount += 1
            switch state.strategy {
            case .none:
                return nil
            case .outOfRange:
                return count + 7
            case .fixed, .increasing, .sequence:
                break
            }
            guard count > 0 else { return nil }
            switch state.strategy {
            case .fixed(let index):
                return index % count
            case .increasing:
                return call % count
            case .sequence(let indices):
                guard !indices.isEmpty else { return nil }
                return indices[call % indices.count] % count
            case .none, .outOfRange:
                return nil
            }
        }
    }

    // MARK: - Control del test

    var callCount: Int { state.withLock { $0.callCount } }
    /// El tamaño del conjunto de cada llamada, en orden: con el filtro puesto, 80 de 100.
    var counts: [Int] { state.withLock { $0.counts } }
}
