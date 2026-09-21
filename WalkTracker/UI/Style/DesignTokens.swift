import SwiftUI

// Vocabulario visual compartido de la app. No es un tema ni una capa de apariencia:
// son constantes, como `UI/Format/` es formato. AD-13 ya decidió que la estética se
// hereda del SDK (Liquid Glass, estilos de texto del sistema, Dynamic Type); lo que
// faltaba era un sitio único donde vivan los pocos números y colores que la plataforma
// NO nombra por nosotros, para que las pantallas que faltan —anillo de meta (3.1),
// logros (3.3), historial (5.2), ajustes (2.3)— no vuelvan a inventarse cada una lo suyo.
//
// Fuentes:
// - `UX-DR3` (vigente entero, `DEROGACIONES.md §4`): escala 4/8/12/16/24, márgenes 16,
//   objetivos táctiles ≥ 44 pt, columna única.
// - `AD-13`: los colores del sistema se referencian, no se cablean; las superficies
//   propias usan las APIs de adopción. Los tres colorsets de aquí viven en
//   `Resources/Assets.xcassets/`, con variante clara y oscura, y son la única excepción
//   declarada a UX-DR1 (`DEROGACIONES.md §4`), que derogó los tokens Volt en hexadecimal.
// - `AD-20`: 44 pt es el mínimo verificable de un objetivo táctil, no una aspiración.
//
// Regla de admisión, y se aplica. Entra aquí un token cuando se cumple una de dos cosas:
//
//   1. **El ROL que nombra se usa en ≥ 2 sitios** —"radio de una tarjeta", "relleno de una
//      tarjeta", "etiqueta de un botón prominente"—, aunque el valor que hoy tiene lo
//      fijara una sola decisión y aunque antes se escribiera con números distintos. Lo que
//      se cuenta es el concepto repetido, no el literal: "radio de tarjeta" tenía tres usos
//      con dos valores (16 y 20), y por eso existe `Radius.card`, que vale 20 porque lo
//      decidió Paul el 2026-09-18.
//   2. **Es normativo**, aunque hoy tenga un solo uso: el 44 pt de AD-20 y el tamaño de
//      partida del héroe, que es lo que sobrevive de UX-DR2.
//
// Lo que NO entra: un valor que aparece una vez y no es normativo (`.padding(.top, 48)`,
// `spacing: 2`, `.system(.title3, …)`), y cualquier rol que el sistema ya nombre
// —`.secondary`, `.subheadline`, `controlSize(.extraLarge)`—: aliasarlo añade indirección
// y aleja del idioma de SwiftUI. `Scripts/check-project-shape.sh` (sección 12) impide
// volver a cablear en una vista lo que vive aquí.

/// Escala de espaciado de UX-DR3. No hay valores intermedios: si un hueco no es uno de
/// estos cinco, la pregunta es cuál de los cinco quería ser.
enum Spacing {

    /// 4 — separación dentro de un mismo elemento (una cifra y su etiqueta).
    static let xs: CGFloat = 4
    /// 8 — elementos hermanos muy relacionados (un icono y su texto).
    static let s: CGFloat = 8
    /// 12 — bloques dentro de una tarjeta, y el hueco entre dos botones lado a lado.
    static let m: CGFloat = 12
    /// 16 — entre secciones; coincide con el margen, y por eso se lee alineado.
    static let l: CGFloat = 16
    /// 24 — respiro mayor alrededor de la métrica principal y entre filas de la rejilla.
    static let xl: CGFloat = 24
}

/// Medidas de disposición. Las dos primeras son normativas (UX-DR3, AD-20); la tercera
/// es lo único que sobrevive de UX-DR2, y sobrevive como punto de partida de
/// `@ScaledMetric`, nunca como tamaño fijo.
///
/// Se llama `LayoutMetrics` y no `Layout` a propósito: `Layout` es el protocolo de
/// SwiftUI (el de `AnyLayout`, que estas mismas vistas usan), y un `enum Layout` a nivel
/// de módulo lo ensombrece — el día que una vista quiera `struct Foo: Layout` o
/// `some Layout`, el nombre estaría tomado.
enum LayoutMetrics {

    /// Margen lateral de una pantalla (UX-DR3). Es el mismo valor que `.padding()` da
    /// por omisión en iOS: escribirlo hace explícito lo que ya ocurría.
    static let margin: CGFloat = 16

    /// Lado mínimo de un objetivo táctil (UX-DR3, AD-20). Va en el marco de la
    /// **etiqueta** del botón, no en el botón: es donde el sistema mide el toque.
    static let touchTargetMin: CGFloat = 44

