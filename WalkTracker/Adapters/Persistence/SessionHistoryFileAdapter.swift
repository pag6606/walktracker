import Domain
import Foundation
import OSLog

/// El historial de caminatas cerradas en `sessions.json`, en Application Support (5.1, CAP-9,
/// FR-9) — AD-9, AD-10, AD-16.
///
/// **Formato.** JSON `Codable` con `schemaVersion` 1 y un array `sessions`. Los instantes van en
/// **ISO-8601** (`ISO8601Timestamp`), no en milisegundos como el snapshot: son dos contratos de
/// datos distintos que conviven en el mismo directorio sin mezclarse.
///
/// **Campos que aún no existen.** Como en `settings.json`, todo campo opcional nuevo se
/// decodifica como tal y cae a su valor por omisión, así que añadir uno no obliga a subir la
/// versión. `recovered` y `degraded` ya se escriben desde el primer día; ausentes se leen como
/// `false`, que es lo que valía para un fichero escrito antes de existir la columna.
///
/// **Un esquema del futuro no es corrupción.** Con un `schemaVersion` **mayor** el fichero se
/// **deja donde está** y la lectura lanza `unsupportedSchemaVersion`, siguiendo el molde de
/// `SettingsFileAdapter` —que intercepta ese caso **antes** del `catch` que aparta— y no el de
/// `ActiveSessionFileAdapter`, que aparta cualquier versión fuera de rango. **La divergencia es
/// deliberada:** un snapshot apartado cuesta una caminata a medias; un historial apartado por
/// instalar un build anterior costaría meses de caminatas que no se pueden reconstruir.
///
/// **Una fila que el dominio rechaza hace ilegible el fichero, y no se salta en silencio.**
/// `SessionRecord` valida en la frontera; si una fila no pasa —solo un fichero manipulado o
/// corrupto llega ahí—, el fichero entero se declara `malformed`, se **aparta** con su nombre
/// único y la app sigue con el historial vacío y un aviso. Saltarse la fila dejaría a Paul con un
/// historial que parece entero y le falta algo, sin que nada lo diga; apartarlo lo conserva (el
/// `.corrupt.` sigue en disco) y **se lo cuenta**. El clima es la única excepción, como en el
/// snapshot: un clima con la forma bien y los rangos mal se lee como sin clima, porque la falta
/// de clima no bloquea nada (AD-11).
///
/// **Disco.** Escritura atómica y apartado del ilegible, de `JSONFileStore`: las mismas garantías
/// que los otros tres ficheros, sin reinventar el mecanismo. Quien lo entrega por el puerto es
/// `FileStorageAdapter`.
struct SessionHistoryFileAdapter {

    /// La versión que se escribe. `sessions.json` nace en la 5.1.
    static let supportedSchemaVersion = 1
    /// Las versiones que se leen. Hoy solo la 1.
    static let readableSchemaVersions: ClosedRange<Int> = 1...1
    /// El nombre base, del que `JSONFileStore` deriva **todos** los nombres.
    private static let base = "sessions"
    static var fileName: String { JSONFileStore.fileName(base: base) }
    /// Prefijo y extensión de un historial apartado: `sessions.corrupt.<marca>.json`.
    static var setAsideFilePrefix: String { JSONFileStore.setAsideFilePrefix(base: base) }
    static var setAsideFileExtension: String { JSONFileStore.setAsideFileExtension }

    private static let log = Logger(subsystem: "com.walktracker.app", category: "SessionHistoryFileAdapter")

    private let file: JSONFileStore

    init(directory: URL = .applicationSupportDirectory) {
        file = JSONFileStore(directory: directory, base: Self.base)
    }

    /// Directorio del historial: Application Support en la app, uno temporal en los tests.
    var directory: URL { file.directory }
    var fileURL: URL { file.fileURL }

    // MARK: - Historial

    func loadSessions() throws(StorageError) -> [SessionRecord]? {
        guard let data = try file.read() else { return nil }
        do {
            return try Self.decode(data)
        } catch .unsupportedSchemaVersion(let version) where version > Self.supportedSchemaVersion {
            // Del futuro, no corrupto: no se aparta, no se migra y no se escribe encima. Lo que
            // se pierde apartándolo no se puede rehacer.
            Self.log.error("sessions.json es de un esquema más nuevo (\(version, privacy: .public) > \(Self.supportedSchemaVersion, privacy: .public)); el fichero se deja donde está y la lectura lanza")
            throw .unsupportedSchemaVersion(version)
        } catch {
            // El apartado es lo secundario: si falla, lo que hay que contar sigue siendo por qué
            // no se pudo leer. Se registra el fallo y se propaga el error original.
            do {
                try file.setAside()
            } catch {
                Self.log.error("No se pudo apartar un historial ilegible: \(String(describing: error), privacy: .public)")
            }
            throw error
        }
    }

    func saveSessions(_ sessions: [SessionRecord]) throws(StorageError) {
        try file.write(try Self.encode(sessions))
    }

    // MARK: - Formato (puro)

    /// El JSON de `schemaVersion` 1.
    private struct File: Codable {
        var schemaVersion: Int
        var sessions: [SessionFile]
    }

