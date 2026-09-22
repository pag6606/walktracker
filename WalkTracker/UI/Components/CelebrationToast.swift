import Domain
import SwiftUI

/// El aviso transitorio con el que la app celebra (3.4, CAP-7, CAP-8, FR-7, FR-8): la meta
/// semanal cumplida y cada logro desbloqueado al cerrar una caminata.
///
/// **No bloquea nada, y eso es la historia entera.** No es modal, no detiene el cronómetro, no
/// tapa los controles y no impide tocar lo que hay debajo: se queda arriba, se va solo al vencer
/// su tiempo (`Celebration.noticeDuration`) o al tocarlo, y mientras tanto la caminata sigue
/// contando por debajo. Por eso **no lleva** `.isModal`, al revés que `QuoteOverlay`, que sí tapa
/// la pantalla entera a propósito.
///
/// **Vista tonta**, como `QuoteOverlay` y por la misma razón: recibe lo que dice y un
/// `onDismiss`, y no temporiza, no encola y no escribe estado. Quien lo presenta gobierna las dos
/// salidas —el toque y el vencimiento— hacia la **misma** intención, y es también quien anima su
/// entrada respetando Reduce Motion.
///
/// **No dispara háptica ni sonido.** Ese canal es del Epic 4 y ya está cableado desde la 4.1, en
/// la capa de aplicación: `feedback.fire(.goal, …)` en `SettingsStore+Goal.swift` y
/// `feedback.fire(.achievement, …)` en `SessionStore+History.swift`. Dispararlo aquí lo duplicaría
/// —dos vibraciones por el mismo suceso— y además es error de la sección 6 del gate.
///
/// **El emoji del logro es dato del catálogo, no chrome** (AD-5), así que se pinta `verbatim`, sin
/// pasar por el String Catalog; el de la meta es un símbolo del sistema, que sí es chrome. Es la
/// misma distinción que hace la insignia de la 3.3.
struct CelebrationToast: View {

    /// Lo que va a la izquierda del texto.
    ///
    /// Son dos casos porque son dos cosas distintas: el logro trae **su** emoji del catálogo
    /// congelado y la meta no tiene ninguno que traer —`weekly_goal` no produce celebración
    /// propia (AD-25)—, así que la suya es iconografía del sistema.
    enum Emblem: Equatable {

        /// Un emoji del catálogo de logros. Dato, no chrome.
        case emoji(String)
        /// Un símbolo de SF Symbols, teñido con el acento del entorno.
        case symbol(String)
    }

    let emblem: Emblem
    /// La línea principal: el nombre del logro o el titular de la meta.
    let title: Text
    /// La línea de abajo, que dice **qué ha pasado**: el título por sí solo no distingue un logro
    /// recién ganado de un nombre cualquiera.
    let message: Text
    /// Lo que VoiceOver lee del aviso entero, en una sola parada. Lo construyen las dos fábricas
    /// de abajo, que son funciones puras y tienen test.
    let spokenLabel: Text
    /// El toque: la misma intención que el vencimiento del tiempo.
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            icon
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                    .font(.subheadline.weight(.semibold))
                message
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Nunca se recorta: con el texto al máximo el aviso crece hacia abajo.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Surface.cardPaddingHorizontal)
        .padding(.vertical, Surface.cardPaddingVertical)
        // Material del sistema, no un color propio: el aviso se pone **encima** de lo que sea que
        // haya debajo —el anillo, la rejilla de métricas, el resumen— y tiene que separarse de
        // todos ellos. Es el mismo recurso que usa el overlay de la frase (AD-13).
        .background(.regularMaterial, in: .rect(cornerRadius: Radius.card))
        // Todo el aviso es el objetivo del toque, no solo su texto.
        .contentShape(.rect)
        .onTapGesture(perform: onDismiss)
        // Una celebración es **un** elemento: el emoji, el titular y su línea no son tres paradas.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(Text("Toca para descartar el aviso. Tu caminata sigue en curso.", comment: "Pista de VoiceOver del aviso de celebración (meta cumplida o logro desbloqueado): cómo se quita y que no detiene nada."))
        .accessibilityAction(.default, onDismiss)
    }

    @ViewBuilder
    private var icon: some View {
        switch emblem {
        case .emoji(let emoji):
            // Dato del catálogo (AD-5): ni se traduce ni se retoca.
            Text(verbatim: emoji)
                .font(.title)
        case .symbol(let name):
            Image(systemName: name)
                .font(.title)
                .foregroundStyle(.tint)
        }
        // El emoji del logro ya lo nombra la etiqueta de arriba; leerlo además haría que
        // VoiceOver dijera "medalla deportiva" antes del nombre del logro.
    }
}

