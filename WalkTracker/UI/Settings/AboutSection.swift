import Foundation

/// Qué contiene la sección "Acerca de" de Ajustes, **sin SwiftUI**: la lógica de
/// presentación vive en un tipo probable y la vista solo la recorre. Es la salida que
/// eligió la decisión D1 del 2026-09-20 —XCUITest descartado, presentación extraída a
/// tipos que la suite actual ya sabe ejecutar—, y aquí es barata porque la sección no
/// pinta más que texto y enlaces.
///
/// **Su forma es la respuesta a un defecto concreto.** La atribución de Open-Meteo no es
/// un adorno: es una **obligación de licencia** (CC BY 4.0 del dato, AD-24). Vivía solo
/// dentro de `if let weather` en `WeatherCard`, así que no se veía sin clima ni fuera de
/// una sesión, y se tardó dos retrospectivas en verlo. Por eso `items` es una **constante**
/// y no una función del estado: no recibe nada, no tiene ningún `if`, y no hay ninguna
/// entrada de la que pudiera colgar uno. Volver a condicionarla al clima exigiría
/// convertirla en función, y entonces `AboutSectionTests` **deja de compilar**.
///
/// Qué exige la cláusula, citada de su fuente, y qué parte cumple cada sitio: `NOTICE`, en
/// la raíz del repositorio. Léelo antes de mover nada de aquí.
enum AboutSection {

    /// El material licenciado, al que la atribución enlaza.
    ///
    /// Es §3(a)(1)(A)(v) de CC BY 4.0 —*"a URI or hyperlink to the Licensed Material"*— y
    /// es también el enlace que Open-Meteo pide *"next to any location Open-Meteo data are
    /// displayed"*. Se escribe a mano, como `MotionBlockedView.settingsURL`, y por eso
    /// lleva test: una errata aquí deja la obligación apuntando a ninguna parte, en verde.
    static let openMeteoURL = URL(string: "https://open-meteo.com/")!

    /// El texto de la licencia bajo la que llega el dato, CC BY 4.0.
    ///
    /// Es la **segunda mitad** de §3(a)(1)(C) —*"indicate the Licensed Material is licensed
    /// under this Public License, and include the text of, or the URI or hyperlink to, this
    /// Public License"*—: nombrar la licencia en el pie no basta, hay que enlazarla. Hasta el
    /// 2026-09-21 ese enlace vivía solo en `NOTICE`, que **no viaja dentro del `.app`**, y por
    /// eso la obligación no se cumplía en el producto.
    ///
    /// La URL es la **canónica** que `NOTICE` §2 cita como fuente verificada (descargada y
    /// con huella el 2026-09-21), no una tecleada de memoria. Lleva test por lo mismo que la
    /// anterior: una errata deja la obligación apuntando a ninguna parte, en verde.
    static let licenseTextURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    /// Cada cosa que "Acerca de" puede pintar. Hoy hay **dos**, y las dos son la misma
    /// obligación de licencia: el crédito al licenciante y el enlace al texto de la licencia.
    /// La versión de la app, licencias de otras cosas y cualquier ajuste pertenecen a sus
    /// historias (Epic 3, 4.2, Epic 5) y no se adelantan aquí.
    enum Item: String, CaseIterable, Identifiable, Sendable {

        /// Crédito a Open-Meteo, con enlace a `openMeteoURL` (AD-24, `NOTICE`).
        case openMeteoAttribution

        /// Enlace al texto de CC BY 4.0, con destino `licenseTextURL`
        /// (§3(a)(1)(C) segunda mitad; decisión de Paul del 2026-09-21, `NOTICE` §5).
        case licenseText

        var id: String { rawValue }
    }

    /// Lo que la sección enseña, en orden. **Constante**, y ahí está todo el criterio de
    /// B-9: la atribución se ve en una instalación que nunca ha capturado clima.
    ///
    /// Se escribe entera a mano, y no como `Item.allCases`, para que el test pueda
    /// compararlas: una entrada declarada que nunca llegue a la pantalla es justo la
    /// manera en que esta obligación se perdió la primera vez.
    ///
    /// El crédito va primero y el enlace a la licencia después, que es el orden en que la
    /// cláusula los pide: primero quién hizo el dato, luego bajo qué condiciones llega.
    static let items: [Item] = [.openMeteoAttribution, .licenseText]

    /// El destino de cada entrada.
    static func url(for item: Item) -> URL {
        switch item {
        case .openMeteoAttribution: openMeteoURL
        case .licenseText: licenseTextURL
        }
    }
}