    /// Tamaño de partida de la métrica principal, en puntos. **Es el único tamaño
    /// tipográfico crudo del producto** —sobreviven otros puntos sin tokenizar, como el
    /// inset superior `.padding(.top, 48)` de las pantallas de permiso— y solo es legítimo
    /// dentro de un `@ScaledMetric(relativeTo:)`: la cifra domina, pero escala con
    /// Dynamic Type (AD-13).
    static let heroSize: CGFloat = 88
}

/// Radios de esquina. Uno solo: dos radios sin razón declarada eran una de las
/// incoherencias que este vocabulario existe para cerrar.
enum Radius {

    /// Esquina de toda superficie propia con relleno: tarjeta de clima, aviso de
    /// estimados, pre-pantalla de ubicación (decisión de Paul, 2026-09-18).
    static let card: CGFloat = 20
}

/// Relleno interior de una superficie propia. Uno solo, asimétrico: 16 a los lados para
/// alinear con el margen de pantalla, 12 arriba y abajo porque una tarjeta no necesita
/// tanto aire vertical como horizontal (decisión de Paul, 2026-09-18).
enum Surface {

    /// Relleno horizontal de una tarjeta.
    static let cardPaddingHorizontal: CGFloat = 16
    /// Relleno vertical de una tarjeta.
    static let cardPaddingVertical: CGFloat = 12

    /// Opacidad con la que un aviso se pinta del color de su propio contenido: el fondo
    /// del aviso de pasos estimados es `Colors.estimated` a este valor.
    ///
    /// Es un token porque **el contraste depende de él**: el caso más apretado de
    /// `DesignTokensTests` es el `~` del aviso sobre este fondo (4,81:1 en claro). Con el
    /// número escrito en la vista, subirlo a 0,18 dejaba al test midiendo 0,12 y en verde.
    /// Ahora la vista y el test leen el mismo sitio.
    static let noticeTintOpacity: Double = 0.12
}

/// Los dos únicos roles tipográficos que el sistema no nombra ya. Todo lo demás
/// —`.headline` de un encabezado, `.subheadline`, `.footnote`— se escribe con su nombre
/// de SwiftUI: aliasarlo no aporta nada.
enum Typography {

    /// Etiqueta de un botón **prominente**: el CTA de una pantalla y el que lo acompaña
    /// en un par de acciones (Iniciar caminata, Permitir, Reanudar/Pausar, Finalizar).
    /// `.headline` en ese sitio es una decisión repetida en seis pantallas, no el nombre
    /// de un rol: por eso tiene nombre aquí.
    ///
    /// **No es "la fuente de todos los botones".** Los secundarios no llevan fuente —
    /// heredan la del sistema— y "Descartar" usa `.subheadline.weight(.semibold)`, más
    /// pequeña a propósito: ponerle esto a todo botón aplanaría la jerarquía.
    static let buttonLabel: Font = .headline

    /// El valor de una métrica: redondeada y en negrita, escalando con Dynamic Type
    /// (`.title` como estilo base, nunca un tamaño de punto). Lo comparten la rejilla de
    /// la sesión y la temperatura de la tarjeta de clima.
    static let metricValue: Font = .system(.title, design: .rounded, weight: .bold)
}

/// Los tres colores que el producto decide. El resto de la paleta es del sistema y se
/// referencia por su nombre (`.primary`, `.secondary`, `.tint`, `.fill.quaternary`):
/// AD-13, y son roles cuyo contraste garantiza el sistema.
///
/// Los tres viven como colorset en `Resources/Assets.xcassets/`, con variante clara y
/// oscura, y su contraste está **medido** contra el fondo real sobre el que se pintan,
/// no supuesto. `DesignTokensTests` recalcula esos ratios en cada ejecución: si alguien
/// retoca un colorset y cae por debajo de 4,5:1, la suite lo dice.
///
/// **Ningún color cromático del sistema se nombra fuera de aquí.** La sección 12 del gate
/// lo impide en `WalkTracker/UI/`: un `.red`, un `.yellow` o un `.mint` escrito en una
/// vista es un color sin medir, y esa es exactamente la puerta por la que entró el
/// incumplimiento AA que este vocabulario existe para cerrar — dos veces.
enum Colors {

