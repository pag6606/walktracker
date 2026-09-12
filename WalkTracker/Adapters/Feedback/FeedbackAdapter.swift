import AudioToolbox
import CoreHaptics
import Domain
import Foundation
import OSLog
import Synchronization

/// `FeedbackPort` sobre CoreHaptics y sonidos de sistema (CAP-12) — AD-10.
///
/// Extraído de `feature/flutter-substrate:ios/Runner/AppDelegate.swift` (líneas 164-238),
/// con **los mismos parámetros** de intensidad, nitidez y `SystemSoundID`. No se porta:
/// - el respaldo con `UIImpactFeedbackGenerator`: todo iPhone con iOS 26 (AD-2) soporta
///   CoreHaptics, así que era código muerto que además exigía el main actor;
/// - la rama "resto" de los parámetros (0,4/0,3 · 1052): `FeedbackEvent` es cerrado y el
///   `switch` exhaustivo no la admite;
/// - el estado `soundEnabled`: la preferencia es de `SettingsStore` y llega por llamada.
///
/// **Reinicio del motor.** El motor se crea perezosamente en el primer disparo. El sistema
/// lo detiene al pasar la app a background y lo reinicia tras un fallo del servidor de
/// háptica; ambos handlers marcan que hay que arrancarlo, y el siguiente disparo lo hace.
final class FeedbackAdapter: FeedbackPort {

    /// Parámetros de un evento: háptica transitoria y sonido de sistema.
    struct Parameters: Equatable, Sendable {
        let intensity: Float
        let sharpness: Float
        let soundID: SystemSoundID
    }

    private struct Engine: ~Copyable {
        var engine: CHHapticEngine?
    }

    private let engine = Mutex(Engine())
    /// Lo escriben los handlers del motor, desde colas del sistema. Atómico y fuera del
    /// `Mutex` para que un handler invocado con el lock tomado no se bloquee.
    private let needsStart = Atomic<Bool>(true)
    private let supportsHaptics: Bool
    private let log = Logger(subsystem: "com.walktracker.app", category: "Feedback")

    init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// El mapa del original, evento a evento.
    static func parameters(for event: FeedbackEvent) -> Parameters {
        switch event {
        case .sessionStart: Parameters(intensity: 0.8, sharpness: 0.5, soundID: 1054)
        case .kilometer: Parameters(intensity: 0.6, sharpness: 0.5, soundID: 1057)
        case .goal, .achievement: Parameters(intensity: 1.0, sharpness: 0.8, soundID: 1025)
        }
    }

    func fire(_ event: FeedbackEvent, soundEnabled: Bool) {
        let parameters = Self.parameters(for: event)
        playHaptic(parameters)
        if soundEnabled {
            AudioServicesPlaySystemSound(parameters.soundID)
        }
    }

    private func playHaptic(_ parameters: Parameters) {
        guard supportsHaptics else { return }
        do {
            try engine.withLock { state in
                let engine = try state.engine ?? makeEngine()
                state.engine = engine
                if needsStart.exchange(false, ordering: .sequentiallyConsistent) {
                    do {
                        try engine.start()
                    } catch {
                        needsStart.store(true, ordering: .sequentiallyConsistent)
                        throw error
                    }
                }
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: parameters.intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: parameters.sharpness),
                    ],
                    relativeTime: 0
                )
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
            }
        } catch {
            // Un feedback perdido no es un fallo de sesión: se registra y se sigue. Si el
            // motor murió, el siguiente disparo lo vuelve a arrancar.
            needsStart.store(true, ordering: .sequentiallyConsistent)
            log.error("Háptica no reproducida: \(String(describing: error), privacy: .public)")
        }
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        // Sin háptica en curso el motor se apaga solo: no queda encendido toda la caminata
        // (AD-21). El `stoppedHandler` marca que el siguiente disparo lo arranque.
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak self] in
            self?.needsStart.store(true, ordering: .sequentiallyConsistent)
        }
        engine.stoppedHandler = { [weak self] _ in
            self?.needsStart.store(true, ordering: .sequentiallyConsistent)
        }
        needsStart.store(true, ordering: .sequentiallyConsistent)
        return engine
    }
}
