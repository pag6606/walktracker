#if DEBUG
import Domain
import SwiftUI

/// Superficie de verificación en el iPhone de la capa nativa extraída en la historia 8.6.
///
/// **Solo `DEBUG`, y temporal:** se borra cuando exista la UI de sesión (registrado en
/// `deferred-work.md`). Usa los cuatro puertos y nada más: no importa CoreMotion,
/// CoreHaptics, HealthKit ni ActivityKit, ni guarda estado de sesión (AD-10). Los textos
/// son literales a propósito: no es UI de producto y no entra al String Catalog.
struct NativeLayerDiagnosticsView: View {

    let clock: any ClockPort
    let motion: any MotionPort
    let feedback: any FeedbackPort
    let health: any HealthPort
    let liveActivity: any LiveActivityPort

    @State private var motionStatus: PermissionStatus?
    @State private var countingSince: Date?
    @State private var liveSample: PedometerSample?
    @State private var queryResult: String?

    @State private var soundEnabled = true
    @State private var lastFeedback: FeedbackEvent?

    @State private var healthStatus: PermissionStatus?
    @State private var healthResult: String?

    @State private var liveActivityStatus: PermissionStatus?
    @State private var liveActivityResult: String?
    @State private var liveActivityRunning = false

    var body: some View {
        List {
            motionSection
            feedbackSection
            healthSection
            liveActivitySection
        }
        .navigationTitle("Capa nativa")
        .onAppear(perform: refreshStatuses)
        .task(id: countingSince) {
            guard let countingSince else { return }
            for await sample in motion.updates(from: countingSince) {
                liveSample = sample
            }
            // Sin cancelación, el sistema detuvo el stream: la UI deja de decir que cuenta.
            // `status` explica la causa solo si fue el permiso.
            if !Task.isCancelled {
                self.countingSince = nil
            }
            motionStatus = motion.status
        }
    }

    // MARK: - Podómetro

    private var motionSection: some View {
        Section("Podómetro") {
            LabeledContent("Permiso", value: text(motionStatus))
            Button("Pedir permiso") {
                Task { motionStatus = await motion.requestPermission() }
            }
            if countingSince == nil {
                Button("Contar pasos en vivo") {
                    liveSample = nil
                    countingSince = clock.now
                }
            } else {
                Button("Detener conteo", role: .destructive) {
                    countingSince = nil
                }
            }
            LabeledContent("Pasos", value: liveSample.map { "\($0.steps)" } ?? "—")
            LabeledContent("Distancia", value: metres(liveSample?.distance))
            Button("Consultar la última hora") {
                Task { await queryLastHour() }
            }
            if let queryResult {
                Text(queryResult).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func queryLastHour() async {
        let end = clock.now
        do throws(CapabilityError) {
            let sample = try await motion.query(from: end.addingTimeInterval(-3600), to: end)
            queryResult = sample.map { "\($0.steps) pasos · \(metres($0.distance))" } ?? "Sin datos (nil)"
        } catch {
            queryResult = text(error)
        }
        motionStatus = motion.status
    }

    // MARK: - Háptica

    private var feedbackSection: some View {
        Section("Háptica y sonido") {
            Toggle("Sonido", isOn: $soundEnabled)
            ForEach(FeedbackEvent.allCases, id: \.self) { event in
                Button(name(event)) {
                    feedback.fire(event, soundEnabled: soundEnabled)
                    lastFeedback = event
                }
            }
            if let lastFeedback {
                Text("Último disparo: \(name(lastFeedback))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Salud

    private var healthSection: some View {
        Section("Apple Salud") {
            LabeledContent("Escritura", value: text(healthStatus))
            Button("Pedir autorización") {
                Task {
                    do throws(CapabilityError) {
                        healthStatus = try await health.requestAuthorization()
                    } catch {
                        healthResult = text(error)
                    }
                    healthStatus = health.status
                }
            }
            Button("Escribir workout de prueba (1 min · 100 pasos · 80 m)") {
                Task { await writeTestWorkout() }
            }
            if let healthResult {
                Text(healthResult).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func writeTestWorkout() async {
        let end = clock.now
        do {
            let record = try WorkoutRecord(start: end.addingTimeInterval(-60), end: end, steps: 100, distance: 80)
            try await health.writeWorkout(record)
            healthResult = "Escrito. Búscalo en Salud → Entrenamientos."
        } catch let error as CapabilityError {
            healthResult = text(error)
        } catch {
            healthResult = "Registro inválido: \(error)"
        }
        healthStatus = health.status
    }

    // MARK: - Live Activity

    private var liveActivitySection: some View {
        Section("Live Activity") {
            LabeledContent("Permiso", value: text(liveActivityStatus))
            if liveActivityRunning {
                Button("Actualizar con los pasos en vivo") {
                    Task { await liveActivity.update(currentLiveActivityState()) }
                }
                Button("Terminar", role: .destructive) {
                    Task {
                        await liveActivity.end()
                        liveActivityRunning = false
                        liveActivityResult = "Terminada."
                    }
                }
            } else {
                Button("Iniciar") {
                    Task { await startLiveActivity() }
                }
            }
            if let liveActivityResult {
                Text(liveActivityResult).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func startLiveActivity() async {
        do throws(CapabilityError) {
            try await liveActivity.start(sessionID: UUID(), state: currentLiveActivityState())
            liveActivityRunning = true
            liveActivityResult = "Iniciada. Bloquea el iPhone para verla."
        } catch {
            liveActivityResult = text(error)
        }
        liveActivityStatus = liveActivity.status
    }

    private func currentLiveActivityState() -> LiveActivityState {
        LiveActivityState(
            steps: liveSample?.steps ?? 0,
            distance: liveSample?.distance ?? 0,
            pace: nil,
            timerStart: countingSince ?? clock.now
        )
    }

    // MARK: - Textos de diagnóstico

    private func refreshStatuses() {
        motionStatus = motion.status
        healthStatus = health.status
        liveActivityStatus = liveActivity.status
    }

    private func text(_ status: PermissionStatus?) -> String {
        switch status {
        case nil: "—"
        case .notDetermined: "Sin decidir"
        case .granted: "Concedido"
        case .denied: "Denegado"
        case .restricted: "Restringido"
        case .unavailable: "No disponible"
        }
    }

    private func text(_ error: CapabilityError) -> String {
        switch error {
        case .unavailable: "No disponible en este dispositivo"
        case .notAuthorized: "Sin permiso"
        case .failed(let operation): "Falló el sistema en \(operation)"
        }
    }

    private func name(_ event: FeedbackEvent) -> String {
        switch event {
        case .sessionStart: "Inicio de sesión"
        case .kilometer: "Kilómetro"
        case .goal: "Meta semanal"
        case .achievement: "Logro"
        }
    }

    private func metres(_ distance: Double?) -> String {
        distance.map { String(format: "%.1f m", $0) } ?? "—"
    }
}
#endif
