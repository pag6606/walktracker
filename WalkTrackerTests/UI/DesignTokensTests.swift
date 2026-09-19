import SwiftUI
import Testing
import UIKit

@testable import WalkTracker

/// Los valores del vocabulario visual, fijados. No es un test de tautologías: es el
/// contrato que heredan las cuatro superficies que faltan —anillo de meta (3.1), logros
/// (3.3), historial (5.2), ajustes (2.3)—, que deben tomar espaciado, margen, radio y
/// objetivo táctil de aquí sin decidir nada nuevo. Si alguien cambia un número, este
/// fichero es el sitio donde esa decisión se ve y se discute.
///
/// La parte que de verdad muerde es el contraste: los dos colorsets se **resuelven** en
/// claro y en oscuro y se recalcula su ratio WCAG contra el fondo real sobre el que se
/// pintan. El `.orange` del sistema daba 2,20:1 sobre blanco —AA incumplida en
/// producción—; si alguien retoca un colorset y vuelve a caer, esto lo dice.
///
/// Este fichero importa UIKit a propósito: resolver un color dinámico contra un
/// `UITraitCollection` es la única forma de medir lo que el usuario verá. AD-10 prohíbe
/// UIKit en `WalkTracker/UI/`, no en la suite (`check-project-shape.sh` no mira
/// `WalkTrackerTests/`).
@Suite("Tokens de estilo")
struct DesignTokensTests {

    // MARK: - Escala de UX-DR3

    @Test("Espaciado: la escala de UX-DR3, sin peldaños intermedios")
    func spacingScale() {
        #expect(Spacing.xs == 4)
        #expect(Spacing.s == 8)
        #expect(Spacing.m == 12)
        #expect(Spacing.l == 16)
        #expect(Spacing.xl == 24)
    }

    @Test("Espaciado: la escala es estrictamente creciente y no repite valores")
    func spacingIsAScale() {
        let scale = [Spacing.xs, Spacing.s, Spacing.m, Spacing.l, Spacing.xl]
        #expect(scale == scale.sorted())
        #expect(Set(scale).count == scale.count)
    }

    @Test("Disposición: margen 16, objetivo táctil 44 pt (AD-20), héroe 88")
    func layout() {
        #expect(LayoutMetrics.margin == 16)
        #expect(LayoutMetrics.touchTargetMin == 44)
        #expect(LayoutMetrics.heroSize == 88)
    }

    @Test("El margen es un peldaño de la escala: el borde de la pantalla y los huecos se leen alineados")
    func marginIsOnTheScale() {
        #expect(LayoutMetrics.margin == Spacing.l)
    }

    @Test("El objetivo táctil nunca baja de las 44 pt que AD-20 exige")
    func touchTargetMeetsAD20() {
        #expect(LayoutMetrics.touchTargetMin >= 44)
    }

    @Test("Radio de tarjeta: uno solo, 20 (decisión de Paul, 2026-09-18)")
    func radius() {
        #expect(Radius.card == 20)
    }

    @Test("Relleno de tarjeta: uno solo, 16 horizontal y 12 vertical")
    func surface() {
        #expect(Surface.cardPaddingHorizontal == 16)
        #expect(Surface.cardPaddingVertical == 12)
        // Alineado con el margen de pantalla a los lados; más apretado en vertical.
        #expect(Surface.cardPaddingHorizontal == LayoutMetrics.margin)
        #expect(Surface.cardPaddingVertical < Surface.cardPaddingHorizontal)
        // El fondo tintado de un aviso: el caso de contraste más apretado depende de él.
        #expect(Surface.noticeTintOpacity == 0.12)
    }

    // MARK: - Tipografía

    @Test("Tipografía: los dos roles que el sistema no nombra")
    func typography() {
        #expect(Typography.buttonLabel == Font.headline)
        #expect(Typography.metricValue == Font.system(.title, design: .rounded, weight: .bold))
    }

    // MARK: - Colores y contraste

    @Test("Los dos colorsets viajan dentro de la app", arguments: ["AccentColor", "EstimatedSteps"])
    func colorsetsShipWithTheApp(named: String) {
        // Un colorset renombrado o dejado fuera del catálogo no rompe el build: SwiftUI
        // pinta un color de relleno y nadie se entera hasta ver la pantalla.
        #expect(UIColor(named: named, in: .main, compatibleWith: nil) != nil)
    }

    @Test("El acento es el del catálogo, no el azul del sistema por omisión")
    func accentIsNotTheSystemDefault() {
        // Lo que este test protege es exactamente lo que denuncia la Intent: que el
        // acento no sea "el azul por omisión". Se compara contra `Color.blue` y NO contra
        // `Color.accentColor`: con `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` puesta,
        // `Color.accentColor` resuelve a ESTE mismo colorset, así que exigir que difieran
        // sería exigir que la key no funcione. Que resuelva o no fuera de una jerarquía de
        // vistas es comportamiento no documentado, y no se apoya un test en él.
        for style in [UIUserInterfaceStyle.light, .dark] {
            #expect(Self.components(of: Colors.accent, style) != Self.components(of: Color.blue, style))
        }
    }

