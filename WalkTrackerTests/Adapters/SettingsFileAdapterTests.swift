import Domain
import Foundation
import Testing

@testable import WalkTracker

/// `settings.json` en el borde (2.2, AD-9): formato con `schemaVersion`, escritura atómica y
/// el fichero ilegible apartado, nunca borrado. Cada test usa su propio directorio temporal.
@Suite("SettingsFileAdapter · ajustes persistentes")
struct SettingsFileAdapterTests {

    /// Un directorio temporal propio, que se borra al terminar.
    private static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SettingsFileAdapterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    /// Nombres de los ajustes apartados (`settings.corrupt.<marca>.json`), en orden alfabético.
    private static func setAsideNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter {
            $0.hasPrefix(SettingsFileAdapter.setAsideFilePrefix) && $0.hasSuffix(SettingsFileAdapter.setAsideFileExtension)
        }.sorted()
    }

    private static func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Formato (puro)

    @Test("Ida y vuelta: los ajustes vuelven iguales")
    func roundTrip() throws {
        for settings in [AppSettings.defaults, AppSettings(recentQuoteIds: [3, 1, 4, 1, 5])] {
            #expect(try SettingsFileAdapter.decode(SettingsFileAdapter.encode(settings)) == settings)
        }
    }

    @Test("El fichero lleva schemaVersion 1 y la ventana de recientes")
    func encodesSchema() throws {
        let object = try Self.json(SettingsFileAdapter.encode(AppSettings(recentQuoteIds: [7, 8])))

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["recentQuoteIds"] as? [Int] == [7, 8])
    }

    @Test("recentQuoteIds ausente o null: la ventana vacía, sin apartar nada", arguments: [
        #"{ "schemaVersion": 1 }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": null }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": [] }"#,
    ])
    func missingWindow(json: String) throws {
        #expect(try SettingsFileAdapter.decode(Data(json.utf8)) == .defaults)
    }

    @Test("Una ventana más larga de lo debido se sanea al leer, quedándose con las últimas 20")
    func overlongWindowIsTrimmedOnRead() throws {
        let ids = (1...50).map(String.init).joined(separator: ",")
        let json = #"{ "schemaVersion": 1, "recentQuoteIds": [\#(ids)] }"#

        let settings = try SettingsFileAdapter.decode(Data(json.utf8))

        #expect(settings.recentQuoteIds == Array(31...50), "las últimas 20, la misma regla que updateRecentIds")
    }

    @Test("Y también al escribir: el fichero nunca guarda más de 20")
    func overlongWindowIsTrimmedOnWrite() throws {
        let object = try Self.json(SettingsFileAdapter.encode(AppSettings(recentQuoteIds: Array(1...50))))

        #expect(object["recentQuoteIds"] as? [Int] == Array(31...50))
    }

    @Test("Una ventana con ids repetidos se deduplica al leer, quedándose con la aparición más reciente")
    func repeatedIdsAreDeduplicatedOnRead() throws {
        // El hueco que los topes no cierran: 20 ids repetidos pasan todos los guardias y
        // dejan la exclusión real en UNA frase, sin que el motor dispare `ignoredRecentWindow`.
        let repeated = Array(repeating: "5", count: 20).joined(separator: ",")
        let json = #"{ "schemaVersion": 1, "recentQuoteIds": [\#(repeated)] }"#

        #expect(try SettingsFileAdapter.decode(Data(json.utf8)).recentQuoteIds == [5])

        let mixed = #"{ "schemaVersion": 1, "recentQuoteIds": [3, 1, 4, 1, 5] }"#
        #expect(
            try SettingsFileAdapter.decode(Data(mixed.utf8)).recentQuoteIds == [3, 4, 1, 5],
            "se conserva el orden y gana la aparición más reciente de cada id"
        )
    }

    @Test("Un campo que el esquema todavía no conoce no rompe: el Epic 3 añadirá la meta semanal")
    func unknownFieldsAreIgnored() throws {
        let json = #"{ "schemaVersion": 1, "recentQuoteIds": [1], "strideM": 0.7, "weeklyGoalKm": 10 }"#

        let settings = try SettingsFileAdapter.decode(Data(json.utf8))

        #expect(settings.recentQuoteIds == [1])
        #expect(settings.strideM == 0.7, "y el que sí conoce desde la 2.3 se lee")
    }

    // MARK: - Zancada (2.3)

    @Test("Ida y vuelta con zancada: vuelve igual y el esquema NO sube de 1")
    func strideRoundTrip() throws {
        var settings = AppSettings(recentQuoteIds: [4, 5])
        try settings.setStrideM(0.670)

        let data = try SettingsFileAdapter.encode(settings)
        let object = try Self.json(data)

        #expect(object["strideM"] as? Double == 0.670)
        #expect(
            object["schemaVersion"] as? Int == 1,
            "un campo opcional nuevo es compatible en las dos direcciones: subirlo a 2 dejaría a un build de la 2.2 leyendo los ajustes como del futuro y perdiendo la ventana"
        )
        #expect(try SettingsFileAdapter.decode(data) == settings)
    }

    @Test("Sin configurar, la clave no se escribe")
    func absentStrideIsNotWritten() throws {
        let object = try Self.json(SettingsFileAdapter.encode(AppSettings(recentQuoteIds: [1])))

        #expect(object["strideM"] == nil)
    }

    @Test("Un fichero de la 2.2 (esquema 1, sin el campo) se lee bien y admite la zancada")
    func fileFromPreviousStoryStillReads() throws {
        let json = #"{ "schemaVersion": 1, "recentQuoteIds": [1, 2, 3] }"#

        var settings = try SettingsFileAdapter.decode(Data(json.utf8))

        #expect(settings.recentQuoteIds == [1, 2, 3])
        #expect(settings.strideM == nil, "sin configurar, no 0,655: el default vive en formulas.json")

        try settings.setStrideM(0.670)
        let object = try Self.json(SettingsFileAdapter.encode(settings))
        #expect(object["strideM"] as? Double == 0.670)
        #expect(object["recentQuoteIds"] as? [Int] == [1, 2, 3])
    }

    @Test("Una zancada corrupta se lee como sin configurar y NO cuesta la ventana de frases", arguments: [
        #"{ "schemaVersion": 1, "recentQuoteIds": [1, 2], "strideM": "abc" }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": [1, 2], "strideM": -1 }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": [1, 2], "strideM": 0 }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": [1, 2], "strideM": null }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": [1, 2], "strideM": [0.7] }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": [1, 2], "strideM": true }"#,
    ])
    func corruptStrideFallsBackToUnset(json: String) throws {
        // La puerta de lectura es TOLERANTE, a diferencia de la de escritura: un `strideM`
        // ilegible no puede apartar el fichero entero ni perder `recentQuoteIds`.
        let settings = try SettingsFileAdapter.decode(Data(json.utf8))

        #expect(settings.strideM == nil)
        #expect(settings.recentQuoteIds == [1, 2])
    }

    @Test("Unos ajustes con la zancada corrupta en disco se leen enteros y no se apartan")
    func corruptStrideOnDiskIsNotSetAside() throws {
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let json = #"{ "schemaVersion": 1, "recentQuoteIds": [9], "strideM": "abc" }"#
            try Data(json.utf8).write(to: adapter.fileURL)

            let settings = try adapter.loadSettings()

            #expect(settings?.strideM == nil)
            #expect(settings?.recentQuoteIds == [9])
            #expect(try Self.setAsideNames(in: directory).isEmpty, "no es un fichero ilegible: no se aparta")
            #expect(FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
        }
    }

    @Test("schemaVersion desconocido: unsupportedSchemaVersion", arguments: [0, 2, 9])
    func unknownSchemaVersion(version: Int) {
        let json = #"{ "schemaVersion": \#(version) }"#
        #expect(throws: StorageError.unsupportedSchemaVersion(version)) {
            try SettingsFileAdapter.decode(Data(json.utf8))
        }
    }

    @Test("JSON roto, sin versión o con un campo de otro tipo: malformed", arguments: [
        "",
        "{ ",
        "[]",
        #"{ "recentQuoteIds": [1] }"#,
        #"{ "schemaVersion": "1" }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": "1,2" }"#,
        #"{ "schemaVersion": 1, "recentQuoteIds": [1.5] }"#,
    ])
    func malformed(json: String) {
        #expect {
            try SettingsFileAdapter.decode(Data(json.utf8))
        } throws: { error in
            guard case StorageError.malformed = error else { return false }
            return true
        }
    }

    // MARK: - Disco

    @Test("Sin fichero: nil, y no se crea nada")
    func missingFile() throws {
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)

            let loaded = try adapter.loadSettings()
            let setAside = try Self.setAsideNames(in: directory)
            #expect(loaded == nil)
            #expect(setAside.isEmpty)
        }
    }

    @Test("Guardar y leer: los ajustes vuelven, y el directorio se crea si no existía")
    func saveAndLoad() throws {
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory.appending(path: "Nested", directoryHint: .isDirectory))
            let settings = AppSettings(recentQuoteIds: [11, 12, 13])

            try adapter.saveSettings(settings)

            #expect(try adapter.loadSettings() == settings)
        }
    }

    @Test("Guardar sustituye de una vez y no deja temporales al lado")
    func saveIsAtomic() throws {
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)
            try adapter.saveSettings(AppSettings(recentQuoteIds: [1]))

            try adapter.saveSettings(AppSettings(recentQuoteIds: [2]))

            #expect(try adapter.loadSettings()?.recentQuoteIds == [2])
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
            #expect(files == [SettingsFileAdapter.fileName], "ningún temporal de la escritura queda al lado")
        }
    }

    @Test("Ilegible: se aparta —no se borra— y la lectura lanza")
    func corruptIsSetAside() throws {
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let broken = Data(#"{ "schemaVersion": 1, "recentQuoteIds": "ay" }"#.utf8)
            try broken.write(to: adapter.fileURL)

            #expect(throws: StorageError.self) { try adapter.loadSettings() }

            let names = try Self.setAsideNames(in: directory)
            #expect(names.count == 1)
            #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
            let apartado = directory.appending(path: names[0], directoryHint: .notDirectory)
            #expect(try Data(contentsOf: apartado) == broken, "el contenido se conserva entero")
        }
    }

    @Test("De un esquema MÁS NUEVO: valores por omisión, y el fichero se queda donde está", arguments: [2, 9])
    func newerSchemaIsLeftAlone(version: Int) throws {
        // Alguien instala un build anterior. Apartar el fichero le costaría la ventana —y la
        // zancada de la 2.3— en cuanto volviera a la versión nueva: un fichero del futuro no
        // es un fichero corrupto.
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let future = Data(#"{ "schemaVersion": \#(version), "recentQuoteIds": [1, 2], "strideM": 0.7 }"#.utf8)
            try future.write(to: adapter.fileURL)

            #expect(try adapter.loadSettings() == .defaults, "no se adivina la ventana de un esquema que no se entiende")
            #expect(try Self.setAsideNames(in: directory).isEmpty, "y no se aparta nada")
            #expect(try Data(contentsOf: adapter.fileURL) == future, "el fichero sigue entero en su sitio")
        }
    }

    @Test("De un esquema ANTERIOR desconocido sí se aparta: ahí no hay nada que recuperar")
    func olderUnknownSchemaIsSetAside() throws {
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(#"{ "schemaVersion": 0 }"#.utf8).write(to: adapter.fileURL)

            #expect(throws: StorageError.unsupportedSchemaVersion(0)) { try adapter.loadSettings() }

            #expect(try Self.setAsideNames(in: directory).count == 1)
            #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
        }
    }

    @Test("Dos apartados seguidos: el primero no se destruye")
    func twoSetAsideKeepBoth() throws {
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            for json in [#"{ "schemaVersion": 0 }"#, #"{ "schemaVersion": 1, "recentQuoteIds": "ay" }"#] {
                try Data(json.utf8).write(to: adapter.fileURL)
                #expect(throws: StorageError.self) { try adapter.loadSettings() }
            }

            #expect(try Self.setAsideNames(in: directory).count == 2)
        }
    }

    @Test("Los nombres que anuncian los estáticos son los que el adapter escribe de verdad")
    func staticNamesMatchTheFileOnDisk() throws {
        // Dos fuentes de verdad serían una trampa: cambiar el `base:` del `JSONFileStore`
        // dejaría estos tests verdes contra un nombre que ya no existe en disco.
        try Self.withDirectory { directory in
            let adapter = SettingsFileAdapter(directory: directory)
            try adapter.saveSettings(.defaults)

            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            #expect(files == [SettingsFileAdapter.fileName])
            #expect(adapter.fileURL.lastPathComponent == SettingsFileAdapter.fileName)
            #expect(SettingsFileAdapter.setAsideFilePrefix.hasPrefix("settings."))
            #expect(SettingsFileAdapter.fileName.hasSuffix(SettingsFileAdapter.setAsideFileExtension))
        }
    }

    // MARK: - El puerto completo

    @Test("FileStorageAdapter reparte: el snapshot y los ajustes son dos ficheros distintos")
    func portRoutesToTwoFiles() throws {
        try Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            let settings = AppSettings(recentQuoteIds: [5])
            let snapshot = ActiveSessionSnapshot(
                startedAt: Date(timeIntervalSince1970: 1_800_000_000), stepsMeasured: 10, stepsEstimated: 0,
                totalPausesS: 0, paused: false, pausedAt: nil, strideM: 0.655, systemDistanceM: nil,
                savedAt: Date(timeIntervalSince1970: 1_800_000_060), lastSampleAt: nil,
                segmentStart: Date(timeIntervalSince1970: 1_800_000_000), segmentSteps: 10,
                distanceBaseM: 0, quoteId: 5
            )

            try storage.saveSettings(settings)
            try storage.saveActiveSession(snapshot)

            #expect(try storage.loadSettings() == settings)
            #expect(try storage.loadActiveSession() == snapshot)

            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
            #expect(files == [ActiveSessionFileAdapter.fileName, SettingsFileAdapter.fileName])

            // Borrar el snapshot no toca los ajustes: son dueños distintos.
            try storage.clearActiveSession()
            #expect(try storage.loadActiveSession() == nil)
            #expect(try storage.loadSettings() == settings)
        }
    }
}

