import Domain
import SwiftUI

/// Vista raíz. En la historia 8.5 solo demuestra que el cableado llega: el `TabView`
/// de cuatro pestañas y el `fullScreenCover` de sesión activa (AD-14) son trabajo de
/// los epics de UI.
///
/// Recibe el reloj **por su puerto**: una vista nunca importa un framework de sistema
/// ni construye un `Calendar` (AD-10, AD-19).
struct RootView: View {

    let clock: any ClockPort

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 48))
            Text("WalkTracker")
                .font(.largeTitle.bold())
            Text(clock.now, format: .dateTime.year().month().day())
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
