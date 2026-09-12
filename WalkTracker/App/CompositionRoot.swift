import Domain
import Foundation

/// El único sitio que conoce todas las capas. Construye los adapters y los entrega a
/// la aplicación y a la UI por sus puertos: nadie más resuelve una dependencia (AD-10).
///
/// Se puebla al entrar cada adapter en su historia. La 8.6 añade los cuatro de la capa
/// nativa extraída de `feature/flutter-substrate`.
@MainActor
struct CompositionRoot {

    /// El reloj y el calendario de la app llegan por puerto (AD-3, AD-19).
    let clock: any ClockPort
    /// Podómetro del coprocesador (CAP-2, CAP-3).
    let motion: any MotionPort
    /// Háptica y sonido de sistema (CAP-12).
    let feedback: any FeedbackPort
    /// Escritura de entrenamientos en Apple Salud (CAP-11).
    let health: any HealthPort
    /// Live Activity de la sesión (CAP-18).
    let liveActivity: any LiveActivityPort

    init(
        clock: any ClockPort = SystemClock(),
        motion: any MotionPort = MotionAdapter(),
        feedback: any FeedbackPort = FeedbackAdapter(),
        health: any HealthPort = HealthAdapter(),
        liveActivity: any LiveActivityPort = LiveActivityAdapter()
    ) {
        self.clock = clock
        self.motion = motion
        self.feedback = feedback
        self.health = health
        self.liveActivity = liveActivity
    }
}
