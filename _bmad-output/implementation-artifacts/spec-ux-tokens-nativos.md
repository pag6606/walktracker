---
title: 'Tokens de estilo nativos: un vocabulario visual compartido para las pantallas que faltan'
type: 'chore'
created: '2026-09-18'
baseline_commit: 'ee17618015b427a8e1b244b80a6a31ff3ee3645f'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** el vocabulario visual no existe en ningún sitio compartido. Las 11 vistas repiten
literales a mano —`minHeight: 44` **13 veces en 7 ficheros**, el margen 16 con **tres sintaxis
distintas** en 9 sitios, `.foregroundStyle(.orange)` como "estimado" en 3, dos radios de tarjeta (16 y
20) sin razón declarada— y las cuatro superficies que faltan (anillo 3.1, logros 3.3, historial 5.2,
ajustes 2.3) volverían a inventarse cada una lo suyo. Es el hallazgo M-13 de la validación de mockups,
textual: *"no hay sistema de componentes"*. Peor: **el acento del producto no está elegido** (no existe
`AccentColor`, así que `.tint` sale azul del sistema por omisión, no por decisión) y **el contraste
nunca se recalculó contra colores del sistema** pese a que `epics.md:100` lo ordena — medido hoy, el
naranja de "pasos estimados" da **2,20:1 sobre blanco** e incumple WCAG AA en producción.

**Enfoque:** extraer a un fichero de tokens los literales que **ya se repiten**, siguiendo el patrón de
`UI/Format/` (enums sin estado, documentados, con tests); elegir el acento y el color semántico de
"estimado" como colorsets con contraste verificado en ambos temas; migrar las 11 vistas sin cambiar el
aspecto salvo lo decidido abajo; y añadir un check a `check-project-shape.sh` que impida volver a
cablear esos literales. No se inventa ningún token que hoy aparezca una sola vez.

## Boundaries & Constraints

**Always:**
- **Solo se tokeniza lo que ya se repite** (≥ 2 apariciones con el mismo significado) **o lo
  normativo** aunque aparezca una vez (el 44 pt, el tamaño del héroe).
- **El aspecto no cambia** salvo las cuatro decisiones de abajo. Migrar es sustituir un literal por el
  token de idéntico valor.
- **AD-13 manda:** Liquid Glass heredado; `.glassEffect`/`ConcentricRectangle` para superficies
  propias, nunca materiales a mano; estilos de texto del sistema y Dynamic Type, sin tamaños de punto
  fijos salvo el héroe con `@ScaledMetric`; prohibida `UIDesignRequiresCompatibility`.
- **UX-DR3 sigue vigente entero** y es la fuente directa de la escala: 4/8/12/16/24, márgenes 16,
  targets ≥ 44 pt, columna única.
- **Contraste verificado, no supuesto:** todo color nuevo o migrado se comprueba en claro y oscuro
  contra el fondo real sobre el que se pinta, y se registra el ratio en las notas.
- **AD-3/AD-10 intactos:** los tokens viven en `WalkTracker/UI/`, importan solo SwiftUI, y ninguna
  vista gana un import de framework de sistema. La migración no puede quitar una `.accessibilityLabel`.

**Decisiones de Paul (2026-09-18):**
- **Acento propio, verde lima**, recuperando el espíritu Volt derogado. Se define como colorset con
  dos variantes. La lima `#CCFF00` se conserva para **oscuro** (14,5:1). Para **claro** NO se usa el
  `#CC9900` del UX-DR1 original: da 2,58:1 —incumple AA— y es un dorado que colisiona con el naranja
  de "estimado". Se usa un verde oliva oscuro, inequívocamente verde, con ≥ 4,5:1 sobre blanco.
- **Radio de tarjeta unificado en 20.** El aviso de estimados y la tarjeta de clima pasan de 16 a 20.
- **Un solo relleno de tarjeta, 16 horizontal / 12 vertical.** El aviso de estimados crece ~8 pt de
  alto; la pre-pantalla de ubicación pasa de 16 uniforme a 16/12.
- **Se migran las 11 vistas ahora**, para poder activar el gate sobre todo el código.

**Never:**
- Rediseñar pantallas, mover elementos o tocar la copia.
- Reabrir la v4 de mockups, dibujar las tres piezas de AD-13 (anillo, tendencia, insignia) ni
  resucitar el resto de los tokens Volt.
