import SwiftUI

/// Pantalla completa bloqueante sin conteo de pasos: la única degradación bloqueante
/// (AD-11). Referencia: `screen-motion-denied` de la v3 (`index.html:249`).
///
/// Denegado o restringido ofrece "Abrir Ajustes"; sin coprocesador, no, porque Ajustes
/// no lo arregla. Las dos vuelven a Inicio sin sesión.
struct MotionBlockedView: View {

    let reason: SessionStore.MotionBlock
    let onBack: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        switch reason {
        case .permissionDenied:
            PermissionScreen(
                systemImage: "figure.walk.motion.trianglebadge.exclamationmark",
                title: "Sensor de movimiento requerido",
                message: "WalkTracker necesita acceso a Movimiento y forma física para contar tus pasos. Actívalo en Ajustes."
            ) {
                Button(action: openSettings) {
                    Text("Abrir Ajustes")
                        .font(Typography.buttonLabel)
                        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)

                backButton
            }
        case .deviceUnsupported:
            PermissionScreen(
                systemImage: "figure.walk.motion.trianglebadge.exclamationmark",
                title: "Sensor de movimiento no disponible",
                message: "Este dispositivo no puede contar pasos: no tiene el sensor de movimiento que WalkTracker necesita."
            ) {
                backButton
            }
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Text("Volver al inicio")
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.touchTargetMin)
        }
        .buttonStyle(.glass)
        .controlSize(.extraLarge)
    }

    /// Los ajustes de la app, donde está el interruptor de Movimiento y forma física.
    ///
    /// `app-settings:` es el valor actual de la constante de UIKit que abre los ajustes
    /// de la app, comprobado por test (`MotionBlockedViewTests`). Se escribe tal cual
    /// para que la vista no use UIKit (AD-10).
    static let settingsURL = URL(string: "app-settings:")

    private func openSettings() {
        guard let url = Self.settingsURL else { return }
        openURL(url)
    }
}
