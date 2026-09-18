import Domain
import Foundation
import OSLog

/// Registro de medición de la caminata del gate (8.4, retro del Epic 1 A-3).
///
/// Una línea por evento en `OSLog`, subsistema `com.walktracker.app`, categoría `Medicion`,
/// nivel `notice`: `info` no se persiste en el dispositivo y se perdería al extraer el
/// registro después de caminar. Sin red, sin fichero propio y sin telemetría: el registro
/// vive en el log del sistema y se exporta a mano con `sudo log collect --device`. Solo
/// lleva conteo, distancia y tiempos de la sesión; nunca ubicación.
///
/// **Formato estable** (lo lee `Scripts/walk-report/report.js`; si cambias uno, cambia el
/// otro y la fixture compartida `MeasurementLogFixture.txt`):
///
///     WTM1 event=<sample|query|queryLate|estimate|session> sid=<inicio de la sesión> clave=valor …
///
/// - El prefijo lleva la versión del formato: el informe rechaza la que no conoce.
/// - Instantes en milisegundos Unix (como el snapshot, domain-model.md §8); distancias en
///   metros con dos decimales; una métrica ausente es `nil`, nunca `0` (AD-4).
/// - El orden de las claves es fijo.
///
/// Las funciones de formateo son puras y se prueban sin `OSLog`; `record(_:)` es lo único
/// que escribe.
enum MeasurementLog {

    /// Prefijo con la versión del formato.
    static let prefix = "WTM1"

    /// Desenlace de una consulta de reconciliación.
    enum QueryOutcome: String, Sendable, CaseIterable {
        /// El sistema dio un acumulado ≥ lo ya visto y se aplica.
        case data
        /// La consulta volvió sin datos para el rango.
        case noResult = "nil"
        /// Ganó el temporizador de `reconciliationTimeoutS`.
        case timeout
        /// El sistema dio un acumulado menor que lo ya visto (R1). Desde la corrección del
        /// 2026-09-17 **también se aplica**: es dato, y `record` no resta. El desenlace se
        /// mantiene aparte de `data` para seguir midiendo cuánto va la consulta por detrás.
        case belowSeen
        /// La consulta lanzó un error.
        case error
    }

    /// Por qué una estimación no llegó a sumar pasos aunque la consulta degradó. Los mismos
    /// casos y los mismos `rawValue` que `GapEstimator.Skip`, que es quien los decide: leer el
    /// registro debe decir qué defensa actuó, no solo que el resultado fue 0.
    enum EstimateSkip: String, Sendable, CaseIterable {
        /// La sesión dejó de estar `active` durante la reconciliación (pausa o fin): no se
        /// estima sobre una sesión que ya no corre.
        case notActive
        /// Los pasos medidos crecieron desde el inicio del gap: el stream ya trajo sus pasos
        /// (evidencia de R2), y estimarlos los contaría dos veces.
        case streamAdvanced
        /// Había menos de `GapEstimator.minPriorSampleS` de sesión al abrir el gap: la cadencia
        /// medida todavía no es representativa.
        case noPriorSample
        /// El gap supera `maxEstimableGapS` (R1): la cadencia de hace tanto ya no dice gran
        /// cosa del rato sin datos, así que no se estima nada.
        case gapAboveCap
        /// La estimación no dio ni un paso: sin pasos medidos al abrir el gap (cadencia 0), con
        /// un gap no positivo (el reloj fue hacia atrás) o con un valor no representable.
        case noCadence

        /// La razón que decidió el dominio, tal cual: los `rawValue` son los mismos y el
        /// `switch` exhaustivo obliga a añadir aquí cualquier defensa nueva del estimador.
        init(_ skip: GapEstimator.Skip) {
            switch skip {
            case .notActive: self = .notActive
            case .streamAdvanced: self = .streamAdvanced
            case .noPriorSample: self = .noPriorSample
            case .gapAboveCap: self = .gapAboveCap
            case .noCadence: self = .noCadence
            }
        }
    }

    /// Versión y build de la app que escribe el registro: comprueba que la caminata usó el
    /// build de TestFlight.
    struct AppBuild: Equatable, Sendable {
        let version: String
        let build: String

        init(version: String, build: String) {
            self.version = MeasurementLog.token(version)
            self.build = MeasurementLog.token(build)
        }

        init(bundle: Bundle) {
            self.init(
                version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "nil",
                build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "nil"
            )
        }

        /// El build de la app en ejecución.
        static let current = AppBuild(bundle: .main)
    }

    /// Transición o hito de la sesión.
    enum Transition: String, Sendable, CaseIterable {
        case start
        case pause
        case resume
        case finish
        /// La app pasó a segundo plano con la sesión abierta.
        case background
        /// La app volvió a primer plano y la reconciliación del gap terminó.
        case active
        /// Sesión restaurada al relanzar (1.6).
        case restore
        /// Sesión huérfana cerrada al relanzar (AD-18).
        case orphan
        /// "Descartar pasos estimados" confirmado.
        case discardEstimated
        /// El sistema terminó el stream del podómetro sin que nadie lo cancelara.
        case streamEnded
    }

    // MARK: - Formateo

    /// Muestra del stream del podómetro, tal como llega (acumulada desde `start`).
    static func sampleLine(sessionStartedAt: Date, sample: PedometerSample) -> String {
        line("sample", sessionStartedAt, [
            ("start", ms(sample.start)),
            ("end", ms(sample.end)),
            ("steps", String(sample.steps)),
            ("distance", meters(sample.distance)),
        ])
    }

