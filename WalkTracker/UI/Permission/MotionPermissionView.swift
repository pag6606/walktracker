import SwiftUI

/// Pre-pantalla explicativa de Motion & Fitness (AD-11): el permiso nunca se pide en
/// frío. "Continuar" dispara el diálogo del sistema; "Ahora no" vuelve a Inicio.
///
/// No conoce el store ni el puerto: recibe las intenciones ya enlazadas.
struct MotionPermissionView: View {

    /// El diálogo del sistema está en pantalla: los botones no admiten otro toque.
    let isRequesting: Bool
    let onContinue: () -> Void
    let onDecline: () -> Void

    var body: some View {
        PermissionScreen(
            systemImage: "figure.walk.motion",
            title: "Cuenta tus pasos",
            message: "WalkTracker usa el sensor de movimiento del iPhone para contar tus pasos, también con la pantalla bloqueada y el teléfono en el bolsillo. A continuación, iOS te pedirá acceso a Movimiento y forma física."
        ) {
            Button(action: onContinue) {
                Group {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Text("Continuar")
                    }
                }
                .font(Typography.buttonLabel)
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)

            Button(action: onDecline) {
                Text("Ahora no")
                    .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
            }
            .buttonStyle(.glass)
            .controlSize(.extraLarge)
        }
        .disabled(isRequesting)
    }
}

/// Esqueleto común de la pre-pantalla y de la pantalla bloqueante: símbolo, título y
/// explicación desplazables (Dynamic Type sin recortes) y las acciones abajo.
struct PermissionScreen<Actions: View>: View {

    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LayoutMetrics.margin)
            .padding(.top, 48)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.m) {
                actions
            }
            .padding(LayoutMetrics.margin)
        }
    }
}
