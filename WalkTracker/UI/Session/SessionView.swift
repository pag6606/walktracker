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
/// Pasos estimados (1.5): la celda de pasos los desglosa con "~" ("4.100 ~236") y, mientras
/// haya, el Estimated Banner bajo la rejilla los muestra con "Descartar", que exige
/// confirmación (AD-20). Mientras el store reconcilia (AD-8) los controles se deshabilitan
/// siempre; el aviso de reconciliación solo aparece si dura más de 0,5 s, para no parpadear.
///
/// Recuperación (1.6): tras restaurar la sesión al relanzar la app, "Sesión recuperada" aparece
/// bajo el título 3 s, sin bloquear nada, y se anuncia a VoiceOver. Con Reduce Motion entra y
/// sale con un fundido, sin desplazamiento.
///
/// Clima (2.1): la tarjeta de clima va bajo las métricas y pinta el snapshot congelado al
/// inicio, la espera de la captura o "Sin clima". Con el permiso de ubicación sin decidir, la
/// pre-pantalla de ubicación aparece arriba, sobre la sesión que ya cuenta, sin tapar los
/// controles.
///
/// Frase (2.2): al iniciar, `QuoteOverlay` se pone **encima de esta pantalla ya corriendo**
/// 3 s, o hasta que Paul la toca. Solo sale cuando el store enciende `store.quote`, que es del
/// arranque: una sesión recuperada tras un force-quit conserva su `quoteId` y **no** vuelve a
/// verla.
///
/// Con tamaños de texto grandes la pantalla se desplaza en vertical en lugar de recortar.
///
/// **Criterio único de `minimumScaleFactor` en esta pantalla (2026-09-18).** Los tres sitios
/// que encogen texto —la cifra del héroe, el valor de una celda y su etiqueta— usaban tres
/// factores distintos (0,4 · 0,3 · 0,5) sin razón declarada, y los dos primeros permitían
/// bajar hasta 8 pt en el tamaño por omisión: ilegible, y justo lo contrario de lo que
/// Dynamic Type persigue. **Un texto puede encogerse hasta la mitad de su tamaño, nunca
/// más**; si a la mitad aún no cabe, la pantalla se desplaza (ya lo hace) o el bloque se
/// apila. Medio tamaño deja el peor caso —la cifra de una celda en la rejilla a tamaño de
/// accesibilidad máximo— con holgura de sobra, así que en la práctica solo cambia el suelo,
/// no lo que se ve.
struct SessionView: View {

    let store: SessionStore

    /// Última sesión finalizada vista, para seguir pintando el resumen mientras el modo se
    /// cierra: al salir del resumen el store ya no tiene sesión. Solo se usa sin sesión en
    /// el store, para que nunca tape una sesión nueva.
    @State private var lastFinished: FinishedWalk?
    /// La reconciliación en curso ya dura más de `reconcilingNoticeDelay`.
    @State private var showsReconcilingNotice = false