- Crear un `Theme` inyectable o un sistema de apariencia configurable: son constantes, no una capa.
- Aliasar roles que el sistema ya nombra (`.secondary`, `controlSize`): añade indirección sin ganancia.
- Tocar `Domain/`, `Application/`, `Adapters/`, la extensión de Live Activity o `UI/Format/`.
- Migrar `UI/Diagnostics/NativeLayerDiagnosticsView.swift`: es `#if DEBUG` y está marcada para borrado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Acento en oscuro | `#CCFF00` sobre fondo oscuro del sistema | ≥ 4,5:1 (medido 14,5:1) | — |
| Acento en claro | oliva oscuro sobre blanco | ≥ 4,5:1; se lee como verde, no como dorado | si baja de 4,5:1, se oscurece más |
| "Estimado" en claro | hoy `.orange` sobre blanco | **debe subir de 2,20:1 a ≥ 4,5:1** con un naranja oscurecido | — |
| "Estimado" en oscuro | naranja del sistema sobre fondo oscuro | ≥ 4,5:1 (medido 8,3:1) | — |
| Acento y "estimado" juntos | aviso de estimados visible durante la sesión | se distinguen entre sí: verde vs naranja, en ambos temas | — |
| Dynamic Type al máximo | tamaño de accesibilidad XXXL | ningún texto recortado; targets ≥ 44 pt | — |
| Gate de literales | una vista escribe `minHeight: 44` a mano | `check-project-shape.sh` falla nombrando fichero y línea | — |
| Gate de hexadecimales | una vista escribe `Color(red:…)` o un hex | falla (AD-13: los colores se referencian) | — |

</frozen-after-approval>

## Code Map

**Inventario** (conteos reales; la base de cada token):

| Literal | Veces | Dónde (resumen) |
|---|---|---|
| `minHeight: 44` (+ un `minWidth: 44`) | **13** | 7 ficheros: `HomeView:55`, `LocationPermissionView:40,53`, `MotionPermissionView:29,36`, `MotionBlockedView:26,47`, `SessionView:215,259,266`, `SessionSummaryView:73`, `WeatherCard:54` |
| margen 16 en **tres sintaxis** | **9** | `.padding()` implícito (4), `.padding(.horizontal)` implícito (2), `.padding(.horizontal, 16)` (2), `.padding(16)` (1) |
| `spacing:` 4 / 8 / 12 / 16 / 24 | 2/6/7/4/3 | las 11 vistas; más `Spacer(minLength: 24)` ×6 |
| `.orange` como "estimado" | **3** | `SessionView:199` (el `~`), `:392` (`~236`), `:228` (fondo `.opacity(0.12)`) |
| `.tint` vs `.accentColor` — **mismo rol, dos nombres** | 3 + 1 | `HomeView:48`, `LocationPermissionView:23`, `MotionPermissionView:60` · `SessionView:261` |
| `.rect(cornerRadius: 16)` / `20` | 2 / 1 | `SessionView:228`, `WeatherCard:41` / `LocationPermissionView:60` |
| `.headline` (etiqueta de botón) | 9 | 6 ficheros |
| `.system(.title, design:.rounded, weight:.bold)` (valor de métrica) | 2 | `SessionView:386`, `WeatherCard:71` |
| `@ScaledMetric … = 88` (héroe) | 1 | `SessionView:301` — **único pt crudo; es lo que sobrevive de UX-DR2** |
| `minimumScaleFactor` 0.3 / 0.4 / 0.5 | 1 c/u | `SessionView:401` / `:310` / `:406` — **incoherencia a reconciliar, no a tokenizar** |

- `WalkTracker/UI/Format/MetricsFormat.swift` — **el molde**: `enum` sin casos, `static`, cabecera que
  cita su AD, doc comment por miembro con el porqué, un test por fichero. Varios enums en un fichero
  cuando comparten tema. El de tokens es su hermano, no una capa.
- `WalkTracker/UI/Session/SessionView.swift` (414) — mayor consumidor: aviso de estimados `:195-228`,
  controles `:251-266`, `DistanceHero` `:300-318` (**no tocar su mecánica de `@ScaledMetric`**),
  `MetricCell` `:383-404`.
- `WalkTracker/UI/Session/WeatherCard.swift` (214), `Session/SessionSummaryView.swift`,
  `Permission/{Location,Motion,MotionBlocked}*.swift`, `Home/HomeView.swift`, `UI/RootView.swift` — el resto.
- `WalkTracker/Resources/Assets.xcassets/` — solo tiene `AppIcon`. Aquí van los dos colorsets.
- `Scripts/check-project-shape.sh` — secciones 7–11 son el patrón; la 10 ya acota `WalkTracker/UI/`.
  ⚠️ **Trampa:** su regex `UI(Application|Device|Screen|ViewController|View)\b` corre sobre el código
  entero, comentarios y literales incluidos. Ningún token ni doc comment puede contener esos nombres.
- `Scripts/check-project-shape-tests.sh` — todo check nuevo llega con casos positivos y negativos (A-6).
- `project.yml` — `sources: WalkTracker` por carpeta: el fichero nuevo entra **solo al regenerar con
  `xcodegen generate`**; sin regenerar se ignora en silencio y la sección 3 del gate lo caza.
- **No hay target de UI tests** (A-4 abierto, `sprint-status.yaml:140`). Lo verificable de este chore es
  la **ausencia** (gate), el **valor** (tests sobre el enum, como `MetricsFormatTests` prueba
  `PaceFormat.absent`) y la **compilación**. La equivalencia visual es manual, y así se declara.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Resources/Assets.xcassets/AccentColor.colorset` — crear el acento lima con variante
      clara (oliva oscuro ≥ 4,5:1) y oscura (`#CCFF00`). Registrar ambos ratios.