    @Test("Acento: verde lima en oscuro, oliva oscuro en claro (decisión de Paul, 2026-09-18)")
    func accentValues() {
        #expect(Self.hex(Colors.accent, .light) == "4F7200")
        #expect(Self.hex(Colors.accent, .dark) == "CCFF00")
    }

    @Test("Estimado: naranja oscurecido en claro, naranja del sistema en oscuro")
    func estimatedValues() {
        #expect(Self.hex(Colors.estimated, .light) == "A34F00")
        #expect(Self.hex(Colors.estimated, .dark) == "FF9F0A")
    }

    @Test("El acento se lee como verde en los dos temas, nunca como el dorado de UX-DR1")
    func accentIsGreen() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let (r, g, b) = Self.components(of: Colors.accent, style)
            // Verde dominante y azul ausente: lima u oliva, no un dorado (que tendría
            // rojo por encima del verde) ni un amarillo (rojo ≈ verde).
            #expect(g > r, "el verde no domina en \(style)")
            #expect(g > b, "el verde no domina en \(style)")
        }
    }

    @Test("El acento y el color de estimado no se confunden entre sí en ningún tema")
    func accentAndEstimatedAreDistinguishable() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let accent = Self.components(of: Colors.accent, style)
            let estimated = Self.components(of: Colors.estimated, style)
            #expect(accent != estimated)
            // El acento es verde (g > r) y el estimado naranja (r > g): el eje que los
            // separa es el tono, no solo la luminancia, así que también se distinguen
            // con visión de color reducida.
            #expect(accent.g > accent.r, "el acento no es verde en \(style)")
            #expect(estimated.r > estimated.g, "el estimado no es naranja en \(style)")
        }
    }

    /// El contraste de cada color contra el fondo real sobre el que se pinta, en los dos
    /// temas. `epics.md:100` (UX-DR6) lo exige verificado, no supuesto; el hallazgo que
    /// abrió este chore fue precisamente un 2,20:1 vivo en producción.
    @Test(
        "Contraste ≥ 4,5:1 (WCAG AA) contra el fondo real, en claro y en oscuro",
        arguments: [
            // El acento pinta iconos y el tinte del botón de reanudar, sobre el fondo de
            // la pantalla: blanco en claro, negro en oscuro.
            ContrastCase("acento sobre el fondo de pantalla, claro", Colors.accent, .light, background: (255, 255, 255)),
            ContrastCase("acento sobre el fondo de pantalla, oscuro", Colors.accent, .dark, background: (0, 0, 0)),
            // Y sobre el gris agrupado, que es el fondo de una lista (historial 5.2, ajustes 2.3).
            ContrastCase("acento sobre el gris agrupado, claro", Colors.accent, .light, background: (242, 242, 247)),
            ContrastCase("acento sobre el gris agrupado, oscuro", Colors.accent, .dark, background: (28, 28, 30)),
            // Y sobre el cristal de la pre-pantalla de ubicación, que es donde el icono de
            // acento se pinta de verdad. Un material no se resuelve a componentes —no hay
            // API que lo devuelva—, así que se mide contra el BORDE DESFAVORABLE de lo que
            // `.regular` puede rendir sobre el fondo de la sesión: en claro el panel
            // esmerilado más oscuro (`#EFEFF4`), en oscuro el más levantado (`#2C2C2E`).
            // Si el sistema rinde algo intermedio, el ratio real es mejor que el medido.
            ContrastCase("acento sobre el cristal de la pre-pantalla, claro", Colors.accent, .light, background: (239, 239, 244)),
            ContrastCase("acento sobre el cristal de la pre-pantalla, oscuro", Colors.accent, .dark, background: (44, 44, 46)),
            // El "~" de la rejilla de métricas va sobre el fondo de pantalla pelado.
            ContrastCase("estimado sobre el fondo de pantalla, claro", Colors.estimated, .light, background: (255, 255, 255)),
            ContrastCase("estimado sobre el fondo de pantalla, oscuro", Colors.estimated, .dark, background: (0, 0, 0)),
            // Y el del aviso de estimados, sobre el fondo del propio aviso: el mismo
            // color al 12 % sobre el fondo de pantalla. Es el caso más apretado.
            ContrastCase("estimado sobre el fondo del aviso, claro", Colors.estimated, .light, background: (255, 255, 255), tintedAt: Surface.noticeTintOpacity),
            ContrastCase("estimado sobre el fondo del aviso, oscuro", Colors.estimated, .dark, background: (0, 0, 0), tintedAt: Surface.noticeTintOpacity),
        ]
    )
    func contrastMeetsAA(testCase: ContrastCase) {
        let foreground = Self.components(of: testCase.color, testCase.style)
        var background = testCase.background
        if let alpha = testCase.tintedAt {
            background = (
                alpha * foreground.r + (1 - alpha) * background.r,
                alpha * foreground.g + (1 - alpha) * background.g,
                alpha * foreground.b + (1 - alpha) * background.b
            )
        }
        let ratio = Self.contrastRatio(foreground, background)
        #expect(ratio >= 4.5, "\(testCase.name): \(String(format: "%.2f", ratio)):1")
    }

    /// El acento no solo pinta texto: es también **relleno**. El CTA "Iniciar caminata"
    /// (`.buttonStyle(.glassProminent)`, seis pantallas) y el botón de Reanudar
    /// (`Glass.regular.tint(Colors.accent)`) pintan una etiqueta ENCIMA del acento, y ahí
    /// el color que importa es el de la etiqueta, no el del acento sobre el fondo.
    ///
    /// El sistema elige esa etiqueta y no hay API que la devuelva resuelta, así que se
    /// mide el peor caso razonable —blanco y negro— y se deja escrito cuál gana:
    ///
    /// - **En claro la etiqueta debe ser BLANCA**: sobre el oliva `#4F7200` da 5,62:1,
    ///   mientras que la negra se queda en 3,73:1 e incumple AA.
    /// - **En oscuro la etiqueta debe ser NEGRA**: sobre el lima `#CCFF00` da 17,87:1;
    ///   una etiqueta blanca sobre el lima daría 1,18:1, que es ilegible.
    ///
    /// Si algún día una vista pinta esa etiqueta a mano, este test dice de qué color.
    @Test("Contraste ≥ 4,5:1 de la etiqueta sobre el relleno del acento, en claro y en oscuro")
    func accentFillLabelContrast() {
        let white: Components = (255, 255, 255)
        let black: Components = (0, 0, 0)

        let accentLight = Self.components(of: Colors.accent, .light)
        let whiteOnLight = Self.contrastRatio(white, accentLight)
        let blackOnLight = Self.contrastRatio(black, accentLight)
        #expect(whiteOnLight >= 4.5, "etiqueta blanca sobre el acento claro: \(String(format: "%.2f", whiteOnLight)):1")
        #expect(whiteOnLight > blackOnLight, "en claro la etiqueta que cumple es la blanca")

        let accentDark = Self.components(of: Colors.accent, .dark)
        let blackOnDark = Self.contrastRatio(black, accentDark)
        let whiteOnDark = Self.contrastRatio(white, accentDark)
        #expect(blackOnDark >= 4.5, "etiqueta negra sobre el acento oscuro: \(String(format: "%.2f", blackOnDark)):1")
        #expect(blackOnDark > whiteOnDark, "en oscuro la etiqueta que cumple es la negra")
    }

    /// Un color migrado sigue cumpliendo AA porque se eligió así, pero la prueba de que
    /// esta medición detecta un incumplimiento es que marque el color que lo incumplía:
    /// el `.orange` del sistema en claro, 2,20:1 sobre blanco.
    @Test("La medición detecta el incumplimiento que este chore arregla")
    func measurementCatchesTheRealFailure() {
        let systemOrangeLight = Self.components(of: Color.orange, .light)
        #expect(Self.contrastRatio(systemOrangeLight, (255, 255, 255)) < 4.5)
        // Y el color nuevo, en el mismo sitio, sí pasa.
        #expect(Self.contrastRatio(Self.components(of: Colors.estimated, .light), (255, 255, 255)) >= 4.5)
    }

    // MARK: - Utilidades

    struct ContrastCase: Sendable, CustomTestStringConvertible {
        let name: String
        let color: Color
        let style: UIUserInterfaceStyle
        let background: Components
        /// El color se pinta sobre su propio fondo tintado a esta opacidad.
        let tintedAt: Double?

        init(_ name: String, _ color: Color, _ style: UIUserInterfaceStyle, background: Components, tintedAt: Double? = nil) {
            self.name = name
            self.color = color
            self.style = style
            self.background = background
            self.tintedAt = tintedAt
        }

        var testDescription: String { name }
    }

    typealias Components = (r: Double, g: Double, b: Double)

    /// Las componentes sRGB (0–255) de un color resuelto en un tema concreto.
    private static func components(of color: Color, _ style: UIUserInterfaceStyle) -> Components {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // `getRed` devuelve `false` para un color que no se puede convertir a RGB (un
        // patrón, un espacio exótico) y deja las componentes a 0: sin esta afirmación se
        // estaría midiendo el contraste del negro y dando el verde por un color que no se
        // ha leído.
        let isRGB = resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(isRGB, "el color no se pudo convertir a sRGB y no se ha medido nada")
        // Y opaco: un colorset semitransparente pasaría esta medición y en pantalla se
        // mezclaría con lo que tenga debajo, con un contraste real menor que el medido.
        #expect(a == 1, "el color no es opaco (alpha \(a)): el contraste medido no es el de la pantalla")
        return (Double(r) * 255, Double(g) * 255, Double(b) * 255)
    }

    private static func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> String {
        let (r, g, b) = components(of: color, style)
        return String(format: "%02X%02X%02X", Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
    }

    /// Luminancia relativa de WCAG 2.1, sobre componentes sRGB de 0 a 255.
    private static func relativeLuminance(_ c: Components) -> Double {
        func channel(_ value: Double) -> Double {
            let v = value / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// Ratio de contraste de WCAG 2.1. AA pide ≥ 4,5:1 para texto normal.
    private static func contrastRatio(_ a: Components, _ b: Components) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
