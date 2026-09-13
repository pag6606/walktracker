import SwiftUI

/// Sesión activa, presentada como `fullScreenCover` (AD-14). Muestra el tiempo en el
/// centro y, debajo, los pasos del coprocesador como segunda métrica (decisión de Paul
/// en la 1.2; en la 1.3 la distancia pasa al centro). Los controles de pausa y cierre
/// llegan en la 1.4: no hay salida de esta pantalla antes.
///
/// El `TimelineView` repinta una vez por segundo, alineado con el inicio de la sesión.
/// Cada repintado relee el tiempo del store, que sale del reloj (con la fecha de la
/// entrada como suelo): el tick no cuenta nada. Los pasos se repintan cuando llega una
/// muestra del podómetro, no con el tick.
struct SessionView: View {

    let store: SessionStore

    /// La métrica principal domina, pero escala con Dynamic Type: no es un tamaño fijo.
    @ScaledMetric(relativeTo: .largeTitle) private var elapsedSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 8) {
            Text("Caminata en curso")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top)

            Spacer()

            if let startedAt = store.session?.startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    elapsed(store.elapsedS(notBefore: context.date))
                }
            }

            Text("Tiempo")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if let steps = store.session?.stepsMeasured {
                stepsMetric(steps)
                    .padding(.top, 32)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled()
    }

    private func elapsed(_ seconds: TimeInterval) -> some View {
        Text(ElapsedTimeFormat.clock(seconds))
            .font(.system(size: elapsedSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel(Text("Tiempo"))
            .accessibilityValue(Text(ElapsedTimeFormat.spoken(seconds)))
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Un solo elemento para VoiceOver, que lee la magnitud completa: "350 pasos".
    private func stepsMetric(_ steps: Int) -> some View {
        VStack(spacing: 4) {
            Text(steps, format: .number)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text("Pasos")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(steps) pasos"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