- [x] `WalkTracker/Resources/Assets.xcassets/EstimatedSteps.colorset` — el naranja semántico con
      variante clara oscurecida (≥ 4,5:1, hoy 2,20:1) y oscura. **Arregla un incumplimiento AA vivo.**
- [x] `WalkTracker/UI/Style/DesignTokens.swift` — `enum Spacing` (4/8/12/16/24), `enum LayoutMetrics`
      (`margin` 16, `touchTargetMin` 44, `heroSize` 88), `enum Radius` (`card` 20), `enum Surface`
      (relleno de tarjeta 16/12 y la opacidad del fondo de un aviso), y los alias de color
      `accent`/`estimated`. Cabecera citando UX-DR3 vigente, AD-13 y `DEROGACIONES.md §4`. Máximo
      tres roles tipográficos, solo los que cubren ≥ 2 usos. **Se llama `LayoutMetrics` y no
      `Layout`**: `Layout` es el protocolo de SwiftUI y un `enum` así a nivel de módulo lo ensombrece.
- [x] `WalkTracker/UI/Session/SessionView.swift` — migrar; radio 16→20; relleno 16/8→16/12; `.orange`
      → token; **reconciliar los tres `minimumScaleFactor`** a un criterio escrito.
- [x] `WalkTracker/UI/Session/WeatherCard.swift`, `Session/SessionSummaryView.swift` — migrar; radio 16→20.
- [x] `WalkTracker/UI/Permission/*.swift`, `Home/HomeView.swift`, `RootView.swift` — migrar;
      **unificar `.accentColor` → `.tint`** para que el rol tenga un solo nombre. Hecho **en parte y
      con una razón**: `.accentColor` ha desaparecido y los tres iconos usan `.foregroundStyle(.tint)`,
      pero `Glass.tint(_:)` exige un `Color` y ahí queda `Colors.accent`. No son dos nombres del mismo
      rol: `.tint` es el acento **del entorno** y `Colors.accent` el **color literal**. Ver las notas.
- [x] `Scripts/check-project-shape.sh` — sección 12: en `WalkTracker/UI/` (excluyendo `Diagnostics/` y
      **el fichero** `Style/DesignTokens.swift`, no la carpeta), prohibir un lado de marco numérico en
      cualquiera de sus formas (`min|max|ideal`, `height`/`width`), `cornerRadius` con número crudo con
      los dos modificadores (`cornerRadius:` y `.cornerRadius(…)`), hexadecimales (también con `_`),
      `Color(red:…)` y `Color.init(red:…)`, `.orange` —el color que los tokens sustituyen— y los cinco
      peldaños de la escala reteclados en `spacing:`, `minLength:` o `.padding(…)`, dejando pasar lo que
      la spec decide no tokenizar. Y `UIDesignRequiresCompatibility` en los `Info.plist` **derivados del
      manifiesto** (AD-13), más `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` en
      `project.yml`, sin la cual el acento vuelve al azul del sistema sin que falle nada.
- [x] `Scripts/check-project-shape-tests.sh` — casos positivos y negativos del check nuevo.
- [x] `WalkTrackerTests/UI/DesignTokensTests.swift` — fijar los valores que heredarán 3.1/3.3/5.2/2.3.
- [x] `_bmad-output/implementation-artifacts/epic-1-context.md` y `epic-2-context.md` — apuntar sus
      secciones `UX & Interaction Patterns` al fichero de tokens como fuente en código.
- [x] `README.md` — una línea: dónde vive el vocabulario visual.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` — registrar los tres hallazgos que este
      chore encuentra y **no** arregla (ver Design Notes).

**Acceptance Criteria:**
- Dado el árbol migrado, cuando se ejecuta `check-project-shape.sh`, entonces pasa; y si se
  reintroduce a mano un `minHeight: 44` o un hex en una vista, falla nombrando fichero y línea.
- Dado el acento nuevo, cuando se abre cualquier pantalla en claro y en oscuro, entonces el elemento
  con `.tint` se ve verde lima (oscuro) u oliva (claro), nunca azul, y nunca se confunde con el
  naranja de "estimado".
- Dada la sesión con pasos estimados en tema claro, cuando se mide el contraste del `~` y su cifra,
  entonces es ≥ 4,5:1 (hoy 2,20:1).
- Dado el fichero de tokens, cuando la 3.1 escriba el anillo de meta, entonces toma espaciado, radio,
  margen y target del mismo sitio sin decidir nada nuevo.

## Implementation Notes

**Los dos colorsets, con los ratios medidos** (WCAG 2.1, calculados y además recalculados por
`DesignTokensTests` en cada ejecución de la suite):

| Colorset | Claro | Oscuro |
|---|---|---|
| `AccentColor` | `#4F7200` oliva oscuro — **5,62:1** sobre blanco, 5,03:1 sobre `#F2F2F7` | `#CCFF00` lima — **17,87:1** sobre negro, 14,48:1 sobre `#1C1C1E` |
| `EstimatedSteps` | `#A34F00` — **5,71:1** sobre blanco y **4,81:1** sobre el fondo del propio aviso (el mismo color al 12 %) | `#FF9F0A` (el naranja del sistema) — 10,22:1 sobre negro, 8,87:1 sobre el fondo del aviso |