/// `SettingsStore` sobre su puerto (AD-16): la lectura única del arranque y la ventana.
@MainActor
@Suite("SettingsStore · dueño de settings.json")
struct SettingsStoreTests {

    @Test("Sin fichero: se parte de los ajustes por omisión")
    func defaultsWhenMissing() {
        let store = SettingsStore(storage: StorageStub())

        #expect(store.settings == .defaults)
        #expect(store.recentQuoteIds.isEmpty)
    }

    @Test("Con fichero: se lee una sola vez, al construirlo")
    func readsOnceOnInit() {
        let storage = StorageStub(settings: AppSettings(recentQuoteIds: [4, 5]))

        let store = SettingsStore(storage: storage)

        #expect(store.recentQuoteIds == [4, 5])
        #expect(storage.settingsLoadCount == 1)
        _ = store.recentQuoteIds
        #expect(storage.settingsLoadCount == 1, "leer la ventana no vuelve al disco")
    }

    @Test("Ilegible: se parte de los por omisión y el adapter ya lo apartó")
    func corruptFallsBackToDefaults() {
        let storage = StorageStub(settings: AppSettings(recentQuoteIds: [1]))
        storage.failLoadSettings(with: .malformed("basura"))

        let store = SettingsStore(storage: storage)

        #expect(store.settings == .defaults)
        #expect(storage.settingsSetAside.count == 1)
    }

