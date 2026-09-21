import Domain
import Foundation
import Testing

/// Validación en frontera del registro de una caminata cerrada (5.1), al molde de
/// `WorkoutRecord`: un registro inválido no llega a `sessions.json`. Y las dos columnas que no
/// están en el agregado —huérfana y métrica degradada—, que son las que impiden que el fichero
/// mienta.
@Suite("SessionRecord · validación")
struct SessionRecordTests {

    private static let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private static let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// El registro válido de referencia, con un solo campo sustituido por la prueba.
    private static func record(
        endOffset: TimeInterval = 1_800,
        stepsMeasured: Int = 4_100,
        stepsEstimated: Int = 236,
        strideM: Double = 0.655,
        distanceM: Double = 2_840.08,
        durationS: Int = 1_800,
        pausesS: Int = 120,
        paceSecPerKm: Int? = 634,
        cadenceSpm: Double = 136.7,
        weather: WeatherSnapshot? = nil,
        quoteId: Int? = nil,
        source: SessionSource = .ios,
        recovered: Bool = false,
        degraded: Bool = false
    ) throws(DomainError) -> SessionRecord {
        try SessionRecord(
            id: id,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(endOffset),
            stepsMeasured: stepsMeasured,
            stepsEstimated: stepsEstimated,
            strideM: strideM,
            distanceM: distanceM,
            durationS: durationS,
            pausesS: pausesS,
            paceSecPerKm: paceSecPerKm,
            cadenceSpm: cadenceSpm,
            weather: weather,
            quoteId: quoteId,
            source: source,
            recovered: recovered,
            degraded: degraded
        )
    }

    @Test("Un registro válido conserva sus valores")
    func validRecordKeepsItsValues() throws {
        let record = try Self.record()

        #expect(record.id == Self.id)
        #expect(record.startedAt == Self.startedAt)
        #expect(record.endedAt == Self.startedAt.addingTimeInterval(1_800))
        #expect(record.stepsMeasured == 4_100)
        #expect(record.stepsEstimated == 236)
        #expect(record.stepsTotal == 4_336)
        #expect(record.strideM == 0.655)
        #expect(record.distanceM == 2_840.08)
        #expect(record.durationS == 1_800)
        #expect(record.pausesS == 120)
        #expect(record.paceSecPerKm == 634)
        #expect(record.cadenceSpm == 136.7)
        #expect(record.source == .ios)
        #expect(!record.recovered)
        #expect(!record.degraded)
    }

