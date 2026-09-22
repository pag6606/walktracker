import Domain
import SwiftUI

/// El anillo de meta semanal de Inicio (3.1, CAP-7, FR-10).
///
/// **Es la primera de las tres piezas dibujadas a mano que AD-13 autoriza** —las otras dos son
/// el gráfico de tendencia (5.2) y la insignia de logro (3.3)—, así que lo que se decida aquí
/// es el patrón que copiarán. Hasta esta historia no había en todo `WalkTracker/` ni un
/// `Canvas`, ni un `Path`, ni un `trim(from:)`.
///
/// **Una forma dibujada no trae etiqueta de accesibilidad**, y ése es el precio de dibujarla:
/// dos círculos superpuestos son, para VoiceOver, dos imágenes sin nombre. Por eso el anillo es
/// **un solo elemento** con etiqueta y valor explícitos, y dice la magnitud entera —meta,
/// completado y porcentaje—, no "75 %" suelto.
///
/// **Reduce Motion, por primera vez fuera de la pantalla de sesión.** Con el ajuste activado el
/// arco aparece ya en su sitio: sin animación, no con una más corta. El precedente del patrón es
/// `SessionView`, que hasta hoy era la única vista que consultaba `accessibilityReduceMotion`.
///
/// **Sin dato no se pinta un 0.** Con el historial ilegible (5.1) el progreso es desconocido, no
/// cero: el anillo se queda en su pista, la cifra es un guion y VoiceOver lo dice. Pintar 0 %
/// sería afirmar que Paul no ha caminado esta semana, que es justo lo que nadie sabe (AD-22).
struct GoalRingView: View {

    /// El progreso de la semana, o `nil` si el historial no se pudo leer.
    let progress: WeeklyProgress?

    /// La meta contra la que se mide, ya resuelta (`SettingsStore.resolvedWeeklyGoalKm`).
    ///
    /// **Va aparte del progreso a propósito.** Son dos preguntas con dos respuestas distintas:
    /// con el historial ilegible no se sabe cuánto ha caminado Paul —y eso se pinta ausente
    /// (AD-22)— pero **sí** se sabe cuál es su meta, porque vive en otro fichero. Sacándola de
    /// `progress?.goalKm`, el pie decía "de 10 km" a quien tuviera 15 guardados.
    let goalKm: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// El grosor escala con Dynamic Type: el anillo engorda con la cifra que lleva dentro.
    @ScaledMetric(relativeTo: .title) private var lineWidth = GoalRing.lineWidth

    var body: some View {
        VStack(spacing: Spacing.s) {
            ring
            caption
        }
        .accessibilityElement(children: .ignore)
        // Misma clave que el encabezado de la sección de Ajustes, y por eso el mismo `comment:`:
        // el String Catalog guarda UNO por clave, y dos textos distintos dejarían al traductor
        // leyendo el del otro sitio — hallazgo 14 de la 2.3, aplicado a la segunda clave que esta
        // historia comparte (la primera es "km").
        .accessibilityLabel(Text("Meta semanal", comment: "Rótulo de la meta semanal, en sus dos sitios: la etiqueta de VoiceOver del anillo de progreso de Inicio —cuyo valor dice el completado, la meta y el porcentaje— y el encabezado de la sección de Ajustes donde se fija. El String Catalog guarda un comentario por clave: si se acorta para el encabezado, se acorta también lo que VoiceOver lee del anillo."))
        .accessibilityValue(Text(verbatim: Self.spokenValue(progress)))
    }

    // MARK: - El dibujo

    private var ring: some View {
        ZStack {
            // La pista: el recorrido que falta. Se pinta entera y el arco se dibuja encima.
            Circle()
                .stroke(Color.primary.opacity(GoalRing.trackOpacity), style: stroke)
            // El arco. Empieza arriba —`trim` empieza a las 3 en punto— y crece en el sentido
            // de las agujas del reloj, que es como se lee un progreso.
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Colors.accent, style: stroke)
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: GoalRing.fillDuration), value: fraction)
            completedValue
        }
        // El anillo ocupa el ancho que le den y se queda cuadrado; `maxDiameter` es su tope, no
        // su tamaño (AD-13: nada de diámetros fijos).
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: GoalRing.maxDiameter)
        // El trazo se dibuja centrado en el borde del círculo, así que la mitad de su grosor
        // cae fuera: sin este hueco, el anillo se recorta contra el borde de la pantalla.
        .padding(lineWidth / 2)
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round)
    }

    /// La fracción de anillo que se dibuja, `0…1`. Sin dato, la pista desnuda.
    private var fraction: Double { progress?.fraction ?? 0 }

    /// Los kilómetros de la semana, dentro del anillo. Es la cifra dominante de Inicio.
    private var completedValue: some View {
        Text(verbatim: progress.map { Self.kilometers($0.completedKm) } ?? PaceFormat.absent)
            .font(Typography.metricValue)
            .monospacedDigit()
            .minimumScaleFactor(GoalRing.minimumValueScale)
            .lineLimit(1)
            .padding(.horizontal, lineWidth)
    }

    /// "de 10 km" debajo del anillo: **la meta de Paul**, siempre visible, también sin dato.
    private var caption: some View {
        Text("de \(Self.kilometers(goalKm)) km", comment: "Pie del anillo de meta de Inicio, debajo de los kilómetros ya caminados esta semana: dice cuál es la meta. El marcador es la meta ya formateada, por ejemplo \"10\".")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Formato

    /// Kilómetros como los leería Paul: hasta dos decimales, sin ceros de relleno.
    ///
    /// **Sale de `completedKm`, que ya viene redondeado del dominio**, y no de los metros: la
    /// vista no tiene un segundo criterio de redondeo. 9 995 m se muestran como `9,99` —el
    /// redondeo binario no los sube a 10, y está registrado en el Spec Change Log de la 3.1—;
    /// el caso que sí sube a `10` sin cumplir la meta es 9 999,6 m, y por eso el arco no se
    /// deriva del porcentaje sino de `WeeklyProgress.fraction`.
    static func kilometers(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return PaceFormat.absent }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// La magnitud entera para VoiceOver. Sin dato dice por qué no lo hay, en vez de leer un
    /// guion suelto.
    static func spokenValue(_ progress: WeeklyProgress?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let progress else {
            return String(localized: "Sin progreso: no se pudo leer tu historial", locale: locale, comment: "Valor de VoiceOver del anillo de meta cuando el historial no se pudo leer. No se lee 0 %: el progreso es desconocido, no cero.")
        }
        let completed = kilometers(progress.completedKm, locale: locale)
        let goal = kilometers(progress.goalKm, locale: locale)
        let percentage = progress.percentage.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return String(localized: "\(completed) de \(goal) kilómetros, \(percentage) por ciento", locale: locale, comment: "Valor de VoiceOver del anillo de meta de Inicio: los kilómetros de la semana, la meta y el porcentaje. Ejemplo: \"7,5 de 10 kilómetros, 75 por ciento\".")
    }
}
