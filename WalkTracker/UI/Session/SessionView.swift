import Domain
import SwiftUI

/// Sesión activa, presentada como `fullScreenCover` (AD-14). La distancia domina en el
/// centro y debajo va una rejilla 2×2 siempre: pasos · tiempo arriba, ritmo · cadencia
/// abajo (decisión de Paul en la 1.3). Los controles de pausa y cierre llegan en la
/// 1.4: no hay salida de esta pantalla antes.
///
/// Solo pinta lo que produce el dominio (AD-22). Distancia, pasos, ritmo y cadencia se
/// repintan cuando llega una muestra del podómetro, no con el tick (AD-21). El tiempo va
/// en un `TimelineView` que repinta una vez por segundo, alineado con el inicio de la
/// sesión: cada repintado relee el tiempo del store, que sale del reloj (con la fecha
/// de la entrada como suelo), así que el tick no cuenta nada.
///
/// Con tamaños de texto grandes la pantalla se desplaza en vertical en lugar de recortar.
struct SessionView: View {

    let store: SessionStore

    /// La métrica principal domina, pero escala con Dynamic Type: no es un tamaño fijo.
    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize: CGFloat = 88

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    Text("Caminata en curso")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top)

                    Spacer(minLength: 24)

                    if let metrics = store.metrics {
                        distance(metrics.distanceM)
                    }

                    Spacer(minLength: 24)

                    if let session = store.session, let metrics = store.metrics {
                        grid(session: session, metrics: metrics)
                    }

                    Spacer(minLength: 16)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Distancia

    /// Un solo elemento para VoiceOver: "Distancia, 3,26 kilómetros".
    private func distance(_ meters: Double) -> some View {
        VStack(spacing: 0) {
            Text(DistanceFormat.kilometers(meters))
                .font(.system(size: distanceSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text("km")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Distancia"))
        .accessibilityValue(Text(DistanceFormat.spoken(meters)))
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Rejilla

    private func grid(session: Session, metrics: SessionMetrics) -> some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 24) {
            GridRow {
                cell(
                    value: session.stepsMeasured.formatted(.number),
                    unit: nil,
                    caption: "Pasos",
                    spokenLabel: Text("\(session.stepsMeasured) pasos"),
                    spokenValue: nil
                )
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    let seconds = store.elapsedS(notBefore: context.date)
                    cell(
                        value: ElapsedTimeFormat.clock(seconds),
                        unit: nil,
                        caption: "Tiempo",
                        spokenLabel: Text("Tiempo"),
                        spokenValue: ElapsedTimeFormat.spoken(seconds)
                    )
                }
            }
            GridRow {
                cell(
                    value: PaceFormat.text(metrics.paceSecPerKm),
                    unit: metrics.paceSecPerKm == nil ? nil : "/km",
                    caption: "Ritmo",
                    spokenLabel: Text("Ritmo"),
                    spokenValue: PaceFormat.spoken(metrics.paceSecPerKm)
                )
                cell(
                    value: CadenceFormat.text(metrics.cadenceSpm),
                    unit: "spm",
                    caption: "Cadencia",
                    spokenLabel: Text("Cadencia"),
                    spokenValue: CadenceFormat.spoken(metrics.cadenceSpm)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Una celda de la rejilla, leída por VoiceOver como un solo elemento con su
    /// magnitud completa. El número se encoge antes que recortarse.
    private func cell(
        value: String,
        unit: LocalizedStringKey?,
        caption: LocalizedStringKey,
        spokenLabel: Text,
        spokenValue: String?
    ) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenValue.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
