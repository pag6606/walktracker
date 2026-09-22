import Domain
import Foundation
import OSLog

/// El único sitio que conoce todas las capas. Construye los adapters y los entrega a
/// la aplicación y a la UI por sus puertos: nadie más resuelve una dependencia (AD-10).
///
/// Se puebla al entrar cada adapter en su historia. La 8.6 añade los cuatro de la capa
/// nativa extraída de `feature/flutter-substrate`.
@MainActor
struct CompositionRoot {

    /// El reloj y el calendario de la app llegan por puerto (AD-3, AD-19).
    let clock: any ClockPort
    /// Podómetro del coprocesador (CAP-2, CAP-3).
    let motion: any MotionPort
    /// Háptica y sonido de sistema (CAP-12).
    let feedback: any FeedbackPort
    /// Escritura de entrenamientos en Apple Salud (CAP-11).
    let health: any HealthPort
    /// Live Activity de la sesión (CAP-18).
    let liveActivity: any LiveActivityPort
    /// Ficheros JSON en Application Support (AD-9), cada uno con su dueño (AD-16): el snapshot de
    /// la sesión viva (`SessionStore`), los ajustes (`SettingsStore`), el historial de caminatas
    /// cerradas (`HistoryStore`, 5.1) y el estado de los logros (`AchievementsStore`, 5.1).
    let storage: any StoragePort
    /// Azar del sistema para elegir la frase del arranque (CAP-6, AD-10).
    let random: any RandomPort
    /// Ubicación aproximada para el clima (CAP-5), redondeada en el adapter.
    let location: any LocationPort
    /// Clima actual de Open-Meteo (CAP-5): la única llamada de red.
    let weather: any WeatherPort
    /// Catálogo de los 14 logros, ya validado (AD-5, CAP-8).
    let achievementCatalog: AchievementCatalog
    /// Constantes de fórmula de `formulas.json`, ya validadas.
    let formulas: Formulas
    /// Banco de las 100 frases, ya validado (CAP-6). **Vacío si el fichero falta o no
    /// valida**: aquí se degrada, no se termina.
    let quotes: QuoteBank
    /// Único dueño de `settings.json` (AD-16, 2.2).
    let settingsStore: SettingsStore
    /// Único dueño de `sessions.json` (AD-16, 5.1): el historial de caminatas cerradas.
    let historyStore: HistoryStore
    /// Único dueño de `achievements.json` **del sandbox** (AD-16, 5.1). No es el catálogo del
    /// bundle, que es `achievementCatalog` y es contenido congelado (AD-5).
    let achievementsStore: AchievementsStore
    /// Único escritor de la sesión (AD-7). Las vistas solo llaman a sus intenciones.
    let sessionStore: SessionStore

    init(
        clock: any ClockPort = SystemClock(),
        motion: any MotionPort = MotionAdapter(),
        feedback: any FeedbackPort = FeedbackAdapter(),
        health: any HealthPort = HealthAdapter(),
        liveActivity: any LiveActivityPort = LiveActivityAdapter(),
        storage: any StoragePort = FileStorageAdapter(),
        location: (any LocationPort)? = nil,
        weather: any WeatherPort = OpenMeteoAdapter(),
        random: any RandomPort = SystemRandom(),
        achievementCatalog: AchievementCatalog? = nil,
        formulas: Formulas? = nil,
        quotes: QuoteBank? = nil
    ) {
        self.clock = clock
        self.motion = motion
        self.feedback = feedback
        self.health = health
        self.liveActivity = liveActivity
        self.storage = storage
        self.random = random
        let location = location ?? LocationAdapter()
        self.location = location
        self.weather = weather
        self.achievementCatalog = achievementCatalog ?? Self.bundledAchievementCatalogOrTerminate()
        let formulas = formulas ?? Self.bundledFormulasOrTerminate()
        self.formulas = formulas
        let quotes = quotes ?? Self.bundledQuoteBankOrEmpty()
        self.quotes = quotes
        // El historial y los logros van primero desde la 3.1: los ajustes necesitan los dos
        // —el anillo suma las caminatas de la semana y cumplir la meta desbloquea
        // `weekly_goal`— y cada fichero conserva **una sola** instancia de su dueño (AD-16).
        // El orden entre los tres no tiene más misterio que ése: ninguno depende de los ajustes.
        let historyStore = HistoryStore(storage: storage)
        self.historyStore = historyStore
        let achievementsStore = AchievementsStore(storage: storage)
        self.achievementsStore = achievementsStore
        // Y los tres antes del store de sesión: la primera caminata ya necesita la ventana de
        // recientes, y `restoreOnLaunch()` consulta el historial para no archivar dos veces una
        // caminata que ya se guardó (5.1).
        let settingsStore = SettingsStore(
            storage: storage,
            history: historyStore,
            achievements: achievementsStore,
            clock: clock
        )
        self.settingsStore = settingsStore
        self.sessionStore = SessionStore(
            clock: clock,
            motion: motion,
            storage: storage,
            defaultStrideM: formulas.defaultStrideM,
            reconciliationTimeoutS: formulas.reconciliationTimeoutS,
            orphanSessionThresholdS: formulas.orphanSessionThresholdS,
            maxEstimableGapS: formulas.maxEstimableGapS,
            location: location,
            weather: weather,
            settings: settingsStore,
            history: historyStore,
            // **La misma instancia** que recibe el store de ajustes, no otra (AD-16): los dos
            // desbloquean logros —el anillo `weekly_goal`, el cierre los demás— y dos dueños del
            // mismo fichero serían dos lectores que no ven lo que escribe el otro.
            achievements: achievementsStore,
            achievementCatalog: self.achievementCatalog,
            quotes: quotes,
            random: random
        )
    }

