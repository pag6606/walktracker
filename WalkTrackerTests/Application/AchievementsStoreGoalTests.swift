import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El desbloqueo de `weekly_goal` (3.1): el único logro que esta historia toca.
@MainActor
@Suite("AchievementsStore · el logro de la meta semanal")
struct AchievementsStoreGoalTests {

    private static let instant = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!

    @Test("La clave que usa el store es la del catálogo congelado, y es la de weeklyGoalMet")
    func theKeyIsTheOneInTheFrozenCatalog() throws {
        // **Esto es lo que hace honesto duplicar la clave en Swift.** El umbral, la comparación,
        // el nombre y el emoji siguen viviendo solo en `Resources/achievements.json` (AD-5); lo
        // único que se escribe aquí es la clave, y este test la ata al catálogo del bundle: si
        // la entrada #5 desapareciera o dejara de ser la de la meta semanal, la suite lo dice en
        // vez de dejar un desbloqueo que no le corresponde a nadie.
        let catalog = try CompositionRoot.loadAchievementCatalog(from: .main)
        let definition = try #require(catalog.definition(for: AchievementsStore.weeklyGoalKey))

        #expect(definition.metric == .weeklyGoalMet)
        #expect(definition.comparison == .eq)
        #expect(definition.threshold == .number(1))
        #expect(AchievementCatalog.requiredKeys.contains(AchievementsStore.weeklyGoalKey))
    }

    @Test("Desbloquearlo lo escribe una vez, con su instante y su progreso")
    func unlockingWritesOnce() throws {
        let storage = StorageStub()
        let store = AchievementsStore(storage: storage)

        #expect(store.unlockWeeklyGoal(at: Self.instant) == true)

        let unlocked = try #require(store.unlock(forKey: AchievementsStore.weeklyGoalKey))
        #expect(unlocked.unlockedAt == Self.instant)
        #expect(unlocked.progress == 1, "su umbral es `eq 1`: no hay medio logro")
        #expect(storage.achievementsSaved.count == 1)
    }

    @Test("Es idempotente y de POR VIDA: la segunda vez no escribe ni cambia el instante")
    func unlockingTwiceIsHarmless() throws {
        let storage = StorageStub()
        let store = AchievementsStore(storage: storage)
        #expect(store.unlockWeeklyGoal(at: Self.instant) == true)

        let later = Self.instant.addingTimeInterval(7 * 24 * 3600)
        #expect(store.unlockWeeklyGoal(at: later) == false)

        #expect(store.unlock(forKey: AchievementsStore.weeklyGoalKey)?.unlockedAt == Self.instant, "AD-17: no se re-dispara")
        #expect(storage.achievementsSaved.count == 1)
    }

    @Test("Una fila con progreso y sin desbloquear se sustituye en su sitio, no se duplica")
    func aPendingRowIsReplacedInPlace() throws {
        let pending = try AchievementUnlock(key: AchievementsStore.weeklyGoalKey, unlockedAt: nil, progress: 0)
        let other = try AchievementUnlock(key: "first_km", unlockedAt: Self.instant, progress: 1)
        let storage = StorageStub(achievements: [other, pending])
        let store = AchievementsStore(storage: storage)

        #expect(store.unlockWeeklyGoal(at: Self.instant) == true)

        #expect(store.unlocks.count == 2, "una clave no aparece dos veces en el fichero")
        #expect(store.unlock(forKey: AchievementsStore.weeklyGoalKey)?.isUnlocked == true)
        #expect(store.unlock(forKey: "first_km") == other, "y el logro de otro no se toca")
    }

    @Test("Con el fichero de logros ilegible no se escribe encima, y se dice que no se desbloqueó")
    func unreadableAchievementsAreNotOverwritten() {
        let storage = StorageStub()
        storage.failLoadAchievements(with: .unsupportedSchemaVersion(99))
        let store = AchievementsStore(storage: storage)

        #expect(store.unlockWeeklyGoal(at: Self.instant) == false)
        #expect(storage.achievementsSaved.isEmpty, "B-1: un esquema del futuro no se sobrescribe")
    }
}
