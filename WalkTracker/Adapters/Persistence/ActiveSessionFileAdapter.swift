import Domain
import Foundation
import OSLog

/// El snapshot de la sesión viva en `activeSession.json`, en Application Support (CAP-1,
/// CAP-9) — AD-9, AD-10, AD-16.
///
/// **Formato.** JSON `Codable` con `schemaVersion`. Los instantes y las pausas van en
/// **milisegundos** enteros (domain-model.md §8: `startedAtMs`, `totalPausesMs`,
/// `pausedAtMs`); la conversión a segundos y `Date` vive aquí y el dominio nunca ve
/// milisegundos. Redondear al milisegundo es la única pérdida del viaje de ida y vuelta.
///
/// **Frontera.** `decode(_:)` valida la forma del JSON (el `TypeError` de
/// `restoreV3Session`): versión, campos obligatorios y tipos. Los rangos (zancada ≤ 0,
/// pasos < 0, pausada sin `pausedAt`) son del dominio, en `Session.restore`.
///
/// **Esquemas.** Escribe la versión 3, que añade `quoteId` (2.2), y sigue leyendo la 1 y la
/// 2: un snapshot de la 1 se lee sin clima y uno de la 2 sin frase, sin apartar ninguno.
///
/// **Disco.** La escritura atómica y el apartado del ilegible son de `JSONFileStore`, que
/// comparte con `SettingsFileAdapter`. Quien lo entrega por el puerto es `FileStorageAdapter`:
/// este tipo no conforma `StoragePort` porque solo cubre uno de sus dos ficheros.
struct ActiveSessionFileAdapter {

    /// La versión que se escribe.
    static let supportedSchemaVersion = 3
    /// Las versiones que se leen: la 1 no tenía `weather` y la 2 no tenía `quoteId`.
    static let readableSchemaVersions: ClosedRange<Int> = 1...3
    /// El nombre base, del que `JSONFileStore` deriva **todos** los nombres: cambiarlo aquí
    /// cambia a la vez lo que el adapter escribe y lo que los estáticos anuncian.
    private static let base = "activeSession"
    static var fileName: String { JSONFileStore.fileName(base: base) }
    /// Prefijo y extensión de un snapshot apartado: `activeSession.corrupt.<marca>.json`.
    static var setAsideFilePrefix: String { JSONFileStore.setAsideFilePrefix(base: base) }
    static var setAsideFileExtension: String { JSONFileStore.setAsideFileExtension }

    private static let log = Logger(subsystem: "com.walktracker.app", category: "ActiveSessionFileAdapter")

    private let file: JSONFileStore

    init(directory: URL = .applicationSupportDirectory) {
        file = JSONFileStore(directory: directory, base: Self.base)
    }

    /// Directorio del snapshot: Application Support en la app, uno temporal en los tests.
    var directory: URL { file.directory }
    var fileURL: URL { file.fileURL }

    // MARK: - Snapshot de la sesión viva

    func loadActiveSession() throws(StorageError) -> ActiveSessionSnapshot? {
        guard let data = try file.read() else { return nil }
        do {
            return try Self.decode(data)
        } catch {
            // El apartado es lo secundario: si falla, lo que hay que contar sigue siendo por
            // qué no se pudo leer. Se registra el fallo y se propaga el error original.
            do {
                try file.setAside()
            } catch {
                Self.log.error("No se pudo apartar un snapshot ilegible: \(String(describing: error), privacy: .public)")
            }
            throw error
        }
    }

    func saveActiveSession(_ snapshot: ActiveSessionSnapshot) throws(StorageError) {
        try file.write(try Self.encode(snapshot))
    }

    func clearActiveSession() throws(StorageError) {
        try file.remove()
    }

    func setAsideActiveSession() throws(StorageError) {
        try file.setAside()
    }

    // MARK: - Formato (puro)

    /// El JSON de `schemaVersion` 1, 2 y 3. Los opcionales que la v3 daba por 0
    /// (`stepsMeasured`, `stepsEstimated`, `totalPausesMs`, `paused`) se aceptan ausentes.
    /// `weather` es de la 2 y `quoteId` de la 3: ausentes o `null`, sin clima y sin frase.
    private struct File: Codable {
        var schemaVersion: Int
        var startedAtMs: Int64
        var stepsMeasured: Int?
        var stepsEstimated: Int?
        var totalPausesMs: Int64?
        var paused: Bool?
        var pausedAtMs: Int64?
        var strideM: Double
        var systemDistanceM: Double?
        var savedAtMs: Int64
        var lastSampleAtMs: Int64?
        var segmentStartMs: Int64
        var segmentSteps: Int
        var distanceBaseM: Double
        var weather: WeatherFile?
        var quoteId: Int?
    }

