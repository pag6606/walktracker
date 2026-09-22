import Domain
import Foundation
import Testing

@testable import WalkTracker

/// La intención que escribe los desbloqueos de un cierre (3.2) — AD-16, AD-17, CAP-15.
///
/// Su hermana `AchievementsStore+Goal.swift` tenía suite propia desde la 3.1 y ésta no: lo que se
/// prueba aquí es lo que el motor **no** puede probar, porque no sabe de ficheros — la escritura
/// única, la sustitución en su sitio de una fila en curso y, sobre todo, **que un desbloqueo no
/// se mueve ni se re-anuncia cuando la relectura de `save(applying:)` lo destapa**.
@MainActor
@Suite("AchievementsStore · los desbloqueos del cierre")
struct AchievementsStoreEvaluationTests {

    private static let earned = ISO8601DateFormatter().date(from: "2026-07-08T12:00:00Z")!
    private static let later = ISO8601DateFormatter().date(from: "2026-09-21T12:00:00Z")!

    private static func definition(_ key: String) throws -> AchievementDefinition {
        try #require(AchievementCatalogFixture.bundled.definition(for: key))
    }

    // MARK: - Lo que escribe

    @Test("Varios logros de un cierre se escriben en UNA sola escritura")
    func severalAchievementsAreWrittenOnce() throws {
        let storage = StorageStub()
        let store = AchievementsStore(storage: storage)

        let written = store.unlock([try Self.definition("first_session"), try Self.definition("first_km")], at: Self.earned)

        #expect(written.map(\.key) == ["first_session", "first_km"])
        #expect(storage.achievementsSaved.count == 1, "una caminata, una escritura")
        #expect(storage.achievements?.allSatisfy { $0.unlockedAt == Self.earned } == true)
        #expect(storage.achievements?.allSatisfy { $0.progress == 1 } == true)
    }

    /// La rama que el defecto podía corromper: una fila **en curso** (con `progress` y sin
    /// `unlockedAt`) sí se sustituye en su sitio, porque una clave no aparece dos veces.
    @Test("Una fila con progreso y sin instante se sustituye en su sitio, no se duplica")
    func aPendingRowIsReplacedInPlace() throws {
        let pending = try AchievementUnlock(key: "first_km", unlockedAt: nil, progress: 800)
        let other = try AchievementUnlock(key: "first_session", unlockedAt: Self.earned, progress: 1)
        let storage = StorageStub(achievements: [other, pending])
        let store = AchievementsStore(storage: storage)

        let written = store.unlock([try Self.definition("first_km")], at: Self.later)

        #expect(written.map(\.key) == ["first_km"])
        #expect(store.unlocks.count == 2, "una clave no aparece dos veces en el fichero")
        #expect(store.unlock(forKey: "first_km")?.unlockedAt == Self.later)
        #expect(store.unlock(forKey: "first_session") == other, "y el logro de otro no se toca")
    }

    // MARK: - Lo que NO reescribe

    @Test("Un logro ya desbloqueado en memoria no vuelve a escribirse ni a anunciarse")
    func anAlreadyUnlockedAchievementIsSkipped() throws {
        let stored = try AchievementUnlock(key: "first_km", unlockedAt: Self.earned, progress: 1)
        let storage = StorageStub(achievements: [stored])
        let store = AchievementsStore(storage: storage)

        #expect(store.unlock([try Self.definition("first_km")], at: Self.later).isEmpty)
        #expect(storage.achievementsSaved.isEmpty)
        #expect(store.unlock(forKey: "first_km")?.unlockedAt == Self.earned)
    }

    /// **El defecto de verdad, y por qué la guarda vive dentro del closure.** `save(applying:)`
    /// empieza por `readOutcome.allowsWriting || reloadBeforeWriting()`, y esa relectura
    /// **repuebla `unlocks` desde disco**. Con el estado en memoria vacío —porque la primera
    /// lectura falló— la decisión de "esto es nuevo" se tomaba contra el estado viejo, y el
    /// closure reescribía filas que la relectura acababa de destapar como ya conseguidas: les
    /// movía el `unlockedAt` y las devolvía como nuevas, o sea **se volvían a celebrar**. AD-17 y
    /// CAP-15 dicen lo contrario: no se re-dispara y nunca se revoca.
    @Test("Si la relectura destapa un logro ya conseguido, su instante NO se mueve ni se re-anuncia")
    func aReloadRevealingAnUnlockedRowDoesNotMoveIt() throws {
        let stored = try AchievementUnlock(key: "first_km", unlockedAt: Self.earned, progress: 1)
        let storage = StorageStub(achievements: [stored])
        // La primera lectura falla de forma **transitoria**: el fichero sigue en disco con su fila,
        // pero el store arranca sin nada en memoria y con la escritura bloqueada.
        storage.failLoadAchievements(with: .failed(operation: "read"))
        let store = AchievementsStore(storage: storage)
        try #require(store.readOutcome.isUnreadable)
        try #require(store.unlocks.isEmpty, "en memoria no consta, y ahí estaba la trampa")

        // El disco se recupera: ahora `reloadBeforeWriting()` sí va a leer la fila.
        storage.failLoadAchievements(with: nil)
        let written = store.unlock(
            [try Self.definition("first_km"), try Self.definition("first_session")],
            at: Self.later
        )

        #expect(written.map(\.key) == ["first_session"], "solo el que de verdad era nuevo")
        #expect(store.unlock(forKey: "first_km")?.unlockedAt == Self.earned, "su instante no se mueve")
        #expect(store.unlock(forKey: "first_session")?.unlockedAt == Self.later)
        #expect(store.unlocks.count == 2)
    }

    @Test("Con el fichero ilegible de verdad no se escribe encima y no se anuncia nada")
    func anUnreadableFileIsNotOverwritten() throws {
        let storage = StorageStub()
        storage.failLoadAchievements(with: .unsupportedSchemaVersion(99))
        let store = AchievementsStore(storage: storage)

        #expect(store.unlock([try Self.definition("first_km")], at: Self.earned).isEmpty)
        #expect(storage.achievementsSaved.isEmpty, "B-1: un esquema del futuro no se sobrescribe")
    }

    @Test("Si el disco falla al escribir, no se anuncia ningún logro")
    func aFailedWriteAnnouncesNothing() throws {
        let storage = StorageStub()
        storage.failSaveAchievements(with: .failed(operation: "write"))
        let store = AchievementsStore(storage: storage)

        #expect(store.unlock([try Self.definition("first_km")], at: Self.earned).isEmpty)
        #expect(storage.achievements == nil)
    }

    /// El mismo invariante por el camino de la meta semanal: las dos intenciones comparten
    /// `upsert(_:into:)` justamente para que no se pueda arreglar una y olvidar la otra.
    @Test("unlockWeeklyGoal tampoco mueve el instante cuando la relectura lo destapa")
    func theWeeklyGoalShareTheSameGuard() throws {
        let stored = try AchievementUnlock(key: AchievementsStore.weeklyGoalKey, unlockedAt: Self.earned, progress: 1)
        let storage = StorageStub(achievements: [stored])
        storage.failLoadAchievements(with: .failed(operation: "read"))
        let store = AchievementsStore(storage: storage)
        try #require(store.unlocks.isEmpty)

        storage.failLoadAchievements(with: nil)

        #expect(store.unlockWeeklyGoal(at: Self.later) == false, "no lo desbloqueó ESTA llamada")
        #expect(store.unlock(forKey: AchievementsStore.weeklyGoalKey)?.unlockedAt == Self.earned)
    }
}
