import Domain
import Foundation

@testable import WalkTracker

/// El catálogo congelado de los 14 logros para los tests que necesitan uno de verdad (3.2).
///
/// **Es el del bundle, no una copia.** Los tests corren alojados en la app, así que `Bundle.main`
/// es la que lleva `achievements.json`. Declarar aquí un catálogo de prueba dejaría que el motor
/// pasara sus tests contra umbrales inventados mientras el fichero de datos se va a la deriva, que
/// es literalmente el incidente de AD-5. Los catálogos **inválidos** sí se fabrican a mano, y eso
/// es de `AchievementCatalogTests`.
/// **Hay un segundo cargador en el target de tests, y la duplicación es deliberada.**
/// `SwiftDomainPorts.bundledCatalog` (`WalkTrackerTests/Vectors/VectorHarness.swift`) lee el mismo
/// fichero y no usa esto: el arnés de vectores importa **solo `Domain`**, a propósito —es la misma
/// regla que hace que los vectores no puedan importar `WalkTracker` (AD-6)—, así que no puede
/// llamar a `CompositionRoot.loadAchievementCatalog(from:)`. Y el comportamiento ante el fallo
/// tiene que ser **distinto** en cada uno: allí un catálogo ilegible rompe **el vector que lo
/// necesita**, con su motivo (`VectorInputError`), porque el arnés existe para nombrar lo que
/// falla; aquí mata el proceso, porque un catálogo inválido deja sin significado a todos los tests
/// que dependen de él. Unificarlos exigiría meter `@testable import WalkTracker` en el arnés, que
/// es justo lo que no se quiere.
enum AchievementCatalogFixture {

    /// Si el catálogo del bundle no valida, no hay test que salvar: la app tampoco arrancaría
    /// (AD-5). Se cae ruidosamente en vez de degradar a un catálogo vacío, que dejaría en verde
    /// todo lo que dependa de él.
    ///
    /// **Es el segundo `fatalError` por esta misma condición** —el primero es
    /// `CompositionRoot.bundledAchievementCatalogOrTerminate()`— y los dos están nombrados en la
    /// entrada de `deferred-work.md` que pide la costura de terminación inyectable.
    static let bundled: AchievementCatalog = {
        do {
            return try CompositionRoot.loadAchievementCatalog(from: .main)
        } catch {
            fatalError("AD-5: el catálogo de logros del bundle no valida y ningún test de logros significa nada — \(error)")
        }
    }()
}
