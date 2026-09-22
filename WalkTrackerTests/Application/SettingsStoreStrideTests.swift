import Domain
import Foundation
import Testing

@testable import WalkTracker

/// La intención de recalibrar (2.3): qué se guarda, qué se rechaza y qué se avisa.
///
/// **Aquí vive la decisión, y por eso la historia se puede probar sin renderizar la pantalla**
/// (A-4 sigue abierto). La vista entrega el texto crudo y pinta `strideOutcome`; todo lo demás
/// —parsear, validar, persistir o no— es de este store.
@MainActor
@Suite("SettingsStore · recalibrar la zancada")
struct SettingsStoreStrideTests {

    private static func store(_ storage: StorageStub = StorageStub()) -> (StorageStub, SettingsStore) {
        (storage, SettingsStoreFixture.store(storage: storage))
    }

    // MARK: - Aceptado

    @Test("Guardar un valor válido: se persiste, sin aviso, y la resolución pasa a darlo")
    func savesValidStride() {
        let (storage, settings) = Self.store()

        settings.saveStride(fromText: "0,670")

        #expect(settings.strideOutcome == .saved)
        #expect(settings.strideM == 0.670)
        #expect(settings.resolvedStrideM(default: 0.655) == 0.670)
        #expect(storage.settingsSaved.map(\.strideM) == [0.670], "una sola escritura por pulsación")
    }

    @Test("Sin recalibrar nunca, la resolución devuelve el default de formulas.json")
    func unsetResolvesToDefault() {
        let (storage, settings) = Self.store()

        #expect(settings.strideM == nil)
        #expect(settings.resolvedStrideM(default: 0.655) == 0.655)
        #expect(storage.settingsSaved.isEmpty, "no tocarlo no escribe nada")
    }

    @Test("Recalibrar no toca la ventana de frases, que sigue en el mismo fichero")
    func savingStrideKeepsTheQuoteWindow() {
        let (storage, settings) = Self.store(StorageStub(settings: AppSettings(recentQuoteIds: [1, 2, 3])))

        settings.saveStride(fromText: "0,7")

        #expect(settings.recentQuoteIds == [1, 2, 3])
        #expect(storage.settingsSaved.last?.recentQuoteIds == [1, 2, 3])
    }

    @Test("Guardar dos veces: gana el último, y cada pulsación escribe una vez")
    func lastSaveWins() {
        let (storage, settings) = Self.store()

        settings.saveStride(fromText: "0,670")
        settings.saveStride(fromText: "0,700")

        #expect(settings.strideM == 0.700)
        #expect(storage.settingsSaved.map(\.strideM) == [0.670, 0.700])
    }

    // MARK: - Aceptado con aviso (el rango humano avisa, no bloquea)

    @Test("Fuera de 0,3–1,2 m: SE GUARDA y se avisa", arguments: ["0,067", "3,0", "0,001"])
    func outOfHumanRangeSavesWithWarning(text: String) throws {
        let (storage, settings) = Self.store()

        settings.saveStride(fromText: text)

        let meters = try #require(AppSettings.strideMeters(fromText: text))
        #expect(settings.strideOutcome == .savedOutsideHumanRange(meters))
        #expect(settings.strideOutcome?.isSaved == true)
        #expect(settings.strideM == meters, "es su app y su zancada: el aviso no bloquea")
        #expect(storage.settingsSaved.map(\.strideM) == [meters])
    }

    @Test("En el borde exacto se guarda SIN aviso", arguments: ["0,3", "1,2"])
    func edgesSaveWithoutWarning(text: String) {
        let (_, settings) = Self.store()

        settings.saveStride(fromText: text)

        #expect(settings.strideOutcome == .saved)
    }

    // MARK: - Rechazado (y el fichero no cambia)

    @Test("No numérico o vacío: rechazado, con mensaje, y el fichero no cambia", arguments: [
        "", "   ", "abc", ",", "0,6,7", "1e3",
    ])
    func rejectsNonNumbers(text: String) {
        let (storage, settings) = Self.store(StorageStub(settings: AppSettings(recentQuoteIds: [5])))

        settings.saveStride(fromText: text)

        #expect(settings.strideOutcome == .rejected(.notANumber))
        #expect(settings.strideOutcome?.isSaved == false)
        #expect(settings.strideM == nil)
        #expect(storage.settingsSaved.isEmpty, "nada se persiste")
        #expect(settings.recentQuoteIds == [5], "y el resto de los ajustes sigue intacto")
    }

