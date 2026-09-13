import SwiftUI

/// Sesión activa, presentada como `fullScreenCover` (AD-14). La 1.1 solo muestra el
/// tiempo: pasos y métricas llegan en la 1.2 y la 1.3, y los controles de pausa y
/// cierre en la 1.4. No hay salida de esta pantalla antes de la 1.4.
///
/// El `TimelineView` repinta una vez por segundo, alineado con el inicio de la sesión.
/// Cada repintado relee el tiempo del store, que sale del reloj (con la fecha de la
/// entrada como suelo): el tick no cuenta nada.
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
}
