import Foundation

/// Categoría interna del clima con la que el catálogo de logros compara (AD-5).
///
/// **Solo existe la que el catálogo nombra.** Hoy el único umbral de categoría de los 14 logros
/// es `"rain"` (`rain_walker`), así que no hay `case other`: una categoría que ningún logro
/// compara no tiene nada que decidir, y añadirla invitaría a escribir comparaciones que el
/// esquema de AD-5 no puede expresar. Un clima que no es lluvia se representa aquí como **la
/// ausencia de categoría** (`nil`), que es lo mismo que "no hay clima" desde el punto de vista
/// del catálogo: en los dos casos el logro climático **no se evalúa**, ni como falso ni como
/// verdadero.
///
/// Se declaraba antes en `AchievementMetric.swift`, junto al resto del esquema del umbral; vive
/// aquí desde la 3.2 porque lo que hacía falta escribir era **el puente**, y el puente vive con
/// el tipo al que llega.
public enum WeatherCategory: String, CaseIterable, Codable, Sendable {
    case rain
}

public extension WeatherCategory {

    /// La categoría de una condición de clima, o `nil` si esa condición no es ninguna de las que
    /// el catálogo sabe comparar.
    ///
    /// **Aquí no hay una segunda lista de códigos de lluvia, y ésa es toda la gracia.** La única
    /// que hay en Swift es la de `WeatherCondition.init(wmoCode:)` (2.1) —`51...67`, `80...82`,
    /// `95...99`— y cuadra con los vectores de `evaluateAchievements.json`. Una segunda lista en
    /// el motor de logros serían dos fuentes de verdad para la misma pregunta, y la que se
    /// quedara atrás lo haría en silencio: es la lección L2 de la retro del Epic 1, y el diferido
    /// que la 2.1 dejó apuntado a esta historia pedía exactamente esto.
    ///
    /// El `switch` es **exhaustivo a propósito**: una condición nueva en `WeatherCondition`
    /// obliga a decidir aquí si tiene categoría de logro, en vez de caer en un `nil` silencioso.
    init?(_ condition: WeatherCondition) {
        switch condition {
        case .rain: self = .rain
        case .other: return nil
        }
    }

    /// La categoría de un código WMO 4677, derivada de la **única** lista de códigos de lluvia.
    ///
    /// Es la composición de `WeatherCondition(wmoCode:)` con el puente de arriba; existe para que
    /// quien tenga el código crudo —un vector, un test— no tenga que dar el rodeo a mano.
    init?(wmoCode: Int) {
        self.init(WeatherCondition(wmoCode: wmoCode))
    }
}