El `.orange` del sistema en claro se midió antes de tocarlo y dio exactamente los **2,20:1** que la
Intent denunciaba, y **2,00:1** sobre el fondo del aviso, que es donde de verdad se lee el `~`. Ese
segundo fondo es el que fijó el valor: `#B35A00`, más saturado y con 4,81:1 sobre blanco, caía a
4,10:1 sobre el aviso. Se eligió `#A34F00` porque cumple AA **en los dos fondos**, no solo en el
fácil. Para el acento en claro se descartó el `#CC9900` de UX-DR1 como ordena la Intent (2,58:1) y
se buscó un oliva con margen sobre 4,5:1 en blanco **y** en el gris agrupado, que será el fondo del
historial (5.2) y de ajustes (2.3).

**`Colors.accent` nombra el colorset, no `Color.accentColor`, y eso lo descubrió un test.** La
primera versión definía `accent = Color.accentColor`, que parecía lo idiomático. El test de valores
falló: `Color.accentColor` es un color del **entorno** y, fuera de una jerarquía de vistas, resuelve
al azul del sistema (`#0088FF`). Habría bastado para pintar en pantalla, pero no es verificable, y
el criterio de la Intent es contraste medido, no supuesto. Ahora el token nombra el colorset y el
test compara contra el azul para que la regresión no pueda volver en silencio. `project.yml` gana
además `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`: sin esa clave el colorset
existiría y el chrome que el sistema tiñe solo —controles, barra de pestañas— seguiría azul **por
omisión, no por decisión**, que es justo lo que la Intent señala.

**`.accentColor` → `.tint`, salvo donde el tipo no lo admite.** La tarea pedía unificar los dos
nombres del rol en `.tint`. La primera versión hizo lo contrario —llevarlo todo a `Colors.accent`—
porque `Glass.tint(_:)` (`SessionView`, el botón de Reanudar) pide un `Color` y `.tint` es un
`ShapeStyle`. La revisión lo corrigió: un `Color` fijo en un icono **le quita la capacidad de seguir
el `.tint(…)` de un ancestro**, y con
`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor` puesta, `.tint` ya resuelve al colorset
del acento. Así que los tres iconos (`HomeView`, `LocationPermissionView`, `MotionPermissionView`)
usan `.foregroundStyle(.tint)` y `Colors.accent` queda **solo** donde hace falta un `Color` de verdad:
`Glass.tint(_:)`.

No son dos nombres arbitrarios del mismo rol, y el token lo documenta: **`.tint` es el acento del
entorno** (lo hereda, lo puede cambiar un ancestro) y **`Colors.accent` el color literal** para las
APIs que exigen un `Color` — que es además lo que permite medir su contraste en un test.
`.accentColor` ha desaparecido de las vistas, que era el objetivo del inventario.

**Criterio único de `minimumScaleFactor`** (escrito en la cabecera de `SessionView.swift`): **un
texto puede encogerse hasta la mitad de su tamaño, nunca más.** Los tres sitios pasan a `0.5`. Los
dos que cambian venían de 0,4 y 0,3, que en el tamaño por omisión permitían caer a 35 pt y a 8 pt
respectivamente: el segundo es ilegible y contradice Dynamic Type. Medio tamaño cubre con holgura el
peor caso real (la cifra de una celda de la rejilla a tamaño de accesibilidad máximo, que necesita
~0,85), así que en la práctica solo se mueve el suelo, no lo que se ve. No se tokeniza: el Code Map
lo pide reconciliado, no convertido en token, y los tres usos viven en el mismo fichero.

**Qué NO se tokenizó, y por qué.** `spacing: 2` (dos usos: `SessionView` y `WeatherCard`, el hueco
entre una cifra y su pie dentro de un mismo bloque) y `spacing: 0` se quedan como literales: 2 no es
un peldaño de UX-DR3, y añadirlo inventaría una escala que la fuente no tiene. `.padding(.top)` sin
argumento (2 usos) tampoco entra: es un inset superior, no el margen lateral, y el inventario de la
spec no lo cuenta entre los 9 sitios del margen 16. `.padding(.top, 48)` de `PermissionScreen`,
`.system(.title3, …)` del desglose estimado y los tres `minimumScaleFactor` aparecen una sola vez
con su significado. `.secondary` (19 usos), `.subheadline`, `.footnote` y `controlSize(.extraLarge)`
(7) son roles que el sistema ya nombra y no se aliasan, como manda la Intent.

