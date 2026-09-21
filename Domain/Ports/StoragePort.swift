import Foundation

/// Por qué el almacenamiento local no pudo leer o escribir (AD-9, AD-10). Un adapter
/// nunca deja escapar un error crudo de `FileManager` ni de `JSONDecoder`.
public enum StorageError: Error, Equatable, Sendable {
    /// El fichero existe pero no es JSON o no tiene la forma del esquema (el `TypeError`
    /// de `restoreV3Session`). El adapter ya lo apartó: no se destruye.
    case malformed(String)
    /// `schemaVersion` desconocido. El adapter ya lo apartó, como un ilegible —salvo el de un
    /// esquema **más nuevo**, que no es corrupto sino de una versión que aún no se conoce: ese
    /// se deja intacto para que quien lo entienda lo recupere entero, y por eso hay que
    /// distinguirlo de "aquí no había nada" (B-1).
    case unsupportedSchemaVersion(Int)
    /// El sistema de ficheros falló durante `operation`. Diagnóstico, no mensaje de usuario.
    case failed(operation: String)
}

/// Persistencia local en JSON (CAP-1, CAP-9) — AD-9, AD-10, AD-16.
///
/// Cubre **cuatro ficheros, cada uno con un único dueño en la aplicación** (AD-16):
/// `activeSession.json`, el snapshot de la sesión viva, que solo escribe `SessionStore`;
/// `settings.json`, los ajustes persistentes, que estrena la 2.2 y solo escribe
/// `SettingsStore`; `sessions.json`, el historial de caminatas cerradas, que estrena la 5.1 y
/// solo escribe `HistoryStore`; y `achievements.json` —el del **sandbox**, no el catálogo del
/// bundle—, cuyo dueño es `AchievementsStore` y cuyo contenido escribe con criterio la 3.2.
///
/// Es **un solo puerto** y no cuatro: AD-10 fija un conjunto cerrado de 11 y `StoragePort` es
/// "persistencia local". Que cada fichero tenga su dueño no lo hace estructural aquí, así que
/// lo comprueba `Scripts/check-project-shape.sh` (sección 9), que sabe qué fichero de
/// `Application/` puede llamar a qué método.
///
/// **`nil` no es un error de lectura, y confundirlos cuesta datos** (B-1). `nil` es "aquí no hay
/// nada que perder" y deja escribir —es la primera instalación—; un error es "hay algo que no
/// pude leer" y **no** deja escribir. Vale para los cuatro ficheros.
///
/// **Síncrono a propósito**, y ahora con un número detrás. Hasta la 5.1 la justificación era que
/// "los dos ficheros ocupan unos cientos de bytes", y con el historial deja de ser cierto: un
/// registro cerrado ronda los 300 B de JSON, así que ~1.500 caminatas —diez años a tres por
/// semana— son unos **450 KB** que se reescriben enteros en el hilo principal **una vez por
/// caminata**, no por muestra. Eso son milisegundos y se queda síncrono. El umbral a partir del
/// cual habría que revisarlo está anotado en `deferred-work.md`: **~5.000 registros (≈1,5 MB)**.
public protocol StoragePort: Sendable {

    // MARK: - Snapshot de la sesión viva (`SessionStore`)

    /// El snapshot guardado, o `nil` si no hay ninguno. Un fichero ilegible se aparta y
    /// lanza `malformed` o `unsupportedSchemaVersion`.
    func loadActiveSession() throws(StorageError) -> ActiveSessionSnapshot?

    /// Sustituye el snapshot de forma atómica: o queda el anterior entero, o el nuevo.
    func saveActiveSession(_ snapshot: ActiveSessionSnapshot) throws(StorageError)

    /// Borra el snapshot al finalizar. Sin snapshot no hace nada.
    func clearActiveSession() throws(StorageError)

    /// Aparta el snapshot que el dominio rechazó (rangos inválidos): deja de restaurarse,
    /// pero no se destruye. Sin snapshot no hace nada.
    func setAsideActiveSession() throws(StorageError)

    // MARK: - Ajustes (`SettingsStore`, 2.2)

    /// Los ajustes guardados, o `nil` si el fichero no existe todavía (primera vez).
    ///
    /// Un fichero ilegible se aparta —como el snapshot, nunca se destruye— y lanza
    /// `malformed` o `unsupportedSchemaVersion`; uno de un esquema **más nuevo** lanza
    /// `unsupportedSchemaVersion` y se queda donde está. Quien llama parte de
    /// `AppSettings.defaults`: unos ajustes corruptos no pueden costar una caminata.
    ///
    /// **`nil` y un error no son lo mismo, y confundirlos cuesta los ajustes.** `nil` es "no
    /// hay nada que perder" y deja escribir; un error es "hay algo que no se pudo leer" y no
    /// (B-1).
    func loadSettings() throws(StorageError) -> AppSettings?

    /// Sustituye los ajustes de forma atómica: o quedan los anteriores enteros, o los nuevos.
    func saveSettings(_ settings: AppSettings) throws(StorageError)

    // MARK: - Historial de caminatas cerradas (`HistoryStore`, 5.1)

    /// El historial guardado, o `nil` si `sessions.json` no existe todavía (primera vez).
    ///
    /// Los registros vienen **en el orden del fichero**; ordenarlos para pintarlos es de quien
    /// pinta (5.2). Un fichero ilegible se aparta —nunca se destruye— y lanza `malformed`; uno de
    /// un esquema **más nuevo** se deja intacto y lanza `unsupportedSchemaVersion`.
    ///
    /// **`nil` y un error no son lo mismo, y aquí cuesta más que en ningún otro fichero.** La
    /// configuración se rehace; el historial **no es reproducible** y CAP-9 lo promete
    /// garantizado, así que un error de lectura bloquea la escritura *y* se avisa en pantalla.
    func loadSessions() throws(StorageError) -> [SessionRecord]?

    /// Sustituye el historial completo de forma atómica: o queda el anterior entero, o el nuevo.
    ///
    /// Se reescribe el fichero entero porque la atomicidad de AD-9 es **por fichero** (temporal +
    /// `rename`): no hay "añadir una línea" que no pueda dejar el fichero a medias.
    func saveSessions(_ sessions: [SessionRecord]) throws(StorageError)

    // MARK: - Estado de los logros (`AchievementsStore`, 5.1 · contenido de la 3.2)

    /// El estado de los logros guardado, o `nil` si `achievements.json` no existe todavía.
    ///
    /// **Es el fichero del sandbox, no el catálogo del bundle**, que se llama igual y es
    /// contenido congelado (AD-5). Mismas reglas de lectura que el historial.
    func loadAchievements() throws(StorageError) -> [AchievementUnlock]?

    /// Sustituye el estado de los logros de forma atómica.
    func saveAchievements(_ achievements: [AchievementUnlock]) throws(StorageError)
}
