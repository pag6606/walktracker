import Domain
import SwiftUI

/// Vista raíz. Hasta que lleguen los epics de UI solo demuestra que el cableado llega:
/// el `TabView` de cuatro pestañas y el `fullScreenCover` de sesión activa (AD-14) son
/// trabajo de esos epics.
///
/// Recibe el reloj **por su puerto**: una vista nunca importa un framework de sistema
/// ni construye un `Calendar` (AD-10, AD-19).
///
/// En `DEBUG` enlaza la pantalla de diagnóstico de la capa nativa (historia 8.6). Llega
/// ya construida desde la app, así que esta vista no conoce los puertos que usa; en
/// `Release` el tipo es `Never` y el enlace no existe.
struct RootView<Diagnostics: View>: View {

    let clock: any ClockPort
    private let diagnostics: Diagnostics?

    init(clock: any ClockPort, @ViewBuilder diagnostics: () -> Diagnostics) {
        self.clock = clock
        self.diagnostics = diagnostics()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 48))
                Text("WalkTracker")
                    .font(.largeTitle.bold())
                Text(clock.now, format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary)
                if let diagnostics {
                    NavigationLink("Diagnóstico de la capa nativa") {
                        diagnostics
                    }
                    .padding(.top, 24)
                }
            }
            .padding()
        }
    }
}

extension RootView where Diagnostics == Never {

    init(clock: any ClockPort) {
        self.clock = clock
        self.diagnostics = nil
    }
}
