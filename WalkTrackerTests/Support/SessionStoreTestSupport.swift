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

/// `SessionStore` sobre un `ClockStub`, un `MotionStub`, un `StorageStub`, un `LocationStub`, un
/// `WeatherStub` y un `RandomStub`, con las líneas de medición en un `LineSink`.
@MainActor
struct SessionStoreFixture {

    nonisolated static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// Umbral de la sesión huérfana del montaje: 6 h, el valor actual de `formulas.json` (21600 s).
    nonisolated static let orphanThresholdS: TimeInterval = 6 * 60 * 60
    /// Gap máximo estimable del montaje: 20 min, el valor de `formulas.json` (1200 s).
    nonisolated static let maxEstimableGapS: TimeInterval = 20 * 60

    let clock: ClockStub
    let motion: MotionStub
    let storage: StorageStub
    let location: LocationStub
    let weather: WeatherStub
    let random: RandomStub
    /// Dueño de los ajustes, montado sobre el mismo `StorageStub` que el snapshot.
    let settings: SettingsStore
    /// Dueño del historial (5.1), sobre el mismo `StorageStub`. "Relanzar" es montar otro
    /// `SessionStoreFixture` sobre el mismo stub: el historial y el snapshot vuelven con él.
    let history: HistoryStore
    /// Dueño del estado de los logros (5.1), sobre el mismo `StorageStub`. **Una sola
    /// instancia**, compartida por el store de ajustes y el de sesión: son los dos que
    /// desbloquean logros (el anillo `weekly_goal`, el cierre los demás) y dos dueños del mismo
    /// fichero no verían lo que escribe el otro (AD-16).
    let achievements: AchievementsStore
    /// Las líneas `WTM1` que escribe el store. Solo observan: sirven de condición de espera.
    let measurements: LineSink
    let store: SessionStore

    /// - Parameters:
    ///   - motion: permiso concedido por defecto.
    ///   - storage: vacío por defecto; "relanzar" es montar otro store sobre el mismo.
    ///   - instant: instante inicial del reloj.
    ///   - defaultStrideM: la zancada **por omisión**, la de `formulas.json`. No es la de la
    ///     sesión: desde la 2.3 el override de `settings` gana, y `openSession()` lo resuelve al
    ///     abrir. Para montar una zancada recalibrada, o se guarda con
    ///     `settings.saveStride(fromText:)` o se parte de un `StorageStub(settings:)`.
    ///   - timeoutS: tope de la reconciliación. Largo por defecto: una consulta inmediata nunca
    ///     pierde contra el temporizador en una máquina cargada.
    ///   - orphanThresholdS: umbral de la sesión huérfana.
    ///   - maxEstimableGapS: gap máximo estimable (R1); por encima no se estima nada.
    ///   - location: permiso de ubicación **denegado** por defecto: sin pre-pantalla ni clima, así
    ///     las suites anteriores a la 2.1 no ven la captura.
    ///   - weather: responde WMO 61 y 18 °C por defecto.
    ///   - weatherStepTimeoutS: tope de cada paso de la captura del clima (ubicación y clima).
    ///   - quotes: banco de frases. **Vacío por defecto**: sin frase ni overlay, así las
    ///     suites anteriores a la 2.2 no ven la selección.
    ///   - random: azar determinista para elegir la frase.
    ///   - catalog: el catálogo congelado de los 14 logros. Por omisión **el del bundle**, que es
    ///     el que la app carga: los tests de logros comprueban la conducta real, no una tabla de
    ///     prueba (AD-5).
    ///   - timeZone: zona del `AppCalendar` del montaje. **UTC por omisión**, como siempre; un
    ///     test que quiera comprobar que las horas y las rachas son **locales** pasa otra, porque
    ///     en UTC el calendario de AD-19 y el de `motivation.js` coinciden y la divergencia no se
    ///     ve desde aquí.
    init(
        motion: MotionStub = MotionStub(status: .granted),
        storage: StorageStub = StorageStub(),
        at instant: Date = SessionStoreFixture.t0,
        defaultStrideM: Double = 0.655,
        timeoutS: TimeInterval = 5,
        orphanThresholdS: TimeInterval = SessionStoreFixture.orphanThresholdS,
        maxEstimableGapS: TimeInterval = SessionStoreFixture.maxEstimableGapS,
        location: LocationStub = LocationStub(status: .denied),
        weather: WeatherStub = WeatherStub(),
        weatherStepTimeoutS: TimeInterval = 5,
        quotes: QuoteBank = .empty,
        random: RandomStub = RandomStub(),
        catalog: AchievementCatalog = AchievementCatalogFixture.bundled,
        timeZone: String = "UTC"
    ) {
        let measurements = LineSink()
        clock = ClockStub(now: instant, timeZone: timeZone)
        self.motion = motion
        self.storage = storage
        self.location = location
        self.weather = weather
        self.random = random
        self.measurements = measurements
        // El historial primero: el store de ajustes lo recibe cableado, porque dos instancias
        // del dueño de `sessions.json` son dos lectores, y leer un historial ilegible lo aparta
        // (AD-16). El reloj es el mismo `ClockStub` que la sesión: el anillo de meta y la
        // caminata no pueden estar en dos semanas distintas.
        let history = HistoryStore(storage: storage)
        self.history = history
        let achievements = AchievementsStore(storage: storage)
        self.achievements = achievements
        let settings = SettingsStore(
            storage: storage,
            history: history,
            achievements: achievements,
            clock: clock
        )
        self.settings = settings
        store = SessionStore(
            clock: clock,
            motion: motion,
            storage: storage,
            defaultStrideM: defaultStrideM,
            reconciliationTimeoutS: timeoutS,
            orphanSessionThresholdS: orphanThresholdS,
            maxEstimableGapS: maxEstimableGapS,
            location: location,
            weather: weather,
            settings: settings,
            history: history,
            achievements: achievements,
            achievementCatalog: catalog,
            quotes: quotes,
            random: random,
            weatherStepTimeoutS: weatherStepTimeoutS,
            measure: { measurements.append($0) }
        )
    }

    /// Un banco de `count` frases con ids 1…`count`, para los tests de la 2.2. `bank(0)` es el
    /// banco **vacío**, no uno de una frase: un `max(1, count)` convertiría un caso límite en
    /// otro sin avisar. Ids únicos y textos no vacíos: la validación del `init` no puede fallar.
    static func bank(_ count: Int) -> QuoteBank {
        try! QuoteBank(quotes: (0..<count).map { Quote(id: $0 + 1, text: "Frase \($0 + 1)") })
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