    /// Consulta de reconciliación del rango `[start, end]`. `result` es la muestra que dio el
    /// sistema, aplicada o no; `seen`, el mayor acumulado visto del tramo al empezar a consultar;
    /// `durationMs`, lo que tardó en resolverse la carrera, medido en la tarea que la ganó
    /// (la respuesta o el temporizador).
    static func queryLine(
        sessionStartedAt: Date,
        start: Date,
        end: Date,
        result: PedometerSample?,
        seen: Int,
        durationMs: Int,
        outcome: QueryOutcome
    ) -> String {
        queryLine(event: "query", sessionStartedAt, start, end, result, seen, durationMs, outcome)
    }

    /// Respuesta de una consulta que llegó **después** del timeout y se descartó. Mismos campos
    /// que `query`, con `durationMs` real desde que se lanzó: la duración que el timeout censuró.
    static func lateQueryLine(
        sessionStartedAt: Date,
        start: Date,
        end: Date,
        result: PedometerSample?,
        seen: Int,
        durationMs: Int,
        outcome: QueryOutcome
    ) -> String {
        queryLine(event: "queryLate", sessionStartedAt, start, end, result, seen, durationMs, outcome)
    }

    /// Desenlace de una consulta que respondió (sin error ni timeout).
    static func outcome(of result: PedometerSample?, seen: Int) -> QueryOutcome {
        guard let result else { return .noResult }
        return result.steps >= seen ? .data : .belowSeen
    }

    private static func queryLine(
        event: String,
        _ sessionStartedAt: Date,
        _ start: Date,
        _ end: Date,
        _ result: PedometerSample?,
        _ seen: Int,
        _ durationMs: Int,
        _ outcome: QueryOutcome
    ) -> String {
        line(event, sessionStartedAt, [
            ("start", ms(start)),
            ("end", ms(end)),
            ("result", result.map { String($0.steps) } ?? "nil"),
            ("distance", meters(result?.distance)),
            ("seen", String(seen)),
            ("ms", String(durationMs)),
            ("outcome", outcome.rawValue),
        ])
    }

    /// Estimación del `GapEstimator` para el gap `[gapStart, gapEnd]`. `steps` puede ser 0: la
    /// estimación corrió pero no sumó nada. Con `skipped`, no se estimó y `steps` es 0.
    static func estimateLine(
        sessionStartedAt: Date,
        gapStart: Date,
        gapEnd: Date,
        steps: Int,
        skipped: EstimateSkip? = nil
    ) -> String {
        line("estimate", sessionStartedAt, [
            ("gapStart", ms(gapStart)),
            ("gapEnd", ms(gapEnd)),
            ("steps", String(steps)),
            ("skipped", skipped?.rawValue ?? "nil"),
        ])
    }

    /// Transición de la sesión con su estado en `at`, después de aplicarla. `start` y `restore`
    /// llevan además `version` y `build` de la app.
    static func sessionLine(transition: Transition, session: Session, at: Date, build: AppBuild = .current) -> String {
        let metrics = session.metrics(at: at)
        var fields = [
            ("transition", transition.rawValue),
            ("at", ms(at)),
            ("status", session.status.rawValue),
            ("elapsedS", String(Int(session.elapsedS(at: at).rounded(.down)))),
            ("measured", String(session.stepsMeasured)),
            ("estimated", String(session.stepsEstimated)),
            ("systemDistance", meters(session.systemDistanceM)),
            ("distance", meters(metrics.distanceM)),
        ]
        if transition == .start || transition == .restore {
            fields += [("version", build.version), ("build", build.build)]
        }
        return line("session", session.startedAt, fields)
    }

    // MARK: - Escritura

    private static let logger = Logger(subsystem: "com.walktracker.app", category: "Medicion")

    /// Escribe la línea en el log del sistema, en `notice` y pública: sin `public`, pasos y
    /// distancia saldrían como `<private>` en el registro extraído del dispositivo.
    static func record(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }

    // MARK: - Piezas

    private static func line(_ event: String, _ sessionStartedAt: Date, _ fields: [(String, String)]) -> String {
        ([prefix, "event=\(event)", "sid=\(ms(sessionStartedAt))"] + fields.map { "\($0.0)=\($0.1)" })
            .joined(separator: " ")
    }

    /// Milisegundos Unix redondeados.
    static func ms(_ date: Date) -> String {
        let value = (date.timeIntervalSince1970 * 1000).rounded()
        guard value.isFinite, abs(value) < 9.0e15 else { return "nil" }
        return String(Int64(value))
    }

    /// Un valor sin espacios ni `=`, para que la línea siga siendo `clave=valor`.
    static func token(_ value: String) -> String {
        let cleaned = value.map { $0.isWhitespace || $0 == "=" ? "_" : $0 }
        return cleaned.isEmpty ? "nil" : String(cleaned)
    }

    /// Metros con dos decimales, sin depender del locale; `nil` si no hay dato.
    static func meters(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.2f", value)
    }

    /// Milisegundos de una `Duration`, redondeados.
    static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        let value = (Double(seconds) * 1000 + Double(attoseconds) / 1e15).rounded()
        return value.isFinite && value >= 0 && value < Double(Int.max) ? Int(value) : 0
    }
}
