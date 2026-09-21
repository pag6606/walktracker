import Domain
import Foundation
import OSLog

/// El estado de los logros en `achievements.json`, en **Application Support** (5.1, CAP-8) —
/// AD-9, AD-10, AD-16.
///
/// **Dos ficheros con el mismo nombre, y no son el mismo fichero.** El catálogo de los 14 logros
/// es contenido congelado en `WalkTracker/Resources/achievements.json`, dentro del **bundle**, lo
/// lee `CompositionRoot.loadAchievementCatalog(from:)` y un gate lo compara campo a campo contra
/// la referencia de la v3 (AD-5). Este adapter nunca lo toca: escribe en el **sandbox**, que es
/// otro directorio, y su contenido es qué ha conseguido Paul —no qué se puede conseguir—.
///
/// **La 5.1 crea el dueño y el esquema; el contenido lo escribe la 3.2** (AD-17: los logros se
/// evalúan al cerrar la sesión, dentro de la misma transacción que la persiste, nunca al abrir
/// una pantalla).
///
/// **Formato.** JSON `Codable` con `schemaVersion` 1 y un array `achievements`, con los instantes
/// en ISO-8601 como el historial. Mismas reglas que `sessions.json`: un esquema del futuro se
/// deja intacto y lanza; un ilegible se aparta y lanza; una fila que el dominio rechaza hace
/// ilegible el fichero en vez de saltarse en silencio.
struct AchievementsFileAdapter {

    /// La versión que se escribe. `achievements.json` nace en la 5.1.
    static let supportedSchemaVersion = 1
    /// Las versiones que se leen. Hoy solo la 1.
    static let readableSchemaVersions: ClosedRange<Int> = 1...1
    /// El nombre base, del que `JSONFileStore` deriva **todos** los nombres.
    private static let base = "achievements"
    static var fileName: String { JSONFileStore.fileName(base: base) }
    /// Prefijo y extensión de un estado apartado: `achievements.corrupt.<marca>.json`.
    static var setAsideFilePrefix: String { JSONFileStore.setAsideFilePrefix(base: base) }
    static var setAsideFileExtension: String { JSONFileStore.setAsideFileExtension }

    private static let log = Logger(subsystem: "com.walktracker.app", category: "AchievementsFileAdapter")

    private let file: JSONFileStore

    init(directory: URL = .applicationSupportDirectory) {
        file = JSONFileStore(directory: directory, base: Self.base)
    }

    /// Directorio del estado de logros: Application Support en la app, uno temporal en los tests.
    /// **Nunca el bundle**, donde vive el catálogo homónimo.
    var directory: URL { file.directory }
    var fileURL: URL { file.fileURL }

    // MARK: - Estado de los logros

    func loadAchievements() throws(StorageError) -> [AchievementUnlock]? {
        guard let data = try file.read() else { return nil }
        do {
            return try Self.decode(data)
        } catch .unsupportedSchemaVersion(let version) where version > Self.supportedSchemaVersion {
            Self.log.error("achievements.json (sandbox) es de un esquema más nuevo (\(version, privacy: .public) > \(Self.supportedSchemaVersion, privacy: .public)); el fichero se deja donde está y la lectura lanza")
            throw .unsupportedSchemaVersion(version)
        } catch {
            do {
                try file.setAside()
            } catch {
                Self.log.error("No se pudo apartar un estado de logros ilegible: \(String(describing: error), privacy: .public)")
            }
            throw error
        }
    }

    func saveAchievements(_ achievements: [AchievementUnlock]) throws(StorageError) {
        try file.write(try Self.encode(achievements))
    }

    // MARK: - Formato (puro)

    private struct File: Codable {
        var schemaVersion: Int
        var achievements: [UnlockFile]
    }

    /// Un logro en el fichero. `unlockedAt` ausente o `null` es "todavía no conseguido".
    private struct UnlockFile: Codable {
        var key: String
        var unlockedAt: String?
        var progress: Double
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int
    }

    /// JSON → estado de logros.
    ///
    /// - Throws: `unsupportedSchemaVersion` con una versión fuera de 1; `malformed` si no es
    ///   JSON, falta `schemaVersion`, un campo tiene otro tipo, un `unlockedAt` no es ISO-8601,
    ///   una clave está repetida o una fila no cruza la frontera del dominio.
    static func decode(_ data: Data) throws(StorageError) -> [AchievementUnlock] {
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw .malformed(String(describing: error))
        }
        guard readableSchemaVersions.contains(version) else { throw .unsupportedSchemaVersion(version) }
        let file: File
        do {
            file = try decoder.decode(File.self, from: data)
        } catch {
            throw .malformed(String(describing: error))
        }
        var unlocks: [AchievementUnlock] = []
        var seen: Set<String> = []
        unlocks.reserveCapacity(file.achievements.count)
        for row in file.achievements {
            // La clave es la identidad de la fila. Con una repetida no hay forma de saber cuál
            // manda, y "la última gana" sería inventarse una regla: el fichero es ilegible.
            guard seen.insert(row.key).inserted else {
                throw .malformed("achievements.json: la clave `\(row.key)` aparece más de una vez")
            }
            let unlockedAt: Date?
            switch row.unlockedAt {
            case nil:
                unlockedAt = nil
            case let text?:
                guard let instant = ISO8601Timestamp.instant(text) else {
                    throw .malformed("achievements.json: `unlockedAt` no es ISO-8601 (\(text))")
                }
                unlockedAt = instant
            }
            do {
                unlocks.append(try AchievementUnlock(key: row.key, unlockedAt: unlockedAt, progress: row.progress))
            } catch {
                throw .malformed("achievements.json: un logro no cruza la frontera del dominio: \(String(describing: error))")
            }
        }
        return unlocks
    }

    /// Estado de logros → JSON, con las claves ordenadas.
    ///
    /// - Throws: `failed(operation: "encode")`.
    static func encode(_ achievements: [AchievementUnlock]) throws(StorageError) -> Data {
        let file = File(
            schemaVersion: supportedSchemaVersion,
            achievements: achievements.map { unlock in
                UnlockFile(
                    key: unlock.key,
                    unlockedAt: unlock.unlockedAt.map(ISO8601Timestamp.text),
                    progress: unlock.progress
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(file)
        } catch {
            throw .failed(operation: "encode")
        }
    }
}
