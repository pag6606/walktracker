import Domain
import SwiftUI

/// Sesión abierta, presentada como `fullScreenCover` (AD-14). La distancia domina en el
/// centro y debajo va una rejilla 2×2 siempre: pasos · tiempo arriba, ritmo · cadencia
/// abajo (decisión de Paul en la 1.3). Al pie, los controles: Pausar y Finalizar con la
/// sesión activa; Reanudar y Finalizar en pausa. Finalizar exige confirmación explícita y
/// es la única salida (AD-20). Con la sesión finalizada, el mismo modo muestra el resumen.
///
/// Una sola señal de estado, el título: "Caminata en curso" o "En pausa". En pausa la
/// distancia se atenúa.
///
/// Solo pinta lo que produce el dominio (AD-22). Distancia, pasos, ritmo y cadencia se
/// repintan cuando llega una muestra del podómetro, no con el tick (AD-21). El tiempo va
/// en un `TimelineView` que repinta una vez por segundo, alineado con el inicio de la
/// sesión: cada repintado relee el tiempo del store, que sale del reloj (con la fecha
/// de la entrada como suelo), así que el tick no cuenta nada; en pausa el store da el
/// tiempo congelado.
///
/// Con tamaños de texto grandes la pantalla se desplaza en vertical en lugar de recortar.
struct SessionView: View {

    let store: SessionStore

    /// Última sesión finalizada vista, para seguir pintando el resumen mientras el modo se
    /// cierra: al salir del resumen el store ya no tiene sesión. Solo se usa sin sesión en
    /// el store, para que nunca tape una sesión nueva.
    @State private var lastFinished: FinishedWalk?

    var body: some View {
        Group {
            if let finished = currentFinished ?? (store.session == nil ? lastFinished : nil) {
                SessionSummaryView(walk: finished, onLeave: store.leaveSummary)
            } else if let session = store.session, let metrics = store.metrics {
                live(session: session, metrics: metrics)
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: currentFinished, initial: true) { _, finished in
            if let finished { lastFinished = finished }
        }
    }

    private var currentFinished: FinishedWalk? {
        guard let session = store.session, session.status == .finished,
              let metrics = store.metrics, let durationS = session.durationS
        else { return nil }
        return FinishedWalk(
            distanceM: metrics.distanceM,
            durationS: durationS,
            steps: session.stepsMeasured,
            paceSecPerKm: metrics.paceSecPerKm,
            cadenceSpm: metrics.cadenceSpm
        )
    }

    // MARK: - Sesión en curso

    private func live(session: Session, metrics: SessionMetrics) -> some View {
        let isPaused = session.status == .paused
        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    Text(isPaused ? "En pausa" : "Caminata en curso")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top)

                    Spacer(minLength: 24)

                    DistanceHero(meters: metrics.distanceM, isDimmed: isPaused)

                    Spacer(minLength: 24)

                    grid(session: session, metrics: metrics)

                    Spacer(minLength: 24)

                    controls(isPaused: isPaused)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Rejilla

    private func grid(session: Session, metrics: SessionMetrics) -> some View {
        Grid(horizontalSpacing: 16, verticalSpacing: 24) {
            GridRow {
                MetricCell.steps(session.stepsMeasured)
                // Alineado con el inicio desplazado por las pausas cerradas: así el tick cae en
                // el cambio de segundo del tiempo neto aunque una pausa tenga fracción.
                TimelineView(.periodic(from: session.startedAt.addingTimeInterval(session.totalPausesS), by: 1)) { context in
                    MetricCell.time(store.elapsedS(notBefore: context.date))
                }
            }
            GridRow {
                MetricCell.pace(metrics.paceSecPerKm)
                MetricCell.cadence(metrics.cadenceSpm)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controles

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Pausar/Reanudar y Finalizar, lado a lado; apilados con tamaños de accesibilidad
    /// para que las etiquetas no se recorten. Objetivo táctil ≥ 44 pt (AD-20).
    ///
    /// Pausar y Reanudar son **un solo botón** que cambia de título, icono, estilo y
    /// acción: con dos, el que tiene el foco de VoiceOver desaparecería al pulsarlo.
    private func controls(isPaused: Bool) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button {
                if isPaused { store.resume() } else { store.pause() }
            } label: {
                Label(isPaused ? "Reanudar" : "Pausar", systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass(isPaused ? Glass.regular.tint(.accentColor) : .regular))

            Button(role: .destructive, action: store.requestFinish) {
                Label("Finalizar", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glass)
            .confirmationDialog("¿Finalizar la caminata?", isPresented: confirmingFinish, titleVisibility: .visible) {
                Button("Finalizar caminata", role: .destructive, action: store.confirmFinish)
                Button("Cancelar", role: .cancel, action: store.cancelFinish)
            } message: {
                Text("No podrás reanudarla.")
            }
        }
        .controlSize(.extraLarge)
    }

    /// La vista no escribe estado del store: cerrar el diálogo es la intención de cancelar.
    private var confirmingFinish: Binding<Bool> {
        Binding(get: { store.isConfirmingFinish }, set: { presented in
            if !presented { store.cancelFinish() }
        })
    }
}

// MARK: - Piezas compartidas con el resumen

/// La distancia como métrica principal. Un solo elemento para VoiceOver: "Distancia,
/// 3,26 kilómetros".
struct DistanceHero: View {

    let meters: Double
    /// En pausa la distancia se atenúa.
    var isDimmed = false

    /// La métrica principal domina, pero escala con Dynamic Type: no es un tamaño fijo.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            Text(DistanceFormat.kilometers(meters))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isDimmed ? .secondary : .primary)
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
}

/// Una celda de la rejilla de métricas, leída por VoiceOver como un solo elemento con su
/// magnitud completa. El número se encoge antes que recortarse.
struct MetricCell: View {

    let value: String
    let unit: LocalizedStringKey?
    let caption: LocalizedStringKey
    let spokenLabel: Text
    let spokenValue: String?

    static func steps(_ steps: Int) -> MetricCell {
        MetricCell(
            value: steps.formatted(.number),
            unit: nil,
            caption: "Pasos",
            spokenLabel: Text("\(steps) pasos"),
            spokenValue: nil
        )
    }

    static func time(_ seconds: TimeInterval) -> MetricCell {
        MetricCell(
            value: ElapsedTimeFormat.clock(seconds),
            unit: nil,
            caption: "Tiempo",
            spokenLabel: Text("Tiempo"),
            spokenValue: ElapsedTimeFormat.spoken(seconds)
        )
    }

    static func pace(_ secPerKm: Int?) -> MetricCell {
        MetricCell(
            value: PaceFormat.text(secPerKm),
            unit: secPerKm == nil ? nil : "/km",
            caption: "Ritmo",
            spokenLabel: Text("Ritmo"),
            spokenValue: PaceFormat.spoken(secPerKm)
        )
    }

    static func cadence(_ spm: Double) -> MetricCell {
        MetricCell(
            value: CadenceFormat.text(spm),
            unit: "spm",
            caption: "Cadencia",
            spokenLabel: Text("Cadencia"),
            spokenValue: CadenceFormat.spoken(spm)
        )
    }

    var body: some View {
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
