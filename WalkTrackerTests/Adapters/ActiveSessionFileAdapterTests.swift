import Domain
import Foundation
import Testing

@testable import WalkTracker

/// `activeSession.json` en el borde (AD-9): formato en milisegundos con `schemaVersion`,
/// escritura atómica y el fichero ilegible apartado, nunca borrado. Cada test usa su propio
/// directorio temporal.
@Suite("ActiveSessionFileAdapter · snapshot de la sesión viva")
struct ActiveSessionFileAdapterTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func snapshot(
        stepsMeasured: Int = 1500,
        paused: Bool = false,
        pausedAt: Date? = nil,
        systemDistanceM: Double? = 980.25,
        lastSampleAt: Date? = t0.addingTimeInterval(1_190.5),
        weather: WeatherSnapshot? = nil,
        quoteId: Int? = nil
    ) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            startedAt: t0,
            stepsMeasured: stepsMeasured,
            stepsEstimated: 320,
            totalPausesS: 60.25,
            paused: paused,
            pausedAt: pausedAt,
            strideM: 0.655,
            systemDistanceM: systemDistanceM,
            savedAt: t0.addingTimeInterval(1_200),
            lastSampleAt: lastSampleAt,
            segmentStart: t0.addingTimeInterval(300),
            segmentSteps: 900,
            distanceBaseM: 400.5,
            weather: weather,
            quoteId: quoteId
        )
    }

    private static let weather = try! WeatherSnapshot(
        tempC: 18.2, feelsLikeC: 17.4, wmoCode: 61, humidityPct: 82, uvIndex: 1.55, windKmh: 12.4,
        capturedAt: t0.addingTimeInterval(2.5)
    )

    /// Un directorio temporal propio, que se borra al terminar.
    private static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ActiveSessionFileAdapterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    /// Nombres de los snapshots apartados en `directory` (`activeSession.corrupt.<marca>.json`),
    /// en orden alfabético.
    private static func setAsideNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).filter {
            $0.hasPrefix(ActiveSessionFileAdapter.setAsideFilePrefix) && $0.hasSuffix(ActiveSessionFileAdapter.setAsideFileExtension)
        }.sorted()
    }

    /// El contenido de cada snapshot apartado en `directory`, uno por fichero y en el orden de
    /// `setAsideNames(in:)`: dos ficheros iguales cuentan dos veces.
    private static func setAsideContents(in directory: URL) throws -> [Data] {
        try setAsideNames(in: directory).map { try Data(contentsOf: directory.appending(path: $0, directoryHint: .notDirectory)) }
    }

    /// Milisegundos de la marca de un apartado (`activeSession.corrupt.<ms>-<sufijo>.json`),
    /// o `nil` si el nombre no tiene esa forma.
    private static func setAsideMs(_ name: String) -> Int64? {
        guard let match = name.wholeMatch(of: /activeSession\.corrupt\.(\d{13})-([0-9a-f]{8})\.json/) else { return nil }
        return Int64(match.output.1)
    }

    /// Dos apartados seguidos, `first` antes que `second`: hay exactamente dos ficheros, con
    /// nombres únicos y bien formados, cada uno con su contenido, y la marca del primero no es
    /// posterior a la del segundo. El snapshot ya no está en su sitio.
    private static func expectTwoSetAside(first: Data, second: Data, in adapter: ActiveSessionFileAdapter) throws {
        let names = try setAsideNames(in: adapter.directory)
        let contents = try setAsideContents(in: adapter.directory)
        #expect(names.count == 2)
        #expect(Set(names).count == 2, "nombres únicos")
        #expect(contents.count == 2)
        #expect(contents.filter { $0 == first }.count == 1, "el primero sigue apartado")
        #expect(contents.filter { $0 == second }.count == 1)
        #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
        let firstMs = try #require(zip(names, contents).first { $0.1 == first }.flatMap { setAsideMs($0.0) })
        let secondMs = try #require(zip(names, contents).first { $0.1 == second }.flatMap { setAsideMs($0.0) })
        #expect(firstMs <= secondMs, "la marca ordena los apartados por tiempo")
    }

    private static func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Formato (puro)

    @Test("Ida y vuelta s ↔ ms: el snapshot vuelve igual")
    func roundTrip() throws {
        for snapshot in [
            Self.snapshot(),
            Self.snapshot(paused: true, pausedAt: Self.t0.addingTimeInterval(1_195), systemDistanceM: nil, lastSampleAt: nil),
            Self.snapshot(weather: Self.weather),
            Self.snapshot(quoteId: 42),
            Self.snapshot(weather: Self.weather, quoteId: 42),
        ] {
            let decoded = try ActiveSessionFileAdapter.decode(ActiveSessionFileAdapter.encode(snapshot))
            #expect(decoded == snapshot)
        }
    }

    @Test("El fichero va en milisegundos enteros, con schemaVersion 3 y los campos de §8")
    func encodesMilliseconds() throws {
        let object = try Self.json(ActiveSessionFileAdapter.encode(Self.snapshot()))

        #expect(object["schemaVersion"] as? Int == 3)
        #expect(object["startedAtMs"] as? Int64 == 1_800_000_000_000)
        #expect(object["totalPausesMs"] as? Int64 == 60_250)
        #expect(object["savedAtMs"] as? Int64 == 1_800_001_200_000)
        #expect(object["lastSampleAtMs"] as? Int64 == 1_800_001_190_500)
        #expect(object["segmentStartMs"] as? Int64 == 1_800_000_300_000)
        #expect(object["stepsMeasured"] as? Int == 1500)
        #expect(object["stepsEstimated"] as? Int == 320)
        #expect(object["paused"] as? Bool == false)
        #expect(object["strideM"] as? Double == 0.655)
        #expect(object["segmentSteps"] as? Int == 900)
        #expect(object["distanceBaseM"] as? Double == 400.5)
        #expect(object["startedAt"] == nil && object["totalPausesS"] == nil, "el fichero nunca lleva segundos")
        #expect(object["weather"] == nil, "sin clima, no hay clave")
        #expect(object["quoteId"] == nil, "sin frase, no hay clave")
    }

    @Test("El clima va en el fichero con capturedAtMs y sin condition, que sale del código WMO")
    func encodesWeather() throws {
        let object = try Self.json(ActiveSessionFileAdapter.encode(Self.snapshot(weather: Self.weather)))
        let weather = try #require(object["weather"] as? [String: Any])

        #expect(weather["tempC"] as? Double == 18.2)
        #expect(weather["feelsLikeC"] as? Double == 17.4)
        #expect(weather["wmoCode"] as? Int == 61)
        #expect(weather["humidityPct"] as? Double == 82)
        #expect(weather["uvIndex"] as? Double == 1.55)
        #expect(weather["windKmh"] as? Double == 12.4)
        #expect(weather["capturedAtMs"] as? Int64 == 1_800_000_002_500)
        #expect(weather["condition"] == nil)
    }

    @Test("Snapshot antiguo: el esquema 1 sin weather se lee sin clima, sin apartarlo")
    func readsSchemaVersion1() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let json = #"{ "schemaVersion": 1, "startedAtMs": 1800000000000, "stepsMeasured": 2450, "strideM": 0.655, "savedAtMs": 1800000001000, "segmentStartMs": 1800000000000, "segmentSteps": 2450, "distanceBaseM": 0 }"#
            try Data(json.utf8).write(to: adapter.fileURL)

            let snapshot = try #require(try adapter.loadActiveSession())

            #expect(snapshot.weather == nil)
            #expect(snapshot.stepsMeasured == 2450)
            #expect(try Self.setAsideNames(in: directory).isEmpty)
            #expect(FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
        }
    }

    @Test("Esquema 2: weather ausente o null se lee sin clima")
    func schema2WithoutWeather() throws {
        for weather in ["", #", "weather": null"#] {
            let json = #"{ "schemaVersion": 2, "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0"# + weather + " }"
            #expect(try ActiveSessionFileAdapter.decode(Data(json.utf8)).weather == nil)
        }
    }

    @Test("Esquema 2: un clima con la forma rota es malformed; con los rangos rotos se lee sin clima y la sesión sigue")
    func schema2InvalidWeather() throws {
        let base = #"{ "schemaVersion": 2, "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0, "weather": "#
        let brokenShape = base + #"{ "tempC": 18, "wmoCode": 61 } }"#
        #expect(throws: StorageError.self) {
            try ActiveSessionFileAdapter.decode(Data(brokenShape.utf8))
        }
        let brokenRange = base + #"{ "tempC": 18, "feelsLikeC": 17, "wmoCode": 61, "humidityPct": 140, "uvIndex": 1, "windKmh": 3, "capturedAtMs": 0 } }"#
        let snapshot = try ActiveSessionFileAdapter.decode(Data(brokenRange.utf8))
        #expect(snapshot.weather == nil)
        #expect(snapshot.strideM == 0.655)
    }

    @Test("El quoteId va en el fichero, y un esquema 2 se lee sin frase, sin apartarlo")
    func quoteIdIsSchema3() throws {
        let object = try Self.json(ActiveSessionFileAdapter.encode(Self.snapshot(quoteId: 42)))
        #expect(object["quoteId"] as? Int == 42)

        // Esquema 2: el campo no existía. Un snapshot de la 2.1 se lee sin frase.
        let schema2 = #"{ "schemaVersion": 2, "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0, "quoteId": 42 }"#
        #expect(try ActiveSessionFileAdapter.decode(Data(schema2.utf8)).quoteId == nil, "el campo de la 3 no se lee de un fichero de la 2")
    }

    @Test("Esquema 3: quoteId ausente o null se lee sin frase")
    func schema3WithoutQuote() throws {
        for quote in ["", #", "quoteId": null"#] {
            let json = #"{ "schemaVersion": 3, "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0"# + quote + " }"
            #expect(try ActiveSessionFileAdapter.decode(Data(json.utf8)).quoteId == nil)
        }
    }

    @Test("Esquema 3: un quoteId de otro tipo es malformed")
    func schema3InvalidQuote() {
        let json = #"{ "schemaVersion": 3, "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0, "quoteId": "42" }"#
        #expect(throws: StorageError.self) {
            try ActiveSessionFileAdapter.decode(Data(json.utf8))
        }
    }

    @Test("Los milisegundos se convierten a segundos al leer")
    func decodesMillisecondsToSeconds() throws {
        let json = #"""
        { "schemaVersion": 1, "startedAtMs": 1800000000000, "stepsMeasured": 2450, "stepsEstimated": 320,
          "totalPausesMs": 60000, "paused": true, "pausedAtMs": 1800000000900, "strideM": 0.655,
          "savedAtMs": 1800000001000, "segmentStartMs": 1800000000000, "segmentSteps": 2450, "distanceBaseM": 0 }
        """#
        let snapshot = try ActiveSessionFileAdapter.decode(Data(json.utf8))

        #expect(snapshot.startedAt == Self.t0)
        #expect(snapshot.totalPausesS == 60)
        #expect(abs(try #require(snapshot.pausedAt).timeIntervalSince(Self.t0) - 0.9) < 0.000_001)
        #expect(snapshot.savedAt == Self.t0.addingTimeInterval(1))
        #expect(snapshot.paused)
        #expect(snapshot.systemDistanceM == nil)
        #expect(snapshot.lastSampleAt == nil)
    }

    @Test("Como la v3: pasos, pausas y paused ausentes valen 0 y false")
    func v3DefaultsWhenAbsent() throws {
        let json = #"{ "schemaVersion": 1, "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#
        let snapshot = try ActiveSessionFileAdapter.decode(Data(json.utf8))

        #expect(snapshot.stepsMeasured == 0)
        #expect(snapshot.stepsEstimated == 0)
        #expect(snapshot.totalPausesS == 0)
        #expect(!snapshot.paused)
    }

    @Test("La forma se valida aquí y los rangos no: zancada 0 y pausada sin pausedAt pasan al dominio")
    func rangesAreNotValidatedHere() throws {
        let json = #"{ "schemaVersion": 1, "startedAtMs": 0, "strideM": 0, "paused": true, "stepsMeasured": -5, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#
        let snapshot = try ActiveSessionFileAdapter.decode(Data(json.utf8))
        #expect(snapshot.strideM == 0)
        #expect(snapshot.pausedAt == nil)
        #expect(snapshot.stepsMeasured == -5)
    }

    @Test("schemaVersion desconocido: unsupportedSchemaVersion", arguments: [0, 4])
    func unknownSchemaVersion(version: Int) {
        let json = #"{ "schemaVersion": \#(version), "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#
        #expect(throws: StorageError.unsupportedSchemaVersion(version)) {
            try ActiveSessionFileAdapter.decode(Data(json.utf8))
        }
    }

    @Test("JSON roto, sin versión, sin un campo obligatorio o con otro tipo: malformed", arguments: [
        "{ \"schemaVersion\": 1, ",
        "",
        #"{ "startedAtMs": 0, "strideM": 0.655 }"#,
        #"{ "schemaVersion": 1, "startedAtMs": 0, "strideM": 0.655, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#,
        #"{ "schemaVersion": 1, "startedAtMs": 0, "strideM": 0.655, "savedAtMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#,
        #"{ "schemaVersion": 1, "startedAtMs": "0", "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#,
        #"{ "schemaVersion": 1, "startedAtMs": 0.5, "strideM": 0.655, "savedAtMs": 0, "segmentStartMs": 0, "segmentSteps": 0, "distanceBaseM": 0 }"#,
        "[]",
    ])
    func malformed(json: String) {
        #expect {
            try ActiveSessionFileAdapter.decode(Data(json.utf8))
        } throws: { error in
            guard case StorageError.malformed = error else { return false }
            return true
        }
    }

    // MARK: - Disco

    @Test("Sin fichero: nil, y borrar o apartar no hacen nada")
    func missingFile() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            #expect(try adapter.loadActiveSession() == nil)
            try adapter.clearActiveSession()
            try adapter.setAsideActiveSession()
            #expect(try Self.setAsideNames(in: directory).isEmpty)
        }
    }

    @Test("Guardar crea el directorio, sustituye el anterior entero y no deja temporales")
    func atomicSave() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory.appending(path: "Nested", directoryHint: .isDirectory))
            let first = Self.snapshot(stepsMeasured: 100)
            let second = Self.snapshot(stepsMeasured: 200)

            try adapter.saveActiveSession(first)
            #expect(try adapter.loadActiveSession() == first)
            try adapter.saveActiveSession(second)

            #expect(try adapter.loadActiveSession() == second)
            #expect(try Data(contentsOf: adapter.fileURL) == ActiveSessionFileAdapter.encode(second))
            let files = try FileManager.default.contentsOfDirectory(atPath: adapter.directory.path(percentEncoded: false))
            #expect(files == [ActiveSessionFileAdapter.fileName], "ningún temporal de la escritura queda al lado")
        }
    }

    @Test("Un fallo de escritura deja el snapshot anterior entero")
    func failedSaveKeepsPrevious() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            let previous = Self.snapshot(stepsMeasured: 100)
            try adapter.saveActiveSession(previous)

            // Un número no finito no se puede codificar: la escritura falla antes de tocar el disco.
            let broken = ActiveSessionSnapshot(
                startedAt: Self.t0, stepsMeasured: 1, stepsEstimated: 0, totalPausesS: 0, paused: false,
                pausedAt: nil, strideM: .nan, systemDistanceM: nil, savedAt: Self.t0, lastSampleAt: nil,
                segmentStart: Self.t0, segmentSteps: 0, distanceBaseM: 0
            )
            #expect(throws: StorageError.failed(operation: "encode")) { try adapter.saveActiveSession(broken) }

            #expect(try adapter.loadActiveSession() == previous)
        }
    }

    @Test("Borrar al finalizar: la siguiente lectura no restaura")
    func clearRemoves() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            try adapter.saveActiveSession(Self.snapshot())

            try adapter.clearActiveSession()

            #expect(try adapter.loadActiveSession() == nil)
        }
    }

    @Test("Fichero ilegible: se aparta a activeSession.corrupt.<marca>.json con su contenido, lanza y la siguiente lectura da nil", arguments: [
        "{ roto",
        #"{ "schemaVersion": 9 }"#,
    ])
    func unreadableIsSetAside(contents: String) throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: adapter.fileURL)

            #expect(throws: StorageError.self) { try adapter.loadActiveSession() }

            #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
            #expect(try Self.setAsideContents(in: directory) == [Data(contents.utf8)], "apartado, no destruido")
            #expect(try adapter.loadActiveSession() == nil)
        }
    }

    @Test("Apartar el snapshot que rechazó el dominio conserva su contenido")
    func setAsideKeepsContents() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            try adapter.saveActiveSession(Self.snapshot())
            let contents = try Data(contentsOf: adapter.fileURL)

            try adapter.setAsideActiveSession()

            #expect(try adapter.loadActiveSession() == nil)
            #expect(!FileManager.default.fileExists(atPath: adapter.fileURL.path(percentEncoded: false)))
            #expect(try Self.setAsideContents(in: directory) == [contents])
        }
    }

    @Test("Dos ilegibles seguidos: cada uno queda apartado con su nombre y su contenido; el segundo no machaca el primero")
    func twoUnreadableAreBothKept() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let first = Data("{ roto".utf8)
            let second = Data(#"{ "schemaVersion": 9 }"#.utf8)

            try first.write(to: adapter.fileURL)
            #expect(throws: StorageError.self) { try adapter.loadActiveSession() }
            try second.write(to: adapter.fileURL)
            #expect(throws: StorageError.self) { try adapter.loadActiveSession() }

            try Self.expectTwoSetAside(first: first, second: second, in: adapter)
            #expect(try adapter.loadActiveSession() == nil)
        }
    }

    @Test("Apartar dos snapshots rechazados seguidos conserva los dos")
    func twoSetAsidesAreBothKept() throws {
        try Self.withDirectory { directory in
            let adapter = ActiveSessionFileAdapter(directory: directory)
            try adapter.saveActiveSession(Self.snapshot(stepsMeasured: 100))
            let first = try Data(contentsOf: adapter.fileURL)
            try adapter.setAsideActiveSession()
            try adapter.saveActiveSession(Self.snapshot(stepsMeasured: 200))
            let second = try Data(contentsOf: adapter.fileURL)
            try adapter.setAsideActiveSession()

            try Self.expectTwoSetAside(first: first, second: second, in: adapter)
        }
    }
}
