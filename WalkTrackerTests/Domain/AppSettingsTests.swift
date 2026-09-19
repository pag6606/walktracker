import Domain
import Foundation
import Testing

/// El invariante de los ajustes (2.2). `AppSettings` es lo que cruza la frontera del fichero y
/// lo que el store lleva en memoria, así que el tope y la forma de la ventana viven **aquí** y
/// no por convención en cada sitio que la toca. La 2.3 añadirá `strideM` por esta misma puerta.
@Suite("AppSettings · la ventana no se puede construir mal")
struct AppSettingsTests {

    @Test("Los ajustes por omisión son la ventana vacía")
    func defaultsAreEmpty() {
        #expect(AppSettings.defaults.recentQuoteIds.isEmpty)
        #expect(AppSettings() == .defaults)
    }

    @Test("Una ventana más larga del tope se recorta a las últimas 20 al construir")
    func overlongWindowIsTrimmed() {
        #expect(AppSettings(recentQuoteIds: Array(1...500)).recentQuoteIds == Array(481...500))
    }

    @Test("Los ids repetidos desaparecen, conservando el orden y la aparición más reciente")
    func repeatedIdsAreDeduplicated() {
        #expect(AppSettings(recentQuoteIds: [3, 1, 4, 1, 5]).recentQuoteIds == [3, 4, 1, 5])
        #expect(AppSettings(recentQuoteIds: Array(repeating: 5, count: 20)).recentQuoteIds == [5])
    }

    @Test("Deduplicar va ANTES de recortar: 40 ids con repetidos dejan 20 distintos, no menos")
    func deduplicationDoesNotEatTheWindow() {
        let ids = Array(1...20) + Array(1...20)

        #expect(AppSettings(recentQuoteIds: ids).recentQuoteIds == Array(1...20))
    }

    @Test("La ventana solo se escribe por su mutador, que normaliza igual")
    func setterNormalisesToo() {
        var settings = AppSettings(recentQuoteIds: [1, 2])

        settings.setRecentQuoteIds([7, 7, 8] + Array(9...40))

        #expect(settings.recentQuoteIds.count == MotivationEngine.recentWindow)
        #expect(Set(settings.recentQuoteIds).count == settings.recentQuoteIds.count, "sin repetidos")
        #expect(settings.recentQuoteIds.last == 40, "la más reciente al final")
    }

    @Test("Lo que updateRecentIds produce entra normalizado: el motor sigue sin deduplicar")
    func engineOutputIsNormalisedOnTheWayIn() {
        // Paridad deliberada con la v3: `updateRecentIds` no deduplica (bloque congelado de la
        // 2.2). Quien cierra el hueco es el tipo que lo guarda, no el motor.
        let repeated = MotivationEngine.updateRecentIds([1, 2, 3], selectedId: 3)
        #expect(repeated == [1, 2, 3, 3], "el motor no deduplica, y así se queda")

        var settings = AppSettings()
        settings.setRecentQuoteIds(repeated)
        #expect(settings.recentQuoteIds == [1, 2, 3], "pero los ajustes sí")
    }
}
