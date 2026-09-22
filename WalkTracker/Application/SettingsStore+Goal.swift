import Domain
import Foundation

/// La meta semanal (3.1, CAP-7, FR-10): la intención de fijar lo que Paul teclea, el progreso
/// que pinta el anillo y la decisión de si toca celebrar.
///
/// **Es el molde de la 2.3, copiado a propósito** (`SettingsStore+Stride.swift`): un resultado
/// observable con sus causas de rechazo separadas, un botón Guardar explícito, una vuelta atrás
/// aparte y un mensaje que se apaga al escribir y al salir de la pantalla. Lo que cambia es el
/// campo; el patrón no se reinventa.
///
/// **Y es además la mitad de aplicación del `GoalEngine`.** El cálculo es puro y vive en
/// `Domain/Engines/WeeklyProgress.swift` porque lo ejecutan los 15 vectores de AD-6; aquí se
/// queda lo que no es cálculo: leer el historial, leer la meta y decidir si toca celebrar.
///
/// **El logro y la celebración son dos cosas distintas (AD-25, decisión D1 de Paul).**
/// `weekly_goal` es un desbloqueo **de por vida e irrevocable** —AD-5 congela el catálogo y el
/// spine lo declara la excepción que evalúa `GoalEngine`, no el cierre de sesión (AD-17)— y
/// **no produce celebración propia**. Quien celebra es siempre el anillo, **una vez por
/// semana**, con estado propio en `settings.json` (`lastGoalCelebratedWeek`). Así la primera
/// semana no celebra dos veces. La 3.2 y la 3.4 heredan esta regla.
///
/// Escribe `goalOutcome` (solo aquí) y, al aceptar, `settings` y `settings.json`.
extension SettingsStore {

    /// Lo que hay que contarle a Paul del último "Guardar" o "Usar el valor por defecto" de la
    /// meta. No lleva el texto: eso es de la capa que pinta.
    enum GoalOutcome: Equatable {

        /// Guardada. La meta no tiene rango de aviso: 3 km y 80 km son igual de suyos.
        case saved
        /// Se quitó la meta configurada: vuelve a mandar el valor por omisión de 10 km.
        case clearedToDefault
        /// El cambio vale para esta ejecución, pero **no quedó escrito**: el disco falló, o los
        /// ajustes que hay en disco no se pudieron leer y escribir encima los borraría (B-1).
        case notPersisted
        /// No se guardó nada y el fichero no cambió.
        case rejected(GoalRejection)

        /// El ajuste quedó escrito en `settings.json`.
        var isSaved: Bool {
            switch self {
            case .saved, .clearedToDefault: true
            case .notPersisted, .rejected: false
            }
        }
    }

    /// Por qué se rechazó. Cuatro causas porque merecen cuatro mensajes: "eso no es un número",
    /// "eso no cabe", "una meta tiene que ser mayor que cero" y "el mínimo es 1 km" no se
    /// corrigen igual.
    enum GoalRejection: Equatable {

        /// Campo vacío, `abc`, `,` suelta: no hay número que leer.
        case notANumber
        /// Son dígitos, pero tantos que desbordan a `inf`, o el texto trae `NaN`: un número que
        /// no es finito. Sin esta causa, 400 dígitos leerían "la meta tiene que ser mayor que
        /// cero", que manda a corregir lo que no está mal.
        case notFinite
        /// Hay número y es finito, pero no es una meta: `0` o negativo.
        case notPositive
        /// Es un positivo por debajo de `AppSettings.minimumWeeklyGoalKm` (decisión de Paul,
        /// 2026-09-21). **Tiene caso propio porque el mensaje tiene que decir cuál es el
        /// mínimo**: con `.notPositive`, un `0,5` leería "tiene que ser mayor que cero", que es
        /// falso.
        case belowMinimum(Double)
    }

    // MARK: - Lectura

    /// La meta configurada, o `nil` si Paul nunca la tocó (3.1). Quien pinta el anillo no lee
    /// esto: usa `resolvedWeeklyGoalKm`, que sabe qué hacer con el `nil`.
    var weeklyGoalKm: Double? { settings.weeklyGoalKm }

    /// La meta con la que se pinta el anillo: la configurada, o los 10 km por omisión.
    var resolvedWeeklyGoalKm: Double { settings.resolvedWeeklyGoalKm }

    /// La semana ISO local en la que el anillo celebró por última vez, o `nil` si nunca (AD-25).
    /// Vive en `settings.json`, no en memoria: relanzar la app no devuelve la celebración.
    var lastGoalCelebratedWeek: String? { settings.lastGoalCelebratedWeek }

