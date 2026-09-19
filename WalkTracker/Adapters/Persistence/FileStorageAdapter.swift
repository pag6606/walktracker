import Domain
import Foundation

/// `StoragePort` sobre ficheros JSON en Application Support (CAP-1, CAP-9) — AD-9, AD-10,
/// AD-16.
///
/// Es **un puerto con dos ficheros**, cada uno con su adapter y su dueño en la aplicación:
///
/// - `activeSession.json` — `ActiveSessionFileAdapter`, escrito solo por `SessionStore`;
/// - `settings.json` — `SettingsFileAdapter`, escrito solo por `SettingsStore` (2.2).
///
/// El puerto es uno porque AD-10 fija un conjunto cerrado de 11 y "persistencia local" es una
/// capacidad, no un fichero. Que cada dueño llame solo a sus métodos no lo impide el
/// compilador: lo comprueba `Scripts/check-project-shape.sh` (sección 9).
///
/// Este tipo no hace nada más que repartir: el formato y el disco son de los dos adapters.
struct FileStorageAdapter: StoragePort {

    let activeSession: ActiveSessionFileAdapter
    let settings: SettingsFileAdapter

    /// - Parameter directory: Application Support en la app, uno temporal en los tests. Los
    ///   dos ficheros viven en el mismo sitio.
    init(directory: URL = .applicationSupportDirectory) {
        activeSession = ActiveSessionFileAdapter(directory: directory)
        settings = SettingsFileAdapter(directory: directory)
    }

    // MARK: - Snapshot de la sesión viva

    func loadActiveSession() throws(StorageError) -> ActiveSessionSnapshot? {
        try activeSession.loadActiveSession()
    }

    func saveActiveSession(_ snapshot: ActiveSessionSnapshot) throws(StorageError) {
        try activeSession.saveActiveSession(snapshot)
    }

    func clearActiveSession() throws(StorageError) {
        try activeSession.clearActiveSession()
    }

    func setAsideActiveSession() throws(StorageError) {
        try activeSession.setAsideActiveSession()
    }

    // MARK: - Ajustes

    func loadSettings() throws(StorageError) -> AppSettings? {
        try settings.loadSettings()
    }

    func saveSettings(_ settings: AppSettings) throws(StorageError) {
        try self.settings.saveSettings(settings)
    }
}