Esta lista es la que **calibra la regla de espaciado del gate**: prohíbe exactamente los cinco
peldaños de UX-DR3 —4, 8, 12, 16, 24— escritos a mano, y no todo número, para que `spacing: 0`,
`spacing: 2` y `.padding(.top, 48)` sigan pasando. Hay caso verde de cada uno: si alguno fallara, la
regla estaría criminalizando lo que esta sección decide a propósito no tokenizar.

**Sí se tokenizó el 0,12 del fondo del aviso** (`Surface.noticeTintOpacity`), que la primera versión
dejó escrito en la vista. No es un número más: es del que depende el caso de contraste más apretado
del vocabulario (4,81:1). Con el literal repartido entre la vista y el test, subirlo a 0,18 en la
vista dejaba al test midiendo 0,12 y en verde. Ahora los dos leen el mismo sitio.

**`RootView.swift` no tenía nada que migrar.** Es `TabView` + `fullScreenCover` + el puente de
`scenePhase`: ni un espaciado, ni un color, ni un marco. Aparece en la lista de vistas migradas por
completitud del barrido, y se deja constancia aquí para que no parezca un olvido.

**El gate (sección 12) exime `Style/DesignTokens.swift` y `Diagnostics/`.** El fichero, no la
carpeta: la primera versión eximía `Style/` entera, y eso era otra puerta —un
`Style/AchievementBadge.swift` con un hexadecimal y un `minHeight: 44` habría pasado—. Hay caso rojo
de las dos direcciones: mover `DesignTokens.swift` fuera de `Style/` falla, y un fichero nuevo dentro
de `Style/` también; `Diagnostics/` porque es `#if DEBUG` y está marcada para borrado. Detalles que
costaron una vuelta: el escaneo usa `code_lines`, que **quita los comentarios pero conserva los
literales de cadena**, así que un doc comment puede citar `#CCFF00` o las 44 pt para explicarse
(hay caso verde que lo fija) mientras que un color escrito dentro de una cadena sigue contando como
cableado (hay caso rojo). Y el check del `Info.plist` busca la **key**
`<key>UIDesignRequiresCompatibility</key>`, no el nombre suelto: el `Info.plist` real la cita en un
comentario precisamente para decir que está prohibida, y ese comentario no puede ser la violación.

**Cambios de aspecto, exactamente los cuatro decididos.** El acento (azul del sistema → lima/oliva);
el radio de tarjeta 16 → 20 en el aviso de estimados y en la tarjeta de clima (la pre-pantalla de
ubicación ya era 20); el relleno del aviso de estimados 16/8 → 16/12, que lo hace ~8 pt más alto; y
la pre-pantalla de ubicación de 16 uniforme a 16/12. Más el color de "estimado", que cambia porque
incumplía AA. Todo lo demás es un literal sustituido por un token del mismo valor, incluidos
`.padding()` y `.padding(.horizontal)` implícitos, que en iOS ya valían 16 y ahora lo dicen.

Con una salvedad que conviene decir en voz alta: la reconciliación de `minimumScaleFactor` a 0,5 es
un **quinto cambio visible**, aunque solo se note a tamaños de accesibilidad grandes, y **no lo
cubre ningún test** —verificarlo exige renderizar una vista y no hay target de UI tests—. Queda
registrado en `deferred-work.md`, no dado por bueno.

**Verificación ejecutada** (2026-09-18, tras la revisión): `check-project-shape.sh` verde con la
sección 12 · `check-project-shape-tests.sh` **139/139**; la suite venía de **81** casos, así que el
chore añade **58** —16 en la primera pasada y 42 en la de la revisión—, no los 36 que decía la
primera versión de esta nota (36 era el total de la suite *antes* del A-6, no los casos nuevos) ·
`verify-domain.sh` verde · `xcodegen generate && xcodebuild test` (iPhone 16e) **461 tests, TEST
SUCCEEDED**, sin warnings propios · `git diff --stat Domain/ WalkTracker/Application/
WalkTracker/Adapters/` **vacío**.

Cada regla nueva o ampliada del gate se comprobó además **por mutación** sobre el árbol real:
escribir el literal prohibido en un fichero bajo `WalkTracker/UI/`, ver el gate fallar nombrando
fichero y línea, y borrarlo.

**Lo que queda por hacer a mano, y no lo cubre nada automático.** La equivalencia visual en el
simulador, en claro y en oscuro, de las once vistas; la lectura del `~` en la sesión con estimados;
y Dynamic Type al máximo en la pantalla de sesión. No hay target de UI tests (A-4 abierto), así que
esto se declara pendiente, no cumplido.

**Auditoría de la matriz: una fila sin test automático.** Siete de las ocho filas de la matriz están
cubiertas por tests que se ejecutan en la suite: las cinco de color por `contrastMeetsAA`,
`accentAndEstimatedAreDistinguishable` y el control negativo `measurementCatchesTheRealFailure`
(que prueba que la medición detecta el 2,20:1 que este chore arregla), y las dos del gate por los
casos de camino rojo de `check-project-shape-tests.sh`. La fila **"Dynamic Type al máximo"** no tiene
—ni puede tener hoy— test automático: exige renderizar una vista, y no hay target de UI tests (A-4
abierto, `sprint-status.yaml:140`). Queda como check manual declarado en Verification, no como
cobertura que no existe.

