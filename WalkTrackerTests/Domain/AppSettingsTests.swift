import Domain
import Foundation
import Testing

/// El invariante de los ajustes (2.2, 2.3). `AppSettings` es lo que cruza la frontera del
/// fichero y lo que el store lleva en memoria, así que el tope y la forma de la ventana viven
/// **aquí** y no por convención en cada sitio que la toca. La 2.3 añadió `strideM` por esta
/// misma puerta, con una diferencia que es el punto de la historia: la ventana **normaliza** y
/// la zancada, al escribirla, **rechaza**.
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

    // MARK: - Zancada (2.3)

    @Test("Sin configurar: la zancada es nil y la sesión usa el default de formulas.json")
    func strideIsUnsetByDefault() {
        #expect(AppSettings.defaults.strideM == nil)
        #expect(AppSettings.defaults.resolvedStrideM(default: 0.655) == 0.655)
    }

    @Test("Configurada: gana el override, y el default deja de importar")
    func configuredStrideWins() throws {
        var settings = AppSettings()
        try settings.setStrideM(0.670)

        #expect(settings.strideM == 0.670)
        #expect(settings.resolvedStrideM(default: 0.655) == 0.670)
    }

    @Test("La puerta de ESCRITURA rechaza y no muta", arguments: [0, -0.5, Double.nan, .infinity, -.infinity])
    func writeGateRejects(invalid: Double) {
        var settings = AppSettings(recentQuoteIds: [1, 2], strideM: 0.670)

        #expect(throws: DomainError.invalidValue(field: "strideM")) { try settings.setStrideM(invalid) }
        #expect(settings.strideM == 0.670, "el valor anterior sigue: rechazar no es borrar")
        #expect(settings.recentQuoteIds == [1, 2], "y el resto de los ajustes tampoco se toca")
    }

    @Test("La puerta de LECTURA tolera: un valor corrupto cae a sin configurar", arguments: [0, -1, Double.nan, .infinity])
    func readGateTolerates(corrupt: Double) {
        // Unos ajustes manipulados no pueden costar la ventana de frases: se ignora ESE campo.
        let settings = AppSettings(recentQuoteIds: [7, 8], strideM: corrupt)

        #expect(settings.strideM == nil)
        #expect(settings.recentQuoteIds == [7, 8], "la ventana sobrevive a una zancada corrupta")
        #expect(settings.resolvedStrideM(default: 0.655) == 0.655)
    }

    @Test("Las dos puertas son DISTINTAS: lo que la lectura tolera, la escritura lo rechaza")
    func theTwoGatesDisagreeOnPurpose() {
        #expect(AppSettings(strideM: -1).strideM == nil, "lectura: se ignora en silencio")

        var settings = AppSettings()
        #expect(throws: DomainError.self) { try settings.setStrideM(-1) }
        #expect(settings.strideM == nil, "escritura: se rechaza con error, y nada se persiste")
    }

    @Test("El rango humano avisa y no bloquea: fuera de 0,3–1,2 se guarda igual", arguments: [0.067, 3.0, 0.001, 50.0])
    func outOfHumanRangeStillSaves(meters: Double) throws {
        var settings = AppSettings()
        try settings.setStrideM(meters)

        #expect(settings.strideM == meters, "se guarda: es su app y su zancada")
        #expect(!AppSettings.isHumanStride(meters), "pero se avisa")
    }

    @Test("En el borde exacto NO hay aviso: el rango es cerrado", arguments: [0.3, 1.2, 0.655, 0.67])
    func humanRangeIsClosed(meters: Double) {
        #expect(AppSettings.isHumanStride(meters))
    }

    @Test("Fuera del borde, por poco que sea, sí avisa", arguments: [0.2999, 1.2001])
    func justOutsideWarns(meters: Double) {
        #expect(!AppSettings.isHumanStride(meters))
    }

    @Test("El rango humano es el de la decisión de Paul: 0,3–1,2 m")
    func humanRangeBounds() {
        #expect(AppSettings.humanStrideRangeM == 0.3...1.2)
        #expect(!AppSettings.isHumanStride(.nan), "un no-número nunca es humano")
    }

    // MARK: - El límite representable (B-3)

    @Test("El borde es EXACTO: la mayor zancada que cabe se guarda, y el Double siguiente ya no")
    func representableLimitIsExactOnBothSides() throws {
        let limit = MetricsCalculator.maxRepresentableStrideM

        #expect(AppSettings.isRepresentableStride(limit), "el límite cabe: es el mayor que cabe")
        #expect(!AppSettings.isRepresentableStride(limit.nextUp), "y su vecino ya no")

        var settings = AppSettings()
        try settings.setStrideM(limit)
        #expect(settings.strideM == limit, "se guarda, aunque sea absurda: no cabe es lo único que bloquea")

        #expect(throws: DomainError.invalidValue(field: "strideM")) { try settings.setStrideM(limit.nextUp) }
        #expect(settings.strideM == limit, "rechazar no borra lo anterior")
    }

    @Test("El caso del crash: 1e307 es finito, tiene 308 dígitos y NO cabe")
    func theCrashValueIsRejected() throws {
        // D3 de la retro del Epic 2: `isRepresentableStride` solo miraba `isFinite`, así que
        // esto se guardaba con el aviso de rango humano y estrellaba la app en CADA caminata
        // posterior. Se teclea como 308 dígitos, que el parser lee sin problema.
        let meters = try #require(AppSettings.strideMeters(fromText: "1" + String(repeating: "0", count: 307)))

        #expect(meters == 1e307)
        #expect(meters.isFinite, "es finito: por eso `isFinite` a secas no lo veía")
        #expect(!AppSettings.isRepresentableStride(meters), "pero no cabe en la fórmula")

        var settings = AppSettings()
        #expect(throws: DomainError.invalidValue(field: "strideM")) { try settings.setStrideM(meters) }
        #expect(settings.strideM == nil)
    }

    @Test("Una zancada absurda pero representable se sigue guardando con su aviso (decisión de la 2.3)")
    func absurdButRepresentableStillSaves() throws {
        // El techo nuevo es el de la aritmética, no un máximo "razonable": poner uno aquí
        // renegociaría por la puerta de atrás la decisión de Paul de avisar y no bloquear.
        var settings = AppSettings()
        try settings.setStrideM(50)

        #expect(settings.strideM == 50)
        #expect(!AppSettings.isHumanStride(50), "se avisa")
        #expect(AppSettings.isRepresentableStride(50), "pero cabe de sobra, así que no se bloquea")
    }

    @Test("Cero y los negativos SIGUEN cabiendo: su motivo es otro y su mensaje también")
    func nonPositiveValuesStillFitTheFormula() {
        #expect(AppSettings.isRepresentableStride(0))
        #expect(AppSettings.isRepresentableStride(-0.5))
        #expect(AppSettings.isRepresentableStride(-1e307), "enorme y negativo: lo suyo es no ser > 0")
        #expect(!AppSettings.isRepresentableStride(.infinity))
        #expect(!AppSettings.isRepresentableStride(.nan), "un no-número no cabe en ninguna fórmula")
    }

    @Test("Una zancada guardada ANTES de B-3 se lee como sin configurar, sin costar la ventana")
    func previouslyStoredOversizedStrideReadsAsUnset() {
        // Un `settings.json` escrito por un build anterior con 1e307 dentro. La puerta
        // tolerante se come ESE campo y nada más: el fichero no se aparta.
        let settings = AppSettings(recentQuoteIds: [7, 8, 9], strideM: 1e307)

        #expect(settings.strideM == nil)
        #expect(settings.resolvedStrideM(default: 0.655) == 0.655, "la caminata usa el default")
        #expect(settings.recentQuoteIds == [7, 8, 9], "y la ventana de frases sobrevive")
    }

    // MARK: - Texto tecleado → metros (2.3)

    @Test("Coma decimal: el teclado en español da coma y se acepta")
    func decimalCommaIsAccepted() {
        #expect(AppSettings.strideMeters(fromText: "0,670") == 0.670)
        #expect(AppSettings.strideMeters(fromText: "0.670") == 0.670, "y el punto también")
        #expect(AppSettings.strideMeters(fromText: " 0,67 ") == 0.67, "con espacios alrededor")
        #expect(AppSettings.strideMeters(fromText: ",7") == 0.7)
        #expect(AppSettings.strideMeters(fromText: "1") == 1)
    }

    @Test("Lo que no es un número no lo es", arguments: [
        "", "   ", "abc", ",", ".", "0,6,7", "0,,7", "1e3", "0x10", "inf", "nan", "0,67 m", "٣", "-", "1-2",
    ])
    func notANumber(text: String) {
        #expect(AppSettings.strideMeters(fromText: text) == nil)
    }

    @Test("El signo se parsea y lo rechaza después la frontera, que es quien sabe por qué")
    func negativeParsesThenGetsRejected() throws {
        let meters = try #require(AppSettings.strideMeters(fromText: "-0,5"))

        #expect(meters == -0.5, "parsear y validar son dos pasos distintos")

        var settings = AppSettings()
        #expect(throws: DomainError.invalidValue(field: "strideM")) { try settings.setStrideM(meters) }
        #expect(settings.strideM == nil)
    }

    @Test("Un número que no cabe se parsea a infinito, y eso NO es el motivo del cero")
    func overflowParsesToInfinity() throws {
        // Es el caso real: 400 dígitos tecleados. Son dígitos, así que el parser los lee; lo
        // que pasa es que no caben. `isRepresentableStride` separa ese motivo del de "≤ 0",
        // que se corrige de otra manera y no es lo que le pasa a este número.
        let meters = try #require(AppSettings.strideMeters(fromText: String(repeating: "9", count: 400)))

        #expect(meters.isInfinite)
        #expect(!AppSettings.isRepresentableStride(meters))
        #expect(AppSettings.isRepresentableStride(0.655))
        #expect(AppSettings.isRepresentableStride(0), "cero cabe: lo suyo es no ser mayor que cero")
        #expect(AppSettings.isRepresentableStride(-0.5), "y un negativo también cabe")
    }

    // MARK: - Volver al valor por defecto (2.3, decisión de Paul)

    @Test("Quitar el override devuelve la zancada al default, y no toca lo demás")
    func clearingTheOverrideReturnsToTheDefault() throws {
        var settings = AppSettings(recentQuoteIds: [4, 5], strideM: 0.067)

        settings.clearStrideM()

        #expect(settings.strideM == nil)
        #expect(settings.resolvedStrideM(default: 0.655) == 0.655)
        #expect(settings.recentQuoteIds == [4, 5], "la ventana de frases no es asunto suyo")
    }

    @Test("Quitar el override sin override es inofensivo")
    func clearingWithoutOverrideIsHarmless() {
        var settings = AppSettings()

        settings.clearStrideM()

        #expect(settings == AppSettings.defaults)
    }

    @Test("Vaciar el campo NO es la vuelta atrás: se sigue rechazando")
    func emptyTextIsStillRejected() {
        // La fila de la matriz sigue congelada: el campo vacío no es un número. La vuelta atrás
        // es `clearStrideM()`, que es una acción explícita y aparte.
        #expect(AppSettings.strideMeters(fromText: "") == nil)
    }

    @Test("Cero se parsea y se rechaza en la frontera")
    func zeroParsesThenGetsRejected() throws {
        let meters = try #require(AppSettings.strideMeters(fromText: "0"))

        var settings = AppSettings()
        #expect(throws: DomainError.invalidValue(field: "strideM")) { try settings.setStrideM(meters) }
        #expect(settings.strideM == nil)
    }
}
