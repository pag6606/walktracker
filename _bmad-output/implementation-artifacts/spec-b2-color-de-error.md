---
title: 'B-2 — El color de un error se mide, y el gate deja de mirar un nombre'
type: 'bugfix'
created: '2026-09-20'
baseline_commit: '408eb2f5a9c826c699e799f74f513c8e6ab39dc4'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-retro-2026-09-20.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-ux-tokens-nativos.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** el mensaje de rechazo de Ajustes se pinta con `Color.red`, que en tema claro da
**3,55:1 sobre blanco** y **3,18:1 sobre el gris agrupado** — por debajo del 4,5:1 que WCAG AA exige
para texto normal. Medido en la retro del Epic 2 (hallazgo D2) y confirmado de forma independiente.

**Lo que importa no es el color: es por qué volvió a pasar.** El chore de tokens nació porque
`.orange` daba 2,20:1 en producción, y dejó dos mecanismos. Los dos son **listas enumeradas**:

- el arnés mide `Colors.accent` y `Colors.estimated`, **los dos tokens**, no el rol;
- el gate veta `.orange` **por su nombre**.

La 2.3 estrenó la primera pantalla posterior al chore y eligió otro color del sistema sin medir. El
comentario que lo justifica razona sobre el **valor** sustituido (*"lo que este vocabulario sustituye
es `.orange`"*) en vez de sobre el **rol**. Gate y suite siguieron verdes: 161 checks, 609 tests.

**Enfoque:** el rol "color de un error" se convierte en token medido, como ya lo son el acento y lo
estimado; y el gate deja de vetar un nombre para exigir que **cualquier color cromático del sistema
usado para pintar texto tenga su medición**. Sin eso, el tercer color se colará igual.

## Boundaries & Constraints

**Always:**
- **El color nuevo se deriva de un valor publicado, no se inventa.** En claro, el rojo accesible que
  Apple publica para ese uso; en oscuro, el rojo del sistema, que ya cumple. Los ratios se miden
  contra los **dos fondos reales** sobre los que puede caer el mensaje —blanco y gris agrupado— y se
  registran.
- **Se mide en el arnés, en cada ejecución**, como los otros dos tokens: si alguien retoca el colorset
  y baja de 4,5:1, la suite lo dice.
- **El gate pasa de vetar un nombre a exigir una medición.** En `WalkTracker/UI/` (fuera de
  `Style/DesignTokens.swift`), nombrar un color **cromático** del sistema para pintar texto es un
  fallo: los colores del producto viven en `Colors` y están medidos.
- **Los roles semánticos del sistema siguen permitidos:** `.primary`, `.secondary`, `.tint` y los
  materiales. El sistema garantiza su contraste y aliasarlos añadiría indirección sin ganancia — es la
  regla de admisión que el fichero de tokens ya fija.
- **El aspecto no cambia más que el color del mensaje de rechazo.** Los otros tres resultados siguen
  distinguiéndose por jerarquía (`.primary` / `.secondary`) y no por color, que fue una decisión
  deliberada de la 2.3.
- El rojo nuevo **no se confunde con el acento ni con lo estimado** en ninguno de los dos temas, y eso
  se comprueba como ya se comprueba entre esos dos.

**Never:**
- Añadir color a los resultados que hoy no lo tienen: el aviso de rango **no es un error**.
- Cambiar los textos del mensaje ni la estructura de la pantalla.
- Tocar `Colors.accent` ni `Colors.estimated`, que están medidos y en producción.
- Arreglar aquí lo que quedó abierto de B-1 (que nadie pinta la lectura fallida) ni de B-3 (que la
  degradación no llega al log).

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Rechazo en claro | mensaje de rechazo sobre blanco | ≥ 4,5:1 | — |
| Rechazo en claro, fondo de lista | el mismo sobre el gris agrupado | ≥ 4,5:1 | — |
| Rechazo en oscuro | sobre negro y sobre el gris agrupado oscuro | ≥ 4,5:1 en los dos | — |
| Error y acento juntos | Ajustes con el acento visible y un rechazo | se distinguen por **tono**, no solo por luminancia | — |
| Error y estimado juntos | los dos tokens cromáticos comparados | no se confunden en ningún tema | — |
| Aviso de rango | valor fuera de 0,3–1,2 m | **sin color de error**: sigue siendo jerarquía | — |
| Control negativo | se mide `Color.red` del sistema en claro | la medición lo detecta por debajo de 4,5:1 | — |
| Gate ante un color cromático | una vista escribe `Color.red`, `.yellow`, `.mint`… para texto | **falla**, nombrando fichero y línea | — |
| Gate ante un rol semántico | una vista escribe `.primary`, `.secondary`, `.tint` | **pasa**: son roles del sistema | — |

</frozen-after-approval>

## Code Map

- `WalkTracker/UI/Settings/SettingsView.swift:218-227` `style(for:)` — el sitio exacto. La línea 225
  es `AnyShapeStyle(Color.red)`, y el comentario de `:223-224` es el razonamiento a corregir: habla del
  valor sustituido, no del rol. Los otros tres casos (`:220-222`) **no se tocan**.
- `WalkTracker/UI/Style/DesignTokens.swift` — `Colors.accent` y `Colors.estimated` son el molde: cada
  uno nombra un colorset de `Assets.xcassets`, con variante clara y oscura, y su doc registra los
  ratios medidos. La **regla de admisión** del fichero (rol repetido ≥ 2 veces **o normativo**) admite
  este por la segunda vía: el contraste AA es normativo, no una preferencia.
- `WalkTracker/Resources/Assets.xcassets/` — ahí viven `AccentColor.colorset` y
  `EstimatedSteps.colorset`. El nuevo va al lado, con el mismo formato.
- `WalkTrackerTests/UI/DesignTokensTests.swift` — `ContrastCase` y `contrastMeetsAA` ya existen y
  recalculan los ratios en cada ejecución; `accentAndEstimatedAreDistinguishable` es el molde para
  comprobar que dos cromáticos no se confunden; y `measurementCatchesTheRealFailure` es el **control
  negativo** que demuestra que la medición sabe detectar un incumplimiento — replicarlo para el rojo
  del sistema, que es el que este chore sustituye.
- `Scripts/check-project-shape.sh` — la sección 12 y su regla de `.orange`; su arnés
  `check-project-shape-tests.sh` exige caso rojo **y verde** por regla. **Cuidado con los falsos
  positivos:** el fichero de tokens debe seguir pudiendo nombrar colores, y `.primary`/`.secondary`/
  `.tint` tienen que pasar. El gate trabaja línea a línea y no ve los comentarios (`code_lines`).
- **Valores medidos para esta spec** (calculados al escribirla, a verificar en la implementación):

  | | claro | oscuro |
  |---|---|---|
  | `#D70015` (rojo accesible de Apple) | **5,38:1** sobre blanco · **4,83:1** sobre gris agrupado | — |
  | `#FF453A` (rojo del sistema, oscuro) | — | **6,16:1** sobre negro · **4,99:1** sobre `#1C1C1E` |
  | `Color.red` actual en claro | 3,55:1 · 3,18:1 | — |

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Resources/Assets.xcassets/` — el colorset del error, con sus dos variantes.
- [x] `WalkTracker/UI/Style/DesignTokens.swift` — el token del rol, con sus ratios documentados y la
      razón de admisión escrita (normativo, no repetido).
- [x] `WalkTracker/UI/Settings/SettingsView.swift` — usar el token y **corregir el comentario**, que
      hoy razona sobre el valor sustituido en vez de sobre el rol.
- [x] `WalkTrackerTests/UI/DesignTokensTests.swift` — los cuatro fondos, la distinción frente a los
      otros dos cromáticos, y el control negativo con el rojo del sistema.
- [x] `Scripts/check-project-shape.sh` — la regla pasa de un nombre a la familia cromática; los roles
      semánticos siguen pasando.
- [x] `Scripts/check-project-shape-tests.sh` — rojo y verde de la regla nueva, incluidos los casos
      verdes de `.primary`, `.secondary`, `.tint` y el fichero de tokens.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` — lo que no se cierre aquí.
- [x] `README.md` — **no estaba en la lista y hubo que tocarlo**: describía la sección 12 diciendo
      que veta `.orange`, y dejarlo así habría sido un documento que miente sobre lo que el gate
      comprueba — el patrón exacto que la retro señala en "Lo que no funcionó" (#1). Ahora nombra la
      familia cromática y los roles que siguen pasando.

**Acceptance Criteria:**
- Dado el mensaje de rechazo, cuando se mide en los cuatro fondos reales, entonces **todos** dan
  ≥ 4,5:1 — y la medición corre en cada ejecución de la suite.
- Dada una vista que escriba `Color.red` o cualquier otro cromático del sistema para texto, cuando
  corre el gate, entonces **falla** nombrando fichero y línea.
- Dada una vista que escriba `.primary`, `.secondary` o `.tint`, cuando corre el gate, entonces **pasa**.
- Dado el aviso de rango, cuando se muestra, entonces **no** usa el color de error.

## Implementation Notes

**El colorset se llama `ErrorMessage` y el token `Colors.error`.** El nombre del colorset dice dónde
se pinta (el mensaje), el del token dice el **rol**, que es lo que la Intent pide tokenizar. Su doc
deja escritas las dos mitades que faltaban en `SettingsView`: que entra por **normativo** y no por
repetido —hoy tiene un solo uso—, y qué **no** es (no es "el color de todo lo que avisa": el aviso
de rango humano se guardó, no falló, y sigue distinguiéndose por jerarquía).

**Los valores de la spec se verificaron antes de escribir el colorset, y salen clavados.**
Recalculados con la fórmula de WCAG 2.1 sobre los cuatro fondos reales:

| | claro | oscuro |
|---|---|---|
| `#D70015` (rojo accesible de Apple) | **5,38:1** sobre blanco · **4,83:1** sobre `#F2F2F7` | — |
| `#FF453A` (rojo del sistema) | — | **6,16:1** sobre negro · **4,99:1** sobre `#1C1C1E` |
| `Color.red` del sistema, en claro | **3,55:1** · **3,18:1** | — |

Los cuatro fondos son los dos de una lista agrupada **y los de su fila**: el mensaje vive en una fila
de un `Form`, así que en claro puede caer sobre blanco (fila) o sobre `#F2F2F7` (lista), y en oscuro
sobre `#1C1C1E` (fila) o negro (lista). Medirlo solo contra el fondo de pantalla habría dejado fuera
el caso más apretado de cada tema.

**"No se confunde con los otros dos" se mide por TONO, no por luminancia.** La comprobación que ya
existía entre el acento y el estimado se apoyaba en que uno es verde (`g > r`) y el otro naranja
(`r > g`). Con el rojo eso no basta: rojo y naranja son los dos cálidos y los dos tienen `r > g`, así
que el test nuevo calcula el **ángulo de tono** (HSV) y exige ≥ 30° de separación, por el camino
corto del círculo, entre el error y cada uno de los otros dos, en los dos temas. Medido: 84° y 35°
en claro, 69° y 33° en oscuro. El umbral no es decorativo — la mutación de abajo lo bajó a **25,9°**
al devolver el rojo del sistema, que además de incumplir AA se parece más al naranja de estimado que
el rojo elegido.

**El control negativo se replica, porque es lo único que prueba que la medición sabe suspender.**
`measurementCatchesTheSystemRed` afirma que `Color.red` del sistema en claro **no llega** a AA en
ninguno de los dos fondos de la pantalla —3,55:1 y 3,18:1, exactamente lo que la retro midió de forma
independiente— y que el token sí llega en esos mismos dos sitios. Sin eso, "el arnés mide el
contraste" sería una afirmación sin prueba: que los colores elegidos pasen no demuestra nada.

**El gate pasa de un nombre a la familia, y ese es el cambio que de verdad cierra el hallazgo.** La
regla vetaba `.orange`; ahora veta los **doce** colores cromáticos con nombre de SwiftUI (`red`,
`orange`, `yellow`, `green`, `mint`, `teal`, `cyan`, `blue`, `indigo`, `purple`, `pink`, `brown`).
Lo que sigue pasando, con caso verde cada uno: los **roles** semánticos del sistema (`.primary`,
`.secondary`, `.tint`), los **acromáticos** (`.black`, `.white`, `.gray`, `Color.clear` — que la
propia pantalla de Ajustes usa dos veces en `.listRowBackground`), los materiales, los tokens del
producto, y el fichero de tokens, que es donde un color del sistema se nombra precisamente para
decir cuál se sustituye y por qué.

**La regla no distingue primer plano de fondo, y se declara.** Un gate que trabaja línea a línea no
puede saber si un color pinta texto o una superficie. La Intent habla de "pintar texto", pero el lado
conservador es prohibir la familia entera en las vistas —es lo que ya hacía la regla de `.orange`, que
tenía caso rojo de `.background(Color.orange)`— y el coste es cero: un color del producto vive en
`Colors`. Queda escrito en el script para que no se lea como un descuido.

**Lo que NO cambió, y se comprobó.** Los otros tres resultados del `switch` siguen en `.secondary` y
`.primary`; ningún texto, ninguna estructura de pantalla; `Colors.accent` y `Colors.estimated`
intactos (`git diff` no los toca). El rojo solo pinta la rama `.rejected`.

## Spec Change Log

## Review Triage Log

## Design Notes

**Por qué el gate cambia y no solo el color.** Arreglar el rojo sin tocar la regla deja el mecanismo
intacto: la próxima pantalla elegirá `.yellow` o `.mint` y volverá a pasar en verde. El chore de
tokens ya vetó un nombre y el siguiente color entró por la puerta de al lado. Vetar la **familia** y
exigir medición ataca la causa, no el síntoma.

**Por qué el rojo no se inventa.** Apple publica un rojo accesible para tema claro precisamente para
este caso; usarlo evita elegir un tono a ojo y da una fuente que citar. En oscuro el rojo del sistema
ya cumple sobre los dos fondos, así que no se toca.

**Por qué los roles semánticos siguen libres.** `.primary` y `.secondary` los garantiza el sistema y
cambian con el tema y con los ajustes de accesibilidad del usuario. Envolverlos añadiría indirección
sin ganancia, y contradiría la regla de admisión que el propio fichero de tokens fija.

## Verification

**Commands:**
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes, con la regla nueva.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED.
- `bash Scripts/verify-domain.sh` — verde y sin cambios: esto no toca el dominio.
- **Mutación obligatoria:** con `Color.red` de vuelta en la vista, el **gate** debe fallar; y con el
  colorset retocado por debajo de 4,5:1, la **suite** debe fallar. Son los dos mecanismos que hoy no
  cazaron nada.
- **Contar los casos nuevos por nombre en el `.xcresult`.**

**Manual checks (simulador):** Ajustes con un valor inválido, en claro y en oscuro — el mensaje se lee
sin esfuerzo y no se confunde con el verde del acento.

**Ejecutado (2026-09-20):**

- `bash Scripts/check-project-shape.sh` — **verde**, con la regla de la familia cromática.
- `bash Scripts/check-project-shape-tests.sh` — **189/189**. Venía de **161**, así que B-2 añade
  **28 casos**, 14 rojos y 14 verdes. Rojos: los doce cromáticos escritos como `.nombre`, más
  `Color.red` en primer plano, más `Color.mint` de fondo, más la **línea literal** que pasó el gate el
  día del merge del chore (`case .rejected: AnyShapeStyle(Color.red)`), que tiene caso propio para que
  la evasión concreta tenga camino rojo y no solo la familia. Verdes: `.primary`, `.secondary`,
  `.tint`, `.tint(Colors.accent)`, las dos ramas reales del `switch` de Ajustes, `Color.clear` de
  `.listRowBackground`, `Color.white`, `Color.black`, `.gray`, dos materiales, un comentario que
  nombra `Color.red` para explicarse, y el fichero de tokens nombrando `Color.red` y `Color.mint`.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — **TEST SUCCEEDED**,
  **638 tests en 50 suites** (venía de **635**, el número que dejó B-3: **+3** funciones de test).
  Ese recuento no ve los argumentos: contándolos, B-2 añade **8 casos ejecutados**, porque dos tests
  parametrizados crecen (ver abajo).
- `bash Scripts/verify-domain.sh` — **verde**, 238 tests en 15 suites.
  `git diff --stat Domain/ WalkTracker/Application/ WalkTracker/Adapters/` — **vacío**.

**Casos nuevos contados por nombre en el `.xcresult`** (los 8: tres funciones y cinco argumentos):

- `Los tres colorsets viajan dentro de la app` con el argumento `"ErrorMessage"` (+1).
- `Error: el rojo accesible de Apple en claro, el rojo del sistema en oscuro` (+1).
- `El rojo del error no se confunde con el acento ni con el estimado en ningún tema` (+1).
- `Contraste ≥ 4,5:1 …` con los cuatro argumentos nuevos: `error sobre la fila de la lista, claro`,
  `error sobre el gris agrupado, claro`, `error sobre el fondo de la lista, oscuro`,
  `error sobre la fila de la lista, oscuro` (+4). El caso pasa de 10 a 14 argumentos.
- `La medición detecta el incumplimiento del rojo del sistema que este chore sustituye` (+1).

**Mutación obligatoria — los dos mecanismos que no cazaron nada, ahora cazan:**

1. **Gate.** Con `case .rejected: AnyShapeStyle(Color.red)` de vuelta en la vista, el gate falla
   nombrando fichero y línea: `WalkTracker/UI/Settings/SettingsView.swift:227: error: AD-13/UX-DR3:
   (UX-DR6) un color cromático del sistema no tiene contraste medido…`, exit 1. Es la línea literal
   que salió verde el día del merge del chore de tokens. Revertida.
2. **Suite.** Con la variante clara del colorset devuelta al rojo del sistema (`#FF3B30`), la suite
   falla con **6 issues** y los números exactos del hallazgo D2:
   `(ratio → 3.547138005400671) >= 4.5` en *error sobre la fila de la lista, claro* y
   `(ratio → 3.1788068188976424) >= 4.5` en *error sobre el gris agrupado, claro*; más el control
   negativo, el valor publicado y la separación de tono, que cae a **25,9°**. Revertida, y verde otra
   vez.

**Lo que queda abierto** (registrado en `deferred-work.md`): nada ata el token a la **rama** que debe
pintarlo. Intercambiar dos ramas de `style(for:)` —pintar de rojo el aviso de rango— deja la suite y
el gate en verde. El test mide el color y el gate prohíbe nombrar un cromático del sistema; el
reparto no lo cubre ninguno de los dos, y cerrarlo exige A-4 (renderizar una vista) o cambiar la
forma de `style(for:)`, que la Intent acota fuera. Anotado también que la sección 12 sigue sin
escanear `WalkTrackerActivity/` — hoy sin ningún cromático, verificado con la misma regex.
