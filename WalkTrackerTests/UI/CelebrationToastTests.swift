import Domain
import Foundation
import SwiftUI
import Testing

@testable import WalkTracker

/// Lo que la celebración **decide y dice** (3.4), sin renderizarla.
///
/// Es la salida de la decisión D1 del 2026-09-20 aplicada a esta historia, la misma que usó la
/// insignia de la 3.3: XCUITest está descartado, así que la lógica de presentación sale de la
/// vista a valores probables —la **cola**, la decisión de Reduce Motion— y a funciones puras
/// —lo que VoiceOver lee—, y se prueba con la suite que ya existe. Lo que queda para el iPhone es
/// lo que solo se ve renderizando: que el aviso se pinte arriba, que no tape los controles, que
/// VoiceOver lo **anuncie** y que SwiftUI honre de verdad la animación que aquí se decide.
///
/// **Y aquí es donde se fija que nunca hay dos avisos a la vez.** Tres logros en un cierre son
/// tres avisos, uno tras otro: la cola entrega **uno** y el siguiente no existe hasta que el
/// anterior se ha ido.
@MainActor
@Suite("Celebración · la cola de avisos y lo que se lee")
struct CelebrationToastTests {

    // MARK: - Soporte

    /// Del catálogo del bundle, no de una copia: si una entrada cambiara, esto lo dice (AD-5).
    private static func definition(_ key: String) -> AchievementDefinition {
        AchievementCatalogFixture.bundled.definition(for: key)!
    }

    /// `AnyTransition` no es `Equatable`, así que la comparación va contra la **forma** de los
    /// valores del propio SDK —`.identity` y `.opacity`—, nunca contra una cadena escrita a mano:
    /// es el mismo recurso con el que `MotionBlockedViewTests` compara su URL con la de
    /// `UIApplication`.
    private static func shape(_ transition: AnyTransition) -> String {
        String(describing: transition)
    }

    // MARK: - La cola (D3)

    @Test("Tres logros en un cierre: tres avisos, uno tras otro, y NUNCA dos a la vez")
    func threeUnlocksAreShownOneAtATime() {
        let unlocked = [Self.definition("first_session"), Self.definition("first_km"), Self.definition("early_bird")]
        var queue = CelebrationQueue()

        queue.receive(unlocked)

        #expect(queue.current == unlocked[0])
        #expect(queue.pending.count == 3, "los otros dos esperan turno, no se pintan")
        queue.advance()
        #expect(queue.current == unlocked[1])
        queue.advance()
        #expect(queue.current == unlocked[2])
        queue.advance()
        #expect(queue.current == nil, "y al terminar no queda ninguno")
        #expect(queue.pending.isEmpty)
    }

    @Test("Un solo logro: un solo aviso")
    func oneUnlockIsOneNotice() {
        var queue = CelebrationQueue()

        queue.receive([Self.definition("first_km")])

        #expect(queue.current == Self.definition("first_km"))
        queue.advance()
        #expect(queue.current == nil)
    }

    /// La fila "ninguno escrito" de la matriz: con `achievements.json` ilegible el store no
    /// publica nada, y no se celebra lo que no se guardó.
    @Test("Sin logros escritos no hay ningún aviso")
    func nothingWrittenIsNothingShown() {
        var queue = CelebrationQueue()

        queue.receive([])

        #expect(queue.current == nil)
        #expect(queue.pending.isEmpty)
    }

    /// La señal es de **un** cierre: se asigna entera y el reset la vacía. Si la cola acumulara,
    /// la vista volvería a encolar los mismos avisos cada vez que releyera la señal.
    @Test("Recibir otra señal sustituye la cola, no la acumula")
    func receivingReplacesTheQueue() {
        var queue = CelebrationQueue()
        queue.receive([Self.definition("first_session"), Self.definition("first_km")])
        queue.advance()

        queue.receive([Self.definition("night_walker")])

        #expect(queue.pending == [Self.definition("night_walker")])
    }

    /// El vencimiento del tiempo y el toque son la misma salida, y pueden llegar los dos: la
    /// tarea se cancela al desmontarse el aviso, pero un segundo `advance()` no puede vaciar de
    /// más la cola ni caerse.
    @Test("Descartar dos veces el mismo aviso no se salta el siguiente ni se cae")
    func advancingOnAnEmptyQueueIsHarmless() {
        var queue = CelebrationQueue()
        queue.receive([])

        queue.advance()
        queue.advance()

        #expect(queue.current == nil)
    }

    // MARK: - Lo que VoiceOver lee