## Spec Change Log

**2026-09-18 · Tras las tres lentes de revisión sobre el diff.** El tema de fondo de los hallazgos:
*el gate prometía más de lo que comprobaba*, y varias evasiones estaban verificadas ejecutándolo.
Lo que cambió, sin tocar el bloque congelado:

- **Gate (sección 12).** Ampliadas cuatro reglas que se esquivaban: el objetivo táctil ahora cubre
  `(min|max|ideal)?(height|width): N` —`.frame(height: 44)` y `.frame(width: 44, height: 44)` pasaban—;
  el radio cubre el modificador antiguo `.cornerRadius(16)`; el hexadecimal admite separadores
  (`0xCC_FF_00`); y el color por componentes admite `Color.init(red:…)`. **Dos reglas nuevas:**
  `.orange` prohibido en las vistas —devolverlo dejaba el gate en verde y **reintroducía en silencio
  el incumplimiento WCAG AA que este chore arregla**— y los cinco peldaños de la escala reteclados en
  `spacing:`, `minLength:` o `.padding(…)`, que el script, el README y los dos `epic-N-context.md` ya
  anunciaban y nadie comprobaba. **Una tercera:** `project.yml` debe conservar
  `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor`; borrarla devolvía todo el chrome al
  azul del sistema sin que fallara nada — el defecto exacto que la Intent denuncia.
- **Gate, higiene.** La exención de `Style/` era una puerta abierta a cualquier fichero de la carpeta:
  ahora exime solo `Style/DesignTokens.swift`. Si `WalkTracker/UI/` no existe, el gate falla en vez de
  saltarse la sección en silencio. Los `Info.plist` se derivan de `INFOPLIST_FILE` del manifiesto (con
  respaldo), así que un target nuevo se comprueba solo. Y la sección ya no pisa el `SCANNED` global de
  las secciones 7–11: escanea en su propia variable (`scan_code_into`).
- **Camino rojo.** La suite pasa de 97 a **139 casos**: rojo y verde de cada regla nueva y de cada
  ampliación, incluidos los verdes que fijan lo que NO se prohíbe.
- **Tests de tokens.** Añadido el caso que faltaba y que es el más visible del producto: **la etiqueta
  sobre el relleno del acento** (el CTA `.glassProminent` y el Reanudar tintado), con el peor caso
  razonable medido y escrito cuál gana —blanca en claro, negra en oscuro; una etiqueta blanca sobre el
  lima daría 1,18:1—. Añadido el contraste del acento sobre el **cristal** de la pre-pantalla de
  ubicación. `components(of:)` ahora afirma que `getRed` devolvió `true` y que el color es opaco: sin
  eso se medía el contraste del negro. Y se quita la comparación contra `Color.accentColor`, que
  **contradecía** el comentario de `project.yml` y solo pasaba por un comportamiento no documentado;
  queda la que de verdad protege, contra `Color.blue`.
- **Código.** Los tres iconos vuelven a `.foregroundStyle(.tint)` (un `Color` fijo les quitaba la
  capacidad de seguir el `.tint` de un ancestro). El 0,12 del fondo del aviso pasa a ser token. `enum
  Layout` se renombra a `LayoutMetrics`: ensombrecía el protocolo `SwiftUI.Layout` a nivel de módulo.
- **Documentación.** `DEROGACIONES.md §4` gana la **excepción declarada** a UX-DR1 —sin ella, la
  fuente de verdad seguía diciendo que cablear estos colores estaba derogado, y el próximo que leyera
  la arquitectura revertiría esto—. El README, la cabecera del script y los dos `epic-N-context.md`
  se alinean con lo que el gate comprueba de verdad, ni más ni menos, y el README nombra la sección.
  Corregidos tres textos falsos o ambiguos del fichero de tokens: `heroSize` no es "el único punto
  crudo del producto" sino el único tamaño tipográfico crudo; `Typography.buttonLabel` es la etiqueta
  de un botón **prominente**, no de todo botón; y la regla de admisión se redacta sobre el **rol
  repetido**, no sobre el literal repetido, que era lo que se prestaba a leer que `Radius.card` la
  incumplía.
