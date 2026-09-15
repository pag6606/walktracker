import Domain
import Foundation
import Synchronization
import Testing

@testable import WalkTracker

/// Soporte común de los tests de `SessionStore` (retro del Epic 1, A-1): el instante base, el
/// store montado sobre sus stubs, abrir una sesión con pasos y la espera por condición.
///
/// Cada suite pasa los parámetros de su montaje (timeout, umbral de huérfana, permiso,
/// almacenamiento) y añade en su fichero, como extensión privada, los pasos que solo usa ella.

/// Una suite del store: `Self.t0` es el instante base común.
protocol SessionStoreSuite {}

extension SessionStoreSuite {

    /// Instante base de los tests del store: el reloj arranca aquí.
    static var t0: Date { SessionStoreFixture.t0 }
}

/// `SessionStore` sobre un `ClockStub`, un `MotionStub`, un `StorageStub`, un `LocationStub` y un
/// `WeatherStub`, con las líneas de medición en un `LineSink`.
@MainActor
struct SessionStoreFixture {

    nonisolated static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// Umbral de la sesión huérfana del montaje: 6 h, el valor actual de `formulas.json` (21600 s).
    nonisolated static let orphanThresholdS: TimeInterval = 6 * 60 * 60

    let clock: ClockStub
    let motion: MotionStub
    let storage: StorageStub
    let location: LocationStub
    let weather: WeatherStub
    /// Las líneas `WTM1` que escribe el store. Solo observan: sirven de condición de espera.
    let measurements: LineSink
    let store: SessionStore

    /// - Parameters:
    ///   - motion: permiso concedido por defecto.
    ///   - storage: vacío por defecto; "relanzar" es montar otro store sobre el mismo.
    ///   - instant: instante inicial del reloj.
    ///   - timeoutS: tope de la reconciliación. Largo por defecto: una consulta inmediata nunca
    ///     pierde contra el temporizador en una máquina cargada.
    ///   - orphanThresholdS: umbral de la sesión huérfana.
    ///   - location: permiso de ubicación **denegado** por defecto: sin pre-pantalla ni clima, así
    ///     las suites anteriores a la 2.1 no ven la captura.
    ///   - weather: responde WMO 61 y 18 °C por defecto.
    ///   - weatherStepTimeoutS: tope de cada paso de la captura del clima (ubicación y clima).
    init(
        motion: MotionStub = MotionStub(status: .granted),
        storage: StorageStub = StorageStub(),
        at instant: Date = SessionStoreFixture.t0,
        strideM: Double = 0.655,
        timeoutS: TimeInterval = 5,
        orphanThresholdS: TimeInterval = SessionStoreFixture.orphanThresholdS,
        location: LocationStub = LocationStub(status: .denied),
        weather: WeatherStub = WeatherStub(),
        weatherStepTimeoutS: TimeInterval = 5
    ) {
        let measurements = LineSink()
        clock = ClockStub(now: instant)
        self.motion = motion
        self.storage = storage
        self.location = location
        self.weather = weather
        self.measurements = measurements
        store = SessionStore(
            clock: clock,
            motion: motion,
            storage: storage,
            strideM: strideM,
            reconciliationTimeoutS: timeoutS,
            orphanSessionThresholdS: orphanThresholdS,
            location: location,
            weather: weather,
            weatherStepTimeoutS: weatherStepTimeoutS,
            measure: { measurements.append($0) }
        )
    }

    var session: Session? { store.session }
    var steps: Int? { store.session?.stepsMeasured }

    /// Abre la sesión y deja `steps` pasos contados en el primer tramo.
    func startWalking(steps: Int, distance: Double? = nil) async {
        await store.start()
        motion.emit(steps: steps, distance: distance)
        await waitUntil { self.store.session?.stepsMeasured == steps }
    }

    /// Las líneas de medición de `event` (`sample`, `query`, `queryLate`…).
    func measurementLines(_ event: String) -> [String] {
        measurements.lines.filter { $0.hasPrefix("WTM1 event=\(event) ") }
    }
}

/// Destino de líneas de medición de test, seguro entre hilos.
final class LineSink: Sendable {

    private let storage = Mutex<[String]>([])

    func append(_ line: String) {
        storage.withLock { $0.append(line) }
    }

    var lines: [String] { storage.withLock { $0 } }
}

/// Espera a que se cumpla `condition` (el consumidor del stream procesó lo emitido, la
/// consulta llegó al stub…). La única espera de los tests del store: nunca un `sleep` fijo.
/// Falla, no cuelga.
@MainActor
func waitUntil(
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0..<2_000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("La condición no se cumplió a tiempo", sourceLocation: sourceLocation)
}
