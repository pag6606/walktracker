import Domain
import Foundation

/// `StoragePort` sobre ficheros JSON en Application Support (CAP-1, CAP-9) — AD-9, AD-10,
/// AD-16.
///
/// Es **un puerto con cuatro ficheros**, cada uno con su adapter y su dueño en la aplicación:
///
/// - `activeSession.json` — `ActiveSessionFileAdapter`, escrito solo por `SessionStore`;
/// - `settings.json` — `SettingsFileAdapter`, escrito solo por `SettingsStore` (2.2);
/// - `sessions.json` — `SessionHistoryFileAdapter`, escrito solo por `HistoryStore` (5.1);
/// - `achievements.json` — `AchievementsFileAdapter`, escrito solo por `AchievementsStore`
///   (5.1). Es el del **sandbox**; el catálogo homónimo vive en el bundle y no se toca (AD-5).
///
/// El puerto es uno porque AD-10 fija un conjunto cerrado de 11 y "persistencia local" es una
/// capacidad, no un fichero. Que cada dueño llame solo a sus métodos no lo impide el
/// compilador: lo comprueba `Scripts/check-project-shape.sh` (sección 9).
///
/// Este tipo no hace nada más que repartir: el formato y el disco son de los cuatro adapters.
struct FileStorageAdapter: StoragePort {

    let activeSession: ActiveSessionFileAdapter
    let settings: SettingsFileAdapter
    let sessions: SessionHistoryFileAdapter
    let achievements: AchievementsFileAdapter

    /// - Parameter directory: Application Support en la app, uno temporal en los tests. Los
    ///   cuatro ficheros viven en el mismo sitio, con cuatro `base` distintos: `JSONFileStore`
    ///   deriva de cada uno su nombre y su prefijo de apartado, así que no pueden colisionar.
    init(directory: URL = .applicationSupportDirectory) {
        activeSession = ActiveSessionFileAdapter(directory: directory)
        settings = SettingsFileAdapter(directory: directory)
        sessions = SessionHistoryFileAdapter(directory: directory)
        achievements = AchievementsFileAdapter(directory: directory)
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

    // MARK: - Historial

    func loadSessions() throws(StorageError) -> [SessionRecord]? {
        try sessions.loadSessions()
    }

    func saveSessions(_ sessions: [SessionRecord]) throws(StorageError) {
        try self.sessions.saveSessions(sessions)
    }

    // MARK: - Estado de los logros

    func loadAchievements() throws(StorageError) -> [AchievementUnlock]? {
        try achievements.loadAchievements()
    }

    func saveAchievements(_ achievements: [AchievementUnlock]) throws(StorageError) {
        try self.achievements.saveAchievements(achievements)
    }
}
