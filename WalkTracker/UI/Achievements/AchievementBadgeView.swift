import Domain
import SwiftUI

/// En qué estado está un logro cuando se pinta el grid (3.3).
///
/// **Son tres, no dos, y el tercero es el que evita una mentira.** Con `achievements.json`
/// ilegible no se sabe si Paul lo ha conseguido: pintarlo bloqueado afirmaría que no, que es
/// justo lo que nadie sabe (AD-22, y es la misma doctrina con la que el anillo se niega a pintar
/// un 0 % sin historial). `unknown` existe para que el grid pueda decir "no lo sé" en la insignia
/// además de decirlo en el aviso de arriba.
///
/// **`locked` lleva el progreso dentro y puede no traerlo**: `nil` es "este logro no tiene
/// barra" —una categoría de clima, una hora, una temperatura, un ritmo y `weekly_goal`, cuyo
/// progreso posee `GoalEngine` (AD-25)— y no "cero".
enum AchievementStatus: Equatable {

    /// Conseguido, con el instante en que se ganó. La fecha se presenta en **hora local**
    /// (AD-19), con el calendario del reloj.
    case unlocked(at: Date)
    /// Aún no conseguido, con lo que se sepa de su avance.
    case locked(AchievementProgress?)
    /// `achievements.json` no se pudo leer: **no se sabe** si está conseguido.
    case unknown
}

/// El avance hacia un logro bloqueado: la fracción que pinta la barra y las dos cifras que la
/// acompañan, en la unidad de la métrica.
///
/// Las tres salen del **mismo** par de funciones del motor, que devuelven `nil` en los mismos
/// casos: así la pantalla no puede enseñar una barra sin cifra ni una cifra sin barra.
struct AchievementProgress: Equatable {

    /// `0…1`, ya capada. **Llegar a 1 no desbloquea nada** (AD-17): ver la nota de
    /// `AchievementEngine.progressFraction(towards:sessions:calendar:)`.
    let fraction: Double
    /// Lo acumulado, en la unidad de la métrica (metros, sesiones o días).
    let accumulated: Double
    /// El umbral del catálogo, en la misma unidad.
    let threshold: Double
}

extension AchievementStatus {

    /// El estado de `definition` ahora mismo, **sin evaluar ni escribir nada** (AD-17).
    ///
    /// Es una función pura para poder probarla sin renderizar —la salida de la decisión D1 del
    /// 2026-09-20— y es donde vive el orden de las tres preguntas: primero si el fichero se pudo
    /// leer, después si hay fila con instante, y solo entonces se calcula el avance.
    ///
    /// **Una fila con `progress` y sin `unlockedAt` se trata como bloqueada y su progreso se
    /// ignora**: el progreso guardado sería una caché que el borrado de una sesión (CAP-15)
    /// dejaría mintiendo, y por eso la decisión D1 de la 3.3 lo deriva del historial cada vez.
    /// Hoy, además, nadie escribe esas filas.
    static func of(
        _ definition: AchievementDefinition,
        unlock: AchievementUnlock?,
        isUnreadable: Bool,
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> AchievementStatus {
        guard !isUnreadable else { return .unknown }
        if let unlockedAt = unlock?.unlockedAt { return .unlocked(at: unlockedAt) }
        return .locked(progress(of: definition, sessions: sessions, calendar: calendar))
    }

    /// El avance hacia `definition`, o `nil` si ese logro no lleva barra.
    private static func progress(
        of definition: AchievementDefinition,
        sessions: [SessionRecord],
        calendar: Calendar
    ) -> AchievementProgress? {
        guard
            let accumulated = AchievementEngine.accumulated(towards: definition, sessions: sessions, calendar: calendar),
            let fraction = AchievementEngine.progressFraction(towards: definition, sessions: sessions, calendar: calendar),
            case .number(let threshold) = definition.threshold
        else { return nil }
        return AchievementProgress(fraction: fraction, accumulated: accumulated, threshold: threshold)
    }
}

/// Una insignia del grid de logros (3.3, CAP-8, FR-8).
///
/// **Es la segunda de las tres piezas dibujadas a mano que AD-13 autoriza** —la primera fue el
/// anillo de meta (3.1) y la tercera será el gráfico de tendencia (5.2)— y copia su molde en vez
/// de inventar otro: `@ScaledMetric(relativeTo:)` y `aspectRatio(1, contentMode: .fit)` con un
/// `frame(maxWidth:)` en vez de un diámetro fijo; `accessibilityElement(children: .ignore)` con
/// etiqueta y valor explícitos, porque una forma dibujada **no trae etiqueta**; Reduce Motion a
/// `nil`, no a una animación más corta; y el formato en **funciones estáticas puras**, que se
/// prueban sin renderizar nada.
///
/// **El emoji es dato del catálogo, no chrome.** AD-5 lo congela junto al nombre y la
/// descripción, así que los tres se pintan `verbatim`: no pasan por el String Catalog ni se
/// retocan aquí. El resto de la insignia —el reborde, la barra, el interrogante del estado
/// desconocido— sí es chrome, y es SF Symbols y formas.
///
/// **El grid no desbloquea, aunque la barra llegue al 100 %.** Es el caso que parece un defecto y
/// no lo es: con 42 km acumulados y sin fila escrita, `marathon_42km` se desbloquea en el
/// **cierre siguiente** (AD-17), no al mirar la pantalla. La alternativa pondría la celebración
/// en manos de cuándo se abre una pestaña.
struct AchievementBadgeView: View {