    /// Sin el prefijo, "Madrugador" a secas no diría que se acaba de ganar. El nombre y la
    /// descripción entran **interpolados** del catálogo congelado (AD-5): no se traducen aquí.
    @Test("El aviso de un logro dice QUÉ ha pasado y de qué logro", arguments: ["first_km", "early_bird", "marathon_42km"])
    func theAchievementLabelNamesTheAchievement(key: String) {
        let definition = Self.definition(key)

        let spoken = CelebrationToast.spokenAchievement(definition)

        #expect(spoken.contains(definition.name), "«\(spoken)» no nombra el logro")
        #expect(spoken.contains(definition.description))
        #expect(spoken != definition.name, "el nombre solo no dice que se acabe de desbloquear")
    }

    @Test("El aviso de la meta no se lee como el de ningún logro")
    func theGoalLabelIsItsOwn() {
        let goal = CelebrationToast.spokenWeeklyGoal

        #expect(!goal.isEmpty)
        for definition in AchievementCatalogFixture.bundled.achievements {
            #expect(goal != CelebrationToast.spokenAchievement(definition))
        }
    }

    // MARK: - Reduce Motion (fila propia de la matriz)

    /// **Sin animación, no un fundido más corto**, que es exactamente lo que la fila de la matriz
    /// distingue. Es la única de las once filas que no se podía afirmar sin renderizar, y por eso
    /// la decisión salió de las dos vistas a una función: quitar el `reduceMotion` de cualquiera
    /// de los dos avisos dejaba las 914 en verde.
    @Test("Con Reduce Motion el aviso aparece SIN animación")
    func reduceMotionMeansNoAnimation() {
        #expect(CelebrationToast.animation(reduceMotion: true) == nil, "un fundido más corto no es 'sin animación'")
        #expect(Self.shape(CelebrationToast.transition(reduceMotion: true)) == Self.shape(.identity))
    }

    @Test("Sin Reduce Motion el aviso entra animado")
    func withoutReduceMotionItAnimates() {
        #expect(CelebrationToast.animation(reduceMotion: false) == .default)
        #expect(Self.shape(CelebrationToast.transition(reduceMotion: false)) == Self.shape(.opacity))
    }

    /// Las dos ramas tienen que **diferenciarse**: sin esto, una implementación que devolviera lo
    /// mismo para los dos valores pasaría los dos casos de arriba si las descripciones del SDK
    /// coincidieran.
    @Test("Las dos ramas no son la misma")
    func theTwoBranchesDiffer() {
        #expect(CelebrationToast.animation(reduceMotion: true) != CelebrationToast.animation(reduceMotion: false))
        #expect(Self.shape(CelebrationToast.transition(reduceMotion: true)) != Self.shape(CelebrationToast.transition(reduceMotion: false)))
    }

    // MARK: - El cableado de los dos avisos

    /// **Este test existe por un criterio de aceptación**: "si se quita el cableado de cualquiera
    /// de los dos avisos, algún test falla". Ningún test renderiza una vista (XCUITest está
    /// descartado desde la decisión D1 del 2026-09-20), así que lo que se comprueba es lo único
    /// comprobable sin renderizar: que el **tipo** del cuerpo de cada pantalla contenga el aviso,
    /// que es lo que deja de ser verdad en cuanto alguien borra el `.overlay`.
    ///
    /// Lo que **no** demuestra: que se vea, que esté arriba, que no tape nada y que se anuncie.
    /// Eso sigue siendo verificación manual y está registrado con el resto.
    @Test("La sesión tiene cableado el aviso de logros")
    func sessionViewWiresTheAchievementNotice() async {
        let fixture = SessionStoreFixture()

        let body = String(describing: type(of: SessionView(store: fixture.store).body))

        #expect(body.contains("CelebrationToast"), "SessionView ya no monta el aviso de logros: \(body)")
    }

    @Test("Las pestañas tienen cableado el aviso de meta")
    func rootViewWiresTheGoalNotice() async {
        let fixture = SessionStoreFixture()
        let root = RootView(
            store: fixture.store,
            settingsStore: fixture.settings,
            historyStore: fixture.history,
            achievementsStore: fixture.achievements,
            achievementCatalog: AchievementCatalogFixture.bundled,
            calendar: fixture.clock.calendar,
            defaultStrideM: 0.655
        )

        let body = String(describing: type(of: root.body))

        #expect(body.contains("CelebrationToast"), "RootView ya no monta el aviso de meta: \(body)")
    }
}
