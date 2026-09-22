import Domain
import Foundation

@testable import WalkTracker

/// El cableado de `SettingsStore` para los tests que **no** miran la meta semanal.
///
/// Desde la 3.1 el store de ajustes necesita el historial, los logros y el reloj —el anillo suma
/// las caminatas de la semana y cumplir la meta desbloquea `weekly_goal`— y los tres son
/// **obligatorios a propósito**: cada fichero tiene un dueño y **una sola instancia** de él
/// (AD-16). Esto evita escribir ese cableado en los treinta sitios a los que la meta les da
/// igual.
///
/// **Cuándo NO se puede usar, y por qué existe la advertencia.** Un test que tenga su propio
/// `HistoryStore` sobre el mismo `storage` tiene que pasarlo aquí (o construir el store a mano):
/// esto crea el suyo, y leer un `sessions.json` ilegible **lo aparta**, así que el segundo lector
/// encontraría "no hay fichero" y el aviso de la 5.1 no saldría. No es hipotético: es lo que pasó
/// al escribir la 3.1, y lo cazó `HistoryStorePersistenceTests`.
enum SettingsStoreFixture {

    /// Miércoles 8 de julio de 2026, 12:00 UTC — la semana ISO **2026-W28**, la misma que usan los
    /// tests de la meta semanal. Fijo a propósito: con el reloj del sistema, la semana del anillo
    /// la decidiría el día en que se ejecute la suite.
    static let defaultNow = Date(timeIntervalSince1970: 1_783_512_000)

    /// Un `SettingsStore` con sus colaboradores sobre el mismo `storage`.
    ///
    /// - Parameter clock: el reloj del anillo. **Un test de meta semanal pasa el suyo**: con el
    ///   del sistema, la semana la fijaría el día en que se ejecute la suite.
    @MainActor
    static func store(
        storage: any StoragePort,
        history: HistoryStore? = nil,
        achievements: AchievementsStore? = nil,
        clock: any ClockPort = ClockStub(now: Self.defaultNow)
    ) -> SettingsStore {
        SettingsStore(
            storage: storage,
            history: history ?? HistoryStore(storage: storage),
            achievements: achievements ?? AchievementsStore(storage: storage),
            clock: clock
        )
    }
}
