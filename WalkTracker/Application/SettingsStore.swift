import Domain
import Foundation
import OSLog

/// Único dueño de `settings.json` (AD-16, 2.2). Nadie más lee ni escribe los ajustes: quien
/// los necesita se los pide a este store, como quien necesita la sesión se la pide a
/// `SessionStore`.
///
/// Lo estrenó la 2.2 con la ventana de frases recientes (`recentQuoteIds`) y la 2.3 le añade
/// la zancada configurada (`SettingsStore+Stride.swift`); la meta semanal llega con el Epic 3
/// y el sonido con la 4.2. Cada una añade su campo a `AppSettings` y su intención aquí.
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
    ///
    /// Acceso de módulo, como el estado de `SessionStore`, para que lo compartan
    /// `SettingsStore*.swift`; fuera de `Application/` lo hace cumplir la sección 6 del gate,
    /// que prohíbe a `UI/` y `App/` tocar `…Store.settings`.
    var settings: AppSettings

    /// Ids de las frases mostradas recientemente, la más reciente al final (CAP-6).
    var recentQuoteIds: [Int] { settings.recentQuoteIds }

    /// Zancada recalibrada, o `nil` si Paul nunca la tocó (2.3). Quien abre una sesión no lee
    /// esto: llama a `resolvedStrideM(default:)`, que sabe qué hacer con el `nil`.
    var strideM: Double? { settings.strideM }

    /// Cómo fue el último "Guardar" de la zancada, o `nil` si no hay nada que decir (2.3).
    ///
    /// **Es estado observable del store, no de la vista** (sección 6 del gate): la pantalla lo
    /// pinta y no decide nada —ni qué es válido, ni qué mensaje toca—. Solo lo escriben las dos
    /// intenciones de `SettingsStore+Stride.swift`; la propiedad vive aquí porque una extensión
    /// de Swift no puede almacenar, igual que `SessionStore.quote` convive con
    /// `SessionStore+Motivation.swift`. Acceso de módulo por la misma razón que el estado de
    /// `SessionStore`: quien lo hace cumplir fuera de `Application/` es la sección 6 del gate.
    var strideOutcome: StrideOutcome?

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

    /// Escribe los ajustes. Un fallo se registra y **no se propaga como error**, pero sí se
    /// devuelve: quien llama decide qué contarle a Paul.
    ///
    /// Devolver `Bool` en vez de tragarse el fallo es lo que impide que la pantalla diga
    /// "Zancada guardada. La siguiente caminata la usará." cuando el disco falló y el valor
    /// desaparece al relanzar. La ventana de frases (`recordShownQuote`) sí puede ignorarlo: no
    /// hay nadie mirando y la siguiente escritura lo reintenta.
    ///
    /// Acceso de módulo para que lo compartan las intenciones de `SettingsStore+Stride.swift`;
    /// sigue siendo el **único** sitio del producto que llama a `saveSettings` del puerto, y eso
    /// lo comprueba la **sección 9** del gate. Que `UI/` y `App/` no puedan llamar a `save()`
    /// —que ya no es `private`— lo comprueba la **sección 6**, que lo lleva en su lista de pasos
    /// internos: son dos comprobaciones distintas, y antes este comentario atribuía las dos a la
    /// 9, que solo mira las llamadas al puerto.
    @discardableResult
    func save() -> Bool {
        do {
            try storage.saveSettings(settings)
            return true
        } catch {
            log.error("No se pudieron guardar los ajustes: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
