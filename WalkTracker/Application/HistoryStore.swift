import Domain
import Foundation
import OSLog

/// Único dueño de `sessions.json` (AD-16, 5.1). Nadie más lee ni escribe el historial: quien lo
/// necesita se lo pide a este store, como quien necesita la sesión se la pide a `SessionStore`.
///
/// Lo estrena la 5.1 con el registro inmutable de cada caminata cerrada. La 5.2 lo **lee** para
/// la lista, los totales y la tendencia; la 3.1 para el anillo semanal y la 3.2 para acumulados y
/// rachas; la 5.3 reutiliza su serialización para el export; la 5.4 borra a través de él.
///
/// **Se lee una vez, al construirlo**, como `SettingsStore`: el historial hace falta en el primer
/// cierre de sesión —para no archivar dos veces una caminata ya guardada— así que no hay un
/// `load()` que alguien pueda olvidarse de llamar.
///
/// **Nunca cuesta una caminata.** Sin fichero se parte de un historial vacío; con el fichero
/// ilegible, el adapter lo aparta —no lo destruye— y se parte igual de vacío.
///
/// **Y tampoco cuesta el historial** (B-1). `readOutcome` recuerda cuál de los tres casos ocurrió
/// y `save(applying:)` no escribe sin una lectura buena detrás, reintentando antes de bloquear.
///
/// **Aquí, además, se avisa.** Esta es la diferencia deliberada con `settings.json` (decisión de
/// Paul, 2026-09-21). Perder los ajustes es perder una zancada y una ventana de frases: molesto y
/// rehacible, y un silencio proporcionado. Perder el historial es perder meses de caminatas que
/// **no se pueden reconstruir** y que CAP-9 promete garantizadas: ese mismo silencio sería
/// desproporcionado. Por eso `showsUnreadableNotice` existe y lo pinta Inicio.
///
/// **Invariante:** solo este fichero llama a `loadSessions`/`saveSessions` del `StoragePort`, y
/// solo él escribe `records`. Lo comprueba `Scripts/check-project-shape.sh` (secciones 9 y 9b).
@MainActor
@Observable
final class HistoryStore {

    /// Las caminatas cerradas, en el orden del fichero (la más antigua primero, porque se añaden
    /// al final). Ordenarlas para pintarlas es de quien pinta (5.2).
    ///
    /// Acceso de módulo, como el estado de los otros stores; fuera de `Application/` lo hace
    /// cumplir la sección 6 del gate.
    private(set) var records: [SessionRecord] = []

    /// Qué se sabe de lo que hay en disco. Lo escribe solo `load()`.
    private(set) var readOutcome: StoredFileReadOutcome = .absent

    /// **El aviso.** Hay un `sessions.json` que esta ejecución no ha podido leer: la app funciona
    /// con el historial vacío, el fichero no se ha destruido y **Paul tiene que enterarse**.
    ///
    /// Es estado observable del store y no de la vista (sección 6 del gate): la pantalla lo pinta
    /// y no decide nada. Se apaga solo, sin intención que lo descarte: un ilegible ya apartado
    /// deja de existir y el arranque siguiente lee "no hay fichero"; uno de un esquema del futuro
    /// sigue ahí y el aviso vuelve a salir, que es exactamente lo que debe pasar mientras no se
    /// pueda escribir encima.
    var showsUnreadableNotice: Bool { readOutcome.isUnreadable }

    @ObservationIgnored let storage: any StoragePort
    @ObservationIgnored let log = Logger(subsystem: "com.walktracker.app", category: "HistoryStore")

    init(storage: any StoragePort) {
        self.storage = storage
        load()
    }

    /// Lee `sessions.json` y **deja constancia de cuál de los tres casos ocurrió**.
    ///
    /// - Returns: `true` si detrás de lo que queda en memoria hay una lectura buena.
    @discardableResult
    private func load() -> Bool {
        do {
            guard let stored = try storage.loadSessions() else {
                records = []
                readOutcome = .absent
                log.info("Sin sessions.json todavía: el historial empieza vacío y se puede escribir")
                return true
            }
            records = stored
            readOutcome = .loaded
            return true
        } catch {
            records = []
            readOutcome = .unreadable(error)
            // Un `catch` por caso no valdría: Swift no comprueba que cubran el enum. La
            // exhaustividad la sostiene el `switch`.
            switch error {
            case .failed(let operation):
                log.error("No se pudo leer el historial (\(operation, privacy: .public)); el fichero sigue en su sitio y NO se escribirá encima hasta poder leerlo")
            case .unsupportedSchemaVersion(let version):
                log.error("sessions.json es de un esquema (\(version, privacy: .public)) que esta versión no sabe leer; se sigue con el historial vacío y NO se escribe encima")
            case .malformed(let detail):
                log.error("sessions.json ilegible, apartado por el adapter: \(detail, privacy: .public); se sigue con el historial vacío")
            }
            return false
        }
    }

