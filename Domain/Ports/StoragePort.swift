import Foundation

/// Por qué el almacenamiento local no pudo leer o escribir (AD-9, AD-10). Un adapter
/// nunca deja escapar un error crudo de `FileManager` ni de `JSONDecoder`.
public enum StorageError: Error, Equatable, Sendable {
    /// El fichero existe pero no es JSON o no tiene la forma del esquema (el `TypeError`
    /// de `restoreV3Session`). El adapter ya lo apartó: no se destruye.
    case malformed(String)
    /// `schemaVersion` desconocido. El adapter ya lo apartó, como un ilegible.
    case unsupportedSchemaVersion(Int)
    /// El sistema de ficheros falló durante `operation`. Diagnóstico, no mensaje de usuario.
    case failed(operation: String)
}

/// Persistencia local en JSON (CAP-1, CAP-9) — AD-9, AD-10, AD-16.
///
/// Cubre dos ficheros, **cada uno con un único dueño en la aplicación** (AD-16):
/// `activeSession.json`, el snapshot de la sesión viva, que solo escribe `SessionStore`; y
/// `settings.json`, los ajustes persistentes, que estrena la 2.2 y solo escribe
/// `SettingsStore`. El historial y los logros llegan con la 5.1.
///
/// Es **un solo puerto** y no dos: AD-10 fija un conjunto cerrado de 11 y `StoragePort` es
/// "persistencia local". Que cada fichero tenga su dueño no lo hace estructural aquí, así que
/// lo comprueba `Scripts/check-project-shape.sh` (sección 9), que sabe qué fichero de
/// `Application/` puede llamar a qué método.
///
/// Síncrono a propósito: los dos ficheros ocupan unos cientos de bytes, y así cada transición
/// queda guardada antes de la siguiente.
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
    /// `malformed` o `unsupportedSchemaVersion`. Quien llama parte de `AppSettings.defaults`:
    /// unos ajustes corruptos no pueden costar una caminata.
    func loadSettings() throws(StorageError) -> AppSettings?

    /// Sustituye los ajustes de forma atómica: o quedan los anteriores enteros, o los nuevos.
    func saveSettings(_ settings: AppSettings) throws(StorageError)
}