    /// Una caminata cerrada en el fichero. Los instantes son cadenas ISO-8601; `recovered` y
    /// `degraded` son opcionales para que un fichero sin ellos siga leyéndose.
    private struct SessionFile: Codable {
        var id: String
        var startedAt: String
        var endedAt: String
        var stepsMeasured: Int
        var stepsEstimated: Int
        var strideM: Double
        var distanceM: Double
        var durationS: Int
        var pausesS: Int
        var paceSecPerKm: Int?
        var cadenceSpm: Double
        var weather: WeatherFile?
        var quoteId: Int?
        var source: String
        var recovered: Bool?
        var degraded: Bool?
    }

    /// El clima en el fichero. `condition` no se guarda: sale de `wmoCode` en el dominio. Su
    /// instante también es ISO-8601, como el resto de este fichero.
    private struct WeatherFile: Codable {
        var tempC: Double
        var feelsLikeC: Double
        var wmoCode: Int
        var humidityPct: Double
        var uvIndex: Double
        var windKmh: Double
        var capturedAt: String
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int
    }

    /// JSON → registros.
    ///
    /// - Throws: `unsupportedSchemaVersion` con una versión fuera de 1; `malformed` si no es
    ///   JSON, falta `schemaVersion`, un campo tiene otro tipo, un instante no es ISO-8601, un
    ///   `id` no es un UUID, una `source` es desconocida o una fila no cruza la frontera del
    ///   dominio.
    static func decode(_ data: Data) throws(StorageError) -> [SessionRecord] {
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
        var records: [SessionRecord] = []
        records.reserveCapacity(file.sessions.count)
        for row in file.sessions {
            records.append(try record(from: row))
        }
        return records
    }

    private static func record(from row: SessionFile) throws(StorageError) -> SessionRecord {
        guard let id = UUID(uuidString: row.id) else {
            throw .malformed("sessions.json: `id` no es un UUID (\(row.id))")
        }
        guard let startedAt = ISO8601Timestamp.instant(row.startedAt) else {
            throw .malformed("sessions.json: `startedAt` no es ISO-8601 (\(row.startedAt))")
        }
        guard let endedAt = ISO8601Timestamp.instant(row.endedAt) else {
            throw .malformed("sessions.json: `endedAt` no es ISO-8601 (\(row.endedAt))")
        }
        guard let source = SessionSource(rawValue: row.source) else {
            throw .malformed("sessions.json: `source` desconocida (\(row.source))")
        }
        do {
            return try SessionRecord(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                stepsMeasured: row.stepsMeasured,
                stepsEstimated: row.stepsEstimated,
                strideM: row.strideM,
                distanceM: row.distanceM,
                durationS: row.durationS,
                pausesS: row.pausesS,
                paceSecPerKm: row.paceSecPerKm,
                cadenceSpm: row.cadenceSpm,
                weather: row.weather.flatMap(weather(from:)),
                quoteId: row.quoteId,
                source: source,
                recovered: row.recovered ?? false,
                degraded: row.degraded ?? false
            )
        } catch {
            throw .malformed("sessions.json: una caminata no cruza la frontera del dominio: \(String(describing: error))")
        }
    }

    private static func weather(from file: WeatherFile) -> WeatherSnapshot? {
        guard let capturedAt = ISO8601Timestamp.instant(file.capturedAt) else { return nil }
        return try? WeatherSnapshot(
            tempC: file.tempC,
            feelsLikeC: file.feelsLikeC,
            wmoCode: file.wmoCode,
            humidityPct: file.humidityPct,
            uvIndex: file.uvIndex,
            windKmh: file.windKmh,
            capturedAt: capturedAt
        )
    }

    /// Registros → JSON, con las claves ordenadas.
    ///
    /// - Throws: `failed(operation: "encode")`.
    static func encode(_ sessions: [SessionRecord]) throws(StorageError) -> Data {
        let file = File(
            schemaVersion: supportedSchemaVersion,
            sessions: sessions.map { record in
                SessionFile(
                    id: record.id.uuidString,
                    startedAt: ISO8601Timestamp.text(record.startedAt),
                    endedAt: ISO8601Timestamp.text(record.endedAt),
                    stepsMeasured: record.stepsMeasured,
                    stepsEstimated: record.stepsEstimated,
                    strideM: record.strideM,
                    distanceM: record.distanceM,
                    durationS: record.durationS,
                    pausesS: record.pausesS,
                    paceSecPerKm: record.paceSecPerKm,
                    cadenceSpm: record.cadenceSpm,
                    weather: record.weather.map { weather in
                        WeatherFile(
                            tempC: weather.tempC,
                            feelsLikeC: weather.feelsLikeC,
                            wmoCode: weather.wmoCode,
                            humidityPct: weather.humidityPct,
                            uvIndex: weather.uvIndex,
                            windKmh: weather.windKmh,
                            capturedAt: ISO8601Timestamp.text(weather.capturedAt)
                        )
                    },
                    quoteId: record.quoteId,
                    source: record.source.rawValue,
                    recovered: record.recovered,
                    degraded: record.degraded
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
