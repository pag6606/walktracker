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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Button(action: onDecline) {
                    Text("Ahora no")
                        .frame(maxWidth: .infinity, minHeight: 44)
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
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(isRequesting)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }
}
