import SwiftUI

/// Pestaña Inicio. Su CTA principal es "Iniciar caminata" (AD-14).
struct HomeView<Diagnostics: View>: View {

    let store: SessionStore
    let diagnostics: Diagnostics?

    @State private var startFailed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "figure.walk")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Button(action: start) {
                    Text("Iniciar caminata")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .disabled(store.hasSession)
                Spacer()
                if let diagnostics {
                    // Solo `DEBUG` y no es UI de producto: fuera del String Catalog.
                    NavigationLink {
                        diagnostics
                    } label: {
                        Text(verbatim: "Diagnóstico de la capa nativa")
                    }
                }
            }
            .padding()
            .navigationTitle("Inicio")
            .alert("No se pudo iniciar la caminata", isPresented: $startFailed) {
                Button("Aceptar", role: .cancel) {}
            }
        }
    }

    private func start() {
        do {
            try store.start()
        } catch {
            startFailed = true
        }
    }
}
