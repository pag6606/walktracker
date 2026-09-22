import Domain
import SwiftUI

/// La pestaña Logros (3.3, CAP-8, FR-8) — AD-5, AD-13, AD-14, AD-17, AD-22.
///
/// **Los 14, siempre.** No hay estado vacío: sin ninguna caminata se ve el grid completo en
/// bloqueado con sus progresos, que es lo que pide UX-DR5 y el criterio de aceptación de la
/// historia. Un `ContentUnavailableView` aquí escondería el catálogo justo el día en que más
/// sirve —el primero—, que es cuando enseña qué hay por conseguir.
///
/// **Aquí no se evalúa nada** (AD-17). Los logros se desbloquean en un único punto, al cerrar
/// una caminata (3.2); esta pantalla **solo lee**: ni desbloquea, ni escribe filas de progreso,
/// ni toca `achievements.json`. El progreso de los bloqueados se **calcula al pintar**, derivado
/// del historial (decisión D1 de la 3.3), así que nunca está viejo y borrar una caminata lo
/// recalcula solo (CAP-15). Calcular una barra no es evaluar.
///
/// **El catálogo y los logros llegan por su propio camino**, desde `CompositionRoot` y a través
/// de `RootView`, no colándose por `SessionStore`: la sección 6 del gate lo impide, y la 3.2
/// dejó escrito por qué —*"no hay razón para que una vista lea el catálogo a través del
/// store"*—. Son dos dueños distintos del mismo puerto, como los ajustes y el historial.
///
/// **Con `achievements.json` ilegible no se pinta todo como bloqueado.** El aviso lo dice arriba
/// y cada insignia lo dice también: no se sabe si está conseguida, y afirmar que falta sería
/// inventarse el dato (AD-22, y la misma doctrina con la que el anillo se niega a pintar un 0 %
/// sin historial). El historial ilegible es otra cosa: ahí el aviso ya lo da Inicio (5.1) y lo
/// que se pierde es el **progreso**, no el estado.
struct AchievementsView: View {

    /// El catálogo congelado de los 14 (AD-5), del bundle. **No es `achievements.json` del
    /// sandbox**: son dos ficheros con el mismo nombre en dos sitios distintos.
    let catalog: AchievementCatalog
    /// Dueño de `achievements.json` del sandbox (AD-16). Solo se le leen los desbloqueos y el
    /// resultado de la última lectura; la vista no escribe nada.
    let achievementsStore: AchievementsStore
    /// Dueño de `sessions.json` (AD-16, 5.1). De aquí sale el progreso de los bloqueados.
    let historyStore: HistoryStore
    /// El `AppCalendar` de AD-19, de `ClockPort.calendar`. Llega cableado desde la app: la vista
    /// no construye calendarios, y el grid y el anillo no pueden dar dos respuestas para el
    /// mismo día.
    let calendar: Calendar

    /// Dos columnas con el tamaño de texto por omisión (UX-DR5) y **una** con Dynamic Type de
    /// accesibilidad, sin ninguna condición escrita a mano: el mínimo escala con el texto, así
    /// que la rejilla se reacomoda sola en vez de recortar los nombres.
    @ScaledMetric(relativeTo: .headline) private var columnMinimum = AchievementBadge.columnMinimum

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    if achievementsStore.readOutcome.isUnreadable {
                        unreadableAchievementsNotice
                    }
                    grid
                }
                .padding(LayoutMetrics.margin)
            }
            .navigationTitle("Logros")
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: columnMinimum), spacing: Spacing.l, alignment: .top)],
            spacing: Spacing.l
        ) {
            // **En el orden del catálogo**, el mismo que recorre el motor al cerrar: la pantalla
            // no reordena por conseguidos primero, porque entonces una insignia cambiaría de
            // sitio al desbloquearse y el grid dejaría de ser un sitio donde buscar.
            ForEach(catalog.achievements, id: \.key) { definition in
                AchievementBadgeView(
                    definition: definition,
                    status: status(of: definition),
                    calendar: calendar
                )
            }
        }
    }

    /// El estado de un logro ahora mismo. La decisión es de `AchievementStatus.of(...)`, que es
    /// pura y tiene tests: aquí solo se le pasa de dónde sale cada cosa.
    private func status(of definition: AchievementDefinition) -> AchievementStatus {
        .of(
            definition,
            unlock: achievementsStore.unlock(forKey: definition.key),
            isUnreadable: achievementsStore.readOutcome.isUnreadable,
            sessions: historyStore.records,
            calendar: calendar
        )
    }

    /// "No se pudieron leer tus logros".
    ///
    /// Mismo tratamiento que el aviso de historial de Inicio (5.1) y por eso comparten vista;
    /// lo que cambia es la consecuencia, y el texto la dice: un logro conseguido **no se ha
    /// borrado** y no se escribirá encima de lo que no se pudo leer (B-1), así que lo que Paul
    /// gane mientras tanto tampoco se registra hasta que el fichero vuelva a leerse.
    private var unreadableAchievementsNotice: some View {
        UnreadableFileNotice(
            title: Text("No se pudieron leer tus logros", comment: "Título del aviso de la pantalla de Logros cuando `achievements.json` existe y no se ha podido leer."),
            message: Text("No se ha borrado nada. Mientras tanto no sabemos cuáles has conseguido, y no se escribirá encima de lo que no se pudo leer.", comment: "Cuerpo del aviso de la pantalla de Logros cuando el fichero de logros no se pudo leer: dice que no se ha perdido nada y por qué las insignias no dicen si están conseguidas.")
        )
    }
}
