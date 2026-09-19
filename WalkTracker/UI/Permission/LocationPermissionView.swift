import SwiftUI

/// Pre-pantalla de ubicación para el clima (2.1, AD-11): aparece **encima de la sesión ya
/// abierta**, arriba, sin tapar los controles ni detener el conteo. "Permitir" dispara el
/// diálogo del sistema; "Ahora no" la cierra y no vuelve a salir al iniciar mientras la app
/// siga abierta. "Ahora no" sigue activo con el diálogo pedido: si el sistema nunca responde, la
/// pre-pantalla no se queda bloqueada encima de la caminata.
///
/// No conoce el store ni el puerto: recibe las intenciones ya enlazadas.
struct LocationPermissionView: View {

    /// El diálogo del sistema está pedido: "Permitir" no admite otro toque.
    let isRequesting: Bool
    let onAllow: () -> Void
    let onDecline: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "cloud.sun")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("¿Añadir el clima a tus caminatas?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("WalkTracker usa tu ubicación aproximada al empezar para guardar el clima. La caminata ya está contando.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Spacing.s))
                : AnyLayout(HStackLayout(spacing: Spacing.m))
            layout {
                Button(action: onDecline) {
                    Text("Ahora no")
                        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
                }
                .buttonStyle(.glass)

                Button(action: onAllow) {
                    Group {
                        if isRequesting {
                            ProgressView()
                        } else {
                            Text("Permitir")
                        }
                    }
                    .font(Typography.buttonLabel)
                    .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
                }
                .buttonStyle(.glassProminent)
                .disabled(isRequesting)
            }
        }
        .padding(.horizontal, Surface.cardPaddingHorizontal)
        .padding(.vertical, Surface.cardPaddingVertical)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .contain)
    }
}