    // MARK: - Catálogo de logros (AD-5)

    private static let log = Logger(subsystem: "com.walktracker.app", category: "AchievementCatalog")

    /// Lee y valida `achievements.json` de un bundle. Separado del arranque para que
    /// cada causa de rechazo sea comprobable sin matar el proceso de test.
    nonisolated static func loadAchievementCatalog(from bundle: Bundle) throws(AchievementCatalogError) -> AchievementCatalog {
        guard let url = bundle.url(forResource: "achievements", withExtension: "json") else {
            throw .malformed("achievements.json no está en el bundle \(bundle.bundleIdentifier ?? bundle.bundlePath)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .malformed("no se puede leer achievements.json: \(error.localizedDescription)")
        }
        return try AchievementCatalog.decode(from: data)
    }

    /// El catálogo de la app o nada: con un catálogo inválido **la app no arranca**
    /// (AD-5). No hay catálogo parcial ni vacío de reserva: degradar aquí es repetir
    /// en silencio el incidente del catálogo reteclado.
    private static func bundledAchievementCatalogOrTerminate() -> AchievementCatalog {
        do {
            return try loadAchievementCatalog(from: .main)
        } catch {
            log.fault("Catálogo de logros inválido: \(String(describing: error), privacy: .public)")
            fatalError("AD-5: el catálogo de logros no valida y la app no arranca — \(error)")
        }
    }

    // MARK: - Banco de frases (CAP-6)

    nonisolated private static let quotesLog = Logger(subsystem: "com.walktracker.app", category: "QuoteBank")

    /// Lee y valida `quotes.json` de un bundle. Separado del arranque, como el catálogo y las
    /// constantes, para que cada causa de rechazo sea comprobable.
    nonisolated static func loadQuoteBank(from bundle: Bundle) throws(QuoteBankError) -> QuoteBank {
        guard let url = bundle.url(forResource: "quotes", withExtension: "json") else {
            throw .malformed("quotes.json no está en el bundle \(bundle.bundleIdentifier ?? bundle.bundlePath)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .malformed("no se puede leer quotes.json: \(error.localizedDescription)")
        }
        return try QuoteBank.decode(from: data)
    }

    /// El banco de la app, o uno vacío. **Aquí se degrada** (decisión de Paul, 2026-09-19), a
    /// diferencia del catálogo de logros (AD-5): una frase que falta no cambia ninguna métrica
    /// ni ningún logro, y matar el arranque por ella sería desproporcionado. Sin banco no hay
    /// overlay y la caminata sigue, con el motivo en el log.
    ///
    /// El `bundle` es un parámetro por la misma razón que en `loadQuoteBank(from:)`: para que
    /// **la degradación**, y no solo el fallo de lectura, sea comprobable sin matar el proceso
    /// de test. Sin esa costura, sustituir este `catch` por el `fatalError` de AD-5 no rompería
    /// nada.
    nonisolated static func bundledQuoteBankOrEmpty(from bundle: Bundle = .main) -> QuoteBank {
        do {
            return try loadQuoteBank(from: bundle)
        } catch {
            quotesLog.error("Banco de frases inválido; las caminatas empiezan sin frase: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    // MARK: - Constantes de fórmula

    private static let formulasLog = Logger(subsystem: "com.walktracker.app", category: "Formulas")

    /// Lee y valida `formulas.json` de un bundle. Separado del arranque, como el
    /// catálogo, para que cada causa de rechazo sea comprobable sin matar el proceso.
    nonisolated static func loadFormulas(from bundle: Bundle) throws(FormulasError) -> Formulas {
        guard let url = bundle.url(forResource: "formulas", withExtension: "json") else {
            throw .malformed("formulas.json no está en el bundle \(bundle.bundleIdentifier ?? bundle.bundlePath)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .malformed("no se puede leer formulas.json: \(error.localizedDescription)")
        }
        return try Formulas.decode(from: data)
    }

    /// Las constantes de la app o nada: con una constante inválida **la app no
    /// arranca**. Una zancada de reserva escondería el fallo en cada distancia.
    private static func bundledFormulasOrTerminate() -> Formulas {
        do {
            return try loadFormulas(from: .main)
        } catch {
            formulasLog.fault("formulas.json inválido: \(String(describing: error), privacy: .public)")
            fatalError("formulas.json no valida y la app no arranca — \(error)")
        }
    }
}