- **Diferidos nuevos** (`deferred-work.md`): la extensión de Live Activity queda fuera de todo esto y
  se volverá azul mientras la app es lima; la verificación de `minimumScaleFactor(0.5)` a tamaño de
  accesibilidad máximo, que es un quinto cambio visible sin test; y el límite conocido del gate con un
  color partido en varias líneas. La entrada duplicada sobre la deuda de imports se anota en la que ya
  existía.

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap). El tema de fondo, en las tres lentes:
**el gate prometía mucho más de lo que comprobaba**, y las evasiones se verificaron ejecutando el gate,
no deduciéndolas.

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH/VG/EC · El script, el README y los dos `epic-N-context.md` anuncian que el espaciado y el margen viven en `Style/`, pero **ninguna regla mira `spacing:` ni `padding(`** | high | Verificado: `VStack(spacing: 16)` y `.padding(16)` dejaban el gate en verde. Es la categoría más numerosa del inventario (9 sitios de margen + ~22 de espaciado) | patch (regla que prohíbe los cinco valores que **sí** son tokens, dejando pasar `0`, `2` y el 48) |
| 2 | VG/EC/BH · `.frame(height: 44)` esquiva la regla, que solo mira `min(Height\|Width)` | high | Verificado en un fichero temporal: exit 0. Es la forma habitual de un target cuadrado | patch (`(min\|max\|ideal)?(Height\|Width)`) |
| 3 | VG · Volver a `.orange` en una vista deja el gate en verde: **el incumplimiento AA que este chore arregla puede reintroducirse en silencio** | high | Verificado. Ninguna de las cuatro reglas miraba colores del sistema | patch (regla 12 nueva) |
| 4 | VG · Borrar `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` devuelve el chrome al azul y **no falla nada** | high | Verificado: colorset intacto, tests en verde, gate en verde. Es literalmente el defecto que la Intent denuncia | patch (regla 12c) |
| 5 | BH · Ningún caso de contraste mide **texto sobre el relleno del acento** — el CTA "Iniciar caminata" con `.glassProminent`, el uso más visible del color nuevo | high | Real: los 8 casos medían el acento como primer plano. Una etiqueta blanca sobre el lima daría 1,18:1 | patch (`accentFillLabelContrast`, que además deja escrito qué etiqueta gana en cada tema) |
| 6 | BH · El 0,12 del fondo del aviso es el número del que depende el caso de contraste más apretado (4,81:1) y **no es un token**: vista, test y prosa por separado | medium | Real: cambiar la vista a 0,18 dejaba el test midiendo 0,12 y en verde | patch (`Surface.noticeTintOpacity`) |
| 7 | BH · `DEROGACIONES.md §4` no se amendó: el código declara una excepción a UX-DR1 que **en la fuente de verdad no existe** | medium | Real, y §4 sigue diciendo que se derogó porque "cablear hexadecimales pelea con el SDK". El próximo que lea la arquitectura revierte los colorsets | patch |
| 8 | BH/EC · `project.yml` afirma que la clave hace resolver `Color.accentColor` al lima; el test afirma `accent != Color.accentColor`. **Las dos no pueden ser ciertas** | medium | Real, y el test solo pasaba por un comportamiento no documentado del SDK (resolver fuera de una jerarquía de vistas) | patch (se conserva la comparación contra `Color.blue`, que es la que protege; comentario corregido) |
| 9 | EC/VG · Los tres `.foregroundStyle(.tint)` migrados a color fijo **pierden el tinte del entorno** | medium | Real; hoy sin defecto visible porque nadie aplica un `.tint(...)` ancestro. Y con la clave global puesta, `.tint` ya resuelve al lima | patch (se revierten; `Colors.accent` queda solo donde hace falta un `Color`) |
| 10 | BH/EC · La exención de `UI/Style/` es una carpeta entera: `Style/AchievementBadge.swift` con hex y `minHeight: 44` pasaría | medium | Real; había caso rojo para sacar el fichero, ninguno para meter una vista | patch (se exime el fichero, no la carpeta) |
| 11 | EC · `enum Layout` ensombrece el protocolo `SwiftUI.Layout` a nivel de módulo | medium | Real: el día que una vista quiera `struct Foo: Layout` o `some Layout`, el nombre está tomado. Los otros cuatro enums no chocan | patch (`LayoutMetrics`) |
| 12 | EC · `components(of:)` ignora si `getRed` falló y descarta el alfa | medium | Real: un color no convertible se mediría como negro, y un colorset semitransparente pasaría AA en el test y fallaría en pantalla | patch |
| 13 | EC · `.cornerRadius(16)`, `0xCC_FF_00` y `Color.init(red:)` esquivan sus reglas | medium | Verificado | patch |
| 14 | EC · Si `WalkTracker/UI` no existe, la sección se salta **en silencio**; y la lista de `Info.plist` es fija | medium | Real: el gate quedaría verde por no haber mirado. Un target nuevo con plist propio no se comprobaba | patch (error explícito; plists derivados de `project.yml`) |
| 15 | BH/EC · `ui_token_rule` no declara `local`, y la sección 12 **pisa el `SCANNED` global** de las secciones 7–11 | medium | Real; hoy inocuo solo porque la 12 es la última. Una sección 13 heredaría un escaneo reducido a `UI/` | patch (`scan_code_into`) |
| 16 | BH · El conteo de casos nuevos del gate estaba inflado: se dijo 36 | medium | Verificado: la suite iba de **81 a 97**, son **+16**. (Tras esta pasada, 139) | patch (corregido en la spec y ante Paul) |
| 17 | BH · `heroSize` se documenta como "el único punto crudo del producto" y es falso | low | Real: sobreviven `.padding(.top, 48)` y `spacing: 2`/`0`, listados en la propia spec como no tokenizados | patch ("el único tamaño tipográfico crudo") |
| 18 | BH · `Typography.buttonLabel` se documenta para un rol más ancho del que cubre | low | Real: "Descartar" usa `.subheadline.weight(.semibold)` y los secundarios no llevan fuente. La 3.1 pondría `.headline` a todos | patch (se documenta como botón **prominente**) |
| 19 | BH · El README numera el check como 6 y todo lo demás como "sección 12" | low | Real; el README es la puerta de entrada de quien no ha abierto el script | patch |
| 20 | BH · La desviación de la tarea `.accentColor → .tint` queda `[x]` como se escribió, y el Spec Change Log está vacío | low | Real; la explicación vivía solo en Implementation Notes | patch |
| 21 | BH · La entrada nueva de `deferred-work.md` sobre la deuda de imports **duplica** la de `:48` | low | Real | patch (anotada en la existente) |
| 22 | BH/EC/VG · La extensión de Live Activity queda fuera de todo: cablea `spacing: 16`/`2`/`.padding()`, no la escanea la sección 12, solo depende de `Shared` —no puede importar los tokens— y no tiene la clave del acento | medium | Real: la app se vuelve lima y su Live Activity se queda azul | defer (entrada en `deferred-work.md`) |
| 23 | VG/EC/BH · Subir `minimumScaleFactor` a 0,5 con `lineLimit(1)` puede truncar la cifra del héroe o de una celda a tamaño de accesibilidad máximo, y **nada lo cubre** | medium | Real, y además es un **quinto cambio visible** que la spec no declaró (Paul aprobó cuatro). Cerrarlo exige renderizar una vista: no hay target de UI tests (A-4 abierto) | defer (registrado como cambio visible sin test) |
| 24 | EC · Un color partido en varias líneas (`Color(` y `red: 0.8` en la siguiente) esquiva el gate | low | Real e inherente a un gate que trabaja línea a línea | defer (límite conocido, anotado) |
| 25 | EC · `Radius.card` (20) y `Surface.cardPaddingVertical` (12) incumplirían la regla de admisión "solo lo que ya se repite" | false | El **rol** "radio de tarjeta" tenía 3 usos; el valor lo fijó una decisión de Paul, no una aparición. La regla hablaba del literal y se prestaba a esta lectura | patch (regla reescrita sobre el rol repetido) |