    @Test("Cero o negativo: rechazado, con mensaje, y el fichero no cambia", arguments: ["0", "0,0", "-0,5", "-1"])
    func rejectsNonPositive(text: String) {
        let (storage, settings) = Self.store()

        settings.saveStride(fromText: text)

        #expect(settings.strideOutcome == .rejected(.notPositive))
        #expect(settings.strideM == nil)
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("Un número que no cabe tiene su propio motivo, no el del cero")
    func rejectsOverflowWithItsOwnReason() {
        let (storage, settings) = Self.store()

        // 400 dígitos son dígitos: se parsean y desbordan a `inf`. Antes los rechazaba
        // `validateStride` por no finito y Paul leía "tiene que ser mayor que cero", para un
        // número que no es ni cero ni negativo.
        settings.saveStride(fromText: String(repeating: "9", count: 400))

        #expect(settings.strideOutcome == .rejected(.tooLarge))
        #expect(settings.strideOutcome != .rejected(.notPositive), "el motivo del cero no vale aquí")
        #expect(settings.strideOutcome != .rejected(.notANumber), "y tampoco el de `abc`: son dígitos")
        #expect(settings.strideM == nil)
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("El caso del crash: 1e307 se rechaza en la frontera y ninguna caminata lo ve")
    func rejectsTheStrideThatUsedToCrashTheApp() throws {
        // D3 de la retro del Epic 2: 308 dígitos. Finito, así que pasaba la frontera, se
        // guardaba con el aviso de rango humano, y `metrics(at:)` estrellaba la app en CADA
        // caminata hasta reinstalar. El motivo es "no cabe", no "no es mayor que cero".
        let (storage, settings) = Self.store(StorageStub(settings: AppSettings(strideM: 0.670)))

        settings.saveStride(fromText: "1" + String(repeating: "0", count: 307))

        #expect(settings.strideOutcome == .rejected(.tooLarge))
        #expect(settings.strideOutcome != .rejected(.notPositive), "no es cero ni negativo")
        #expect(storage.settingsSaved.isEmpty, "el fichero no cambia")
        #expect(settings.strideM == 0.670, "y la zancada buena sigue en su sitio")

        // Lo que importa del rechazo: la caminata siguiente nace con un valor con el que la
        // distancia se puede calcular.
        var session = try Session.start(at: Date(timeIntervalSince1970: 0), strideM: settings.resolvedStrideM(default: 0.655))
        try session.addMeasuredSteps(4980)
        let metrics = session.metrics(at: Date(timeIntervalSince1970: 3720))
        #expect(metrics.distanceM.isFinite)
        #expect(!metrics.degraded)
    }

    @Test("Una zancada absurda pero representable se sigue guardando con su aviso (2.3)")
    func absurdButRepresentableStrideStillSaves() {
        // El techo nuevo es el de la aritmética y nada más: 50 m sigue siendo cosa de Paul.
        let (storage, settings) = Self.store()

        settings.saveStride(fromText: "50")

        #expect(settings.strideOutcome == .savedOutsideHumanRange(50))
        #expect(settings.strideM == 50)
        #expect(storage.settingsSaved.map(\.strideM) == [50])
    }

    @Test("Un rechazo no borra la zancada que ya estaba guardada")
    func rejectionKeepsThePreviousValue() {
        let (storage, settings) = Self.store(StorageStub(settings: AppSettings(strideM: 0.670)))

        settings.saveStride(fromText: "abc")

        #expect(settings.strideM == 0.670)
        #expect(settings.resolvedStrideM(default: 0.655) == 0.670)
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("Las dos causas de rechazo se distinguen: merecen mensajes distintos")
    func rejectionReasonsAreDistinct() {
        let (_, notANumber) = Self.store()
        notANumber.saveStride(fromText: "abc")
        let (_, notPositive) = Self.store()
        notPositive.saveStride(fromText: "0")

        #expect(notANumber.strideOutcome != notPositive.strideOutcome)
    }

    // MARK: - El mensaje en línea

    @Test("Volver a escribir apaga el mensaje anterior")
    func editingClearsTheOutcome() {
        let (_, settings) = Self.store()
        settings.saveStride(fromText: "abc")
        #expect(settings.strideOutcome != nil)

        settings.strideEditingDidChange()

        #expect(settings.strideOutcome == nil)
    }

    @Test("Sin mensaje que apagar, escribir no hace nada")
    func editingWithoutOutcomeIsInert() {
        let (storage, settings) = Self.store()

        settings.strideEditingDidChange()

        #expect(settings.strideOutcome == nil)
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("Salir de Ajustes apaga el mensaje: era de aquella pulsación", arguments: ["0,670", "abc"])
    func leavingTheScreenClearsTheOutcome(text: String) {
        let (_, settings) = Self.store()
        settings.saveStride(fromText: text)
        #expect(settings.strideOutcome != nil)

        settings.strideScreenDidDisappear()

        // Sin esto, volver a la pestaña enseñaba otra vez el mensaje de hace diez minutos.
        #expect(settings.strideOutcome == nil)
    }

    @Test("Salir sin nada que apagar no hace nada")
    func leavingWithoutOutcomeIsInert() {
        let (storage, settings) = Self.store()

        settings.strideScreenDidDisappear()

        #expect(settings.strideOutcome == nil)
        #expect(storage.settingsSaved.isEmpty)
    }

    // MARK: - Volver al valor por defecto (decisión de Paul, 2026-09-19)

    @Test("Usar el valor por defecto: se borra el override y vuelve a mandar formulas.json")
    func clearingReturnsToTheDefault() {
        let (storage, settings) = Self.store()
        settings.saveStride(fromText: "0,067")
        #expect(settings.strideM == 0.067, "el dedazo se guardó, como dice la matriz")

        settings.clearStride()

        #expect(settings.strideOutcome == .clearedToDefault)
        #expect(settings.strideM == nil)
        #expect(settings.resolvedStrideM(default: 0.655) == 0.655, "la siguiente caminata vuelve al default")
        #expect(storage.settingsSaved.last?.strideM == nil, "y queda escrito: no es solo de esta ejecución")
    }

    @Test("Es la ÚNICA vuelta atrás: vaciar el campo se sigue rechazando")
    func clearingIsTheOnlyWayBack() {
        let (storage, settings) = Self.store(StorageStub(settings: AppSettings(strideM: 0.067)))

        settings.saveStride(fromText: "")

        #expect(settings.strideOutcome == .rejected(.notANumber), "la fila congelada de la matriz no cambia")
        #expect(settings.strideM == 0.067, "y el dedazo sigue ahí")

        settings.clearStride()

        #expect(settings.strideM == nil)
        #expect(storage.settingsSaved.map(\.strideM) == [nil], "una sola escritura, la del botón")
    }

    @Test("Volver al default sobrevive a relanzar la app")
    func clearedStrideSurvivesRelaunch() {
        let storage = StorageStub()
        let settings = SettingsStoreFixture.store(storage: storage)
        settings.saveStride(fromText: "0,670")
        settings.clearStride()

        let relaunched = SettingsStoreFixture.store(storage: storage)

        #expect(relaunched.strideM == nil)
        #expect(relaunched.resolvedStrideM(default: 0.655) == 0.655)
    }

    @Test("Sin override que quitar no se escribe nada")
    func clearingWithoutOverrideWritesNothing() {
        let (storage, settings) = Self.store()

        settings.clearStride()

        #expect(settings.strideM == nil)
        #expect(settings.strideOutcome == nil, "no hay nada que contar")
        #expect(storage.settingsSaved.isEmpty)
    }

    @Test("Volver al default no toca la ventana de frases")
    func clearingKeepsTheQuoteWindow() {
        let (storage, settings) = Self.store(StorageStub(settings: AppSettings(recentQuoteIds: [1, 2], strideM: 0.9)))

        settings.clearStride()

        #expect(settings.recentQuoteIds == [1, 2])
        #expect(storage.settingsSaved.last?.recentQuoteIds == [1, 2])
    }

    // MARK: - Relanzar

    @Test("La zancada guardada sobrevive a relanzar la app")
    func strideSurvivesRelaunch() {
        let storage = StorageStub()
        SettingsStoreFixture.store(storage: storage).saveStride(fromText: "0,670")

        // "Relanzar" es montar otro store sobre el mismo almacenamiento.
        let relaunched = SettingsStoreFixture.store(storage: storage)

        #expect(relaunched.strideM == 0.670)
        #expect(relaunched.strideOutcome == nil, "el mensaje es de la pulsación, no del ajuste")
    }

    @Test("Un fallo de disco no cambia lo que la app usa en esta ejecución, y NO se cuenta como guardado")
    func diskFailureKeepsTheValueInMemory() {
        let storage = StorageStub()
        storage.failSaveSettings(with: .failed(operation: "write"))
        let settings = SettingsStoreFixture.store(storage: storage)

        settings.saveStride(fromText: "0,670")

        #expect(settings.strideM == 0.670, "la siguiente caminata ya la usa")
        // El comportamiento se conserva a propósito —la caminata no se para por un fallo de
        // disco—, pero el mensaje no puede decir "Zancada guardada. La siguiente caminata la
        // usará.": no se escribió nada y al relanzar la app el valor ya no está.
        #expect(settings.strideOutcome == .notPersisted)
        #expect(settings.strideOutcome?.isSaved == false)
    }

    @Test("Un fallo de disco al volver al default tampoco se cuenta como guardado")
    func diskFailureWhenClearingIsReported() {
        let storage = StorageStub(settings: AppSettings(strideM: 0.067))
        let settings = SettingsStoreFixture.store(storage: storage)
        storage.failSaveSettings(with: .failed(operation: "write"))

        settings.clearStride()

        #expect(settings.strideM == nil, "esta ejecución ya vuelve al default")
        #expect(settings.strideOutcome == .notPersisted)
    }
}