    /// El progreso de esta semana, o **`nil` si el historial no se pudo leer**.
    ///
    /// El `nil` no es un detalle: con `sessions.json` ilegible la app funciona con el historial
    /// vacío, y un anillo a 0 % diría que Paul no ha caminado esta semana, que es exactamente lo
    /// que nadie sabe. Una magnitud ausente se representa como ausente, nunca como `0` (AD-22),
    /// y el aviso de la 5.1 sigue donde estaba.
    ///
    /// **Una caminata recuperada u huérfana suma aquí**, aunque no cuente para logros: son dos
    /// preguntas distintas y `SessionRecord.countsForAchievements` responde a la otra.
    var weeklyProgress: WeeklyProgress? {
        guard !history.readOutcome.isUnreadable else { return nil }
        return GoalEngine.weeklyProgress(
            records: history.records,
            goalKm: settings.resolvedWeeklyGoalKm,
            now: clock.now,
            calendar: clock.calendar
        )
    }

    // MARK: - Intenciones de la pantalla

    /// "Guardar" en la sección de meta semanal: parsea el texto, lo valida en la frontera y, si
    /// pasa, lo persiste.
    ///
    /// **Una meta inválida no toca el fichero.** No se normaliza, no se guarda a medias y el
    /// `settings.json` que hubiera se queda exactamente como estaba; lo único que cambia es
    /// `goalOutcome`, que es lo que la pantalla pinta en línea.
    func saveGoal(fromText text: String) {
        guard let kilometers = AppSettings.weeklyGoalKm(fromText: text) else {
            log.info("Meta semanal rechazada: el campo no contiene un número")
            goalOutcome = .rejected(.notANumber)
            return
        }
        guard AppSettings.isRepresentableGoalKm(kilometers) else {
            log.info("Meta semanal rechazada: el número no es finito")
            goalOutcome = .rejected(.notFinite)
            return
        }
        guard !AppSettings.isTooSmallGoalKm(kilometers) else {
            log.info("Meta semanal rechazada: por debajo del mínimo de \(AppSettings.minimumWeeklyGoalKm, privacy: .public) km")
            goalOutcome = .rejected(.belowMinimum(AppSettings.minimumWeeklyGoalKm))
            return
        }
        // La frontera se prueba sobre una copia y **antes** de tocar nada: un valor inválido no
        // llega a `save(applying:)`, así que no puede disparar una relectura ni una escritura.
        var probe = settings
        do {
            try probe.setWeeklyGoalKm(kilometers)
        } catch {
            log.info("Meta semanal rechazada en la frontera: \(String(describing: error), privacy: .public)")
            goalOutcome = .rejected(.notPositive)
            return
        }
        // El `change` va con su testigo, y no con un `try?` mudo. Ya está validada justo arriba,
        // así que aquí no puede fallar; si algún día la regla cambiara solo en la frontera, un
        // `_ = try? …` escribiría `settings.json` **sin la meta** y diría ".saved". Va dentro del
        // `change` para que, si la lectura se recupera en el reintento, la meta se escriba sobre
        // lo que hay en disco y no sobre los valores por omisión: es lo que salva la zancada y la
        // ventana de frases que el fichero ya tenía.
        var applied = false
        let persisted = save { settings in
            do {
                try settings.setWeeklyGoalKm(kilometers)
                applied = true
            } catch {
                applied = false
            }
        }
        guard applied else {
            log.error("La meta pasó la frontera sobre una copia y la rechazó al aplicarla: no se dice que se guardó")
            goalOutcome = .rejected(.notPositive)
            return
        }
        goalOutcome = persisted ? .saved : .notPersisted
    }

    /// "Usar 10 km" en Ajustes: quita la meta configurada y vuelve al valor por omisión.
    ///
    /// Es la misma vuelta atrás que la zancada estrenó en la 2.3 y por la misma razón: vaciar el
    /// campo se **rechaza**, así que sin esta acción una meta tecleada mal no se podría deshacer.
    ///
    /// Sin nada que quitar no escribe nada: apaga el mensaje anterior y se acabó.
    func clearGoal() {
        guard settings.weeklyGoalKm != nil else {
            log.info("Volver a la meta por defecto sin meta que quitar: no se escribe nada")
            goalOutcome = nil
            return
        }
        goalOutcome = save { $0.clearWeeklyGoalKm() } ? .clearedToDefault : .notPersisted
    }

    /// Paul vuelve a escribir en el campo: el mensaje anterior ya no habla de lo que hay en
    /// pantalla, así que se apaga.
    func goalEditingDidChange() {
        guard goalOutcome != nil else { return }
        goalOutcome = nil
    }

    /// Ajustes se va de pantalla: el mensaje era de **aquella** pulsación y no sobrevive a la
    /// salida, igual que el de la zancada.
    func goalScreenDidDisappear() {
        guard goalOutcome != nil else { return }
        goalOutcome = nil
    }

    /// La semana puede haber cambiado debajo: la app vuelve de segundo plano, o lleva abierta
    /// desde antes del lunes.
    ///
    /// Hace dos cosas: mueve `goalRefreshToken`, que es lo que obliga a la pantalla a **repintar**
    /// el anillo con la semana de ahora —`clock.now` no es estado observable, así que sin esto
    /// nada la haría recalcular—, y vuelve a mirar si toca celebrar.
    ///
    /// **Lo que NO cubre, y está registrado:** la app abierta en Inicio cruzando la medianoche del
    /// domingo **sin** ningún cambio de fase de escena. Ahí no hay nada que despierte a nadie, y
    /// cerrarlo pediría un temporizador vivo; está en `deferred-work.md` con su destino.
    func weekMayHaveChanged() {
        goalRefreshToken &+= 1
        goalRingDidUpdate()
    }

