import Domain
import Foundation
import Testing

@testable import WalkTracker

/// Matriz de fases de la escena del A-1 (retro del Epic 1) sobre `SessionStore`: el único
/// punto de entrada `scenePhaseDidChange(to:)` reproduce lo que hacían `RootView` (gap y
/// reconciliación) y `HomeView` (releer el permiso solo tras `.background → .active`).
@MainActor
@Suite("SessionStore · fases de la escena")
struct SessionStoreScenePhaseTests: SessionStoreSuite {

    private typealias Fixture = SessionStoreFixture

    // MARK: - background → active

    @Test("Fases · background → active con la bloqueante: relee el permiso y cierra a Inicio sin arrancar")
    func backgroundThenActiveRereadsPermission() async throws {
        let fixture = Fixture(motion: MotionStub(status: .denied))
        await fixture.store.start()
        #expect(fixture.store.startFlow == .blocked(.permissionDenied))

        // Viaje a Ajustes: la escena pasa por background e inactive antes de volver.
        fixture.store.scenePhaseDidChange(to: .background)
        fixture.motion.setStatus(.granted)
        fixture.store.scenePhaseDidChange(to: .inactive)
        #expect(fixture.store.startFlow == .blocked(.permissionDenied), "inactive no relee")
        let returning = try #require(fixture.store.scenePhaseDidChange(to: .active))
        await returning.value

        #expect(fixture.store.startFlow == .idle)
        #expect(fixture.session == nil, "no arranca sola")
        #expect(fixture.motion.updateStarts.isEmpty)
        #expect(fixture.motion.queriedRanges.isEmpty, "sin sesión no hay gap que reconciliar")
    }

    @Test("Fases · background → active con la sesión activa: reconcilia el gap como appDidBecomeActive()")
    func backgroundThenActiveReconcilesGap() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 300)
        fixture.clock.advance(by: 60)
        fixture.store.scenePhaseDidChange(to: .background)
        fixture.clock.advance(by: 300)
        fixture.motion.setQueryResponse(.sample(steps: 820, distance: nil))

        fixture.store.scenePhaseDidChange(to: .inactive)
        let returning = try #require(fixture.store.scenePhaseDidChange(to: .active))
        await returning.value

        #expect(fixture.session?.stepsMeasured == 820)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.session?.status == .active)
        #expect(fixture.motion.queriedRanges == [.init(start: Self.t0, end: Self.t0.addingTimeInterval(360))])
        #expect(fixture.store.backgroundedAt == nil, "el gap quedó reconciliado")
        #expect(!fixture.store.isReconciling)
        #expect(fixture.storage.snapshot?.stepsMeasured == 820, "guarda lo reconciliado")
        #expect(fixture.measurementLines("session").last?.contains(" transition=active ") == true)
    }

    @Test("Fases · la relectura del permiso se consume: un inactive → active posterior ya no relee")
    func rereadHappensOncePerBackground() async throws {
        let fixture = Fixture(motion: MotionStub(status: .denied))
        await fixture.store.start()

        fixture.store.scenePhaseDidChange(to: .background)
        await fixture.store.scenePhaseDidChange(to: .active)?.value
        #expect(fixture.store.startFlow == .blocked(.permissionDenied), "sigue denegado")

        fixture.motion.setStatus(.granted)
        fixture.store.scenePhaseDidChange(to: .inactive)
        await fixture.store.scenePhaseDidChange(to: .active)?.value

        #expect(fixture.store.startFlow == .blocked(.permissionDenied), "sin otro background no relee")
    }

    // MARK: - inactive → active

    @Test("Fases · inactive → active (cerrar un diálogo del sistema): no relee el permiso")
    func inactiveThenActiveDoesNotRereadPermission() async throws {
        let fixture = Fixture(motion: MotionStub(status: .denied))
        await fixture.store.start()
        fixture.motion.setStatus(.granted)

        fixture.store.scenePhaseDidChange(to: .inactive)
        await fixture.store.scenePhaseDidChange(to: .active)?.value

        #expect(fixture.store.startFlow == .blocked(.permissionDenied))
    }

    @Test("Fases · inactive → active con la sesión activa: ni abre gap, ni guarda, ni reconcilia")
    func inactiveThenActiveDoesNotReconcile() async throws {
        let fixture = Fixture()
        await fixture.startWalking(steps: 300)
        let saves = fixture.storage.saved.count

        fixture.clock.advance(by: 60)
        #expect(fixture.store.scenePhaseDidChange(to: .inactive) == nil)
        #expect(fixture.store.backgroundedAt == nil, "inactive no es un gap")
        fixture.clock.advance(by: 300)
        await fixture.store.scenePhaseDidChange(to: .active)?.value

        #expect(fixture.motion.queriedRanges.isEmpty)
        #expect(!fixture.store.isReconciling)
        #expect(fixture.storage.saved.count == saves)
        #expect(fixture.session?.stepsEstimated == 0)
        #expect(fixture.session?.status == .active)
        #expect(fixture.store.isCountingSteps)
    }

    // MARK: - background

    @Test("Fases · background con la sesión activa: abre el gap, fija el tope de R4 y guarda, como appDidEnterBackground()")
    func backgroundOpensGapCapsAndSaves() async throws {
        let fixture = Fixture()
        let twin = Fixture()
        for walker in [fixture, twin] {
            await walker.store.start()
            walker.motion.emit(steps: 300, end: Self.t0.addingTimeInterval(60))
            await waitUntil { walker.session?.stepsMeasured == 300 }
            walker.clock.advance(by: 600)
        }
        let saves = fixture.storage.saved.count

        #expect(fixture.store.scenePhaseDidChange(to: .background) == nil)
        twin.store.appDidEnterBackground()

        let backgroundedAt = Self.t0.addingTimeInterval(600)
        #expect(fixture.session?.status == .active, "nunca pausa")
        #expect(fixture.store.backgroundedAt == backgroundedAt)
        #expect(fixture.store.stepsMeasuredAtGapStart == 300, "los pasos medidos al abrir el gap (R1)")
        #expect(fixture.store.lastSampleAtCap == backgroundedAt)
        #expect(fixture.storage.saved.count == saves + 1)
        let saved = try #require(fixture.storage.snapshot)
        #expect(saved.savedAt == backgroundedAt)
        #expect(saved.lastSampleAt == Self.t0.addingTimeInterval(60))
        #expect(fixture.measurementLines("session").last?.contains(" transition=background ") == true)

        #expect(twin.store.backgroundedAt == fixture.store.backgroundedAt)
        #expect(twin.store.stepsMeasuredAtGapStart == fixture.store.stepsMeasuredAtGapStart)
        #expect(twin.store.lastSampleAtCap == fixture.store.lastSampleAtCap)
        #expect(twin.storage.saved == fixture.storage.saved)
        #expect(twin.measurements.lines == fixture.measurements.lines)
    }
}
