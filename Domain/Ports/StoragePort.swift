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
/// Por ahora solo cubre el snapshot de la sesión viva, `activeSession.json`; el historial,
/// los logros y los ajustes llegan con la 5.1. Su **único** escritor es `SessionStore`
/// (AD-16): nadie más llama a estos métodos.
///
/// Síncrono a propósito: el snapshot ocupa unos cientos de bytes, y así cada transición
/// queda guardada antes de la siguiente.
public protocol StoragePort: Sendable {
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
}