    @Test("No se puede leer (failed): se parte de los por omisión y el fichero sigue en su sitio")
    func unreadableKeepsTheFile() {
        let storage = StorageStub(settings: AppSettings(recentQuoteIds: [1]))
        storage.failLoadSettings(with: .failed(operation: "read"))

        let store = SettingsStore(storage: storage)

        #expect(store.settings == .defaults)
        #expect(storage.settingsSetAside.isEmpty)
        #expect(storage.settings != nil, "no se destruye lo que no se pudo leer")
    }

    @Test("recordShownQuote: FIFO con tope de 20, y cada vez se guarda")
    func recordShownQuoteAppendsAndSaves() {
        let storage = StorageStub()
        let store = SettingsStore(storage: storage)

        for id in 1...25 {
            store.recordShownQuote(id: id)
        }

        #expect(store.recentQuoteIds == Array(6...25))
        #expect(storage.settingsSaved.count == 25)
        #expect(storage.settings?.recentQuoteIds == Array(6...25))
    }

    @Test("Un fallo al guardar no se propaga y la ventana en memoria avanza igual")
    func saveFailureDoesNotPropagate() {
        let storage = StorageStub()
        storage.failSaveSettings(with: .failed(operation: "write"))
        let store = SettingsStore(storage: storage)

        store.recordShownQuote(id: 7)

        #expect(store.recentQuoteIds == [7])
        #expect(storage.settings == nil)
    }
}
