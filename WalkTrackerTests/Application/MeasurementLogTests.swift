import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Registro de medición de la 8.4: formato de cada línea, el contrato con el informe
/// (`Scripts/walk-report/report.js`) por la fixture compartida, y las líneas que escribe
/// `SessionStore` en los puntos de la matriz de la spec.
@MainActor
@Suite("MeasurementLog · registro de medición del gate 8.4")
struct MeasurementLogTests {

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let sid = "sid=1800000000000"

    private static func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - Formato

    @Test("Muestra del stream: steps, distance y end con el prefijo versionado")
    func sampleLine() {
        let sample = PedometerSample(steps: 820, distance: 540, start: Self.t0, end: Self.at(600))
        #expect(MeasurementLog.sampleLine(sessionStartedAt: Self.t0, sample: sample)
            == "WTM1 event=sample sid=1800000000000 start=1800000000000 end=1800000600000 steps=820 distance=540.00")
    }

    @Test("Muestra sin distancia del sistema: distance=nil, nunca 0")
    func sampleWithoutDistance() {
        let sample = PedometerSample(steps: 100, distance: nil, start: Self.t0, end: Self.at(60.0004))
        #expect(MeasurementLog.sampleLine(sessionStartedAt: Self.t0, sample: sample)
            == "WTM1 event=sample sid=1800000000000 start=1800000000000 end=1800000060000 steps=100 distance=nil")
    }

    @Test("Consulta con dato: rango, resultado, visto, duración y desenlace")
    func queryLineWithData() {
        let result = PedometerSample(steps: 900, distance: 590.5, start: Self.t0, end: Self.at(900))
        let line = MeasurementLog.queryLine(
            sessionStartedAt: Self.t0, start: Self.t0, end: Self.at(900),
            result: result, seen: 820, durationMs: 40, outcome: .data
        )
        #expect(line == "WTM1 event=query sid=1800000000000 start=1800000000000 end=1800000900000 result=900 distance=590.50 seen=820 ms=40 outcome=data")
    }

    @Test("Consulta sin resultado: result y distance nil", arguments: [
        (MeasurementLog.QueryOutcome.noResult, "nil"),
        (.timeout, "timeout"),
        (.error, "error"),
    ])
    func queryLineWithoutResult(outcome: MeasurementLog.QueryOutcome, raw: String) {
        let line = MeasurementLog.queryLine(
            sessionStartedAt: Self.t0, start: Self.t0, end: Self.at(900),
            result: nil, seen: 820, durationMs: 3001, outcome: outcome
        )
        #expect(line == "WTM1 event=query sid=1800000000000 start=1800000000000 end=1800000900000 result=nil distance=nil seen=820 ms=3001 outcome=\(raw)")
    }

    @Test("Desenlaces con los nombres que lee el informe")
    func outcomeNames() {
        #expect(MeasurementLog.QueryOutcome.allCases.map(\.rawValue) == ["data", "nil", "timeout", "belowSeen", "error"])
    }

    @Test("Razones de estimación omitida: los mismos casos y los mismos nombres que GapEstimator.Skip")
    func skipNamesMatchTheDomain() {
        #expect(MeasurementLog.EstimateSkip.allCases.map(\.rawValue)
            == GapEstimator.Skip.allCases.map(\.rawValue))
        // El `init` traduce cada razón del dominio a la suya, sin perder ninguna por el camino.
        for skip in GapEstimator.Skip.allCases {
            #expect(MeasurementLog.EstimateSkip(skip).rawValue == skip.rawValue)
        }
    }

    @Test("Estimación: gap, pasos y skipped=nil")
    func estimateLine() {
        #expect(MeasurementLog.estimateLine(sessionStartedAt: Self.t0, gapStart: Self.at(600), gapEnd: Self.at(900), steps: 400)
            == "WTM1 event=estimate sid=1800000000000 gapStart=1800000600000 gapEnd=1800000900000 steps=400 skipped=nil")
    }

    @Test("Estimación omitida: steps=0 y skipped=streamAdvanced")
    func skippedEstimateLine() {
        #expect(MeasurementLog.estimateLine(sessionStartedAt: Self.t0, gapStart: Self.at(600), gapEnd: Self.at(900), steps: 0, skipped: .streamAdvanced)
            == "WTM1 event=estimate sid=1800000000000 gapStart=1800000600000 gapEnd=1800000900000 steps=0 skipped=streamAdvanced")
    }

    @Test("Respuesta tardía: mismos campos que query con event=queryLate")
    func lateQueryLine() {
        let result = PedometerSample(steps: 950, distance: nil, start: Self.t0, end: Self.at(900))
        let line = MeasurementLog.lateQueryLine(
            sessionStartedAt: Self.t0, start: Self.t0, end: Self.at(900),
            result: result, seen: 820, durationMs: 4200, outcome: MeasurementLog.outcome(of: result, seen: 820)
        )
        #expect(line == "WTM1 event=queryLate sid=1800000000000 start=1800000000000 end=1800000900000 result=950 distance=nil seen=820 ms=4200 outcome=data")
        #expect(MeasurementLog.outcome(of: nil, seen: 820) == .noResult)
        #expect(MeasurementLog.outcome(of: result, seen: 951) == .belowSeen)
    }

    @Test("Transición: estado de la sesión tras aplicarla, con distancia de la zancada sin sistema")
    func sessionLine() throws {
        var session = try Session.start(at: Self.t0, strideM: 0.655)
        try session.addMeasuredSteps(800)
        try session.addEstimatedSteps(400)
        #expect(MeasurementLog.sessionLine(transition: .active, session: session, at: Self.at(900.7))
            == "WTM1 event=session sid=1800000000000 transition=active at=1800000900700 status=active elapsedS=900 measured=800 estimated=400 systemDistance=nil distance=786.00")
    }

    @Test("Inicio y restauración llevan versión y build de la app; el resto no", arguments: MeasurementLog.Transition.allCases)
    func buildOnOpeningTransitions(transition: MeasurementLog.Transition) throws {
        let session = try Session.start(at: Self.t0, strideM: 0.655)
        let line = MeasurementLog.sessionLine(
            transition: transition, session: session, at: Self.t0, build: .init(version: "4.0.0", build: "38")
        )
        if transition == .start || transition == .restore {
            #expect(line.hasSuffix(" distance=0.00 version=4.0.0 build=38"))
        } else {
            #expect(line.hasSuffix(" distance=0.00"))
        }
        #expect(MeasurementLog.AppBuild(version: "4.0 beta", build: "").build == "nil")
        #expect(MeasurementLog.AppBuild(version: "4.0 beta", build: "").version == "4.0_beta")
    }

    @Test("Metros sin locale y milisegundos redondeados")
    func pieces() {
        #expect(MeasurementLog.meters(1000.25) == "1000.25")
        #expect(MeasurementLog.meters(0) == "0.00")
        #expect(MeasurementLog.meters(.nan) == "nil")
        #expect(MeasurementLog.ms(Date(timeIntervalSince1970: 1.0006)) == "1001")
        #expect(MeasurementLog.milliseconds(.milliseconds(40)) == 40)
        #expect(MeasurementLog.milliseconds(.seconds(3) + .microseconds(600)) == 3001)
    }

    // MARK: - Contrato con el informe

    /// La caminata limpia de `MeasurementLogFixture.txt` es la que `walk-report-tests.sh`
    /// pasa por el informe. Si la app escribe otra cosa, este test se pone rojo; si el
    /// informe deja de leerla, el script.
    @Test("La fixture compartida con walk-report.sh es exactamente lo que escribe la app")
    func sharedFixtureMatchesApp() throws {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "MeasurementLogFixture", withExtension: "txt"),
            "MeasurementLogFixture.txt no está en el bundle de tests. ¿Falta `xcodegen generate`?"
        )
        let fixture = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line in line.range(of: "WTM1 ").map { String(line[$0.lowerBound...]) } }

        var session = try Session.start(at: Self.t0, strideM: 0.655)
        var expected = [MeasurementLog.sessionLine(
            transition: .start, session: session, at: Self.t0, build: .init(version: "4.0.0", build: "38")
        )]
        expected.append(MeasurementLog.sampleLine(
            sessionStartedAt: Self.t0,
            sample: PedometerSample(steps: 100, distance: nil, start: Self.t0, end: Self.at(60))
        ))
        try session.addMeasuredSteps(100)
        expected.append(MeasurementLog.sampleLine(
            sessionStartedAt: Self.t0,
            sample: PedometerSample(steps: 820, distance: 540, start: Self.t0, end: Self.at(600))
        ))
        try session.addMeasuredSteps(720)
        try session.recordSystemDistance(540)
        expected.append(MeasurementLog.sessionLine(transition: .background, session: session, at: Self.at(600)))
        expected.append(MeasurementLog.queryLine(
            sessionStartedAt: Self.t0, start: Self.t0, end: Self.at(900),
            result: PedometerSample(steps: 900, distance: 590.5, start: Self.t0, end: Self.at(900)),
            seen: 820, durationMs: 40, outcome: .data
        ))
        try session.addMeasuredSteps(80)
        try session.recordSystemDistance(590.5)
        expected.append(MeasurementLog.sessionLine(transition: .active, session: session, at: Self.at(900)))
        expected.append(MeasurementLog.sampleLine(
            sessionStartedAt: Self.t0,
            sample: PedometerSample(steps: 1500, distance: 1000.25, start: Self.t0, end: Self.at(1500))
        ))
        try session.addMeasuredSteps(600)
        try session.recordSystemDistance(1000.25)
        expected.append(MeasurementLog.queryLine(
            sessionStartedAt: Self.t0, start: Self.t0, end: Self.at(1800),
            result: PedometerSample(steps: 1800, distance: 1200, start: Self.t0, end: Self.at(1800)),
            seen: 1500, durationMs: 35, outcome: .data
        ))
        try session.addMeasuredSteps(300)
        try session.recordSystemDistance(1200)
        try session.finish(at: Self.at(1800))
        expected.append(MeasurementLog.sessionLine(transition: .finish, session: session, at: Self.at(1800)))

        #expect(fixture == expected)
    }

    // MARK: - SessionStore

    @MainActor
    private struct Fixture {
        let clock: ClockStub
        let motion: MotionStub
        let sink: LineSink
        let store: SessionStore

        /// Timeout largo por defecto: una consulta inmediata nunca pierde contra el
        /// temporizador en una máquina cargada.
        init(timeoutS: TimeInterval = 5, snapshot: ActiveSessionSnapshot? = nil) {
            let clock = ClockStub(now: MeasurementLogTests.t0)
            let motion = MotionStub(status: .granted)
            let sink = LineSink()
            self.clock = clock
            self.motion = motion
            self.sink = sink
            let storage = StorageStub(snapshot: snapshot)
            store = SessionStore(
                clock: clock, motion: motion, storage: storage, defaultStrideM: 0.655,
                reconciliationTimeoutS: timeoutS, orphanSessionThresholdS: 21_600, maxEstimableGapS: 1200,
                location: LocationStub(status: .denied), weather: WeatherStub(),
                settings: SettingsStore(storage: storage),
                history: HistoryStore(storage: storage),
                measure: { sink.append($0) }
            )
        }

        /// Abre la sesión, cuenta 820 pasos y 540 m en 10 min y pasa 5 min en segundo plano.
        func walkThenBackground() async {
            await store.start()
            motion.emit(steps: 820, distance: 540, end: MeasurementLogTests.at(600))
            await waitUntil { self.store.session?.stepsMeasured == 820 }
            clock.advance(by: 600)
            store.appDidEnterBackground()
            clock.advance(by: 300)
        }

        func lines(_ event: String) -> [String] {
            sink.lines.filter { $0.hasPrefix("WTM1 event=\(event) ") }
        }
    }

    @Test("Store · muestra del stream: una línea sample con steps, distance y end")
    func storeSample() async {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 820, distance: 540, end: Self.at(600))
        await waitUntil { fixture.store.session?.stepsMeasured == 820 }

        #expect(fixture.lines("sample") == [
            "WTM1 event=sample \(Self.sid) start=1800000000000 end=1800000600000 steps=820 distance=540.00",
        ])
    }

    @Test("Store · consulta con dato: query → 900, visto 820, desenlace data y sin estimación")
    func storeQueryWithData() async throws {
        let fixture = Fixture()
        await fixture.walkThenBackground()
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: 590))

        await fixture.store.appDidBecomeActive()

        let query = try #require(fixture.lines("query").only)
        #expect(query.hasPrefix("WTM1 event=query \(Self.sid) start=1800000000000 end=1800000900000 result=900 distance=590.00 seen=820 ms="))
        #expect(query.hasSuffix(" outcome=data"))
        #expect(fixture.lines("estimate").isEmpty)
        #expect(fixture.lines("sample").count == 1, "la muestra aplicada de la consulta no se registra como sample")
        #expect(fixture.store.session?.stepsMeasured == 900, "medir no cambia la decisión")
    }

    @Test("Store · consulta por debajo de lo visto: desenlace belowSeen, se aplica y no hay línea estimate (R1)")
    func storeBelowSeenQuery() async throws {
        let fixture = Fixture()
        await fixture.walkThenBackground()
        fixture.motion.setQueryResponse(.sample(steps: 814, distance: 536))

        await fixture.store.appDidBecomeActive()

        let query = try #require(fixture.lines("query").only)
        #expect(query.contains(" result=814 "))
        #expect(query.contains(" seen=820 "))
        #expect(query.hasSuffix(" outcome=belowSeen"))
        #expect(fixture.lines("estimate").isEmpty, "con respuesta del sistema no se estima")
        #expect(fixture.store.session?.stepsMeasured == 820, "record nunca resta")
        #expect(fixture.store.session?.stepsEstimated == 0)
    }

    @Test("Store · consulta sin respuesta: su desenlace y una línea estimate con los pasos", arguments: [
        (MotionStub.QueryResponse.none, "nil", "result=nil"),
        (.failure(.failed(operation: "pedometer")), "error", "result=nil"),
    ])
    func storeDegradedQuery(response: MotionStub.QueryResponse, outcome: String, result: String) async throws {
        let fixture = Fixture()
        await fixture.walkThenBackground()
        fixture.motion.setQueryResponse(response)

        await fixture.store.appDidBecomeActive()

        let query = try #require(fixture.lines("query").only)
        #expect(query.contains(" \(result) "))
        #expect(query.contains(" seen=820 "))
        #expect(query.hasSuffix(" outcome=\(outcome)"))
        let estimated = try #require(fixture.store.session?.stepsEstimated)
        #expect(estimated > 0)
        #expect(fixture.lines("estimate") == [
            "WTM1 event=estimate \(Self.sid) gapStart=1800000600000 gapEnd=1800000900000 steps=\(estimated) skipped=nil",
        ])
    }

    @Test("Store · timeout: desenlace timeout y, al llegar la respuesta tardía, queryLate con su duración real")
    func storeTimeout() async throws {
        let fixture = Fixture(timeoutS: 0.05)
        await fixture.walkThenBackground()
        fixture.motion.setQueryResponse(.hang)

        await fixture.store.appDidBecomeActive()
        let query = try #require(fixture.lines("query").only)
        #expect(query.hasSuffix(" outcome=timeout"))
        #expect(query.contains(" result=nil "))
        let ms = try #require(query.field("ms").flatMap(Int.init))
        #expect(ms >= 50, "el store esperó al menos el timeout")
        #expect(fixture.lines("estimate").count == 1)
        #expect(fixture.lines("queryLate").isEmpty, "la consulta sigue colgada")

        // Tiempo real tras el timeout: la duración de queryLate tiene que incluirlo.
        let lateBy = ContinuousClock.now.advanced(by: .milliseconds(30))
        await waitUntil { ContinuousClock.now >= lateBy }
        fixture.motion.resolvePendingQueries(with: .sample(steps: 950, distance: nil))
        await waitUntil { fixture.lines("queryLate").count == 1 }

        let late = try #require(fixture.lines("queryLate").only)
        #expect(late.hasPrefix("WTM1 event=queryLate \(Self.sid) start=1800000000000 end=1800000900000 result=950 distance=nil seen=820 ms="))
        #expect(late.hasSuffix(" outcome=data"))
        let lateMs = try #require(late.field("ms").flatMap(Int.init))
        #expect(lateMs >= ms + 30, "la duración real incluye la espera tras el timeout")
        #expect(fixture.store.session?.stepsMeasured == 820, "la respuesta tardía se sigue ignorando")
    }

    @Test("Store · el stream avanza durante una consulta degradada: estimate con steps=0 y skipped=streamAdvanced")
    func storeSkippedEstimate() async throws {
        let fixture = Fixture(timeoutS: 0.5)
        await fixture.walkThenBackground()
        fixture.motion.setQueryResponse(.hang)
        let store = fixture.store
        let reconciliation = Task { await store.appDidBecomeActive() }
        await waitUntil { store.isReconciling && fixture.motion.hasPendingQuery }

        fixture.motion.emit(steps: 1000, end: Self.at(905))
        await waitUntil { fixture.store.session?.stepsMeasured == 1000 }
        await reconciliation.value
        fixture.motion.resolvePendingQueries(with: .none)

        #expect(fixture.lines("query").only?.hasSuffix(" outcome=timeout") == true)
        #expect(fixture.lines("estimate") == [
            "WTM1 event=estimate \(Self.sid) gapStart=1800000600000 gapEnd=1800000900000 steps=0 skipped=streamAdvanced",
        ])
        #expect(fixture.store.session?.stepsEstimated == 0)
    }

    /// Snapshot activo desde `startedAgoS` antes de `t0`, guardado en `t0`.
    private static func snapshot(startedAgoS: TimeInterval, steps: Int) -> ActiveSessionSnapshot {
        let startedAt = t0.addingTimeInterval(-startedAgoS)
        return ActiveSessionSnapshot(
            startedAt: startedAt, stepsMeasured: steps, stepsEstimated: 0, totalPausesS: 0,
            paused: false, pausedAt: nil, strideM: 0.655, systemDistanceM: nil, savedAt: t0,
            lastSampleAt: startedAt.addingTimeInterval(600), segmentStart: startedAt,
            segmentSteps: steps, distanceBaseM: 0
        )
    }

    @Test("Store · restaurar al relanzar: transición restore con versión y build de la app")
    func storeRestore() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(startedAgoS: 20 * 60, steps: 1500))
        fixture.motion.setQueryResponse(.sample(steps: 1700, distance: nil))

        await fixture.store.restoreOnLaunch()

        let restore = try #require(fixture.lines("session").last)
        #expect(restore.field("transition") == "restore")
        #expect(restore.field("measured") == "1700")
        #expect(restore.field("version") == MeasurementLog.AppBuild.current.version)
        #expect(restore.field("build") == MeasurementLog.AppBuild.current.build)
    }

    @Test("Store · huérfana al relanzar: transición orphan finalizada")
    func storeOrphan() async throws {
        let fixture = Fixture(snapshot: Self.snapshot(startedAgoS: 7 * 60 * 60, steps: 4000))

        await fixture.store.restoreOnLaunch()

        let orphan = try #require(fixture.lines("session").only)
        #expect(orphan.field("transition") == "orphan")
        #expect(orphan.field("status") == "finished")
        #expect(orphan.field("elapsedS") == "600")
    }

    @Test("Store · descartar estimados: transición discardEstimated con estimated=0")
    func storeDiscardEstimated() async throws {
        let fixture = Fixture()
        await fixture.walkThenBackground()
        await fixture.store.appDidBecomeActive()
        fixture.store.requestDiscardEstimated()
        fixture.store.confirmDiscardEstimated()

        let discard = try #require(fixture.lines("session").last)
        #expect(discard.field("transition") == "discardEstimated")
        #expect(discard.field("estimated") == "0")
    }

    @Test("Store · el sistema termina el stream: transición streamEnded")
    func storeStreamEnded() async throws {
        let fixture = Fixture()
        await fixture.store.start()
        fixture.motion.emit(steps: 420)
        fixture.motion.finishUpdates()
        await fixture.store.stepCounting?.value

        let ended = try #require(fixture.lines("session").last)
        #expect(ended.field("transition") == "streamEnded")
        #expect(ended.field("measured") == "420")
    }

    @Test("Store · transiciones: inicio, background, vuelta, pausa, reanudación y fin, en orden")
    func storeTransitions() async {
        let fixture = Fixture()
        await fixture.walkThenBackground()
        fixture.motion.setQueryResponse(.sample(steps: 900, distance: nil))
        await fixture.store.appDidBecomeActive()
        fixture.store.pause()
        fixture.clock.advance(by: 60)
        fixture.store.resume()
        fixture.clock.advance(by: 60)
        fixture.motion.setQueryResponse(.none)
        await fixture.store.confirmFinish()

        #expect(fixture.lines("session").compactMap { $0.field("transition") }
            == ["start", "background", "active", "pause", "resume", "finish"])
        let start = fixture.lines("session").first
        #expect(start?.field("version") == MeasurementLog.AppBuild.current.version)
        #expect(start?.field("build") == MeasurementLog.AppBuild.current.build)
        let finish = fixture.lines("session").last
        #expect(finish?.field("status") == "finished")
        #expect(finish?.field("measured") == "900")
        #expect(finish?.field("estimated") == "0")
    }
}

// MARK: - Soporte

private final class BundleToken {}

private extension Array {
    /// El único elemento, o `nil` si hay cero o más de uno.
    var only: Element? { count == 1 ? first : nil }
}

private extension String {
    /// Valor de `clave=valor` en una línea de medición.
    func field(_ key: String) -> String? {
        split(separator: " ").first { $0.hasPrefix("\(key)=") }.map { String($0.dropFirst(key.count + 1)) }
    }
}