## Design Notes

**Por qué tokens y no un tema.** AD-13 ya decidió que la estética se hereda del sistema. Falta
vocabulario compartido, no una capa de apariencia: un `enum` con `static let`, como `DistanceFormat`.
Un `Theme` inyectable sería una capa que nadie pidió y que el gate no podría comprobar.

**Por qué el gate es la mitad del valor.** Sin target de UI tests, nada impide que la 3.1 cablee
`minHeight: 44` a mano y el vocabulario se erosione en la primera historia que lo use. El check es lo
único que mantiene esto cierto dentro de tres historias — el mismo razonamiento del A-6.

**Qué NO se aliasa.** `.secondary` aparece 19 veces y ya es un rol semántico del sistema: envolverlo
añade indirección y aleja del idioma de SwiftUI. Igual con `controlSize(.extraLarge)` (7 usos).

**Tres hallazgos que este chore declara y no arregla** (van a `deferred-work.md`):
1. **Tres mecanismos distintos para superficies propias** — `glassEffect` (el correcto según AD-13),
   `.background(.fill.quaternary)` y `.background(.orange.opacity())` — y **ninguno usa
   `ConcentricRectangle`**, que AD-13 nombra explícitamente. Unificarlos es un cambio de aspecto real,
   fuera de este alcance.
2. **Reduce Motion solo lo lee `SessionView`.** `HomeView`, `SessionSummaryView`, `PermissionScreen` y
   `WeatherCard` no lo consultan; hoy no animan, pero nada lo garantiza.
3. La deuda ya registrada del propio gate (`deferred-work.md:48`): la sección 4 no reconoce imports con
   atributo o nivel de acceso.

## Verification

**Commands:**
- `bash Scripts/check-project-shape.sh` — verde, con la sección 12 nueva.
- `bash Scripts/check-project-shape-tests.sh` — verde, incluidos los casos del check nuevo.
- `bash Scripts/verify-domain.sh` — verde y sin cambios: este chore no toca el dominio.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED, sin
  warnings propios.
- `git diff --stat Domain/ WalkTracker/Application/ WalkTracker/Adapters/` — **vacío**.

**Manual checks (simulador; no hay target de UI tests):**
- Inicio, sesión activa, sesión en pausa, resumen, las tres pantallas de permiso y la tarjeta de clima,
  en claro y en oscuro: iguales salvo el acento, el radio 20 y el relleno 16/12.
- Sesión con pasos estimados en claro y en oscuro: el `~` se lee sin esfuerzo y no se confunde con el acento.
- Dynamic Type al máximo en la pantalla de sesión: sin recortes, botones aún pulsables.
