import Domain
import Foundation
import Testing

@testable import WalkTracker

/// El ida y vuelta del campo de zancada (2.3): lo que la pantalla **escribe** en el campo tiene
/// que ser lo que su propio parser **lee**.
///
/// Este emparejamiento no existía y por eso se rompió tres veces seguidas en el mismo sitio:
/// `SettingsView.decimalText` formateaba con el locale del sistema y `AppSettings.strideMeters`
/// solo entiende dígitos ASCII, coma o punto y ningún separador de millares. En `ar_EG` el campo
/// nacía con `٠٫٦٥٥` y pulsar Guardar **sin tocar nada** respondía "Escribe la longitud en
/// metros"; una zancada grande salía `10.000,000` y pasaba lo mismo; y con tres decimales fijos,
/// un valor guardado con más se sembraba redondeado y Guardar lo sobrescribía en silencio.
///
/// `decimalText` es interno —no privado— justo para que se pueda emparejar aquí sin renderizar
/// la vista, como `MotionBlockedView.settingsURL` lo es para `MotionBlockedViewTests`.
@Suite("Ajustes · lo que la pantalla escribe, su parser lo lee")
struct SettingsViewTests {

    /// Regiones que rompen el ida y vuelta de tres maneras distintas: numeración no latina
    /// (`ar_EG`, `fa_IR`, `ne_NP`, `my_MM`), agrupamiento de millares con punto (`es_ES`,
    /// `de_DE`), con espacio (`fr_FR`, `ru_RU`) y con lakh (`en_IN`).
    static let locales = [
        "es_ES", "en_US", "ar_EG", "fa_IR", "ne_NP", "my_MM", "de_DE", "fr_FR", "ru_RU", "en_IN",
    ]

    /// Valores que la pantalla siembra de verdad: el default, una recalibración, un dedazo, el
    /// borde del rango, más decimales de los que caben en tres, y una zancada absurda de cinco
    /// cifras, que es la que saca el separador de millares.
    static let values: [Double] = [0.655, 0.67, 0.067, 1.2, 0.6789, 10_000, 0.001, 1]

    @Test("El campo sembrado se vuelve a leer como el mismo número, en cualquier región", arguments: locales, values)
    func seededTextParsesBackToTheSameValue(locale id: String, meters: Double) throws {
        let text = SettingsView.decimalText(meters, locale: Locale(identifier: id))

        let parsed = try #require(
            AppSettings.strideMeters(fromText: text),
            "la app rellenó el campo con «\(text)» y su propio parser lo rechaza (\(id))"
        )
        #expect(parsed == meters, "«\(text)» se lee como \(parsed) y no como \(meters) (\(id))")
    }

    @Test("Los dígitos son latinos aunque la región no lo sea")
    func digitsAreAlwaysLatin() {
        // Sin fijar la numeración, esto daba `٠٫٦٥٥` y `۰٫۶۵۵`.
        #expect(SettingsView.decimalText(0.655, locale: Locale(identifier: "ar_EG")) == "0.655")
        #expect(SettingsView.decimalText(0.655, locale: Locale(identifier: "fa_IR")) == "0.655")
        // Y el separador decimal sigue siendo el de cada región.
        #expect(SettingsView.decimalText(0.655, locale: Locale(identifier: "es_ES")) == "0,655")
        #expect(SettingsView.decimalText(0.655, locale: Locale(identifier: "en_US")) == "0.655")
    }

    @Test("Sin separador de millares: dos separadores hacen `nil` al parser")
    func noGroupingSeparator() {
        #expect(SettingsView.decimalText(10_000, locale: Locale(identifier: "es_ES")) == "10000")
        #expect(SettingsView.decimalText(10_000, locale: Locale(identifier: "en_US")) == "10000")
    }

    @Test("Se siembra la precisión real, no tres decimales")
    func seedsTheStoredPrecision() {
        let spain = Locale(identifier: "es_ES")

        // Con `.fractionLength(3)` esto era "0,679" y Guardar cambiaba el valor sin decirlo.
        #expect(SettingsView.decimalText(0.6789, locale: spain) == "0,6789")
        #expect(SettingsView.decimalText(0.655, locale: spain) == "0,655", "y no se inventan ceros de más")
        #expect(SettingsView.decimalText(1, locale: spain) == "1")
    }

    @Test("El aviso de rango lleva sus dos extremos por separado, y con locale")
    func humanRangeHasTwoSeparateBounds() {
        // Dos marcadores en el mensaje, no un "0,3 y 1,2" opaco: el traductor tiene que poder
        // reordenarlos y cambiar la conjunción.
        let spain = SettingsView.humanRangeBounds(locale: Locale(identifier: "es_ES"))
        #expect(spain.lower == "0,3")
        #expect(spain.upper == "1,2")

        let us = SettingsView.humanRangeBounds(locale: Locale(identifier: "en_US"))
        #expect(us.lower == "0.3")
        #expect(us.upper == "1.2")

        // Y salen del rango que decide el dominio, no de dos números tecleados en un mensaje.
        #expect(AppSettings.humanStrideRangeM.lowerBound == 0.3)
        #expect(AppSettings.humanStrideRangeM.upperBound == 1.2)
    }

    @Test("Cada resultado tiene SU texto, y el del disco fallido no dice \"guardada\"")
    @MainActor
    func everyOutcomeHasItsOwnMessage() {
        let outcomes: [SettingsStore.StrideOutcome] = [
            .saved, .savedOutsideHumanRange(0.067), .clearedToDefault, .notPersisted,
            .rejected(.notANumber), .rejected(.tooLarge), .rejected(.notPositive),
        ]

        let messages = outcomes.map { SettingsView.message(for: $0) }

        #expect(Set(messages).count == outcomes.count, "dos resultados con el mismo texto es un mensaje que miente")
        #expect(!SettingsView.message(for: .notPersisted).contains("guardada"), "el disco falló: no se guardó nada")
        #expect(SettingsView.message(for: .savedOutsideHumanRange(0.067)).contains("0,3"), "el aviso interpola el rango real")
    }
}
