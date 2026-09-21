import Domain
import Foundation
import Testing

@testable import WalkTracker

/// `HistoryStore`, dueño único de `sessions.json` (5.1, AD-16): la doctrina heredada de B-1
/// —`nil` no es un error, y sin una lectura buena no se escribe— y lo que esta historia añade,
/// que es el **aviso**.
@MainActor
@Suite("HistoryStore · dueño de sessions.json")
struct HistoryStoreTests {

    private static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private static func record(startedAt: Date = HistoryStoreTests.startedAt, distanceM: Double = 2_840.08) throws -> SessionRecord {
        try SessionRecord(
            id: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            stepsMeasured: 4_100,
            stepsEstimated: 0,
            strideM: 0.655,
            distanceM: distanceM,
            durationS: 1_800,
            pausesS: 0,
            paceSecPerKm: 634,
            cadenceSpm: 136.7
        )
    }

    // MARK: - Lectura

    @Test("Sin fichero: historial vacío, se puede escribir y no se avisa de nada")
    func absentFileStartsEmptyAndWritable() throws {
        let storage = StorageStub()

        let history = HistoryStore(storage: storage)

        #expect(history.records.isEmpty)
        #expect(history.readOutcome == .absent)
        #expect(!history.showsUnreadableNotice)
        #expect(history.append(try Self.record()))
        #expect(storage.sessions?.count == 1, "la primera instalación SÍ escribe")
    }

    @Test("Con fichero: el historial viene de él")
    func storedHistoryIsLoaded() throws {
        let stored = [try Self.record()]
        let history = HistoryStore(storage: StorageStub(sessions: stored))

        #expect(history.records == stored)
        #expect(history.readOutcome == .loaded)
        #expect(!history.showsUnreadableNotice)
    }

    /// El aviso que `settings.json` no necesita. Lo que se pierde aquí no se puede reconstruir.
    @Test("Historial ilegible: vacío, sin poder escribir, y CON aviso", arguments: [
        StorageError.malformed("roto"),
        StorageError.unsupportedSchemaVersion(99),
        StorageError.failed(operation: "read"),
    ])
    func unreadableHistoryWarnsAndBlocksWriting(error: StorageError) throws {
        let storage = StorageStub(sessions: [try Self.record()])
        storage.failLoadSessions(with: error)

        let history = HistoryStore(storage: storage)

        #expect(history.records.isEmpty, "la app sigue, con el historial vacío")
        #expect(history.readOutcome == .unreadable(error))
        #expect(history.showsUnreadableNotice, "y Paul se entera: esto es lo que diferencia al historial de los ajustes")
    }

    /// `malformed` lo aparta el adapter; lo apartado sigue en disco con su nombre único. Un
    /// esquema del futuro y un fallo de lectura dejan el fichero exactamente donde está.
    @Test("Un ilegible se aparta y no se destruye; el del futuro y el ilegible transitorio no se tocan")
    func unreadableFilesAreNeverDestroyed() throws {
        let stored = [try Self.record()]
        for (error, apartados) in [
            (StorageError.malformed("roto"), 1),
            (StorageError.unsupportedSchemaVersion(99), 0),
            (StorageError.failed(operation: "read"), 0),
        ] {
            let storage = StorageStub(sessions: stored)
            storage.failLoadSessions(with: error)

            _ = HistoryStore(storage: storage)

            #expect(storage.sessionsSetAside.count == apartados, "\(error)")
            if apartados == 0 {
                #expect(storage.sessions == stored, "\(error): el fichero sigue entero")
            }
        }
    }

    // MARK: - Escritura

    /// **La mutación que la spec exige**: sin esta guarda, un historial que no se pudo leer se
    /// sustituye por la caminata de hoy y los meses anteriores desaparecen.
    @Test("Con la lectura fallida de forma permanente NO se escribe encima")
    func permanentlyUnreadableHistoryIsNeverOverwritten() throws {
        let stored = [try Self.record()]
        let storage = StorageStub(sessions: stored)
        storage.failLoadSessions(with: .unsupportedSchemaVersion(99))
        let history = HistoryStore(storage: storage)

        let guardada = history.append(try Self.record(startedAt: Self.startedAt.addingTimeInterval(86_400)))

        #expect(!guardada)
        #expect(storage.sessionsSaved.isEmpty, "no se ha tocado el fichero")
        #expect(storage.sessions == stored, "y lo que había sigue entero")
        #expect(history.records.isEmpty, "el cambio tampoco se aplica en memoria: fingir que está guardada sería peor")
    }

