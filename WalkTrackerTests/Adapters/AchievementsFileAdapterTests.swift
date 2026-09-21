import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El `achievements.json` **del sandbox** en el borde (5.1, AD-9). El fichero lo estrena esta
/// historia; su contenido lo escribe la 3.2.
///
/// Su primer test es el que separa los dos ficheros que se llaman igual: este adapter escribe en
/// Application Support y el catálogo congelado sigue en el bundle, sin tocar.
@Suite("AchievementsFileAdapter · estado de los logros")
struct AchievementsFileAdapterTests {

    private static let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AchievementsFileAdapterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private static func setAsideNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter {
            $0.hasPrefix(AchievementsFileAdapter.setAsideFilePrefix)
                && $0.hasSuffix(AchievementsFileAdapter.setAsideFileExtension)
        }.sorted()
    }

    // MARK: - Los dos ficheros que se llaman igual

    /// **El riesgo que la spec nombra por su nombre.** El catálogo de los 14 logros es contenido
    /// congelado del bundle (AD-5) y este adapter escribe otro fichero homónimo en el sandbox.
    /// Si alguna vez se cruzaran, o se rompe el gate del catálogo o se pisa contenido congelado.
    @Test("El store del sandbox no toca el catálogo del bundle, que sigue validando")
    func theSandboxStoreDoesNotTouchTheBundledCatalog() throws {
        try Self.withDirectory { directory in
            let adapter = AchievementsFileAdapter(directory: directory)
            try adapter.saveAchievements([try AchievementUnlock(key: "inventado", unlockedAt: Self.instant, progress: 1)])

            #expect(adapter.fileURL.deletingLastPathComponent() == directory)
            // El catálogo se sigue leyendo del bundle de la app y sigue siendo el congelado.
            let catalog = try CompositionRoot.loadAchievementCatalog(from: .main)
            #expect(catalog.achievements.map(\.key) == AchievementCatalog.requiredKeys)
            #expect(!catalog.achievements.contains { $0.key == "inventado" })
        }
    }

    // MARK: - Formato (puro)

    @Test("Ida y vuelta: desbloqueados y en progreso vuelven iguales")
    func roundTrip() throws {
        let unlocks = [
            try AchievementUnlock(key: "first_walk", unlockedAt: Self.instant, progress: 1),
            try AchievementUnlock(key: "marathon_42km", unlockedAt: nil, progress: 12_500.5),
        ]

        #expect(try AchievementsFileAdapter.decode(AchievementsFileAdapter.encode(unlocks)) == unlocks)
    }

    @Test("Un fichero sin logros es válido")
    func emptyRoundTrips() throws {
        #expect(try AchievementsFileAdapter.decode(AchievementsFileAdapter.encode([])).isEmpty)
    }

    @Test("`unlockedAt` va en ISO-8601 y ausente significa `todavía no`")
    func unlockedAtIsISO8601() throws {
        let data = try AchievementsFileAdapter.encode([
            try AchievementUnlock(key: "first_walk", unlockedAt: Self.instant, progress: 1),
            try AchievementUnlock(key: "consistency_30", unlockedAt: nil, progress: 3),
        ])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(object["achievements"] as? [[String: Any]])

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(rows[0]["unlockedAt"] as? String == "2027-01-15T08:00:00.000Z")
        #expect(rows[1]["unlockedAt"] == nil)
    }

    /// "La última gana" sería inventarse una regla que nadie ha decidido: el fichero es ilegible.
    @Test("Una clave repetida hace ilegible el fichero")
    func repeatedKeyIsMalformed() {
        let json = #"""
        { "schemaVersion": 1, "achievements": [
            { "key": "first_walk", "unlockedAt": null, "progress": 1 },
            { "key": "first_walk", "unlockedAt": null, "progress": 2 }] }
        """#

        #expect(throws: StorageError.self) { try AchievementsFileAdapter.decode(Data(json.utf8)) }
    }

    @Test("Una fila que el dominio rechaza hace ilegible el fichero, no se salta")
    func rowRejectedByTheDomainIsMalformed() {
        let json = #"{ "schemaVersion": 1, "achievements": [{ "key": "x", "unlockedAt": null, "progress": -1 }] }"#

        #expect(throws: StorageError.self) { try AchievementsFileAdapter.decode(Data(json.utf8)) }
    }

    @Test("Lo que no es JSON o no tiene la forma del esquema es `malformed`", arguments: [
        "", "{}", #"{ "schemaVersion": 1 }"#,
        #"{ "schemaVersion": 1, "achievements": [{ "key": "x" }] }"#,
        #"{ "schemaVersion": 1, "achievements": [{ "key": "x", "unlockedAt": "anoche", "progress": 1 }] }"#,
    ])
    func malformedFiles(json: String) {
        #expect(throws: (any Error).self) { try AchievementsFileAdapter.decode(Data(json.utf8)) }
    }

    @Test("Una versión fuera de rango lanza `unsupportedSchemaVersion`", arguments: [0, 2, 99])
    func unsupportedVersions(version: Int) {
        let json = #"{ "schemaVersion": \#(version), "achievements": [] }"#

        #expect(throws: StorageError.unsupportedSchemaVersion(version)) {
            try AchievementsFileAdapter.decode(Data(json.utf8))
        }
    }

    // MARK: - Disco

    @Test("Sin fichero, el estado es `nil` y no se crea nada")
    func absentFileReadsAsNil() throws {
        try Self.withDirectory { directory in
            let adapter = AchievementsFileAdapter(directory: directory)

            let cargado = try adapter.loadAchievements()
            #expect(cargado == nil)
            #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
        }
    }

    @Test("Un estado ilegible se aparta y la lectura lanza")
    func unreadableStateIsSetAside() throws {
        try Self.withDirectory { directory in
            let adapter = AchievementsFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data("no soy json".utf8)
            try bytes.write(to: adapter.fileURL)

            #expect(throws: (any Error).self) { try adapter.loadAchievements() }

            let apartados = try Self.setAsideNames(in: directory)
            #expect(apartados.count == 1)
            let apartado = directory.appending(path: try #require(apartados.first), directoryHint: .notDirectory)
            #expect(try Data(contentsOf: apartado) == bytes)
        }
    }

    @Test("Un estado de un esquema del futuro se deja INTACTO y la lectura lanza")
    func futureSchemaIsLeftUntouched() throws {
        try Self.withDirectory { directory in
            let adapter = AchievementsFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data(#"{ "schemaVersion": 99, "achievements": [] }"#.utf8)
            try bytes.write(to: adapter.fileURL)

            #expect(throws: StorageError.unsupportedSchemaVersion(99)) { try adapter.loadAchievements() }

            #expect(try Data(contentsOf: adapter.fileURL) == bytes)
            #expect(try Self.setAsideNames(in: directory).isEmpty)
        }
    }

    @Test("Lo guardado se relee igual, y el fichero se llama `achievements.json`")
    func savedStateIsReadBack() throws {
        try Self.withDirectory { directory in
            let adapter = AchievementsFileAdapter(directory: directory)
            let unlocks = [try AchievementUnlock(key: "first_walk", unlockedAt: Self.instant, progress: 1)]

            try adapter.saveAchievements(unlocks)

            #expect(adapter.fileURL.lastPathComponent == "achievements.json")
            let releído = try adapter.loadAchievements()
            #expect(releído == unlocks)
        }
    }
}