    @Test("Un cierre anterior al inicio lanza `endedAt`")
    func endedBeforeStartedThrows() {
        #expect(throws: DomainError.invalidValue(field: "endedAt")) {
            try Self.record(endOffset: -1)
        }
    }

    /// El único sitio donde este registro es **más tolerante** que `WorkoutRecord`, y a
    /// propósito: una huérfana sin ninguna muestra del coprocesador se cierra en su propio
    /// `startedAt` (AD-18), y ese registro tiene que poder existir.
    @Test("Un cierre en el mismo instante del inicio es válido: la huérfana sin muestras")
    func endedAtStartIsValid() throws {
        let record = try Self.record(endOffset: 0, stepsMeasured: 0, stepsEstimated: 0, distanceM: 0, durationS: 0, pausesS: 0, paceSecPerKm: nil, cadenceSpm: 0, recovered: true)

        #expect(record.endedAt == record.startedAt)
        #expect(record.durationS == 0)
    }

    @Test("Los pasos negativos lanzan con su campo", arguments: [
        (-1, 0, "stepsMeasured"),
        (0, -1, "stepsEstimated"),
    ])
    func negativeStepsThrow(measured: Int, estimated: Int, field: String) {
        #expect(throws: DomainError.invalidValue(field: field)) {
            try Self.record(stepsMeasured: measured, stepsEstimated: estimated)
        }
    }

    /// La zancada pasa por `Session.validateStride`, **la misma puerta que el agregado**, y no
    /// por una copia: si fueran dos reglas, un registro podría guardar una zancada con la que la
    /// sesión que lo produjo no habría podido nacer.
    @Test("La zancada usa la regla del agregado", arguments: [
        0.0, -0.1, Double.nan, Double.infinity, MetricsCalculator.maxRepresentableStrideM.nextUp,
    ])
    func invalidStrideThrows(stride: Double) {
        #expect(throws: DomainError.invalidValue(field: "strideM")) {
            try Self.record(strideM: stride)
        }
    }

    @Test("La zancada en el borde exacto de lo representable sí entra")
    func maximumRepresentableStrideIsAccepted() throws {
        let record = try Self.record(strideM: MetricsCalculator.maxRepresentableStrideM)

        #expect(record.strideM == MetricsCalculator.maxRepresentableStrideM)
    }

    @Test("Las demás magnitudes fuera de rango lanzan con su campo", arguments: [
        (-1.0, 0, 0, 1.0, "distanceM"),
        (Double.nan, 0, 0, 1.0, "distanceM"),
        (Double.infinity, 0, 0, 1.0, "distanceM"),
        (0.0, -1, 0, 1.0, "durationS"),
        (0.0, 0, -1, 1.0, "pausesS"),
        (0.0, 0, 0, -1.0, "cadenceSpm"),
        (0.0, 0, 0, Double.nan, "cadenceSpm"),
        (0.0, 0, 0, Double.infinity, "cadenceSpm"),
    ])
    func outOfRangeMagnitudesThrow(distanceM: Double, durationS: Int, pausesS: Int, cadenceSpm: Double, field: String) {
        #expect(throws: DomainError.invalidValue(field: field)) {
            try Self.record(distanceM: distanceM, durationS: durationS, pausesS: pausesS, cadenceSpm: cadenceSpm)
        }
    }

    /// Un ritmo de `0` no es "sin ritmo": sería 0 s/km, que no existe. Una magnitud ausente se
    /// guarda **ausente** (AD-22), y por eso el `nil` es el que vale.
    @Test("Un ritmo no positivo lanza; el ritmo ausente es válido", arguments: [0, -1])
    func nonPositivePaceThrows(pace: Int) {
        #expect(throws: DomainError.invalidValue(field: "paceSecPerKm")) {
            try Self.record(paceSecPerKm: pace)
        }
    }

    @Test("El ritmo ausente es válido")
    func absentPaceIsValid() throws {
        #expect(try Self.record(paceSecPerKm: nil).paceSecPerKm == nil)
    }

    // MARK: - Las dos columnas

    /// AD-18 en una línea, y **el punto donde se enchufa la 3.2**: lo que una huérfana no puede
    /// hacer es disparar logros. Sumar distancia sí: sus pasos los contó el coprocesador.
    @Test("Una huérfana no cuenta para logros; una caminata normal sí")
    func orphanDoesNotCountForAchievements() throws {
        let normal = try Self.record(recovered: false)
        let orphan = try Self.record(recovered: true)

        #expect(normal.countsForAchievements)
        #expect(!orphan.countsForAchievements)
        // Y su distancia sigue siendo real: lo que AD-18 prohíbe es la celebración, no existir.
        #expect(orphan.distanceM == normal.distanceM)
    }

    /// La marca viaja **con** el registro por la misma razón que `recovered`: el registro es
    /// inmutable y un `distanceM: 0` sin ella es indistinguible de una caminata sin pasos.
    @Test("La marca de métrica degradada se conserva en el registro")
    func degradedMarkTravelsWithTheRecord() throws {
        let degraded = try Self.record(distanceM: 0, paceSecPerKm: nil, degraded: true)

        #expect(degraded.degraded)
        #expect(degraded.distanceM == 0)
        #expect(try !Self.record(distanceM: 0, paceSecPerKm: nil).degraded)
    }
}

/// Validación en frontera del estado de un logro (5.1). El fichero lo estrena esta historia; su
/// contenido lo escribe la 3.2.
@Suite("AchievementUnlock · validación")
struct AchievementUnlockTests {

    private static let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Un desbloqueo válido conserva sus valores")
    func validUnlockKeepsItsValues() throws {
        let unlock = try AchievementUnlock(key: "marathon_42km", unlockedAt: Self.instant, progress: 42_195)

        #expect(unlock.key == "marathon_42km")
        #expect(unlock.id == "marathon_42km")
        #expect(unlock.unlockedAt == Self.instant)
        #expect(unlock.progress == 42_195)
        #expect(unlock.isUnlocked)
    }

    @Test("Sin `unlockedAt` es progreso, no desbloqueo")
    func withoutUnlockedAtItIsProgress() throws {
        let unlock = try AchievementUnlock(key: "consistency_30", unlockedAt: nil, progress: 12)

        #expect(!unlock.isUnlocked)
        #expect(unlock.progress == 12)
    }

    @Test("Una clave vacía lanza")
    func emptyKeyThrows() {
        #expect(throws: DomainError.invalidValue(field: "key")) {
            try AchievementUnlock(key: "", unlockedAt: nil, progress: 0)
        }
    }

    @Test("Un progreso negativo o no finito lanza", arguments: [-1.0, Double.nan, Double.infinity])
    func invalidProgressThrows(progress: Double) {
        #expect(throws: DomainError.invalidValue(field: "progress")) {
            try AchievementUnlock(key: "first_walk", unlockedAt: nil, progress: progress)
        }
    }
}