    /// Retraso del aviso de reconciliación (decisión de Paul, 1.5): una reconciliación
    /// rápida solo deshabilita los controles, sin texto que parpadee.
    private static let reconcilingNoticeDelay: Duration = .milliseconds(500)
    /// Cuánto dura "Sesión recuperada" (CAP-1, EXPERIENCE.md#95: 3 s).
    private static let recoveredNoticeDuration: Duration = .seconds(3)
    /// Cuánto dura la frase del arranque: 3 s, como la v3, con holgura frente al criterio
    /// "antes de los 4 s" del épico (decisión de Paul, 2026-09-19).
    private static let quoteDuration: Duration = .seconds(3)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            estimatedSteps: session.stepsEstimated,
            paceSecPerKm: metrics.paceSecPerKm,
            cadenceSpm: metrics.cadenceSpm,
            recovered: session.recovered,
            notPersisted: store.finishedWalkNotPersisted
        )
    }

    // MARK: - Sesión en curso

    private func live(session: Session, metrics: SessionMetrics) -> some View {
        let isPaused = session.status == .paused
        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.s) {
                    Text(isPaused ? "En pausa" : "Caminata en curso")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top)

                    if store.showsRecoveredNotice {
                        recoveredNotice
                    }

                    if store.isReconciling && showsReconcilingNotice {
                        Text("Recuperando los pasos del rato en segundo plano. Los controles vuelven en un momento.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: Spacing.xl)

                    DistanceHero(meters: metrics.distanceM, isDimmed: isPaused)

                    Spacer(minLength: Spacing.xl)

                    grid(session: session, metrics: metrics)

                    if session.stepsEstimated > 0 {
                        estimatedBanner(session.stepsEstimated)
                            .padding(.top, Spacing.l)
                    }

                    WeatherCard(weather: session.weather, isCapturing: store.isCapturingWeather)
                        .padding(.top, Spacing.l)

                    Spacer(minLength: Spacing.xl)

                    controls(isPaused: isPaused)
                }
                .padding(LayoutMetrics.margin)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .default, value: store.showsRecoveredNotice)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .default, value: store.isCapturingWeather)
                .task(id: store.showsRecoveredNotice) {
                    guard store.showsRecoveredNotice else { return }
                    AccessibilityNotification.Announcement(String(localized: "Sesión recuperada", comment: "Indicador transitorio (3 s) bajo el título de la pantalla de sesión, y anuncio de VoiceOver, al restaurar la caminata tras relanzar la app.")).post()
                    try? await Task.sleep(for: Self.recoveredNoticeDuration)
                    if !Task.isCancelled { store.dismissRecoveredNotice() }
                }
                .task(id: store.isReconciling) {
                    showsReconcilingNotice = false
                    guard store.isReconciling else { return }
                    try? await Task.sleep(for: Self.reconcilingNoticeDelay)
                    if !Task.isCancelled, store.isReconciling { showsReconcilingNotice = true }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .top) {
            if let prompt = store.locationPrompt {
                LocationPermissionView(
                    isRequesting: prompt == .requesting,
                    onAllow: { Task { await store.confirmLocationPermission() } },
                    onDecline: store.declineLocationPermission
                )
                .padding(.horizontal, LayoutMetrics.margin)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .default, value: store.locationPrompt)
        .overlay {
            if let quote = store.quote {
                QuoteOverlay(text: quote.text, onDismiss: store.dismissQuote)
                    // Reduce Motion: aparece sin fundido, no con uno más corto.
                    .transition(reduceMotion ? .identity : .opacity)
                    // El `id` es la frase, NO `store.quote`: solo existe mientras el overlay
                    // está montado, así que una sesión recuperada (que nunca lo monta) no
                    // puede redisparar el temporizador.
                    .task(id: quote.id) {
                        // Una señal corta, no la frase: el modal ya lleva el texto como su
                        // etiqueta y el foco lo lee al aparecer. Anunciar además la frase
                        // entera la diría dos veces seguidas. El precedente de "Sesión
                        // recuperada" anuncia dos palabras porque ahí no hay modal que leer.
                        AccessibilityNotification.Announcement(String(localized: "Frase motivacional", comment: "Anuncio corto de VoiceOver al aparecer el overlay de la frase motivacional, al iniciar una caminata. La frase en sí la lee el foco del modal.")).post()
                        try? await Task.sleep(for: Self.quoteDuration)
                        if !Task.isCancelled { store.dismissQuote() }
                    }
            }
        }
        .animation(reduceMotion ? nil : .default, value: store.quote)
    }

    // MARK: - Sesión recuperada

    /// Indicador transitorio, sin botón: no bloquea ni pide nada.
    private var recoveredNotice: some View {
        Label("Sesión recuperada", systemImage: "arrow.clockwise")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Rejilla

    private func grid(session: Session, metrics: SessionMetrics) -> some View {
        Grid(horizontalSpacing: Spacing.l, verticalSpacing: Spacing.xl) {
            GridRow {
                MetricCell.steps(session.stepsMeasured, estimated: session.stepsEstimated)
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

    // MARK: - Estimated Banner

    /// "~N pasos estimados" y "Descartar", visible mientras haya estimados, también en
    /// pausa. Descartar pide confirmación y es irreversible (AD-20).
    private func estimatedBanner(_ estimated: Int) -> some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "~")
                        .foregroundStyle(Colors.estimated)
                        .accessibilityHidden(true)
                    Text("\(estimated) pasos estimados")
                }
                .font(.subheadline.weight(.semibold))
                Text("Del intervalo que el sistema no pudo reconstruir")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(role: .destructive, action: store.requestDiscardEstimated) {
                // El marco va en la etiqueta: así el objetivo táctil es ≥ 44 pt (AD-20).
                Text("Descartar")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: LayoutMetrics.touchTargetMin, minHeight: LayoutMetrics.touchTargetMin)
                    .contentShape(.rect)
            }
            .disabled(store.isReconciling)
            .confirmationDialog("¿Descartar los pasos estimados?", isPresented: confirmingDiscard, titleVisibility: .visible) {
                Button("Descartar pasos estimados", role: .destructive, action: store.confirmDiscardEstimated)
                Button("Cancelar", role: .cancel, action: store.cancelDiscardEstimated)
            } message: {
                Text("La distancia y el ritmo se recalcularán sin ellos. No se puede deshacer.")
            }
        }
        .padding(.horizontal, Surface.cardPaddingHorizontal)
        .padding(.vertical, Surface.cardPaddingVertical)
        .background(Colors.estimated.opacity(Surface.noticeTintOpacity), in: .rect(cornerRadius: Radius.card))
    }

    /// La vista no escribe estado del store: cerrar el diálogo es la intención de cancelar.
    private var confirmingDiscard: Binding<Bool> {
        Binding(get: { store.isConfirmingDiscard }, set: { presented in
            if !presented { store.cancelDiscardEstimated() }
        })
    }

    // MARK: - Controles

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Pausar/Reanudar y Finalizar, lado a lado; apilados con tamaños de accesibilidad
    /// para que las etiquetas no se recorten. Objetivo táctil ≥ 44 pt (AD-20).
    ///
    /// Pausar y Reanudar son **un solo botón** que cambia de título, icono, estilo y
    /// acción: con dos, el que tiene el foco de VoiceOver desaparecería al pulsarlo.
    ///
    /// Deshabilitados mientras el store reconcilia (AD-8), que además los rechaza.
    private func controls(isPaused: Bool) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Spacing.m))
            : AnyLayout(HStackLayout(spacing: Spacing.m))
        return layout {
            Button {
                if isPaused { store.resume() } else { store.pause() }
            } label: {
                Label(isPaused ? "Reanudar" : "Pausar", systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(Typography.buttonLabel)
                    .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
            }
            .buttonStyle(.glass(isPaused ? Glass.regular.tint(Colors.accent) : .regular))

            Button(role: .destructive, action: store.requestFinish) {
                Label("Finalizar", systemImage: "stop.fill")
                    .font(Typography.buttonLabel)
                    .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
            }
            .buttonStyle(.glass)
            .confirmationDialog("¿Finalizar la caminata?", isPresented: confirmingFinish, titleVisibility: .visible) {
                Button("Finalizar caminata", role: .destructive) {
                    Task { await store.confirmFinish() }
                }
                Button("Cancelar", role: .cancel, action: store.cancelFinish)
            } message: {
                Text("No podrás reanudarla.")
            }
        }
        .controlSize(.extraLarge)
        .disabled(store.isReconciling)
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
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = LayoutMetrics.heroSize

    var body: some View {
        VStack(spacing: 0) {
            Text(DistanceFormat.kilometers(meters))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isDimmed ? .secondary : .primary)
                .lineLimit(1)
                // Hasta la mitad, nunca más (criterio único de la pantalla).
                .minimumScaleFactor(0.5)
            Text("km", comment: "Unidad de los kilómetros: la distancia en la pantalla de sesión y el valor del campo de meta semanal en Ajustes.")
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
    /// Desglose de pasos estimados ("~236"), marcado en naranja. `nil` sin estimados.
    var estimate: String?
    let unit: LocalizedStringKey?
    let caption: LocalizedStringKey
    let spokenLabel: Text
    let spokenValue: String?

    /// Pasos medidos y, si hay, los estimados desglosados: "4.100 ~236". VoiceOver lee
    /// "4100 pasos, 236 estimados": nunca los suma.
    static func steps(_ steps: Int, estimated: Int = 0) -> MetricCell {
        let measured = String(localized: "\(steps) pasos", comment: "Lectura de VoiceOver de los pasos medidos en la celda de pasos, en la pantalla de sesión y en el resumen: la magnitud completa.")
        guard estimated > 0 else {
            return MetricCell(value: steps.formatted(.number), unit: nil, caption: "Pasos", spokenLabel: Text(verbatim: measured), spokenValue: nil)
        }
        let estimatedSpoken = String(localized: "\(estimated) estimados", comment: "Lectura de VoiceOver de los pasos estimados en la celda de pasos, en la pantalla de sesión y en el resumen, tras los medidos: \"4100 pasos, 236 estimados\".")
        return MetricCell(
            value: steps.formatted(.number),
            estimate: "~" + estimated.formatted(.number),
            unit: nil,
            caption: "Pasos",
            spokenLabel: Text(verbatim: "\(measured), \(estimatedSpoken)"),
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
        VStack(spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(Typography.metricValue)
                    .monospacedDigit()
                if let estimate {
                    Text(verbatim: estimate)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Colors.estimated)
                }
                if let unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            // Hasta la mitad, nunca más (criterio único de la pantalla).
            .minimumScaleFactor(0.5)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Hasta la mitad, nunca más (criterio único de la pantalla).
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenValue.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
