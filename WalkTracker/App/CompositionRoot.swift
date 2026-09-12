import Domain
import Foundation

/// El único sitio que conoce todas las capas. Construye los adapters y los entrega a
/// la aplicación y a la UI por sus puertos: nadie más resuelve una dependencia.
///
/// Andamiaje de la historia 8.5 — se puebla al entrar cada adapter en su historia.
@MainActor
struct CompositionRoot {

    /// El reloj y el calendario de la app llegan por puerto (AD-3, AD-19).
    let clock: any ClockPort

    init(clock: any ClockPort = SystemClock()) {
        self.clock = clock
    }
}