    /// El logro del catálogo congelado (AD-5). De aquí salen el emoji, el nombre y la
    /// descripción, tal cual.
    let definition: AchievementDefinition
    let status: AchievementStatus
    /// El `AppCalendar` de AD-19, para presentar la fecha de desbloqueo en **hora local**.
    let calendar: Calendar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// El medallón engorda con el emoji que lleva dentro, como el anillo con su cifra.
    @ScaledMetric(relativeTo: .largeTitle) private var medallionSize = AchievementBadge.maxDiameter
    @ScaledMetric(relativeTo: .largeTitle) private var rimWidth = AchievementBadge.rimWidth
    @ScaledMetric(relativeTo: .caption) private var barHeight = AchievementBadge.barHeight

    var body: some View {
        VStack(spacing: Spacing.s) {
            medallion
            Text(verbatim: definition.name)
                .font(.headline)
            Text(verbatim: definition.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
            detail
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, Surface.cardPaddingHorizontal)
        .padding(.vertical, Surface.cardPaddingVertical)
        .background(.fill.quaternary, in: .rect(cornerRadius: Radius.card))
        // Una insignia es **un** elemento: el emoji, el nombre, la descripción y la barra no son
        // cuatro paradas de VoiceOver. Lo que se lee sale de las tres funciones puras de abajo.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: definition.name))
        .accessibilityValue(Text(verbatim: Self.spokenValue(status, metric: definition.metric, calendar: calendar)))
        .accessibilityHint(Text(verbatim: definition.description))
    }

    // MARK: - El dibujo

    /// El medallón: un disco con su reborde trazado y, dentro, el emoji del catálogo.
    private var medallion: some View {
        ZStack {
            Circle()
                .fill(.background)
            Circle()
                .strokeBorder(rim, lineWidth: rimWidth)
            icon
        }
        // Ocupa el ancho de su celda y se queda cuadrado; `maxDiameter` es su tope, no su
        // tamaño (AD-13: nada de diámetros fijos).
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: medallionSize)
    }