    /// ¿Hay ya una caminata que empezó en `startedAt`?
    ///
    /// **Cierra la ventana de duplicado del cierre de sesión.** Guardar el registro antes de
    /// borrar el snapshot es lo correcto —un fallo de disco no pierde la caminata— pero durante
    /// un instante la sesión existe en los **dos** ficheros. Si la app muere justo ahí, al
    /// relanzar la recuperación vería una sesión viva y la archivaría por segunda vez. Esto es lo
    /// que lo impide, y `startedAt` es la clave natural: no puede haber dos caminatas que
    /// empiecen en el mismo instante.
    func contains(startedAt: Date) -> Bool {
        records.contains { $0.startedAt == startedAt }
    }

    /// Añade una caminata cerrada al historial y lo persiste.
    ///
    /// El registro es **inmutable** y no se reconcilia con nada: si ya hay uno con el mismo
    /// `startedAt` no se añade otro y se devuelve `true`, porque el resultado observable que
    /// interesa a quien llama —"esta caminata está guardada"— ya se cumple, y duplicarla sería
    /// contar dos veces sus kilómetros en el anillo y en los logros.
    ///
    /// - Returns: `true` si la caminata quedó escrita en `sessions.json`. `false` es lo que
    ///   `SessionStore` traduce en **no borrar el snapshot** y avisar antes de salir del resumen.
    @discardableResult
    func append(_ record: SessionRecord) -> Bool {
        guard !contains(startedAt: record.startedAt) else {
            log.info("La caminata ya estaba en el historial: no se añade dos veces")
            return true
        }
        return save { records in records.append(record) }
    }

    /// Aplica `change` al historial y lo escribe. Un fallo se registra y **no se propaga como
    /// error**, pero sí se devuelve: quien llama decide qué contarle a Paul.
    ///
    /// **Sin una lectura buena no se escribe** (B-1). Antes de bloquear se reintenta la lectura:
    /// un fallo transitorio se recupera solo, y entonces `change` se aplica **sobre lo que hay en
    /// disco**, no sobre el historial vacío que el store arrastraba —por eso el cambio es una
    /// función y no una mutación hecha antes de llamar aquí—. Lo que de verdad no se puede
    /// interpretar, un esquema del futuro, sigue fallando el reintento por definición.
    ///
    /// **Con la escritura bloqueada el cambio NO se aplica en memoria**, y aquí diverge a
    /// propósito de `SettingsStore.save(applying:)`. Allí aplicarlo es lo correcto: la ventana de
    /// frases de esta ejecución no debe repetir aunque el disco falle. Aquí sería mentir: un
    /// historial en memoria que no está en disco haría creer a `contains(startedAt:)` que la
    /// caminata está a salvo, y con ella se borraría el snapshot que es su única copia.
    ///
    /// - Returns: `true` si quedó escrito en `sessions.json`.
    @discardableResult
    func save(applying change: (inout [SessionRecord]) -> Void) -> Bool {
        guard readOutcome.allowsWriting || reloadBeforeWriting() else { return false }
        var updated = records
        change(&updated)
        do {
            try storage.saveSessions(updated)
            records = updated
            return true
        } catch {
            log.error("No se pudo guardar el historial: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// El reintento que convierte un fallo transitorio en un caso que se arregla solo. Mismo
    /// razonamiento que en `SettingsStore`: bloquear de por vida convertiría un problema de un
    /// segundo en una ejecución entera sin guardar nada, y lo que no es transitorio vuelve a
    /// fallar aquí.
    ///
    /// - Returns: `true` si la lectura funcionó y ya se puede escribir.
    private func reloadBeforeWriting() -> Bool {
        log.info("Hay una caminata que guardar y la última lectura del historial no fue buena: se reintenta leer antes de decidir")
        guard load() else {
            log.error("El historial sigue sin poder leerse: no se escribe encima. La caminata no se persiste y el snapshot NO se borra")
            return false
        }
        log.info("El historial se leyó al reintentar: la caminata se añade sobre lo que hay en disco")
        return true
    }
}
