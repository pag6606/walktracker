import Foundation

/// El **estado** de un logro en `achievements.json` (5.1, CAP-8, FR-8) — AD-9, AD-16.
///
/// **No es el catálogo.** Los 14 logros son contenido congelado que vive en
/// `Resources/achievements.json`, dentro del bundle, y los valida `AchievementCatalog` contra la
/// referencia de la v3. Esto es el fichero **del sandbox**, que se llama igual y no tiene nada
/// que ver: guarda qué ha conseguido Paul, no qué se puede conseguir. Confundirlos rompe el gate
/// del catálogo o pisa contenido congelado.
///
/// **La 5.1 define su dueño (`AchievementsStore`) y su esquema; quien lo escribe con criterio es
/// la 3.2** (AD-17: los logros se evalúan al cerrar la sesión, nunca al pintar una lista).
///
/// `progress` es el acumulado hacia el umbral, en la unidad de la métrica del logro
/// (`AchievementMetric`): metros para `marathon_42km`, días para `consistency_30`. Un logro
/// **desbloqueado** lleva su `unlockedAt`; uno en curso lo lleva a `nil` y solo avanza
/// `progress`. Un `unlockedAt` **nunca vuelve a nulo** (5.4): borrar una sesión recalcula el
/// progreso de los que aún no se han desbloqueado, y jamás revoca uno conseguido.
public struct AchievementUnlock: Equatable, Sendable, Identifiable {

    /// Clave estable del catálogo (`first_walk`, `marathon_42km`…). Nunca se renumera, y es la
    /// identidad de la fila: un `key` no aparece dos veces en el fichero.
    public let key: String
    /// Instante del desbloqueo, o `nil` si todavía no se ha conseguido.
    public let unlockedAt: Date?
    /// Acumulado hacia el umbral, en la unidad de la métrica. No negativo y finito.
    public let progress: Double

    public var id: String { key }

    /// - Throws: `DomainError.invalidValue` con `key` (vacía) o `progress` (< 0 o no finito).
    public init(key: String, unlockedAt: Date?, progress: Double) throws(DomainError) {
        guard !key.isEmpty else { throw .invalidValue(field: "key") }
        guard progress.isFinite, progress >= 0 else { throw .invalidValue(field: "progress") }
        self.key = key
        self.unlockedAt = unlockedAt
        self.progress = progress
    }

    /// El logro está conseguido.
    public var isUnlocked: Bool { unlockedAt != nil }
}
