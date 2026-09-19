import Domain
import Foundation

/// El trato con el disco que comparten los ficheros de `StoragePort` (AD-9): leer, sustituir
/// de forma **atómica**, borrar y **apartar** el ilegible sin destruirlo.
///
/// Existe desde la 2.2, cuando `settings.json` necesitó exactamente las mismas garantías que
/// `activeSession.json`. Son las garantías las que se comparten; el formato (esquemas,
/// milisegundos, validación de la forma) sigue siendo de cada adapter.
///
/// **Escritura atómica.** Se escribe un temporal en el mismo directorio y se renombra sobre
/// el destino con `rename(2)`, que lo sustituye de una vez: un corte a mitad deja el fichero
/// anterior entero, nunca uno a medias.
///
/// **Ilegible.** Nunca se borra: se renombra a `<base>.corrupt.<marca>.json`, con una marca
/// única. `RENAME_EXCL` falla si el destino ya existe en vez de sustituirlo, así que un
/// apartado anterior nunca se destruye.
struct JSONFileStore: Sendable {

    /// Directorio del fichero: Application Support en la app, uno temporal en los tests.
    let directory: URL
    /// Nombre del fichero, con extensión (`activeSession.json`).
    let fileName: String
    /// Prefijo de un apartado: `activeSession.corrupt.`.
    let setAsideFilePrefix: String
    /// Extensión de un apartado: `.json`.
    let setAsideFileExtension: String

    /// - Parameter base: el nombre sin extensión (`activeSession`, `settings`), del que salen
    ///   tanto el fichero como el prefijo de los apartados.
    init(directory: URL, base: String) {
        self.directory = directory
        self.fileName = Self.fileName(base: base)
        self.setAsideFilePrefix = Self.setAsideFilePrefix(base: base)
        self.setAsideFileExtension = Self.setAsideFileExtension
    }

    // MARK: - Los nombres, en un solo sitio

    // Cada adapter anuncia sus nombres como estáticos (los tests afirman contra ellos) y a la
    // vez deriva los suyos de su `base`. Si fueran dos literales, cambiar `base:` dejaría los
    // tests verdes contra un nombre que el adapter ya no escribe: por eso las dos fuentes son
    // estas funciones, y el adapter solo elige su `base`.

    /// El nombre del fichero de un `base`: `activeSession` → `activeSession.json`.
    static func fileName(base: String) -> String { "\(base).json" }

    /// El prefijo de los apartados de un `base`: `activeSession` → `activeSession.corrupt.`.
    static func setAsideFilePrefix(base: String) -> String { "\(base).corrupt." }

    /// La extensión de un apartado, igual para todos los ficheros.
    static let setAsideFileExtension = ".json"

    var fileURL: URL { directory.appending(path: fileName, directoryHint: .notDirectory) }

    /// El contenido del fichero, o `nil` si no existe.
    ///
    /// - Throws: `failed(operation: "read")` si existe y no se puede leer.
    func read() throws(StorageError) -> Data? {
        do {
            return try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw .failed(operation: "read")
        }
    }

    /// Sustituye el fichero por `data` de una sola vez.
    ///
    /// - Throws: `failed` con `createDirectory`, `write` o `rename`.
    func write(_ data: Data) throws(StorageError) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .failed(operation: "createDirectory")
        }
        let temporary = directory.appending(path: ".\(fileName).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
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

    /// Borra el fichero. Si no existe no hace nada.
    ///
    /// - Throws: `failed(operation: "remove")`.
    func remove() throws(StorageError) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            throw .failed(operation: "remove")
        }
    }

    /// Renombra el fichero a `<base>.corrupt.<marca>.json`. Sin fichero no hace nada.
    ///
    /// - Throws: `failed(operation: "setAside")`.
    func setAside() throws(StorageError) {
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

    /// Un nombre de apartado nuevo. La marca es el instante en ms, con 13 cifras para que el
    /// orden alfabético sea el cronológico, y un sufijo aleatorio que la hace única dentro del
    /// mismo milisegundo: `activeSession.corrupt.1800000000000-1a2b3c4d.json`.
    private func newSetAsideURL() -> URL {
        let ms = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let marker = String(repeating: "0", count: max(0, 13 - String(ms).count)) + "\(ms)-\(suffix)"
        let name = "\(setAsideFilePrefix)\(marker)\(setAsideFileExtension)"
        return directory.appending(path: name, directoryHint: .notDirectory)
    }
}
