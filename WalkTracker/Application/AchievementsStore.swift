import Domain
import Foundation
import OSLog

/// Único dueño de `achievements.json` **del sandbox** (AD-16, 5.1). Nadie más lee ni escribe el
/// estado de los logros.
///
/// **No es el catálogo.** Los 14 logros son contenido congelado del bundle
/// (`WalkTracker/Resources/achievements.json`, AD-5), los carga `CompositionRoot` y un gate los
/// compara con la referencia de la v3. Este store escribe el fichero homónimo del sandbox, que
/// guarda **qué ha conseguido Paul**. Son dos ficheros distintos con el mismo nombre en dos
/// directorios distintos, y confundirlos rompe el gate o pisa contenido congelado.
///
/// **La 5.1 crea el dueño y el esquema; el contenido lo escribe la 3.2.** AD-17 fija que los
/// logros se evalúan **al cerrar la sesión, dentro de la misma transacción que la persiste**, y
/// ese punto es `SessionStore.confirmFinish()`. Lo que la 3.2 encontrará hecho: el fichero, su
/// adapter, este dueño y una caminata cerrada que ya sabe decir si cuenta para logros
/// (`SessionRecord.countsForAchievements`, que es `false` para una huérfana — AD-18).
///
/// **La transacción que esta historia no puede cerrar, dicha en voz alta.** AD-17 pide
/// atomicidad conjunta entre la sesión y los logros; AD-16 pide un fichero, un dueño; y la
/// escritura atómica de AD-9 es **por fichero**. Dos ficheros con dos dueños no se pueden
/// escribir de una sola vez, así que un corte entre las dos escrituras puede dejar una caminata
/// guardada cuyos logros no se evaluaron. El problema se crea aquí aunque se manifieste en la
/// 3.2, y por eso está escrito en `deferred-work.md` con su destino en vez de descubrirse
/// entonces.
///
/// **Invariante:** solo este fichero llama a `loadAchievements`/`saveAchievements` del
/// `StoragePort`, y solo él escribe `unlocks`. Lo comprueba `Scripts/check-project-shape.sh`
/// (secciones 9 y 9b).
@MainActor
@Observable
final class AchievementsStore {

    /// El estado de cada logro con algo que contar: desbloqueado, o con progreso hacia su
    /// umbral. Un logro sin fila es uno que nunca se ha tocado.
    private(set) var unlocks: [AchievementUnlock] = []

    /// Qué se sabe de lo que hay en disco. Lo escribe solo `load()`.
    private(set) var readOutcome: StoredFileReadOutcome = .absent

    @ObservationIgnored let storage: any StoragePort
    @ObservationIgnored let log = Logger(subsystem: "com.walktracker.app", category: "AchievementsStore")

    init(storage: any StoragePort) {
        self.storage = storage
        load()
    }

    /// Lee `achievements.json` y deja constancia de cuál de los tres casos ocurrió.
    ///
    /// - Returns: `true` si detrás de lo que queda en memoria hay una lectura buena.
    @discardableResult
    private func load() -> Bool {
        do {
            guard let stored = try storage.loadAchievements() else {
                unlocks = []
                readOutcome = .absent
                log.info("Sin achievements.json todavía: ningún logro registrado y se puede escribir")
                return true
            }
            unlocks = stored
            readOutcome = .loaded
            return true
        } catch {
            unlocks = []
            readOutcome = .unreadable(error)
            switch error {
            case .failed(let operation):
                log.error("No se pudo leer el estado de los logros (\(operation, privacy: .public)); el fichero sigue en su sitio y NO se escribirá encima hasta poder leerlo")
            case .unsupportedSchemaVersion(let version):
                log.error("achievements.json (sandbox) es de un esquema (\(version, privacy: .public)) que esta versión no sabe leer; NO se escribe encima")
            case .malformed(let detail):
                log.error("achievements.json (sandbox) ilegible, apartado por el adapter: \(detail, privacy: .public)")
            }
            return false
        }
    }

    /// El estado de un logro, o `nil` si nunca se ha tocado.
    func unlock(forKey key: String) -> AchievementUnlock? {
        unlocks.first { $0.key == key }
    }

    /// Aplica `change` al estado de los logros y lo escribe, con la misma puerta que el historial
    /// y los ajustes: **sin una lectura buena no se escribe**, con un reintento antes de
    /// bloquear, y sin aplicar el cambio en memoria si no llegó al disco.
    ///
    /// Aquí no hay intenciones todavía: quien decide qué logro sube y cuál se desbloquea es la
    /// 3.2, y sus intenciones vivirán en `AchievementsStore+…swift`, exentas por la misma regla
    /// de forma que las de los otros dueños.
    ///
    /// - Returns: `true` si quedó escrito en `achievements.json`.
    @discardableResult
    func save(applying change: (inout [AchievementUnlock]) -> Void) -> Bool {
        guard readOutcome.allowsWriting || reloadBeforeWriting() else { return false }
        var updated = unlocks
        change(&updated)
        do {
            try storage.saveAchievements(updated)
            unlocks = updated
            return true
        } catch {
            log.error("No se pudo guardar el estado de los logros: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// - Returns: `true` si la lectura funcionó y ya se puede escribir.
    private func reloadBeforeWriting() -> Bool {
        log.info("Hay un cambio de logros que guardar y la última lectura no fue buena: se reintenta leer antes de decidir")
        guard load() else {
            log.error("El estado de los logros sigue sin poder leerse: no se escribe encima")
            return false
        }
        return true
    }
}
