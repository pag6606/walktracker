import Domain
import Foundation
import OSLog

/// Único dueño de `settings.json` (AD-16, 2.2). Nadie más lee ni escribe los ajustes: quien
/// los necesita se los pide a este store, como quien necesita la sesión se la pide a
/// `SessionStore`.
///
/// Lo estrenó la 2.2 con la ventana de frases recientes (`recentQuoteIds`), la 2.3 le añadió
/// la zancada configurada (`SettingsStore+Stride.swift`) y la 3.1 la meta semanal
/// (`SettingsStore+Goal.swift`); el sonido llega con la 4.2. Cada una añade su campo a
/// `AppSettings` y su intención aquí.
///
/// **Y desde la 3.1 tiene tres colaboradores, que no son suyos.** El historial, el estado de
/// los logros y el reloj entran por el init porque la meta semanal no se puede responder solo
/// con `settings.json`: el anillo suma las caminatas de la semana (`HistoryStore`), la semana la
/// define el `AppCalendar` de AD-19 (`ClockPort`) y cumplir la meta desbloquea `weekly_goal`
/// (`AchievementsStore`). Lo que este store aporta es **la decisión**: leer la meta, leer el
/// historial y decidir si toca celebrar — el cálculo es puro y vive en `GoalEngine` (AD-3), y
/// cada fichero lo sigue escribiendo su único dueño por sus intenciones (AD-16, sección 9b del
/// gate). La celebración semanal (`lastGoalCelebratedWeek`) es estado de ESTE fichero, y por eso
/// la decisión vive donde vive (AD-25).
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
/// **Y tampoco cuesta los ajustes** (B-1). Partir de los valores por omisión es lo correcto
/// para seguir andando, pero escribirlos encima de un fichero que sigue ahí y no se pudo leer
/// borra lo que contenía. Por eso la lectura deja constancia de **cuál** de los tres casos
/// ocurrió (`ReadOutcome`) y `save(applying:)` no escribe sin una lectura buena detrás.
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

    /// Cómo fue el último "Guardar" de la meta semanal, o `nil` si no hay nada que decir (3.1).
    ///
    /// Vive aquí por la misma razón que `strideOutcome` —una extensión de Swift no puede
    /// almacenar— y lo escriben solo las intenciones de `SettingsStore+Goal.swift`.
    var goalOutcome: GoalOutcome?

    /// La meta semanal se acaba de cumplir **por primera vez esta semana** y su aviso visible
    /// todavía no se ha descartado (3.4).
    ///
    /// **Es la mitad observable de una señal que antes era solo un valor de retorno.**
    /// `goalRingDidUpdate()` devuelve `true` la primera vez de cada semana, y sus dos llamadores
    /// —`HomeView` al pintar el anillo y `weekMayHaveChanged()` al volver de segundo plano—
    /// **descartaban el `Bool`**. Con la celebración colgando de ese retorno, cumplir la meta con
    /// la app en otra pestaña se habría perdido sin celebrar, que es justo el caso más probable:
    /// `weekMayHaveChanged()` se llama al volver a primer plano. Así el aviso **espera a que haya
    /// dónde mostrarlo** en vez de morir con la llamada.
    ///
    /// Es el molde de `SessionStore.showsRecoveredNotice` (1.6): lo enciende quien decide que se
    /// celebra y lo apaga una intención, `dismissGoalCelebration()`. La vista no lo escribe
    /// (sección 6 del gate).
    ///
    /// **No sobrevive al relanzamiento a propósito.** Vive en memoria, no en `settings.json`: la
    /// semana celebrada sí es persistente (`lastGoalCelebratedWeek`) y es ella quien impide
    /// celebrar dos veces; esto es solo el aviso que está en pantalla ahora.
    var showsGoalCelebration = false

    /// Cambia cada vez que la semana **puede** haber cambiado debajo (3.1).
    ///
    /// **Existe porque `ClockPort.now` no es estado observable.** `weeklyProgress` se recalcula
    /// cuando cambian los ajustes o el historial, pero no cuando cambia la hora: con la app
    /// abierta o en segundo plano cruzando el lunes a las 00:00 locales, el anillo seguiría
    /// pintando la semana pasada y la celebración de la nueva no se dispararía nunca. Quien lo
    /// lee obliga a repintar; quien lo mueve es `weekMayHaveChanged()`.
    var goalRefreshToken: Int = 0

    /// Cómo fue la última lectura de `settings.json`, y por tanto si hay algo en disco que una
    /// escritura destruiría (B-1, hallazgo D1 de la retro del Epic 2).
    ///
    /// **Son tres casos, no uno.** Los tres acababan en `AppSettings.defaults` sin dejar
    /// rastro en el objeto, así que la primera escritura —la de la frase, al pulsar "Iniciar
    /// caminata"— no tenía cómo saber que estaba escribiendo encima de unos ajustes que
    /// seguían enteros en disco.
    enum ReadOutcome: Equatable {

        /// Había fichero y se leyó entero: lo que hay en memoria viene de él.
        case loaded
        /// No hay `settings.json` todavía (primera instalación). **No hay nada que perder.**
        case absent
        /// Hay algo y no se pudo interpretar: un fallo del sistema de ficheros, un esquema
        /// del futuro o un ilegible. Lo que hay en memoria son los valores por omisión, que
        /// **no representan lo que hay en disco**.
        case unreadable(StorageError)

        /// Se puede escribir sin destruir nada: o se leyó lo que había, o no había nada.
        ///
        /// "Sin fichero" tiene que dejar escribir, o la primera instalación no guardaría nunca.
        var allowsWriting: Bool {
            switch self {
            case .loaded, .absent: true
            case .unreadable: false
            }
        }
    }

    /// Qué se sabe de lo que hay en disco. Lo escribe solo `load()`.
    ///
    /// Acceso de módulo, como el resto del estado del store: fuera de `Application/` lo hace
    /// cumplir la sección 6 del gate.
    private(set) var readOutcome: ReadOutcome = .absent

    @ObservationIgnored let storage: any StoragePort
    /// Dueño de `sessions.json` (AD-16, 5.1). De él sale la suma del anillo, y se le piden
    /// intenciones y lecturas: escribirlo es cosa suya (sección 9b del gate).
    @ObservationIgnored let history: HistoryStore
    /// Dueño de `achievements.json` del sandbox (AD-16, 5.1). Aquí solo se le pide desbloquear
    /// `weekly_goal` cuando la meta se cumple (AD-25).
    @ObservationIgnored let achievements: AchievementsStore
    /// El reloj y el `AppCalendar` de AD-19: la semana del anillo no se calcula con otro.
    @ObservationIgnored let clock: any ClockPort
    /// Háptica y sonido de sistema (CAP-12, AD-10). Aquí solo se dispara la meta cumplida, la
    /// primera vez de cada semana (`goalRingDidUpdate()`).
    ///
    /// **Obligatorio y sin valor por omisión**, como los tres de arriba y por la lección de la
    /// 3.1: un colaborador con defecto se olvida en el composition root sin que nada falle. El
    /// olvido aquí sería una meta que se cumple en silencio, y ningún test lo diría.
    @ObservationIgnored let feedback: any FeedbackPort
    @ObservationIgnored let log = Logger(subsystem: "com.walktracker.app", category: "SettingsStore")

    /// El historial y los logros **se inyectan, no se construyen aquí**, y eso no es estilo: un
    /// dueño es un fichero **y una sola instancia**. Construirlos por omisión —que es como
    /// nacieron mientras se escribía la 3.1— crea un segundo lector de `sessions.json`, y leer
    /// tiene efecto: un historial ilegible lo **aparta** el primero que lo lea, así que el
    /// segundo encuentra "no hay fichero" y el aviso de la 5.1 desaparece. Lo cazó
    /// `HistoryStorePersistenceTests`, y por eso el compilador ya no deja repetirlo.
    ///
    /// **Un test que toque la meta semanal tiene que pasar su `ClockStub`.** Con el reloj por
    /// omisión, la semana del anillo la fija el día en que se ejecute la suite, y un test así no
    /// es un test: es un calendario.
    init(
        storage: any StoragePort,
        history: HistoryStore,
        achievements: AchievementsStore,
        feedback: any FeedbackPort,
        clock: any ClockPort = SystemClock()
    ) {
        self.storage = storage
        self.history = history
        self.achievements = achievements
        self.feedback = feedback
        self.clock = clock
        self.settings = .defaults
        load()
    }

    /// Lee `settings.json` y **deja constancia de cuál de los tres casos ocurrió**: no hay
    /// fichero, se leyó, o hay algo que no se pudo interpretar.
    ///
    /// En los tres se sigue con unos ajustes usables —sin fichero y sin lectura, los valores
    /// por omisión—, porque perder la configuración no puede impedir caminar. Lo que cambia
    /// es que ahora queda escrito en `readOutcome`, y eso es lo que impide que la siguiente
    /// escritura borre lo que no se supo leer.
    ///
    /// **El log distingue los tres casos**, porque no distinguirlos fue la causa raíz: el
    /// mismo `AppSettings.defaults` en memoria tapaba a la vez la primera instalación, un
    /// error transitorio de disco y un fichero de un esquema más nuevo.
    ///
    /// Se llama al construir el store y, una sola vez más, antes de bloquear una escritura
    /// (`reloadBeforeWriting()`).
    ///
    /// - Returns: `true` si detrás de lo que queda en memoria hay una lectura buena.
    @discardableResult
    private func load() -> Bool {
        do {
            guard let stored = try storage.loadSettings() else {
                settings = .defaults
                readOutcome = .absent
                log.info("Sin settings.json todavía: se parte de los ajustes por omisión y se puede escribir")
                return true
            }
            settings = stored
            readOutcome = .loaded
            return true
        } catch {
            readOutcome = .unreadable(error)
            // Un `catch` por caso no valdría: Swift no comprueba que los `catch` cubran el
            // enum, así que la exhaustividad —y con ella el tercer mensaje del día que alguien
            // añada un caso— la sostiene el `switch`.
            switch error {
            case .failed(let operation):
                log.error("No se pudieron leer los ajustes (\(operation, privacy: .public)); el fichero sigue en su sitio y NO se escribirá encima hasta poder leerlo")
            case .unsupportedSchemaVersion(let version):
                log.error("settings.json es de un esquema (\(version, privacy: .public)) que esta versión no sabe leer; se parte de los valores por omisión y NO se escribe encima")
            case .malformed(let detail):
                log.error("settings.json ilegible, apartado por el adapter: \(detail, privacy: .public); se parte de los valores por omisión")
            }
            return false
        }
    }

    /// Registra la frase que se acaba de mostrar: entra al final de la ventana, que se recorta
    /// al tope de `MotivationEngine.recentWindow` (FIFO), y los ajustes se guardan.
    ///
    /// El guardado no puede fallar hacia fuera: si el disco falla —o si los ajustes no se
    /// pudieron leer y por eso no se escribe—, la ventana en memoria ya está actualizada
    /// —dentro de esta ejecución no habrá repeticiones— y la siguiente escritura lo reintenta.
    ///
    /// **Esta es la escritura que destruía la configuración** (D1): `openSession()` la dispara
    /// en la primera caminata, sin que nadie esté mirando y sin nada que decidir. Ahora pasa
    /// por la misma puerta que las demás.
    func recordShownQuote(id: Int) {
        save { settings in
            settings.setRecentQuoteIds(MotivationEngine.updateRecentIds(settings.recentQuoteIds, selectedId: id))
        }
    }

    /// Aplica `change` a los ajustes y los escribe. Un fallo se registra y **no se propaga como
    /// error**, pero sí se devuelve: quien llama decide qué contarle a Paul.
    ///
    /// Devolver `Bool` en vez de tragarse el fallo es lo que impide que la pantalla diga
    /// "Zancada guardada. La siguiente caminata la usará." cuando el valor desaparece al
    /// relanzar. La ventana de frases (`recordShownQuote`) sí puede ignorarlo: no hay nadie
    /// mirando y la siguiente escritura lo reintenta.
    ///
    /// **Sin una lectura buena no se escribe** (B-1). Antes de bloquear se reintenta la
    /// lectura: un fallo transitorio se recupera solo, y entonces `change` se aplica **sobre lo
    /// que hay en disco**, no sobre los valores por omisión que el store arrastraba —por eso el
    /// cambio es un `change`, y no una mutación hecha antes de llamar aquí—. Lo que de verdad
    /// no se puede interpretar, un esquema del futuro, sigue fallando el reintento por
    /// definición y queda protegido mientras exista.
    ///
    /// Con la escritura bloqueada el cambio **sí se aplica en memoria**: la app sigue
    /// funcionando, la ventana de esta ejecución no repite frases y la zancada recalibrada vale
    /// para la siguiente caminata. Lo único que no ocurre es tocar el fichero.
    ///
    /// Acceso de módulo para que lo compartan las intenciones de `SettingsStore+Stride.swift`;
    /// sigue siendo el **único** sitio del producto que llama a `saveSettings` del puerto, y eso
    /// lo comprueba la **sección 9** del gate. Que `UI/` y `App/` no puedan llamar a `save()`
    /// —que ya no es `private`— lo comprueba la **sección 6**, que lo lleva en su lista de pasos
    /// internos: son dos comprobaciones distintas, y antes este comentario atribuía las dos a la
    /// 9, que solo mira las llamadas al puerto.
    ///
    /// - Parameter change: la mutación que se quiere persistir, aplicable **más de una vez y
    ///   sobre cualquier punto de partida**: puede recibir los ajustes que acaban de leerse del
    ///   disco en vez de los que había en memoria.
    /// - Returns: `true` si quedó escrito en `settings.json`.
    @discardableResult
    func save(applying change: (inout AppSettings) -> Void) -> Bool {
        let writable = readOutcome.allowsWriting || reloadBeforeWriting()
        change(&settings)
        guard writable else { return false }
        do {
            try storage.saveSettings(settings)
            return true
        } catch {
            log.error("No se pudieron guardar los ajustes: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// El reintento que convierte un fallo transitorio en un caso que se arregla solo.
    ///
    /// **No se bloquea para siempre.** Un fallo de lectura al arrancar es casi siempre de un
    /// instante; dejar el store sin escribir el resto de la ejecución convertiría un problema
    /// de un segundo en una sesión entera sin guardar nada. Y lo que no es transitorio —un
    /// esquema del futuro— vuelve a fallar aquí, que es justo lo que hay que proteger.
    ///
    /// - Returns: `true` si la lectura funcionó y ya se puede escribir.
    private func reloadBeforeWriting() -> Bool {
        log.info("Hay un cambio que guardar y la última lectura de los ajustes no fue buena: se reintenta leer antes de decidir")
        guard load() else {
            log.error("Los ajustes siguen sin poder leerse: no se escribe encima. El cambio vale para esta ejecución y el fichero se queda como está")
            return false
        }
        log.info("Los ajustes se leyeron al reintentar: el cambio se aplica sobre lo que hay en disco")
        return true
    }
}
