import Domain
import Foundation
import OSLog

/// Los ajustes persistentes en `settings.json`, en Application Support (2.2, CAP-6) — AD-9,
/// AD-10, AD-16.
///
/// **Formato.** JSON `Codable` con `schemaVersion`, como el snapshot. Aquí no hay
/// milisegundos que convertir: los ajustes son valores del producto, no instantes.
///
/// **Campos que aún no existen.** Todo campo se decodifica como opcional y cae a su valor por
/// omisión: la 2.3 añadió `strideM`, el Epic 3 traerá la meta semanal y la 4.2 el sonido, y un
/// `settings.json` escrito hoy tiene que seguir leyéndose entonces sin apartarse.
///
/// **`schemaVersion` sigue en 1 con la zancada dentro, y es deliberado** (2.3). Un campo
/// opcional nuevo es compatible en las dos direcciones: un fichero de la 2.2 se lee entero y
/// admite la zancada, y un fichero con zancada sigue siendo legible por un build de la 2.2, que
/// ignora el campo desconocido. Subirlo a 2 habría hecho que un build de la 2.2 ya instalado
/// leyera los ajustes como "del futuro" y perdiera la ventana de frases.
///
/// **La ventana se sanea al leer.** Lo hace `AppSettings`, que normaliza en su `init`: sin
/// repetidos y como mucho `MotivationEngine.recentWindow`, quedándose con los **últimos**. Ni
/// un fichero manipulado con 500 ids deja al motor excluyendo medio banco, ni uno con 20 ids
/// repetidos deja la exclusión real en una sola frase. La zancada pasa por la misma puerta, la
/// tolerante: `-1` o `0` se leen como "sin configurar".
///
/// **Un fichero del futuro no es un fichero corrupto.** Con un `schemaVersion` **mayor** que
/// el que esta versión escribe —alguien instaló un build anterior— se parte de
/// `AppSettings.defaults` y el fichero **se deja donde está**: apartarlo perdería la ventana,
/// y mañana la zancada de la 2.3, en cuanto Paul volviera a la versión nueva. Solo se aparta
/// lo que de verdad no se puede leer: JSON roto, campos de otro tipo o una versión anterior
/// que ya no se sabe migrar.
///
/// **Disco.** Escritura atómica y apartado del ilegible, de `JSONFileStore`: mismas garantías
/// que `activeSession.json`. Unos ajustes corruptos no pueden costar una caminata — se
/// apartan, la lectura lanza y `SettingsStore` parte de `AppSettings.defaults`.
struct SettingsFileAdapter {

    /// La versión que se escribe.
    static let supportedSchemaVersion = 1
    /// Las versiones que se leen. Hoy solo la 1: `settings.json` nace en la 2.2.
    static let readableSchemaVersions: ClosedRange<Int> = 1...1
    /// El nombre base, del que `JSONFileStore` deriva **todos** los nombres: cambiarlo aquí
    /// cambia a la vez lo que el adapter escribe y lo que los estáticos anuncian.
    private static let base = "settings"
    static var fileName: String { JSONFileStore.fileName(base: base) }
    /// Prefijo y extensión de unos ajustes apartados: `settings.corrupt.<marca>.json`.
    static var setAsideFilePrefix: String { JSONFileStore.setAsideFilePrefix(base: base) }
    static var setAsideFileExtension: String { JSONFileStore.setAsideFileExtension }

    private static let log = Logger(subsystem: "com.walktracker.app", category: "SettingsFileAdapter")

    private let file: JSONFileStore

    init(directory: URL = .applicationSupportDirectory) {
        file = JSONFileStore(directory: directory, base: Self.base)
    }

    /// Directorio de los ajustes: Application Support en la app, uno temporal en los tests.
    var directory: URL { file.directory }
    var fileURL: URL { file.fileURL }

    // MARK: - Ajustes