    // MARK: - El anillo llega al 100 % (AD-25)

    /// El anillo ha pintado el progreso de la semana: si la meta está cumplida, se registra lo
    /// que hay que registrar.
    ///
    /// Hace **dos cosas que no son la misma** (AD-25):
    ///
    /// 1. Desbloquea `weekly_goal`, que es **de por vida e irrevocable** y por tanto se hace una
    ///    sola vez en toda la vida de la app. Lo escribe su dueño, `AchievementsStore`, por su
    ///    intención (AD-16).
    /// 2. Marca la semana como celebrada, **como mucho una vez por semana**. Refrescar la
    ///    pantalla, volver a Inicio o relanzar la app no vuelven a disparar nada, porque la
    ///    semana celebrada vive en `settings.json` y no en memoria.
    ///
    /// - Returns: `true` **la primera vez de cada semana** que la meta aparece cumplida. Los dos
    ///   canales de celebración cuelgan de ese mismo punto: la háptica (4.1) y el aviso visible
    ///   (3.4), este último a través de `showsGoalCelebration`, que es estado observable **porque
    ///   los dos llamadores descartan este `Bool`** (decisión D1 de la 3.4). El valor se conserva
    ///   para quien quiera saber si esta llamada celebró — hoy, los tests.
    @discardableResult
    func goalRingDidUpdate() -> Bool {
        // Sin historial legible no se sabe si la meta está cumplida, así que no se celebra ni se
        // desbloquea nada: `weeklyProgress` ya devuelve `nil` en ese caso.
        guard let progress = weeklyProgress, progress.isComplete else { return false }

        // El desbloqueo es de por vida: se intenta siempre que la meta esté cumplida, también en
        // semanas ya celebradas. Es idempotente y no escribe si ya estaba. **Su fallo no
        // cancela la celebración**: son dos cosas distintas (AD-25) y con `achievements.json`
        // ilegible el anillo sigue estando al 100 %.
        if !achievements.unlockWeeklyGoal(at: clock.now) {
            log.info("El desbloqueo de weekly_goal no se escribió en esta llamada: o ya estaba, o el fichero de logros no se puede escribir")
        }

        let week = GoalEngine.weekKey(for: clock.now, calendar: clock.calendar)
        guard !week.isEmpty, settings.lastGoalCelebratedWeek != week else { return false }
        // Si el disco falla, se celebra igual y **dentro de esta ejecución no se repite**:
        // `SettingsStore.save(applying:)` aplica el cambio en memoria aunque no llegue a escribir.
        // Lo que no sobrevive es al relanzar, y entonces se celebra una segunda vez — que es el
        // lado correcto del error: celebrar dos veces molesta, no celebrar nunca rompe la promesa.
        if !save(applying: { $0.setLastGoalCelebratedWeek(week) }) {
            log.error("La semana celebrada no quedó escrita: vale para esta ejecución y al relanzar se celebrará otra vez")
        }
        // El canal de feedback de la meta (4.1, CAP-12). Va **donde se decide que se celebra**,
        // no donde se pinta: la sección 10 del gate prohíbe `CoreHaptics` en `WalkTracker/UI/`, y
        // los dos entrantes de esta función —`HomeView` al pintar el anillo y
        // `weekMayHaveChanged()` al volver de background— comparten este único punto, así que la
        // meta vibra una vez por semana y no una por repintado.
        //
        // `soundEnabled: false` es la decisión D1: la preferencia de sonido es de la 4.2.
        feedback.fire(.goal, soundEnabled: false)
        // Y la mitad **visible** (3.4, D1), que es estado observable y no este `return`: los dos
        // llamadores descartan el `Bool`, así que una celebración colgada de él se perdería al
        // cumplir la meta con la app en otra pestaña — que es lo que pasa cuando quien llama es
        // `weekMayHaveChanged()` al volver de segundo plano. El aviso espera a que haya dónde
        // mostrarlo y lo apaga `dismissGoalCelebration()`.
        //
        // La háptica de arriba y esto son **el mismo suceso celebrado por dos canales**, no dos
        // decisiones: por eso comparten este único punto, el mismo que garantiza "una vez por
        // semana".
        showsGoalCelebration = true
        log.info("Meta semanal cumplida por primera vez esta semana: el anillo celebra")
        return true
    }

    /// El aviso de meta cumplida se va: lo tocaron, o venció su tiempo.
    ///
    /// **Las dos salidas son la misma intención**, como en el overlay de la frase (2.2): la vista
    /// no apaga el estado, lo pide. Y apagarlo **no descelebra nada** —la semana ya quedó marcada
    /// en `settings.json`—, así que volver a Inicio después no vuelve a encenderlo.
    func dismissGoalCelebration() {
        guard showsGoalCelebration else { return }
        showsGoalCelebration = false
    }
}