// MARK: - Reduce Motion, decidido en un solo sitio

extension CelebrationToast {

    /// Cómo se anima la aparición, el relevo y la salida de un aviso, **según Reduce Motion**.
    ///
    /// **Con el ajuste activo es `nil`: sin animación, no un fundido más corto.** Lo pide el
    /// criterio de aceptación de la 3.4 y es el dialecto que ya usan el anillo (3.1), la insignia
    /// (3.3) y el overlay de la frase (2.2).
    ///
    /// **Es una función y no un ternario repetido en dos vistas** por dos razones. La primera es
    /// que esta decisión **no se puede probar renderizando** —no hay XCUITest (decisión D1 del
    /// 2026-09-20)— y sacada aquí sí se prueba, que es lo mismo que hizo `GoalRingView` con lo que
    /// VoiceOver dice del anillo. La segunda es que los dos avisos son **el mismo componente en
    /// dos superficies**: con el ternario escrito dos veces, arreglar uno dejaba el otro roto en
    /// verde.
    ///
    /// Esto **no unifica los dos dialectos del árbol**: los cuatro sitios de la 1.6, la 2.1 y la
    /// 2.2 que usan el fundido corto siguen como estaban, y su unificación sigue registrada en
    /// `deferred-work.md` con destino. Lo que comparten aquí son los **dos** sitios que esta
    /// historia añade.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .default
    }

    /// Cómo entra y sale el aviso, **según Reduce Motion**: `.identity` —aparece ya puesto— o un
    /// fundido. Es la otra mitad de la misma decisión que `animation(reduceMotion:)`, y va aparte
    /// porque SwiftUI las pide en dos modificadores distintos.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }
}

// MARK: - Los dos avisos que existen

extension CelebrationToast {

    /// La meta semanal cumplida, **una vez por semana** (AD-25). Se presenta sobre el `TabView`
    /// porque la meta se cumple mirando Inicio o al volver de segundo plano, no dentro de la
    /// sesión.
    static func weeklyGoal(onDismiss: @escaping () -> Void) -> CelebrationToast {
        CelebrationToast(
            emblem: .symbol("trophy.fill"),
            title: Text("¡Meta semanal cumplida!", comment: "Titular del aviso de celebración al completar la meta semanal de kilómetros."),
            message: Text("Has completado los kilómetros de esta semana.", comment: "Segunda línea del aviso de celebración de la meta semanal, bajo el titular."),
            spokenLabel: Text(verbatim: spokenWeeklyGoal),
            onDismiss: onDismiss
        )
    }

    /// Un logro recién desbloqueado y **ya escrito en disco** (3.2): el nombre y el emoji salen
    /// del catálogo congelado, no se inventan aquí.
    static func achievement(_ definition: AchievementDefinition, onDismiss: @escaping () -> Void) -> CelebrationToast {
        CelebrationToast(
            emblem: .emoji(definition.icon),
            title: Text(verbatim: definition.name),
            message: Text("Logro desbloqueado", comment: "Segunda línea del aviso de celebración de un logro, bajo el nombre del logro."),
            spokenLabel: Text(verbatim: spokenAchievement(definition)),
            onDismiss: onDismiss
        )
    }

    /// Lo que VoiceOver lee del aviso de la meta. Es una clave del String Catalog y no el
    /// titular pintado: el titular lleva signos de exclamación y un salto de línea implícito con
    /// su segunda línea, y lo que se **lee** tiene que ser una frase entera.
    static var spokenWeeklyGoal: String {
        String(localized: "Meta semanal cumplida. Has completado los kilómetros de esta semana.", comment: "Lectura de VoiceOver del aviso de celebración de la meta semanal: el aviso entero en una sola frase.")
    }

    /// Lo que VoiceOver lee del aviso de un logro: **qué ha pasado y de qué logro**, en ese
    /// orden. Sin el prefijo, el nombre solo ("Madrugador") no diría que se acaba de ganar.
    ///
    /// El nombre y la descripción son dato del catálogo (AD-5) y entran interpolados, no
    /// traducidos.
    static func spokenAchievement(_ definition: AchievementDefinition) -> String {
        String(localized: "Logro desbloqueado: \(definition.name). \(definition.description)", comment: "Lectura de VoiceOver del aviso de celebración de un logro. Los dos marcadores son el nombre y la descripción del logro, que salen del catálogo congelado y no se traducen aquí.")
    }
}
