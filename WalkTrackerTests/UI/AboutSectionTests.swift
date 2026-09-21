import Foundation
import Testing

@testable import WalkTracker

/// La atribución de Open-Meteo en Ajustes → Acerca de (B-9), que es una **obligación de
/// licencia** (CC BY 4.0 del dato, AD-24; la cláusula citada está en `NOTICE`).
///
/// El defecto que estos tests impiden repetir tiene nombre y dos retrospectivas: la
/// atribución vivía **solo** dentro de `if let weather` en `WeatherCard`, así que en una
/// instalación que nunca hubiera capturado clima **no se veía en ningún sitio**, y ni la
/// suite ni el gate lo notaron.
///
/// Desde el 2026-09-21 la sección cumple la obligación **entera**: §3(a)(1)(C) pide nombrar
/// la licencia **e incluir su texto o un enlace a ella**, así que además del crédito hay una
/// fila que enlaza el texto de CC BY 4.0. Las dos filas están fijadas aquí de la misma
/// manera, y la URL de la licencia sale de `NOTICE` §2, que la verificó descargándola.
///
/// Se prueba sin renderizar, como manda la decisión D1 del 2026-09-20: lo que la sección
/// contiene lo declara `AboutSection`, que no importa SwiftUI. Mismo trato que
/// `MotionBlockedView.settingsURL` con `MotionBlockedViewTests`.
@Suite("Ajustes · Acerca de: la atribución no depende del clima")
struct AboutSectionTests {

    /// **El criterio de B-9.** `AboutSection.items` es una constante: no recibe estado de
    /// sesión ni de clima, así que la atribución se ve siempre.
    ///
    /// Esta es la mutación que se comprobó: esconder la atribución tras una condición de
    /// clima obliga a convertir `items` en una función, y entonces esta línea **deja de
    /// compilar**. No hay forma de condicionarla al clima dejando la suite en verde.
    @Test("La atribución está en «Acerca de» sin depender de nada")
    func attributionIsUnconditional() {
        #expect(AboutSection.items.contains(.openMeteoAttribution))
    }

    /// La **otra mitad** de §3(a)(1)(C), cerrada el 2026-09-21 por decisión de Paul: la
    /// cláusula pide indicar la licencia *"and include the text of, or the URI or hyperlink
    /// to, this Public License"*. El pie de la sección la **nombra**; esta fila es la que la
    /// **enlaza**. Antes de esta entrada el enlace vivía solo en `NOTICE`, que no viaja
    /// dentro del `.app`, así que la obligación no se cumplía en el producto.
    ///
    /// Va fijada igual que la de arriba y por lo mismo: constante, sin estado del que colgar
    /// un `if`.
    @Test("El enlace al texto de la licencia está en «Acerca de» sin depender de nada")
    func licenseTextLinkIsUnconditional() {
        #expect(AboutSection.items.contains(.licenseText))
    }

    /// Nada declarado se queda sin pintar. Es la otra mitad del mismo fallo: una entrada
    /// que existe en el tipo y no llega a la pantalla es invisible igual que una metida
    /// dentro de un `if`.
    @Test("Todo lo que «Acerca de» declara es lo que enseña")
    func everyDeclaredItemIsShown() {
        #expect(AboutSection.items == AboutSection.Item.allCases)
    }

    /// Los dos sitios donde vive la atribución apuntan al **mismo** destino.
    ///
    /// Las dos URL se escriben a mano en ficheros distintos —la tarjeta no se toca, y
    /// centralizarlas acoplaría Ajustes a la pantalla de sesión—, así que esto es lo único
    /// que impide que diverjan en silencio. La de la tarjeta no se puede quitar: Open-Meteo
    /// pide el enlace "next to any location Open-Meteo data are displayed".
    @Test("Ajustes y la tarjeta de clima llevan al mismo sitio")
    func bothAttributionsPointToTheSameDestination() {
        #expect(AboutSection.url(for: .openMeteoAttribution) == WeatherCard.attributionURL)
    }

    /// La URL es la del licenciante y va por HTTPS.
    ///
    /// Es §3(a)(1)(A)(v) de CC BY 4.0 —"a URI or hyperlink to the Licensed Material"—, y
    /// una errata en una cadena escrita a mano deja la obligación apuntando a ninguna parte
    /// sin que nada se queje. El producto además no hace ni una petición que no sea HTTPS.
    @Test("El destino de la atribución es open-meteo.com por HTTPS")
    func attributionURLIsTheLicensorSite() throws {
        let url = AboutSection.url(for: .openMeteoAttribution)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "open-meteo.com")
    }

    /// El destino del enlace de licencia es **el texto canónico de CC BY 4.0**, y no otra
    /// cosa que también se llame "licencia".
    ///
    /// La URL es la que `NOTICE` §2 registra como fuente verificada —`legalcode.txt`
    /// descargado el 2026-09-21, con tamaño y SHA-256, y su URL canónica
    /// `https://creativecommons.org/licenses/by/4.0/`—, no una escrita de memoria. Se fija
    /// entera, ruta incluida: apuntar a `creativecommons.org` a secas, o a la versión 3.0,
    /// dejaría de cumplir §3(a)(1)(C) sin que nada se queje.
    @Test("El enlace de licencia lleva al texto de CC BY 4.0 por HTTPS")
    func licenseURLIsTheCanonicalCCBY40Text() throws {
        let url = AboutSection.url(for: .licenseText)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "creativecommons.org")
        #expect(components.path == "/licenses/by/4.0/")
    }

    /// Cada entrada lleva a **su** sitio. Las dos filas dicen cosas distintas —una acredita
    /// al licenciante, la otra enlaza la licencia—, así que un `case` mal cableado en
    /// `url(for:)` convertiría una de las dos en un duplicado silencioso de la otra: la
    /// pantalla seguiría enseñando dos filas y una de las dos obligaciones dejaría de
    /// cumplirse.
    @Test("Las dos entradas de «Acerca de» no llevan al mismo sitio")
    func eachItemHasItsOwnDestination() {
        let destinations = AboutSection.items.map { AboutSection.url(for: $0) }

        #expect(Set(destinations).count == AboutSection.items.count)
    }
}
