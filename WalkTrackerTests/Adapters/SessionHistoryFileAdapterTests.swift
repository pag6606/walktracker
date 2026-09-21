import Domain
import Foundation
import Testing

@testable import WalkTracker

/// `sessions.json` en el borde (5.1, AD-9): formato ISO-8601 con `schemaVersion`, escritura
/// atómica, el fichero ilegible **apartado y no borrado**, y el del futuro **intacto**. Cada
/// test usa su propio directorio temporal.
@Suite("SessionHistoryFileAdapter · historial de caminatas")
struct SessionHistoryFileAdapterTests {

    static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    static let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func record(
        id: UUID = SessionHistoryFileAdapterTests.id,
        startedAt: Date = SessionHistoryFileAdapterTests.startedAt,
        durationS: Int = 1_800,
        strideM: Double = 0.655,
        distanceM: Double = 2_840.08,
        stepsMeasured: Int = 4_100,
        stepsEstimated: Int = 236,
        paceSecPerKm: Int? = 634,
        cadenceSpm: Double = 136.7,
        weather: WeatherSnapshot? = nil,
        quoteId: Int? = nil,
        recovered: Bool = false,
        degraded: Bool = false
    ) throws -> SessionRecord {
        try SessionRecord(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(durationS)),
            stepsMeasured: stepsMeasured,
            stepsEstimated: stepsEstimated,
            strideM: strideM,
            distanceM: distanceM,
            durationS: durationS,
            pausesS: 120,
            paceSecPerKm: paceSecPerKm,
            cadenceSpm: cadenceSpm,
            weather: weather,
            quoteId: quoteId,
            recovered: recovered,
            degraded: degraded
        )
    }

    static let weather = try! WeatherSnapshot(
        tempC: 18,
        feelsLikeC: 17.5,
        wmoCode: 61,
        humidityPct: 70,
        uvIndex: 3,
        windKmh: 12,
        capturedAt: startedAt
    )

    /// Un directorio temporal propio, que se borra al terminar.
    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SessionHistoryFileAdapterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    /// Nombres de los historiales apartados (`sessions.corrupt.<marca>.json`).
    static func setAsideNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter {
            $0.hasPrefix(SessionHistoryFileAdapter.setAsideFilePrefix)
                && $0.hasSuffix(SessionHistoryFileAdapter.setAsideFileExtension)
        }.sorted()
    }

    private static func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Formato (puro)

    @Test("Ida y vuelta: cada caminata vuelve igual, con clima, frase y las dos marcas")
    func roundTrip() throws {
        let records = [
            try Self.record(),
            try Self.record(id: UUID(), startedAt: Self.startedAt.addingTimeInterval(86_400), paceSecPerKm: nil, weather: Self.weather, quoteId: 7, recovered: true, degraded: true),
        ]

        #expect(try SessionHistoryFileAdapter.decode(SessionHistoryFileAdapter.encode(records)) == records)
    }

    @Test("Un historial vacío es un fichero válido, no la ausencia de fichero")
    func emptyHistoryRoundTrips() throws {
        #expect(try SessionHistoryFileAdapter.decode(SessionHistoryFileAdapter.encode([])).isEmpty)
    }

    /// El contrato de datos del historial va en ISO-8601, no en los milisegundos del snapshot.
    /// Las dos serializaciones conviven en el mismo directorio y no se mezclan.
    @Test("Los instantes se escriben en ISO-8601, no en milisegundos")
    func timestampsAreISO8601() throws {
        let data = try SessionHistoryFileAdapter.encode([try Self.record(weather: Self.weather)])
        let object = try Self.json(data)
        let sessions = try #require(object["sessions"] as? [[String: Any]])
        let row = try #require(sessions.first)

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(row["startedAt"] as? String == "2027-01-15T08:00:00.000Z")
        #expect(row["endedAt"] as? String == "2027-01-15T08:30:00.000Z")
        #expect(row["startedAtMs"] == nil, "los milisegundos son del snapshot, no de este fichero")
        let weather = try #require(row["weather"] as? [String: Any])
        #expect(weather["capturedAt"] as? String == "2027-01-15T08:00:00.000Z")
    }

    @Test("Medidos y estimados van siempre desglosados, nunca sumados")
    func stepsAreAlwaysBrokenDown() throws {
        let object = try Self.json(try SessionHistoryFileAdapter.encode([try Self.record()]))
        let row = try #require((object["sessions"] as? [[String: Any]])?.first)

        #expect(row["stepsMeasured"] as? Int == 4_100)
        #expect(row["stepsEstimated"] as? Int == 236)
        #expect(row["steps"] == nil)
    }

    /// Una magnitud ausente se representa como ausente, nunca como `0` (AD-22).
    @Test("El ritmo ausente no se escribe como 0")
    func absentPaceIsAbsent() throws {
        let object = try Self.json(try SessionHistoryFileAdapter.encode([try Self.record(paceSecPerKm: nil)]))
        let row = try #require((object["sessions"] as? [[String: Any]])?.first)

        #expect(row["paceSecPerKm"] == nil)
        let ida = try SessionHistoryFileAdapter.decode(SessionHistoryFileAdapter.encode([try Self.record(paceSecPerKm: nil)]))
        #expect(ida.first?.paceSecPerKm == nil)
    }

    @Test("Un instante sin fracción de segundo también se lee")
    func wholeSecondTimestampsAreAccepted() throws {
        let json = #"""
        { "schemaVersion": 1, "sessions": [{
            "id": "11111111-2222-3333-4444-555555555555",
            "startedAt": "2027-01-15T08:00:00Z", "endedAt": "2027-01-15T08:30:00Z",
            "stepsMeasured": 10, "stepsEstimated": 0, "strideM": 0.655, "distanceM": 6.55,
            "durationS": 1800, "pausesS": 0, "cadenceSpm": 0.3, "source": "ios" }] }
        """#

        let records = try SessionHistoryFileAdapter.decode(Data(json.utf8))

        #expect(records.first?.startedAt == Self.startedAt)
        #expect(records.first?.endedAt == Self.startedAt.addingTimeInterval(1_800))
    }

    /// Añadir una columna no obliga a subir la versión: un fichero escrito antes de que existiera
    /// se sigue leyendo con su valor por omisión.
    @Test("`recovered` y `degraded` ausentes se leen como falsos, sin apartar nada")
    func missingMarksDefaultToFalse() throws {
        let json = #"""
        { "schemaVersion": 1, "sessions": [{
            "id": "11111111-2222-3333-4444-555555555555",
            "startedAt": "2027-01-15T08:00:00.000Z", "endedAt": "2027-01-15T08:30:00.000Z",
            "stepsMeasured": 10, "stepsEstimated": 0, "strideM": 0.655, "distanceM": 6.55,
            "durationS": 1800, "pausesS": 0, "cadenceSpm": 0.3, "source": "ios" }] }
        """#

        let record = try #require(try SessionHistoryFileAdapter.decode(Data(json.utf8)).first)

        #expect(!record.recovered)
        #expect(!record.degraded)
    }

    @Test("Lo que no es JSON, o no tiene la forma del esquema, es `malformed`", arguments: [
        "",
        "no soy json",
        "{}",
        #"{ "schemaVersion": "uno", "sessions": [] }"#,
        #"{ "schemaVersion": 1 }"#,
        #"{ "schemaVersion": 1, "sessions": {} }"#,
        #"{ "schemaVersion": 1, "sessions": [{ "id": "x" }] }"#,
    ])
    func malformedFiles(json: String) {
        #expect(throws: (any Error).self) { try SessionHistoryFileAdapter.decode(Data(json.utf8)) }
    }

    @Test("Un `id`, un instante o una `source` que no se pueden interpretar son `malformed`", arguments: [
        (#""id": "no-soy-un-uuid""#, #""startedAt": "2027-01-15T08:00:00.000Z""#, #""source": "ios""#),
        (#""id": "11111111-2222-3333-4444-555555555555""#, #""startedAt": "ayer por la tarde""#, #""source": "ios""#),
        (#""id": "11111111-2222-3333-4444-555555555555""#, #""startedAt": "2027-01-15T08:00:00.000Z""#, #""source": "android""#),
    ])
    func uninterpretableFieldsAreMalformed(id: String, startedAt: String, source: String) {
        let json = #"""
        { "schemaVersion": 1, "sessions": [{
            \#(id), \#(startedAt), "endedAt": "2027-01-15T08:30:00.000Z",
            "stepsMeasured": 10, "stepsEstimated": 0, "strideM": 0.655, "distanceM": 6.55,
            "durationS": 1800, "pausesS": 0, "cadenceSpm": 0.3, \#(source) }] }
        """#

        #expect(throws: (any Error).self) { try SessionHistoryFileAdapter.decode(Data(json.utf8)) }
    }

    /// **La fila mala no se salta en silencio.** Un historial al que le falta una caminata sin
    /// que nada lo diga es peor que uno apartado entero: apartarlo conserva el fichero y avisa.
    @Test("Una fila que el dominio rechaza hace ilegible el fichero, no se salta")
    func rowRejectedByTheDomainMakesTheFileMalformed() {
        let json = #"""
        { "schemaVersion": 1, "sessions": [{
            "id": "11111111-2222-3333-4444-555555555555",
            "startedAt": "2027-01-15T08:00:00.000Z", "endedAt": "2027-01-15T08:30:00.000Z",
            "stepsMeasured": -10, "stepsEstimated": 0, "strideM": 0.655, "distanceM": 6.55,
            "durationS": 1800, "pausesS": 0, "cadenceSpm": 0.3, "source": "ios" }] }
        """#

        #expect(throws: StorageError.self) { try SessionHistoryFileAdapter.decode(Data(json.utf8)) }
    }

    /// La excepción, la misma que en el snapshot: la falta de clima no bloquea nada (AD-11).
    @Test("Un clima con la forma bien y los rangos mal se lee como sin clima, sin tirar la caminata")
    func outOfRangeWeatherReadsAsNoWeather() throws {
        let json = #"""
        { "schemaVersion": 1, "sessions": [{
            "id": "11111111-2222-3333-4444-555555555555",
            "startedAt": "2027-01-15T08:00:00.000Z", "endedAt": "2027-01-15T08:30:00.000Z",
            "stepsMeasured": 10, "stepsEstimated": 0, "strideM": 0.655, "distanceM": 6.55,
            "durationS": 1800, "pausesS": 0, "cadenceSpm": 0.3, "source": "ios",
            "weather": { "tempC": 18, "feelsLikeC": 17.5, "wmoCode": 999, "humidityPct": 70,
                         "uvIndex": 3, "windKmh": 12, "capturedAt": "2027-01-15T08:00:00.000Z" } }] }
        """#

        let record = try #require(try SessionHistoryFileAdapter.decode(Data(json.utf8)).first)

        #expect(record.weather == nil)
        #expect(record.stepsMeasured == 10, "la caminata sigue entera")
    }

    @Test("Una versión fuera de rango lanza `unsupportedSchemaVersion`", arguments: [0, 2, 99])
    func unsupportedVersions(version: Int) {
        let json = #"{ "schemaVersion": \#(version), "sessions": [] }"#

        #expect(throws: StorageError.unsupportedSchemaVersion(version)) {
            try SessionHistoryFileAdapter.decode(Data(json.utf8))
        }
    }

    // MARK: - Disco

    @Test("Sin fichero, el historial es `nil` y no se crea nada")
    func absentFileReadsAsNil() throws {
        try Self.withDirectory { directory in
            let adapter = SessionHistoryFileAdapter(directory: directory)

            let cargado = try adapter.loadSessions()
            #expect(cargado == nil)
            #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
        }
    }

    @Test("Lo guardado se relee igual, y el fichero se llama `sessions.json`")
    func savedHistoryIsReadBack() throws {
        try Self.withDirectory { directory in
            let adapter = SessionHistoryFileAdapter(directory: directory)
            let records = [try Self.record(), try Self.record(id: UUID(), startedAt: Self.startedAt.addingTimeInterval(3_600))]

            try adapter.saveSessions(records)

            #expect(adapter.fileURL.lastPathComponent == "sessions.json")
            let releído = try adapter.loadSessions()
            #expect(releído == records)
        }
    }

    /// La regla heredada que no se afloja: **se aparta, no se destruye**.
    @Test("Un historial ilegible se aparta con nombre único y la lectura lanza")
    func unreadableHistoryIsSetAside() throws {
        try Self.withDirectory { directory in
            let adapter = SessionHistoryFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data("no soy json".utf8)
            try bytes.write(to: adapter.fileURL)

            #expect(throws: (any Error).self) { try adapter.loadSessions() }

            #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
            let apartados = try Self.setAsideNames(in: directory)
            #expect(apartados.count == 1)
            let apartado = directory.appending(path: try #require(apartados.first), directoryHint: .notDirectory)
            #expect(try Data(contentsOf: apartado) == bytes, "el contenido se conserva entero")
        }
    }

    /// La divergencia declarada con `ActiveSessionFileAdapter`: aquí se sigue el molde de
    /// `SettingsFileAdapter` —interceptar el esquema del futuro **antes** del `catch` que
    /// aparta— porque un historial apartado por instalar un build anterior no se rehace.
    @Test("Un historial de un esquema del futuro se deja INTACTO y la lectura lanza")
    func futureSchemaIsLeftUntouched() throws {
        try Self.withDirectory { directory in
            let adapter = SessionHistoryFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = Data(#"{ "schemaVersion": 99, "sessions": [] }"#.utf8)
            try bytes.write(to: adapter.fileURL)

            #expect(throws: StorageError.unsupportedSchemaVersion(99)) { try adapter.loadSessions() }

            #expect(try Data(contentsOf: adapter.fileURL) == bytes, "sigue donde estaba, byte a byte")
            #expect(try Self.setAsideNames(in: directory).isEmpty)
        }
    }

    @Test("Guardar sustituye el fichero entero de una vez")
    func savingReplacesTheWholeFile() throws {
        try Self.withDirectory { directory in
            let adapter = SessionHistoryFileAdapter(directory: directory)
            try adapter.saveSessions([try Self.record()])
            let segundo = try Self.record(id: UUID(), startedAt: Self.startedAt.addingTimeInterval(3_600))

            try adapter.saveSessions([try Self.record(), segundo])

            let releído = try adapter.loadSessions()
            #expect(releído?.count == 2)
            let temporales = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
                .filter { $0.hasSuffix(".tmp") }
            #expect(temporales.isEmpty, "el temporal de la escritura atómica no se queda")
        }
    }

    /// El aviso de la spec: el store de desbloqueos y el catálogo se llaman igual. Aquí se
    /// comprueba que los **cuatro** ficheros del puerto conviven en el mismo directorio sin
    /// pisarse, que es el riesgo real del nombre repetido.
    @Test("Los cuatro ficheros del puerto conviven en el mismo directorio sin pisarse")
    func theFourFilesCoexist() throws {
        try Self.withDirectory { directory in
            let storage = FileStorageAdapter(directory: directory)
            let record = try Self.record()

            try storage.saveSessions([record])
            try storage.saveAchievements([try AchievementUnlock(key: "first_walk", unlockedAt: Self.startedAt, progress: 1)])
            try storage.saveSettings(AppSettings(recentQuoteIds: [1, 2, 3]))

            let nombres = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
            #expect(nombres == ["sessions.json", "achievements.json", "settings.json"])
            let historial = try storage.loadSessions()
            let logros = try storage.loadAchievements()
            let ajustes = try storage.loadSettings()
            #expect(historial == [record])
            #expect(logros?.first?.key == "first_walk")
            #expect(ajustes?.recentQuoteIds == [1, 2, 3])
        }
    }
}