    func loadSettings() throws(StorageError) -> AppSettings? {
        guard let data = try file.read() else { return nil }
        do {
            return try Self.decode(data)
        } catch .unsupportedSchemaVersion(let version) where version > Self.supportedSchemaVersion {
            // Del futuro, no corrupto: se ignora su contenido y se deja intacto, para que la
            // versión que sí lo entiende lo recupere entero.
            Self.log.error("settings.json es de un esquema más nuevo (\(version, privacy: .public) > \(Self.supportedSchemaVersion, privacy: .public)); se parte de los ajustes por omisión y el fichero se deja donde está")
            return .defaults
        } catch {
            // El apartado es lo secundario: si falla, lo que hay que contar sigue siendo por
            // qué no se pudo leer. Se registra el fallo y se propaga el error original.
            do {
                try file.setAside()
            } catch {
                Self.log.error("No se pudieron apartar unos ajustes ilegibles: \(String(describing: error), privacy: .public)")
            }
            throw error
        }
    }

    func saveSettings(_ settings: AppSettings) throws(StorageError) {
        try file.write(try Self.encode(settings))
    }

    // MARK: - Formato (puro)

    /// El JSON de `schemaVersion` 1. `recentQuoteIds` ausente o `null` es la ventana vacía;
    /// `strideM` ausente o `null` es "sin configurar" (2.3).
    private struct File: Codable {

        var schemaVersion: Int
        var recentQuoteIds: [Int]?
        var strideM: Double?

        // `CodingKeys` no se escribe: Swift lo sintetiza igual aunque `init(from:)` sea a mano
        // —lo que la suprime es declararla—, y tenerla a mano obliga a acordarse de ella cada
        // vez que una épica futura añada un campo. El init por miembros sí hay que restaurarlo:
        // ese lo suprime declarar cualquier init propio.
        init(schemaVersion: Int, recentQuoteIds: [Int]?, strideM: Double?) {
            self.schemaVersion = schemaVersion
            self.recentQuoteIds = recentQuoteIds
            self.strideM = strideM
        }

        /// Decodificación a mano por **un solo campo**: `strideM`.
        ///
        /// Los demás mantienen la regla de la 2.2 —un campo de otro tipo hace ilegible el
        /// fichero, que se aparta—, pero la zancada no puede costar la ventana de frases: la
        /// matriz de la 2.3 exige que unos ajustes con `strideM: "abc"` se lean como "sin
        /// configurar" y que el resto siga en pie. Con la síntesis de `Codable` un
        /// `typeMismatch` en la zancada tiraba el fichero entero.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            recentQuoteIds = try container.decodeIfPresent([Int].self, forKey: .recentQuoteIds)
            strideM = try? container.decodeIfPresent(Double.self, forKey: .strideM)
        }
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int
    }

    /// JSON → ajustes. Solo valida la forma: el saneado de los valores lo hace `AppSettings`
    /// al construirse, que es el único sitio donde vive el invariante de cada campo.
    ///
    /// - Throws: `unsupportedSchemaVersion` con una versión fuera de 1; `malformed` si no es
    ///   JSON, falta `schemaVersion` o un campo tiene otro tipo.
    static func decode(_ data: Data) throws(StorageError) -> AppSettings {
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
        return AppSettings(recentQuoteIds: file.recentQuoteIds ?? [], strideM: file.strideM)
    }

    /// Ajustes → JSON, con las claves ordenadas.
    ///
    /// - Throws: `failed(operation: "encode")`.
    static func encode(_ settings: AppSettings) throws(StorageError) -> Data {
        // `AppSettings` ya garantiza la ventana normalizada y una zancada válida o ausente:
        // aquí no se vuelve a recortar ni a validar. Sin configurar, la clave no se escribe.
        let file = File(
            schemaVersion: supportedSchemaVersion,
            recentQuoteIds: settings.recentQuoteIds,
            strideM: settings.strideM
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
