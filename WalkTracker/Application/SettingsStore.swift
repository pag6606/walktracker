import Domain
import Foundation
import OSLog

/// Único dueño de `settings.json` (AD-16, 2.2). Nadie más lee ni escribe los ajustes: quien
/// los necesita se los pide a este store, como quien necesita la sesión se la pide a
/// `SessionStore`.
///
/// Lo estrena la 2.2 con la ventana de frases recientes (`recentQuoteIds`); la zancada
/// configurada llega con la 2.3, la meta semanal con el Epic 3 y el sonido con la 4.2. Cada
/// una añade su campo a `AppSettings` y su intención aquí.
///
/// **Se lee una vez, al construirlo.** Los ajustes hacen falta en el primer arranque de
/// sesión, así que no hay un `load()` que alguien pueda olvidarse de llamar. El fichero
/// ocupa unos cientos de bytes y la lectura es síncrona, igual que la del snapshot.
///
/// **Nunca cuesta una caminata.** Sin fichero se parte de `AppSettings.defaults`; con el
/// fichero corrupto, el adapter lo aparta —no lo destruye— y se parte igual de los valores
/// por omisión, con un `error` en el log. Un fallo de escritura se registra y el siguiente
/// guardado lo reintenta: la sesión sigue con los ajustes que ya tiene en memoria.
///
/// **Invariante:** solo este fichero llama a `loadSettings`/`saveSettings` del `StoragePort`,
/// y solo él escribe `settings`. Lo comprueba `Scripts/check-project-shape.sh` (sección 9).
@MainActor
@Observable
final class SettingsStore {

    /// Los ajustes en memoria. Es la copia de la que todo el mundo lee: el fichero solo se
    /// relee al construir el store.
    private(set) var settings: AppSettings

    /// Ids de las frases mostradas recientemente, la más reciente al final (CAP-6).
    var recentQuoteIds: [Int] { settings.recentQuoteIds }

    @ObservationIgnored let storage: any StoragePort
    @ObservationIgnored let log = Logger(subsystem: "com.walktracker.app", category: "SettingsStore")

    init(storage: any StoragePort) {
        self.storage = storage
        self.settings = .defaults
        load()
    }

    /// Lee `settings.json` una vez. Sin fichero, o con uno ilegible (que el adapter ya apartó),
    /// se queda con `AppSettings.defaults`: la ventana vacía, y la primera frase se elige de
    /// las 100.
    private func load() {
        do {
            guard let stored = try storage.loadSettings() else {
                log.info("Sin settings.json todavía: se parte de los ajustes por omisión")
                return
            }
            settings = stored
        } catch .failed(let operation) {
            log.error("No se pudieron leer los ajustes (\(operation, privacy: .public)); siguen en su sitio y se parte de los valores por omisión")
        } catch {
            log.error("settings.json ilegible, apartado: \(String(describing: error), privacy: .public)")
        }
    }

    /// Registra la frase que se acaba de mostrar: entra al final de la ventana, que se recorta
    /// al tope de `MotivationEngine.recentWindow` (FIFO), y los ajustes se guardan.
    ///
    /// El guardado no puede fallar hacia fuera: si el disco falla, la ventana en memoria ya
    /// está actualizada —dentro de esta ejecución no habrá repeticiones— y la siguiente
    /// escritura lo reintenta.
    func recordShownQuote(id: Int) {
        settings.setRecentQuoteIds(MotivationEngine.updateRecentIds(settings.recentQuoteIds, selectedId: id))
        save()
    }

    /// Escribe los ajustes. Un fallo se registra y no se propaga.
    private func save() {
        do {
            try storage.saveSettings(settings)
        } catch {
            log.error("No se pudieron guardar los ajustes: \(String(describing: error), privacy: .public)")
        }
    }
}
