import Domain
import Foundation
import OSLog

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
    /// Catálogo de los 14 logros, ya validado (AD-5, CAP-8).
    let achievementCatalog: AchievementCatalog

    init(
        clock: any ClockPort = SystemClock(),
        motion: any MotionPort = MotionAdapter(),
        feedback: any FeedbackPort = FeedbackAdapter(),
        health: any HealthPort = HealthAdapter(),
        liveActivity: any LiveActivityPort = LiveActivityAdapter(),
        achievementCatalog: AchievementCatalog? = nil
    ) {
        self.clock = clock
        self.motion = motion
        self.feedback = feedback
        self.health = health
        self.liveActivity = liveActivity
        self.achievementCatalog = achievementCatalog ?? Self.bundledAchievementCatalogOrTerminate()
    }

    // MARK: - Catálogo de logros (AD-5)

    private static let log = Logger(subsystem: "com.walktracker.app", category: "AchievementCatalog")

    /// Lee y valida `achievements.json` de un bundle. Separado del arranque para que
    /// cada causa de rechazo sea comprobable sin matar el proceso de test.
    nonisolated static func loadAchievementCatalog(from bundle: Bundle) throws(AchievementCatalogError) -> AchievementCatalog {
        guard let url = bundle.url(forResource: "achievements", withExtension: "json") else {
            throw .malformed("achievements.json no está en el bundle \(bundle.bundleIdentifier ?? bundle.bundlePath)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .malformed("no se puede leer achievements.json: \(error.localizedDescription)")
        }
        return try AchievementCatalog.decode(from: data)
    }

    /// El catálogo de la app o nada: con un catálogo inválido **la app no arranca**
    /// (AD-5). No hay catálogo parcial ni vacío de reserva: degradar aquí es repetir
    /// en silencio el incidente del catálogo reteclado.
    private static func bundledAchievementCatalogOrTerminate() -> AchievementCatalog {
        do {
            return try loadAchievementCatalog(from: .main)
        } catch {
            log.fault("Catálogo de logros inválido: \(String(describing: error), privacy: .public)")
            fatalError("AD-5: el catálogo de logros no valida y la app no arranca — \(error)")
        }
    }
}
