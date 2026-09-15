import Domain
import Foundation

/// `StoragePort` sobre `activeSession.json` en Application Support (CAP-1, CAP-9) — AD-9,
/// AD-10, AD-16.
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
/// **Escritura atómica.** Se escribe un temporal en el mismo directorio y se renombra sobre
/// el destino con `rename(2)`, que lo sustituye de una vez: un corte a mitad deja el
/// snapshot anterior entero, nunca uno a medias.
///
/// **Esquemas.** Escribe la versión 2, que añade `weather` (2.1), y sigue leyendo la 1: un
/// snapshot de la 1 se lee sin clima, sin apartarlo.
///
/// **Ilegible.** Nunca se borra: se renombra a `activeSession.corrupt.<marca>.json`, con una
/// marca única, y la lectura lanza. Un apartado nunca sustituye a otro anterior.
struct ActiveSessionFileAdapter: StoragePort {

    /// La versión que se escribe.
    static let supportedSchemaVersion = 2
    /// Las versiones que se leen: la 1 no tenía `weather`.
    static let readableSchemaVersions: ClosedRange<Int> = 1...2
    static let fileName = "activeSession.json"
    /// Prefijo y extensión de un snapshot apartado: `activeSession.corrupt.<marca>.json`.
    static let setAsideFilePrefix = "activeSession.corrupt."
    static let setAsideFileExtension = ".json"

    /// Directorio del snapshot: Application Support en la app, uno temporal en los tests.
    let directory: URL

    init(directory: URL = .applicationSupportDirectory) {
        self.directory = directory
    }

    var fileURL: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }

    /// Un nombre de apartado nuevo. La marca es el instante en ms, con 13 cifras para que el
    /// orden alfabético sea el cronológico, y un sufijo aleatorio que la hace única dentro del
    /// mismo milisegundo: `activeSession.corrupt.1800000000000-1a2b3c4d.json`.
    private func newSetAsideURL() -> URL {
        let ms = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let marker = String(repeating: "0", count: max(0, 13 - String(ms).count)) + "\(ms)-\(suffix)"
        let name = "\(Self.setAsideFilePrefix)\(marker)\(Self.setAsideFileExtension)"
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    // MARK: - StoragePort

    func loadActiveSession() throws(StorageError) -> ActiveSessionSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw .failed(operation: "read")
        }
        do {
            return try Self.decode(data)
        } catch {
            try setAside()
            throw error
        }
    }

    func saveActiveSession(_ snapshot: ActiveSessionSnapshot) throws(StorageError) {
        let data = try Self.encode(snapshot)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .failed(operation: "createDirectory")
        }
        let temporary = directory.appending(path: ".\(Self.fileName).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw .failed(operation: "write")
        }
        guard rename(temporary.path(percentEncoded: false), fileURL.path(percentEncoded: false)) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw .failed(operation: "rename")
        }
    }

    func clearActiveSession() throws(StorageError) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            throw .failed(operation: "remove")
        }
    }

    func setAsideActiveSession() throws(StorageError) {
        try setAside()
    }

    /// Renombra el snapshot a `activeSession.corrupt.<marca>.json`. Sin snapshot no hace nada.
    ///
    /// `RENAME_EXCL` falla si el destino ya existe en vez de sustituirlo: aunque la marca
    /// repitiera, un apartado anterior nunca se destruye.
    private func setAside() throws(StorageError) {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        let destination = newSetAsideURL()
        guard renamex_np(
            fileURL.path(percentEncoded: false),
            destination.path(percentEncoded: false),
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw .failed(operation: "setAside")
        }
    }

    // MARK: - Formato (puro)

    /// El JSON de `schemaVersion` 1 y 2. Los opcionales que la v3 daba por 0 (`stepsMeasured`,
    /// `stepsEstimated`, `totalPausesMs`, `paused`) se aceptan ausentes. `weather` es de la 2:
    /// ausente o `null`, sin clima.
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
    /// - Throws: `unsupportedSchemaVersion` con una versión fuera de 1–2; `malformed` si no es
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
            weather: version >= 2 ? file.weather.flatMap(weather(from:)) : nil
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
