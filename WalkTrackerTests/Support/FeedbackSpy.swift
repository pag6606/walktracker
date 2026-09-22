import Domain
import Foundation
import Synchronization

/// `FeedbackPort` de test: registra lo que se le dispara y no toca la háptica (4.1).
///
/// **Hoy no existía ningún doble del puerto** —el único consumidor de `FeedbackPort` era la
/// pantalla de diagnóstico, que lo lanza a mano— y sin él "un suceso, un evento" no se puede
/// afirmar: la diferencia entre vibrar una vez y vibrar tres no la ve ningún test que solo
/// compruebe que algo pasó.
///
/// `Mutex` y no un array suelto porque el puerto es `Sendable` y `fire` es `nonisolated`: lo
/// puede llamar cualquier aislamiento, como el adapter de verdad.
final class FeedbackSpy: FeedbackPort {

    /// Un disparo tal y como llegó: **con su `soundEnabled`**, porque la decisión D1 —solo
    /// háptica hasta que la 4.2 traiga la preferencia— se afirma sobre ese argumento y no sobre
    /// el evento.
    struct Fired: Equatable, Sendable {
        let event: FeedbackEvent
        let soundEnabled: Bool
    }

    private let state = Mutex<[Fired]>([])

    /// Todo lo disparado, en orden.
    var fired: [Fired] { state.withLock { $0 } }

    /// Solo los eventos, en orden: lo que basta para la mayoría de las aserciones.
    var events: [FeedbackEvent] { fired.map(\.event) }

    /// Cuántas veces se disparó `event`. **Es el contador que hace verdadera la regla "un
    /// suceso, un evento"**: `contains` no distingue una vibración de tres.
    func count(of event: FeedbackEvent) -> Int {
        fired.count { $0.event == event }
    }

    /// Olvida lo disparado hasta ahora, para que un test pueda montar su precondición y después
    /// afirmar sobre lo que ocurre **a partir de ahí** (abrir la sesión siempre dispara
    /// `.sessionStart`, y eso tapa lo que venga detrás).
    func clear() {
        state.withLock { $0.removeAll() }
    }

    // MARK: - FeedbackPort

    func fire(_ event: FeedbackEvent, soundEnabled: Bool) {
        state.withLock { $0.append(Fired(event: event, soundEnabled: soundEnabled)) }
    }
}