    /// El clima en el fichero. `condition` no se guarda: sale de `wmoCode` en el dominio.
    private struct WeatherFile: Codable {
        var tempC: Double
        var feelsLikeC: Double
        var wmoCode: Int
        var humidityPct: Double
        var uvIndex: Double
        var windKmh: Double
        var capturedAtMs: Int64
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int
    }

    /// JSON → snapshot en segundos. Solo valida la forma: los rangos de la sesión son del
    /// dominio (`Session.restore`).
    ///
    /// El clima es la excepción, porque `WeatherSnapshot` solo existe validado: un clima con la
    /// forma bien y los rangos mal (solo un fichero manipulado) se lee como sin clima. Nunca
    /// aparta la caminata: la falta de clima no bloquea nada (AD-11).
    ///
    /// - Throws: `unsupportedSchemaVersion` con una versión fuera de 1–3; `malformed` si no es
    ///   JSON, falta un campo obligatorio o un campo tiene otro tipo.
    static func decode(_ data: Data) throws(StorageError) -> ActiveSessionSnapshot {
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
        let paused = file.paused ?? false
        return ActiveSessionSnapshot(
            startedAt: date(ms: file.startedAtMs),
            stepsMeasured: file.stepsMeasured ?? 0,
            stepsEstimated: file.stepsEstimated ?? 0,
            totalPausesS: seconds(ms: file.totalPausesMs ?? 0),
            paused: paused,
            pausedAt: file.pausedAtMs.map(date(ms:)),
            strideM: file.strideM,
            systemDistanceM: file.systemDistanceM,
            savedAt: date(ms: file.savedAtMs),
            lastSampleAt: file.lastSampleAtMs.map(date(ms:)),
            segmentStart: date(ms: file.segmentStartMs),
            segmentSteps: file.segmentSteps,
            distanceBaseM: file.distanceBaseM,
            weather: version >= 2 ? file.weather.flatMap(weather(from:)) : nil,
            quoteId: version >= 3 ? file.quoteId : nil
        )
    }

    private static func weather(from file: WeatherFile) -> WeatherSnapshot? {
        try? WeatherSnapshot(
            tempC: file.tempC,
            feelsLikeC: file.feelsLikeC,
            wmoCode: file.wmoCode,
            humidityPct: file.humidityPct,
            uvIndex: file.uvIndex,
            windKmh: file.windKmh,
            capturedAt: date(ms: file.capturedAtMs)
        )
    }

    /// Snapshot → JSON en milisegundos, con las claves ordenadas.
    ///
    /// - Throws: `failed(encode)` con un instante o una duración que no caben en milisegundos
    ///   enteros, o un número no finito.
    static func encode(_ snapshot: ActiveSessionSnapshot) throws(StorageError) -> Data {
        let file = File(
            schemaVersion: supportedSchemaVersion,
            startedAtMs: try ms(snapshot.startedAt.timeIntervalSince1970),
            stepsMeasured: snapshot.stepsMeasured,
            stepsEstimated: snapshot.stepsEstimated,
            totalPausesMs: try ms(snapshot.totalPausesS),
            paused: snapshot.paused,
            pausedAtMs: try snapshot.pausedAt.map { date throws(StorageError) in try ms(date.timeIntervalSince1970) },
            strideM: snapshot.strideM,
            systemDistanceM: snapshot.systemDistanceM,
            savedAtMs: try ms(snapshot.savedAt.timeIntervalSince1970),
            lastSampleAtMs: try snapshot.lastSampleAt.map { date throws(StorageError) in try ms(date.timeIntervalSince1970) },
            segmentStartMs: try ms(snapshot.segmentStart.timeIntervalSince1970),
            segmentSteps: snapshot.segmentSteps,
            distanceBaseM: snapshot.distanceBaseM,
            weather: try snapshot.weather.map { weather throws(StorageError) in
                WeatherFile(
                    tempC: weather.tempC,
                    feelsLikeC: weather.feelsLikeC,
                    wmoCode: weather.wmoCode,
                    humidityPct: weather.humidityPct,
                    uvIndex: weather.uvIndex,
                    windKmh: weather.windKmh,
                    capturedAtMs: try ms(weather.capturedAt.timeIntervalSince1970)
                )
            },
            quoteId: snapshot.quoteId
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(file)
        } catch {
            throw .failed(operation: "encode")
        }
    }

    private static func date(ms: Int64) -> Date {
        Date(timeIntervalSince1970: seconds(ms: ms))
    }

    private static func seconds(ms: Int64) -> TimeInterval {
        TimeInterval(ms) / 1000
    }

    private static func ms(_ seconds: TimeInterval) throws(StorageError) -> Int64 {
        let ms = (seconds * 1000).rounded()
        guard ms.isFinite, ms >= Double(Int64.min), ms < Double(Int64.max) else {
            throw .failed(operation: "encode")
        }
        return Int64(ms)
    }
}
