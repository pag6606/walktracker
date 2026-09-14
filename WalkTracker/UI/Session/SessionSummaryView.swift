import SwiftUI

/// Las métricas finales de una sesión cerrada, ya congeladas por el dominio: el tiempo es
/// `durationS`, y ritmo y cadencia salen de él.
struct FinishedWalk: Equatable {
    let distanceM: Double
    let durationS: Int
    let steps: Int
    /// Pasos estimados, desglosados con "~". En el resumen no se descartan.
    let estimatedSteps: Int
    let paceSecPerKm: Int?
    let cadenceSpm: Double
}

/// Resumen mínimo tras finalizar (decisión de Paul, 1.4): distancia, tiempo, pasos, ritmo
/// y cadencia finales y un único botón, "Volver al inicio". Solo avanza: no hay vuelta a
/// la sesión. Se muestra dentro del mismo modo de sesión (AD-14).
///
/// Solo pinta magnitudes que produce el dominio (AD-22): nada de Salud, logros, kcal ni
/// "Nueva caminata"; el resumen completo no tiene aún historia dueña. Los pasos estimados
/// se muestran desglosados con "~", sin descarte: la sesión finalizada es inmutable.
struct SessionSummaryView: View {

    let walk: FinishedWalk
    let onLeave: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    Text("Caminata completada")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top)

                    Spacer(minLength: 24)

                    DistanceHero(meters: walk.distanceM)

                    Spacer(minLength: 24)

                    Grid(horizontalSpacing: 16, verticalSpacing: 24) {
                        GridRow {
                            MetricCell.steps(walk.steps, estimated: walk.estimatedSteps)
                            MetricCell.time(TimeInterval(walk.durationS))
                        }
                        GridRow {
                            MetricCell.pace(walk.paceSecPerKm)
                            MetricCell.cadence(walk.cadenceSpm)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 24)

                    Button(action: onLeave) {
                        Label("Volver al inicio", systemImage: "house")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