    /// Acento del producto: verde lima `#CCFF00` en oscuro —el espíritu Volt de UX-DR1,
    /// recuperado por decisión de Paul (2026-09-18)— y verde oliva oscuro `#4F7200` en
    /// claro. En claro NO se usa el `#CC9900` del UX-DR1 original: da 2,58:1, incumple
    /// AA y es un dorado que se confunde con el naranja de "estimado".
    ///
    /// Medido: **5,62:1** sobre blanco y 5,03:1 sobre el gris agrupado claro (`#F2F2F7`);
    /// **17,87:1** sobre negro y 14,48:1 sobre el gris agrupado oscuro (`#1C1C1E`).
    ///
    /// Es el mismo rol que `.tint`, y por eso el colorset se llama `AccentColor`: con
    /// `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` (en `project.yml`, y la sección 12
    /// del gate comprueba que sigue ahí) el sistema lo toma como acento de la app, y el
    /// chrome que tiñe solo —controles, barra de pestañas, `.tint` heredado— sale verde
    /// sin que nadie lo pida.
    ///
    /// **`.tint` y `Colors.accent` no son dos nombres arbitrarios del mismo rol**, y por
    /// eso conviven:
    /// - `.foregroundStyle(.tint)` es el acento **del entorno**: sigue el `.tint(…)` que
    ///   ponga un ancestro y, con la key de arriba, resuelve a este mismo colorset. Es lo
    ///   que usan los iconos de Inicio y de las dos pre-pantallas de permiso.
    /// - `Colors.accent` es el **color literal**, para las APIs que exigen un `Color` y no
    ///   aceptan un `ShapeStyle`: `Glass.tint(_:)` del botón de Reanudar es el caso, y es
    ///   también lo que permite medir su contraste en un test.
    ///
    /// Se nombra el colorset y **no** `Color.accentColor`: ese es un color del entorno y,
    /// fuera de una jerarquía de vistas, resuelve al azul del sistema. Verificado —
    /// `DesignTokensTests` lo pilló al escribirlo—, no supuesto.
    static let accent = Color("AccentColor")

    /// Lo estimado, nunca lo medido: el `~` del aviso de pasos estimados, su cifra en la
    /// rejilla y el fondo del propio aviso al 12 %.
    ///
    /// En claro es un naranja oscurecido, `#A34F00`: el `.orange` del sistema daba
    /// **2,20:1** sobre blanco e incumplía AA en producción. Medido ahora: **5,71:1**
    /// sobre blanco y **4,81:1** sobre el propio fondo del aviso (el mismo color al 12 %
    /// sobre blanco), que es el fondo real bajo el `~`. En oscuro se conserva el naranja
    /// del sistema, `#FF9F0A`: 10,22:1 sobre negro y 8,87:1 sobre el fondo del aviso.
    ///
    /// El 12 % de ese fondo es `Surface.noticeTintOpacity`, y lo leen tanto la vista como
    /// el test de contraste: el caso más apretado del vocabulario depende de ese número.
    static let estimated = Color("EstimatedSteps")

    /// **Un error**: algo que Paul pidió y no se hizo, y que solo él puede resolver. Hoy
    /// lo usa el mensaje de rechazo de Ajustes (campo vacío, no numérico, cero o negativo,
    /// desbordado); mañana, cualquier otro rechazo del mismo tipo.
    ///
    /// **Entra aquí por normativo, no por repetido** (segunda vía de la regla de admisión
    /// de la cabecera): hoy tiene un solo uso, y el 4,5:1 de WCAG AA para texto normal es
    /// una norma, no una preferencia. Con un uso y sin token, el color volvería a elegirse
    /// a ojo en la siguiente pantalla — que es literalmente lo que pasó: el chore de tokens
    /// sustituyó `.orange` por incumplir AA y la primera pantalla posterior eligió
    /// `Color.red`, que en claro da **3,55:1** sobre blanco y **3,18:1** sobre el gris
    /// agrupado. Lo que faltaba no era el color: era el **rol** medido.
    ///
    /// **Lo que NO es.** No es "el color de todo lo que avisa". El aviso de rango humano
    /// (*"guardada, aunque lo normal es entre 0,3 y 1,2 m"*) **no es un error** —se guardó—
    /// y se distingue por jerarquía (`.primary` / `.secondary`), que fue una decisión
    /// deliberada de la 2.3. Pintarlo de rojo diría que algo falló.
    ///
    /// **El valor no se inventa.** En claro es el rojo accesible que Apple publica para
    /// este uso, `#D70015`; en oscuro, el rojo del sistema, `#FF453A`, que ya cumple sobre
    /// los dos fondos y por eso no se toca. Medido contra los **dos fondos reales** sobre
    /// los que puede caer el mensaje —el de una lista agrupada y el de su fila—:
    /// **5,38:1** sobre blanco y **4,83:1** sobre el gris agrupado claro (`#F2F2F7`);
    /// **6,16:1** sobre negro y **4,99:1** sobre el gris agrupado oscuro (`#1C1C1E`).
    ///
    /// Y no se confunde con los otros dos cromáticos: su tono está a ≥ 30° del acento y
    /// del estimado en los dos temas, así que el eje que los separa es el **tono** y no
    /// solo la luminancia. `DesignTokensTests` lo mide, como mide todo lo de arriba.
    static let error = Color("ErrorMessage")
}
