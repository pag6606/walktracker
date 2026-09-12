import ActivityKit
import Shared
import SwiftUI
import WidgetKit

/// La extensión **solo renderiza** (AD-15). No calcula, no lee ficheros y no importa
/// `Domain` — el grafo de targets lo impide: `Domain` no está enlazado aquí, así que
/// sus símbolos no existen en este módulo.
///
/// El único cálculo permitido es animar el cronómetro con `Text(timerInterval:)`,
/// que no consume actualizaciones (AD-21).
struct WalkTrackerLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WalkTrackerActivityAttributes.self) { context in
            LockScreenView(snapshot: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.stepsText, systemImage: "figure.walk")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distanceText)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        TimerView(snapshot: context.state)
                        Spacer()
                        Text(context.state.paceText)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.walk")
            } compactTrailing: {
                TimerView(snapshot: context.state)
            } minimal: {
                Image(systemName: "figure.walk")
            }
        }
    }
}

/// Cronómetro: mientras la sesión corre lo anima el sistema desde `timerStart` —que
/// ya viene descontado el tiempo en pausa—; en pausa se pinta el valor congelado,
/// porque un `timerInterval` seguiría avanzando.
struct TimerView: View {

    let snapshot: ActivitySnapshot

    var body: some View {
        if snapshot.isPaused {
            Text(snapshot.frozenElapsedText)
                .monospacedDigit()
        } else {
            Text(timerInterval: snapshot.timerStart...Date.distantFuture,
                 countsDown: false)
                .monospacedDigit()
        }
    }
}

struct LockScreenView: View {

    let snapshot: ActivitySnapshot

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: snapshot.isPaused ? "pause.circle" : "figure.walk")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                TimerView(snapshot: snapshot)
                    .font(.title3.bold())
                Text(snapshot.paceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(snapshot.distanceText)
                    .font(.headline)
                Text(snapshot.stepsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
