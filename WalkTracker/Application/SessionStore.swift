import Domain
import Foundation
import Observation

/// Único escritor de la sesión (AD-7). Las vistas leen su estado y llaman a sus
/// intenciones; nunca escriben una propiedad. Adapters y timers solo le publican
/// eventos.
///
/// La 1.1 cubre iniciar y el cronómetro. La sesión no se persiste (1.6, 5.1): cerrar la
/// app la descarta y se vuelve a Inicio.
@MainActor
@Observable
final class SessionStore {

    /// La sesión en curso, o `nil` antes de iniciar ("idle").
    private(set) var session: Session?

    @ObservationIgnored private let clock: any ClockPort
    /// Zancada con la que nace cada sesión. Hoy es la de `formulas.json`; el perfil de
    /// calibración la sustituirá.
    @ObservationIgnored private let strideM: Double

    init(clock: any ClockPort, strideM: Double) {
        self.clock = clock
        self.strideM = strideM
    }

    /// Hay una sesión abierta y la UI la presenta como modo a pantalla completa (AD-14).
    var hasSession: Bool { session != nil }

    /// Tiempo transcurrido **leído del reloj** en cada lectura. El tick de 1 Hz de la
    /// vista solo provoca la relectura: nunca acumula ni es fuente de verdad.
    var elapsedS: TimeInterval {
        elapsedS(notBefore: .distantPast)
    }

    /// Tiempo transcurrido en `max(instant, clock.now)`. Para el `TimelineView`, que puede
    /// evaluar una entrada un instante antes de su fecha: sin el suelo, el truncado
    /// mostraría k−1 y después saltaría un segundo. El reloj sigue mandando: la fecha
    /// de la entrada solo impide quedarse por detrás de ella.
    func elapsedS(notBefore instant: Date) -> TimeInterval {
        session?.elapsedS(at: max(instant, clock.now)) ?? 0
    }

    // MARK: - Intenciones

    /// Inicia una caminata que empieza ahora.
    ///
    /// Con una sesión ya abierta no hace nada: un doble toque en "Iniciar caminata" no
    /// crea otra ni reinicia el cronómetro.
    ///
    /// - Throws: `DomainError.invalidValue(field: "strideM")` si la zancada no vale; en
    ///   ese caso no se crea ninguna sesión.
    func start() throws(DomainError) {
        guard session == nil else { return }
        session = try Session.start(at: clock.now, strideM: strideM)
    }
}