    /// Diverge a propósito de `SettingsStore`: allí el cambio sí vale para la ejecución. Aquí
    /// un registro en memoria que no está en disco haría que `contains(startedAt:)` diera por
    /// salvada una caminata cuya única copia es el snapshot que se iba a borrar.
    @Test("Un fallo de ESCRITURA tampoco deja la caminata en memoria")
    func aFailedWriteDoesNotLeaveTheRecordInMemory() throws {
        let storage = StorageStub()
        let history = HistoryStore(storage: storage)
        storage.failSaveSessions(with: .failed(operation: "write"))

        let record = try Self.record()
        #expect(!history.append(record))
        #expect(history.records.isEmpty)
        #expect(!history.contains(startedAt: record.startedAt))
    }

    /// Un fallo de lectura al arrancar es casi siempre de un instante: bloquear la escritura de
    /// por vida convertiría un problema de un segundo en una ejecución sin guardar nada.
    @Test("Un fallo transitorio se recupera solo, y el cambio se aplica SOBRE lo que hay en disco")
    func transientFailureRecoversOnRetry() throws {
        let anterior = try Self.record()
        let storage = StorageStub(sessions: [anterior])
        storage.failLoadSessions(with: .failed(operation: "read"))
        let history = HistoryStore(storage: storage)
        #expect(history.records.isEmpty)

        storage.failLoadSessions(with: nil)
        let nueva = try Self.record(startedAt: Self.startedAt.addingTimeInterval(86_400))
        #expect(history.append(nueva))

        #expect(storage.sessions?.map(\.id) == [anterior.id, nueva.id], "la caminata anterior NO se ha perdido")
        #expect(!history.showsUnreadableNotice, "y el aviso se apaga solo al recuperarse")
    }

    /// El registro es inmutable y no se reconcilia: duplicarlo contaría dos veces sus kilómetros
    /// en el anillo y en los logros.
    @Test("Añadir dos veces la misma caminata no la duplica, y se sigue considerando guardada")
    func appendingTheSameWalkTwiceIsIdempotent() throws {
        let storage = StorageStub()
        let history = HistoryStore(storage: storage)
        let record = try Self.record()

        #expect(history.append(record))
        #expect(history.append(record))

        #expect(history.records.count == 1)
        #expect(storage.sessionsSaved.count == 1, "la segunda vez ni siquiera escribe")
    }

    @Test("`contains(startedAt:)` reconoce la caminata por su instante de inicio")
    func containsRecognisesTheWalkByItsStart() throws {
        let history = HistoryStore(storage: StorageStub(sessions: [try Self.record()]))

        #expect(history.contains(startedAt: Self.startedAt))
        #expect(!history.contains(startedAt: Self.startedAt.addingTimeInterval(1)))
    }

    @Test("Lo guardado se relee al montar otro store sobre el mismo almacenamiento")
    func savedHistorySurvivesANewStore() throws {
        let storage = StorageStub()
        let record = try Self.record()
        #expect(HistoryStore(storage: storage).append(record))

        let relanzado = HistoryStore(storage: storage)

        #expect(relanzado.records == [record])
    }
}

/// `AchievementsStore`, dueño único del `achievements.json` del sandbox (5.1). La 3.2 escribirá
/// su contenido; lo que se prueba aquí es que el dueño existe con la misma doctrina que los otros.
@MainActor
@Suite("AchievementsStore · dueño de achievements.json")
struct AchievementsStoreTests {

    private static let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Sin fichero: sin logros y se puede escribir")
    func absentFileStartsEmptyAndWritable() throws {
        let storage = StorageStub()
        let store = AchievementsStore(storage: storage)

        #expect(store.unlocks.isEmpty)
        #expect(store.readOutcome == .absent)
        let unlock = try AchievementUnlock(key: "first_walk", unlockedAt: Self.instant, progress: 1)
        let guardado = store.save { unlocks in unlocks.append(unlock) }
        #expect(guardado)
        #expect(storage.achievements == [unlock])
    }

    @Test("Con fichero: el estado viene de él y se consulta por clave")
    func storedStateIsLoaded() throws {
        let stored = [try AchievementUnlock(key: "marathon_42km", unlockedAt: nil, progress: 12_500)]
        let store = AchievementsStore(storage: StorageStub(achievements: stored))

        #expect(store.readOutcome == .loaded)
        #expect(store.unlock(forKey: "marathon_42km")?.progress == 12_500)
        #expect(store.unlock(forKey: "no_existe") == nil)
    }

    /// Un `unlockedAt` no puede volver a nulo por un fallo de lectura: sin lectura buena, no se
    /// escribe.
    @Test("Con la lectura fallida NO se escribe encima")
    func unreadableStateIsNeverOverwritten() throws {
        let stored = [try AchievementUnlock(key: "first_walk", unlockedAt: Self.instant, progress: 1)]
        let storage = StorageStub(achievements: stored)
        storage.failLoadAchievements(with: .unsupportedSchemaVersion(99))
        let store = AchievementsStore(storage: storage)

        let guardado = store.save { unlocks in unlocks = [] }
        #expect(!guardado)

        #expect(storage.achievementsSaved.isEmpty)
        #expect(storage.achievements == stored)
    }
}
