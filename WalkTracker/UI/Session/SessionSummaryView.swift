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
    /// Sesión huérfana que la app cerró sola al arrancar (AD-18).
    var recovered = false
    /// La caminata **no se pudo guardar en el historial** (5.1). El resumen lo dice antes de
    /// dejar salir, porque es el único momento en que Paul está mirando; el snapshot no se ha
    /// borrado, así que la caminata vuelve al relanzar la app.
    var notPersisted = false
}

/// Resumen mínimo tras finalizar (decisión de Paul, 1.4): distancia, tiempo, pasos, ritmo
/// y cadencia finales y un único botón, "Volver al inicio". Solo avanza: no hay vuelta a
/// la sesión. Se muestra dentro del mismo modo de sesión (AD-14).
///
/// Solo pinta magnitudes que produce el dominio (AD-22): nada de Salud, logros, kcal ni
/// "Nueva caminata"; el resumen completo no tiene aún historia dueña. Los pasos estimados
/// se muestran desglosados con "~", sin descarte: la sesión finalizada es inmutable.
///
/// Una sesión huérfana cerrada al arrancar (1.6, AD-18) usa el mismo resumen como "Caminata
/// recuperada", con una nota de que se cerró sola en el último paso registrado. Sin logros
/// ni celebración.
struct SessionSummaryView: View {

    let walk: FinishedWalk
    let onLeave: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.s) {
                    Text(walk.recovered ? "Caminata recuperada" : "Caminata completada")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top)

                    if walk.recovered {
                        Text("Se cerró sola en el último paso registrado.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if walk.notPersisted {
                        notPersistedNotice
                    }

                    Spacer(minLength: Spacing.xl)

                    DistanceHero(meters: walk.distanceM)

                    Spacer(minLength: Spacing.xl)

                    Grid(horizontalSpacing: Spacing.l, verticalSpacing: Spacing.xl) {
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

                    Spacer(minLength: Spacing.xl)

                    Button(action: onLeave) {
                        Label("Volver al inicio", systemImage: "house")
                            .font(Typography.buttonLabel)
                            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                }
                .padding(LayoutMetrics.margin)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// "No se pudo guardar", dicho **antes de dejar salir del resumen** (5.1).
    ///
    /// No bloquea ni pide nada: la caminata no se ha perdido —su snapshot sigue en disco y vuelve
    /// al relanzar la app— y lo único que hace falta es que Paul lo sepa y no se quede esperando
    /// verla en el historial. El color del error es el rol medido de B-2, no un `.red` a mano.
    private var notPersistedNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("No se pudo guardar esta caminata")
                    .font(.subheadline.weight(.semibold))
                Text("Sigue a salvo: volverá a aparecer la próxima vez que abras la app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Colors.error)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Surface.cardPaddingHorizontal)
        .padding(.vertical, Surface.cardPaddingVertical)
        .background(Colors.error.opacity(Surface.noticeTintOpacity), in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}
