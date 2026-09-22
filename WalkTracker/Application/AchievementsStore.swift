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
/// **La 5.1 creó el dueño y el esquema; la 3.2 escribe el contenido.** Sus dos intenciones viven
/// en extensiones: `AchievementsStore+Goal.swift` (`weekly_goal`, la excepción de AD-25 que
/// desbloquea `GoalEngine` al cumplirse la meta) y `AchievementsStore+Evaluation.swift` (los
/// logros que el `AchievementEngine` da por cumplidos al cerrar una caminata, AD-17).
///
/// **La transacción que no se puede cerrar, dicha en voz alta.** AD-17 pide atomicidad conjunta
/// entre la sesión y los logros; AD-16 pide un fichero, un dueño; y la escritura atómica de AD-9
/// es **por fichero**. Dos ficheros con dos dueños no se pueden escribir de una sola vez, así que
/// un corte entre las dos escrituras puede dejar una caminata guardada cuyos logros no se
/// evaluaron. La 3.2 lo resuelve con un orden declarado —**sesión primero, logros después**
/// (decisión D1 de Paul): el peor caso es un logro que falta, nunca un logro fantasma
/// irrevocable, y los cuatro acumulados se curan solos en el cierre siguiente. El límite sigue
/// registrado en `deferred-work.md` como lo que es: conocido, no pendiente.
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
    /// Aquí no se decide **qué** logro se desbloquea: eso es de las intenciones
    /// (`AchievementsStore+Goal.swift`, `AchievementsStore+Evaluation.swift`), exentas por la
    /// misma regla de forma que las de los otros dueños.
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

    /// Inserta la fila de un logro, o sustituye la que hubiera, **sin tocar una ya desbloqueada**.
    ///
    /// **La guarda vive aquí dentro y no en quien llama, y eso es el arreglo de un defecto real.**
    /// `save(applying:)` empieza por `readOutcome.allowsWriting || reloadBeforeWriting()`, y esa
    /// recarga **repuebla `unlocks` desde disco**: una fila que en memoria no constaba puede
    /// aparecer ya desbloqueada justo antes de aplicar el cambio. Decidir fuera, contra el estado
    /// viejo, le movía el `unlockedAt` y la devolvía como nueva —es decir, **la volvía a
    /// celebrar**—, rompiendo el invariante que AD-17 y CAP-15 fijan: un desbloqueo no se
    /// re-dispara y **nunca** se revoca. Dentro del closure la decisión se toma contra lo que de
    /// verdad se va a escribir.
    ///
    /// Vive en el store y no en una de las dos intenciones porque **las dos lo necesitan igual**
    /// (`unlockWeeklyGoal(at:)` y `unlock(_:at:)`), y eran carácter por carácter el mismo bloque:
    /// dos copias de la guarda serían dos sitios donde se puede arreglar solo uno.
    ///
    /// Una clave no aparece dos veces en el fichero: una fila con `progress` y sin `unlockedAt`
    /// —un logro **en curso**— sí se sustituye en su sitio, que es como se consigue.
    ///
    /// - Returns: `true` si esta llamada escribió la fila.
    @discardableResult
    func upsert(_ row: AchievementUnlock, into stored: inout [AchievementUnlock]) -> Bool {
        guard let index = stored.firstIndex(where: { $0.key == row.key }) else {
            stored.append(row)
            return true
        }
        guard !stored[index].isUnlocked else {
            log.info("'\(row.key, privacy: .public)' ya estaba desbloqueado al escribir: su instante NO se mueve")
            return false
        }
        stored[index] = row
        return true
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