    /// El reborde: el acento del producto cuando está conseguido, un rol del sistema cuando no.
    /// Ningún color nuevo — la excepción de UX-DR1 son exactamente tres colorsets (AD-13).
    private var rim: AnyShapeStyle {
        switch status {
        case .unlocked: AnyShapeStyle(Colors.accent)
        case .locked, .unknown: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .unknown:
            // **No se pinta como bloqueado**: con el fichero ilegible no se sabe si está
            // conseguido, y el interrogante dice eso en vez de afirmar que falta (AD-22).
            Image(systemName: "questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        case .unlocked:
            Text(verbatim: definition.icon)
                .font(.largeTitle)
        case .locked:
            // Atenuado y en gris: lo que falta por ganar se enseña, no se esconde (UX-DR5).
            Text(verbatim: definition.icon)
                .font(.largeTitle)
                .grayscale(1)
                .opacity(AchievementBadge.lockedOpacity)
        }
    }

    /// El pie de la insignia: la fecha si está conseguido, la barra y su cifra si hay avance que
    /// contar, y **nada** si no lo hay — un 0 % sería falso.
    @ViewBuilder
    private var detail: some View {
        switch status {
        case .unlocked(let instant):
            Text("Conseguido el \(Self.dateText(instant, calendar: calendar))", comment: "Pie de una insignia conseguida en el grid de Logros: cuándo se ganó. El marcador es la fecha ya formateada en hora local, por ejemplo \"21 sept 2026\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .locked(let progress):
            if let progress {
                VStack(spacing: Spacing.xs) {
                    bar(progress.fraction)
                    if let caption = Self.progressText(progress, metric: definition.metric) {
                        Text(verbatim: caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        case .unknown:
            EmptyView()
        }
    }

    /// La barra: la pista con lo que falta y el relleno con lo llevado.
    private func bar(_ fraction: Double) -> some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: barHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Colors.accent)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            // `nil`, no una animación más corta: es el patrón que dejó el anillo (3.1).
            .animation(reduceMotion ? nil : .easeOut(duration: AchievementBadge.fillDuration), value: fraction)
    }

    // MARK: - Formato

    /// La fecha de desbloqueo en **hora local** (AD-19), con el calendario del reloj y no con uno
    /// construido aquí: el grid y el historial no pueden fechar la misma caminata en dos días
    /// distintos.
    static func dateText(_ instant: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        // El calendario **y su zona** van explícitos: sin la zona, el formato usaría la del
        // sistema y un desbloqueo de las 21:00 locales se fecharía al día siguiente.
        instant.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
        )
    }

    /// "19,88 de 42,00 km", "3 de 30 sesiones", "2 de 7 días" — el acumulado frente a su umbral,
    /// en la unidad de la métrica, o `nil` si esa métrica no se acumula.
    ///
    /// **Los kilómetros salen de `DistanceFormat`**, que es el único criterio de redondeo de
    /// distancias del producto: un segundo aquí haría que la misma caminata se leyera de dos
    /// maneras según la pantalla.
    ///
    /// Es `String?` y **exhaustiva sin `default`** por la misma razón que el motor: las cinco
    /// métricas que no se acumulan no llegan aquí —su progreso es `nil` y la insignia no pinta
    /// barra— y una métrica nueva obliga a decidir en qué unidad se lee.
    static func progressText(
        _ progress: AchievementProgress,
        metric: AchievementMetric,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        switch metric {
        case .sessionDistanceM, .totalDistanceM:
            let done = DistanceFormat.kilometers(progress.accumulated, locale: locale)
            let goal = DistanceFormat.kilometers(progress.threshold, locale: locale)
            return String(localized: "\(done) de \(goal) km", locale: locale, comment: "Progreso de un logro de distancia en el grid de Logros: los kilómetros acumulados frente a los que pide el logro. Los dos marcadores son cifras ya formateadas, por ejemplo \"19,88\" y \"42,00\".")
        case .sessionCount:
            let done = whole(progress.accumulated, locale: locale)
            let goal = whole(progress.threshold, locale: locale)
            return String(localized: "\(done) de \(goal) sesiones", locale: locale, comment: "Progreso de un logro de número de caminatas en el grid de Logros: las sesiones hechas frente a las que pide el logro.")
        case .consecutiveDays:
            let done = whole(progress.accumulated, locale: locale)
            let goal = whole(progress.threshold, locale: locale)
            return String(localized: "\(done) de \(goal) días", locale: locale, comment: "Progreso de un logro de racha en el grid de Logros: los días seguidos con caminata frente a los que pide el logro.")
        case .startHourLocal, .weatherCategory, .tempC, .paceSecPerKm, .weeklyGoalMet:
            return nil
        }
    }

    /// Lo que VoiceOver lee como **valor** de la insignia: el estado y, si está bloqueado, su
    /// progreso. El nombre es la etiqueta y la descripción es la pista, así que no se repiten.
    ///
    /// Un logro bloqueado **dice que está bloqueado**: una forma dibujada y un emoji en gris no
    /// lo dicen solos.
    static func spokenValue(
        _ status: AchievementStatus,
        metric: AchievementMetric,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch status {
        case .unlocked(let instant):
            let date = dateText(instant, calendar: calendar, locale: locale)
            return String(localized: "Conseguido el \(date)", locale: locale, comment: "Pie de una insignia conseguida en el grid de Logros: cuándo se ganó. El marcador es la fecha ya formateada en hora local, por ejemplo \"21 sept 2026\".")
        case .locked(let progress):
            guard let progress, let text = progressText(progress, metric: metric, locale: locale) else {
                return String(localized: "Bloqueado", locale: locale, comment: "Valor de VoiceOver de una insignia que aún no se ha conseguido y no tiene barra que leer, en el grid de Logros.")
            }
            return String(localized: "Bloqueado. \(text)", locale: locale, comment: "Valor de VoiceOver de una insignia bloqueada con avance, en el grid de Logros: dice que está bloqueada y lee su progreso. El marcador es el progreso ya formateado, por ejemplo \"19,88 de 42,00 km\".")
        case .unknown:
            return String(localized: "No se pudo leer si lo has conseguido", locale: locale, comment: "Valor de VoiceOver de una insignia cuando el fichero de logros no se pudo leer. No se dice \"bloqueado\": no se sabe si está conseguido.")
        }
    }

    /// Una cuenta entera (sesiones, días) como la leería Paul.
    private static func whole(_ value: Double, locale: Locale) -> String {
        guard value.isFinite else { return PaceFormat.absent }
        return value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}
