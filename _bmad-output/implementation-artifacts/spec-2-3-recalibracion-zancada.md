---
title: '2.3 — Recalibración de zancada en Ajustes'
type: 'feature'
created: '2026-09-19'
baseline_commit: '575c1f116d4234324731419135f793bb3a819dbf'
status: 'done'
route: 'dispatch'
review_loop_iteration: 1
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-2-2-frase-motivacional.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la distancia sale de multiplicar pasos por una zancada que hoy es una constante fija
de `formulas.json` (0,655 m) e igual para todo el mundo. Paul no puede corregirla, y la pestaña
Ajustes no existe: es un `EmptyTabView` que dice "Todavía no hay nada que ajustar".

**El riesgo central, localizado antes de empezar:** `SessionStore.strideM` es un `let` fijado al
construir el store, y `openSession()` lo lee de ahí. Si esta historia solo escribe el ajuste y no
cambia **de dónde se lee al abrir sesión**, la zancada nueva únicamente se aplicaría tras relanzar
la app, el criterio central quedaría incumplido y **ningún test actual fallaría**. Es la tercera vez
que aparece este patrón (el tope de 20 min en R1, el cableado de las frases en la 2.2), así que
lleva test propio y comprobación por mutación.

**Enfoque:** `strideM` opcional en `AppSettings` (`nil` = sin configurar), resuelto contra el default
de `formulas.json` al abrir cada sesión; una intención en `SettingsStore` que **valide y rechace**
en vez de normalizar en silencio; y la pestaña Ajustes, que nace aquí con un único campo.

## Boundaries & Constraints

**Always:**
- **La zancada nueva se aplica a la siguiente sesión sin relanzar la app.** `openSession()` resuelve
  la zancada en el momento de abrir, no en el de construir el store.
- **Validación en la frontera, no normalización:** `> 0` y finita. Un valor inválido **se rechaza con
  mensaje y no se persiste**. La puerta de lectura del fichero (tolerante: un valor corrupto cae a
  "sin configurar") y la de escritura desde la UI (que rechaza) son distintas.
- **`Session.strideM` sigue congelada:** es un `let` del agregado y recalibrar nunca reescribe una
  sesión, ni la viva ni su snapshot.
- **Sin subir `schemaVersion` de `settings.json`.** Un campo opcional nuevo es compatible en las dos
  direcciones; subirlo a 2 haría que un build de la 2.2 ya instalado leyera los ajustes como "del
  futuro" y perdiera la ventana de frases.
- **La pantalla nace cumpliendo la sección 12 del gate**: tokens de `UI/Style/`, nada de marcos
  numéricos, radios, hexadecimales ni valores de la escala cableados.
- **La vista no escribe el estado** (sección 6): guardar es una intención del store, y el resultado
  —aceptado, rechazado, o aceptado con aviso— es estado observable.
- Objetivos táctiles ≥ 44 pt; Dynamic Type sin recortes; VoiceOver lee etiqueta, valor y error.

**Decisiones de Paul (2026-09-19):**
- **El ajuste es un override opcional.** Solo se guarda si Paul lo toca; quien no lo toca sigue el
  default de `formulas.json`, que queda como único sitio donde vive el 0,655. Diverge a propósito de
  `domain-model.md:95`, que modela `config.strideM` como campo con valor: duplicar el default en dos
  ficheros los deja divergir sin que nadie lo note.
- **Botón Guardar explícito.** Hace inequívoco qué significa "no se persiste el valor inválido" y
  permite escribir mal sin consecuencias.
- **Rango razonable 0,3–1,2 m: avisa, no bloquea.** Fuera de ese rango se guarda igual —es su app y
  su zancada— pero se dice que está fuera de lo humano, por si fue un dedazo (0,067 por 0,67). El
  rechazo duro sigue siendo solo `≤ 0`, no finita o no numérica.
- **Solo la zancada.** La pantalla nace con un único campo.
- **Botón "Usar el valor por defecto" (renegociado el 2026-09-19, durante la revisión).** Una vez
  guardada una zancada propia no había forma de volver al valor de fábrica: vaciar el campo se
  rechaza —y esa fila de la matriz **no cambia**—, así que un dedazo guardado (0,067) dejaba a
  Paul sin manera de recuperar el 0,655 salvo reinstalando la app. La vuelta atrás es una **acción
  explícita y aparte**, con su intención en el store, su resultado observable y su fila propia en
  la matriz.

**Never:**
- Meta semanal, sonido, exportar, borrar datos ni "Acerca de": son de las épicas 3 y 5.
- Tocar el flujo de clima de la 2.1, ni cerrar aquí el diferido del "Ahora no" de la ubicación: su
  mitad de persistencia ya no está bloqueada, pero la otra mitad toca la 2.1. Se re-apunta con razón.
- Reescribir `Session.strideM`, el historial (que no existe hasta la 5.1) ni el snapshot ya escrito.
- Recategorizar los vectores `recalibrate`: están declarados muertos (agregada v1 eliminada) y tocar
  `baseline`/`totals` del inventario es trabajo aparte.
- Sustituir los `EmptyTabView` de Historial y Logros: siguen siendo suyos.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Sin configurar | `settings.json` sin `strideM` | la sesión nace con 0,655 de `formulas.json` | — |
| Recalibrar y caminar | se guarda 0,670 y se inicia sesión **sin relanzar** | la sesión nace con **0,670** | — |
| Sesión viva | hay sesión abierta con 0,655 y se recalibra a 0,670 | la sesión viva **sigue** con 0,655, y su snapshot no se reescribe | — |
| Cero o negativo | se guarda `0` o `-0,5` | **rechazado**, con mensaje; el fichero no cambia | mensaje en línea |
| No numérico o vacío | campo vacío, `abc`, `,` | **rechazado**, con mensaje; el fichero no cambia | mensaje en línea |
| Fuera de rango humano | se guarda `0,067` o `3,0` | **se guarda**, con aviso de que está fuera de 0,3–1,2 m | aviso, no bloqueo |
| En el borde | se guarda `0,3` o `1,2` exactos | se guarda **sin** aviso | — |
| Coma decimal | se escribe `0,670` con el teclado en español | se acepta como 0,670 | — |
| Ajustes corruptos | `settings.json` con `strideM: "abc"` o `-1` | se lee como **sin configurar**; no se pierde la ventana de frases | — |
| Fichero de la 2.2 | `settings.json` sin el campo, esquema 1 | se lee bien y se le puede añadir la zancada | — |
| Guardar dos veces | se guarda 0,670 y luego 0,700 | gana el último; una sola escritura por pulsación | — |
| Volver al valor por defecto | hay 0,067 guardado y se pulsa "Usar el valor por defecto" | se **borra** el override y la siguiente sesión vuelve a 0,655; el campo vacío se sigue rechazando | — |

</frozen-after-approval>

## Code Map

**La cadena de `strideM` hoy** (todo constante):
- `WalkTracker/Resources/formulas.json:3` `defaultStrideM: 0.655` → `Domain/Formulas/Formulas.swift:23`,
  validado en `:81-84` delegando en `Session.validateStride`, y listado en `constantNames` (`:44`).
- `WalkTracker/App/CompositionRoot.swift:80` inyecta `strideM: formulas.defaultStrideM` al store.
- `WalkTracker/Application/SessionStore.swift:161-163` — **`@ObservationIgnored let strideM: Double`**,
  fijado en el init (`:267`, `:282`). Su propio doc dice "el perfil de calibración la sustituirá".
- `WalkTracker/Application/SessionStore+StartFlow.swift:96` `Session.start(at:strideM:)` — **el punto
  exacto que hay que cambiar**.
- `Domain/Session/Session.swift:28` `public let strideM: Double` ("Congelada: recalibrar nunca
  reescribe una sesión"); `:140-143` `validateStride` (`isFinite`, `> 0`) — **reutilizar, no duplicar**.

**La infraestructura que dejó la 2.2** (se construye encima, no se rehace):
- `Domain/Ports/AppSettings.swift` — un solo campo `private(set) var recentQuoteIds`, `defaults`
  (`:21`), init que **normaliza** (`:50-57`) y `setRecentQuoteIds` (`:37`). Su doc `:8-16` **ya
  anuncia esta historia**. Ojo: normalizar en silencio es lo contrario de "rechazar con mensaje";
  hacen falta dos puertas.
- `WalkTracker/Application/SettingsStore.swift:24-26` `@MainActor @Observable`, `private(set) var
  settings` (`:30`), una única intención `recordShownQuote(id:)` (`:67`), `save()` privado que no
  propaga fallo (`:73-79`). **La UI no lo consume todavía**: solo `CompositionRoot` y `SessionStore`.
  Esta historia estrena su cableado hacia la UI (`WalkTrackerApp` → `RootView` → Ajustes).
- `WalkTracker/Adapters/Persistence/SettingsFileAdapter.swift:86-89` `File { schemaVersion,
  recentQuoteIds }`, esquema 1 leíble `1...1`; campo desconocido se ignora, ausente cae a default
  (`:115`); un esquema mayor **no se aparta** (`:62-66`). Ya hay test que mete `"strideM": 0.7` y
  afirma que no rompe (`SettingsFileAdapterTests.swift:91-93`).
- `JSONFileStore.swift` — escritura atómica y apartado. **No tocar.**
- `Scripts/check-project-shape.sh:370, 385-391` — la sección 9 ya exime `DUEÑO+Algo.swift` y su
  comentario **nombra explícitamente `SettingsStore+Stride.swift`**.

**La pantalla, que no existe:**
- `WalkTracker/UI/RootView.swift:51-58` — la pestaña Ajustes es `EmptyTabView` (`:102-119`,
  `ContentUnavailableView` en `NavigationStack`). Historial (`:35-42`) y Logros (`:43-50`) siguen igual.
- **Cero precedente de entrada de texto en todo el árbol**: ni un `TextField`, `Form`, `FocusState`
  ni `.keyboardType`. El único `List` es el de `Diagnostics/`, que es `#if DEBUG` y está exento.
  Esta historia estrena el primer input del producto.
- `WalkTracker/UI/Style/DesignTokens.swift` — `Spacing` 4/8/12/16/24, `LayoutMetrics.margin` 16 y
  `.touchTargetMin` 44, `Radius.card` 20, `Surface`, `Typography`, `Colors`. **Trampa de la sección
  12:** la forma natural de estrechar un `TextField` (`.frame(width:)`) está prohibida y **no hay
  token para ese rol**; hay que resolverlo con layout, no con marco fijo. `Color.red` sí se permite
  (solo `.orange` está prohibido).
- De UX-DR4 sobrevive la **estructura** —etiqueta · campo · error en línea debajo—, no sus colores
  (UX-DR1 derogado). El maquetado `mock-07-settings.html` contradice el flujo 5 y su `0,75 m` es un
  fixture inventado: **no es contrato**.

**Verificación:**
- `WalkTrackerTests/Domain/AppSettingsTests.swift` existe y su doc `:6` **ya anuncia la 2.3**; está
  en la lista de `-only-testing:` de `verify-domain.sh:86`, así que ampliarlo entra gratis. **Un suite
  nuevo hay que añadirlo a mano** al script o no se ejecuta y nadie se entera.
- No hay target de UI tests (A-4 abierto).

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Ports/AppSettings.swift` — `strideM` opcional, con la puerta tolerante (lectura) y la
      que valida y rechaza (escritura) separadas.
- [x] `Domain/Session/Session.swift` o donde corresponda — exponer el rango humano 0,3–1,2 como
      aviso, sin convertirlo en rechazo. Reutilizar `validateStride` para el rechazo duro.
- [x] `WalkTracker/Adapters/Persistence/SettingsFileAdapter.swift` — `strideM` en el `File`, decode y
      encode, **sin tocar `schemaVersion`**; un valor corrupto se lee como sin configurar.
- [x] `WalkTracker/Application/SettingsStore+Stride.swift` — la intención de guardar, con su
      resultado (aceptado / aceptado con aviso / rechazado) como estado observable.
- [x] `WalkTracker/Application/SessionStore+StartFlow.swift` + `SessionStore.swift` — **resolver la
      zancada al abrir sesión**, no al construir el store. Es el criterio central.
- [x] `WalkTracker/UI/Settings/SettingsView.swift` — la pantalla, con el campo, el botón Guardar, el
      mensaje en línea y el aviso de rango. Escrita contra la sección 12 desde el primer commit.
- [x] `WalkTracker/UI/RootView.swift` — sustituir **solo** el `EmptyTabView` de Ajustes, y cablear el
      `SettingsStore` desde `WalkTrackerApp`.
- [x] `WalkTracker/Resources/Localizable.xcstrings` — las cadenas nuevas, en el mismo commit.
- [x] Tests de la matriz, ampliando `AppSettingsTests` en lugar de crear suite nueva; si se crea
      alguna, añadirla a `verify-domain.sh` en el mismo commit.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` — re-apuntar el "Ahora no" de la
      ubicación con su razón, y registrar lo que no se puede verificar sin renderizar vista.
- [x] **Revisión (2026-09-19):** `clearStride()` y el botón "Usar el valor por defecto", con su
      resultado observable y sus tests; el ida y vuelta del campo por locale, con
      `WalkTrackerTests/UI/SettingsViewTests.swift` emparejando `decimalText` con el parser; los
      dos mensajes que mentían (`notPersisted`, `rejected(.tooLarge)`); el teclado con "Listo",
      el anuncio de VoiceOver, el objetivo táctil en el control y la etiqueta única; `save` en la
      sección 6 del gate y la sección 9b nueva, con sus casos rojo y verde; y
      `SettingsStoreStrideTests` **fuera** de `verify-domain.sh`, que es un gate de dominio.

**Acceptance Criteria:**
- Dada una zancada recalibrada, cuando se inicia la siguiente sesión **sin relanzar la app**,
  entonces la sesión nace con el valor nuevo — y esto se comprueba en un test, no a ojo.
- Dado un valor inválido, cuando se pulsa Guardar, entonces hay mensaje y el fichero **no cambia**.
- Dado un valor fuera de 0,3–1,2 m, cuando se pulsa Guardar, entonces **se guarda** y se avisa.
- Dado un `settings.json` escrito por la 2.2, cuando se lee, entonces funciona y admite la zancada.

## Implementation Notes

**El criterio central, escrito donde no se puede olvidar.** `SessionStore.strideM` pasó a
llamarse `defaultStrideM`, y `openSession()` resuelve la zancada **en el momento de abrir**:
`settings.resolvedStrideM(default: defaultStrideM)`. El renombrado no es cosmético — es lo que
impide que alguien vuelva a escribir `Session.start(at:strideM: strideM)` creyendo que lee la
buena. La mutación está comprobada: devolver esa línea a `defaultStrideM` deja
`SessionStoreTests.recalibratedStrideAppliesToTheNextSession` en rojo (esperaba 0,670, sale
0,655) y todo lo demás en verde.

**Dos puertas, un solo sitio.** Las dos viven en `AppSettings`, que es lo que cruza la frontera
del fichero: el `init` **tolera** (lo que no valida se lee como "sin configurar") y
`setStrideM(_:)` **rechaza** con `DomainError.invalidValue(field: "strideM")`. Las dos delegan
en `Session.validateStride`, que no se ha duplicado. Es la puerta que la 2.2 dejó anunciada en
el doc de `AppSettings`, usada tal cual.

**El parser vive en el dominio, y por eso la matriz se prueba sin pantalla.**
`AppSettings.strideMeters(fromText:)` convierte lo tecleado en metros aceptando coma **y**
punto, y nada más. Rechaza a propósito tres cosas que `Double(_:)` sí acepta y que serían una
sorpresa en un campo de zancada: notación científica (`1e3`), literales hexadecimales (`0x10`
→ 16) y las palabras `inf`/`nan`. Parsear y validar son dos pasos distintos: `-0,5` **se
parsea** y lo rechaza después la frontera, que es quien sabe decir por qué. Así "campo vacío",
"`abc`", "`,`" y "cero o negativo" son filas de `AppSettingsTests`, no checks manuales.

**Cinco resultados, no dos, y viven en el store.** `SettingsStore.strideOutcome` es
`saved` / `savedOutsideHumanRange(Double)` / `clearedToDefault` / `notPersisted` /
`rejected(.notANumber | .tooLarge | .notPositive)`. Las causas de rechazo están separadas
porque merecen mensajes distintos: "eso no es un número", "eso no cabe" y "tiene que ser mayor
que cero" no se corrigen igual. Los dos resultados que la revisión añadió son mensajes que
antes mentían:

- **`notPersisted`.** `save()` se tragaba el fallo de disco, así que el resultado era `.saved`
  y la pantalla decía "Zancada guardada. La siguiente caminata la usará." de un valor que
  desaparecía al relanzar. Ahora `save()` **devuelve** si escribió —sin propagar el error: una
  caminata no se para por un fallo de disco— y el mensaje dice las dos verdades: se usa ahora,
  no quedó guardado. El test que fijaba el comportamiento (`diskFailureKeepsTheValueInMemory`)
  **se conserva**; lo que cambia es lo que se afirma del mensaje.
- **`rejected(.tooLarge)`.** Un número de 400 dígitos se parsea —son dígitos— y desborda a
  `inf`; `Session.validateStride` lo rechazaba junto al cero y Paul leía "la zancada tiene que
  ser mayor que cero" de un número que no es ni cero ni negativo.
  `AppSettings.isRepresentableStride(_:)` separa los dos motivos en el dominio, donde ya viven
  las otras reglas.

El enum **no lleva el texto**: eso es de la capa que pinta, y meterlo en `Application/`
obligaría al store a conocer el String Catalog.

**`schemaVersion` sigue en 1, y hay test que lo ata.** `strideRoundTrip` afirma
`schemaVersion == 1` con la zancada dentro, con el porqué escrito en el propio `#expect`:
subirlo a 2 haría que un build de la 2.2 ya instalado leyera los ajustes como "del futuro" (la
regla que la 2.2 estrenó) y perdiera la ventana de frases.

**La zancada es el único campo con decode a mano, y no es un capricho.** Con la síntesis de
`Codable`, un `strideM: "abc"` lanzaba `typeMismatch` y tiraba el fichero **entero** al
apartado: la ventana de frases se perdía por un campo que la matriz dice que debe leerse como
"sin configurar". `File.init(from:)` decodifica `schemaVersion` y `recentQuoteIds` con la regla
de la 2.2 —un tipo equivocado sigue haciendo el fichero ilegible— y solo `strideM` con
`try? decodeIfPresent`. Hay test de disco (`corruptStrideOnDiskIsNotSetAside`) que comprueba
que el fichero se queda donde está.

**El acceso de módulo que esto abrió, y los dos huecos que dejó.**
`SettingsStore.settings` dejó de ser `private(set)` y `save()` dejó de ser `private`, porque
una extensión de Swift en otro fichero no ve lo privado — es exactamente el reparto que ya
tiene `SessionStore` con sus siete extensiones. `strideOutcome` es un `var` de módulo por la
misma razón.

La red **no estaba puesta**, y el propio código lo afirmaba mal: el comentario de `save()` decía
que "la sección 9 del gate lo comprueba", y la sección 9 solo mira las llamadas al **puerto**
(`loadSettings`/`saveSettings`), no los métodos del store. Una vista podía escribir
`settingsStore.save()` y pasar los dos gates. Cerrado en dos sitios, cada uno con sus casos
rojo y verde en `check-project-shape-tests.sh`:

- **Sección 6** (`UI/`, `App/`): `save` entra en la lista de pasos internos del store. No pisa
  las intenciones —`save\b` no casa con `saveStride`, y hay caso verde que lo fija—.
- **Sección 9b, nueva** (`Application/`): el hueco equivalente un piso más adentro. `SessionStore`
  tiene el store de ajustes inyectado en una propiedad llamada `settings`, así que
  `settings.settings = …` y `settings.save()` compilaban desde `SessionStore*.swift`. Ahora se
  prohíbe asignarle estado y llamarle `save()` desde cualquier fichero de `Application/` que no
  sea `SettingsStore.swift` o una extensión suya; pedirle intenciones
  (`recordShownQuote`, `resolvedStrideM`) sigue permitido, con caso verde.

Y el comentario de `save()` dice ahora cuál es cada gate.

**El gate se mordió la cola una vez.** La sección 6 busca sobre líneas **crudas**, sin quitar
comentarios (a diferencia de las secciones 7–12, que usan `code_lines`), así que un doc comment
en `RootView` que decía "la sección 6 prohíbe tocar `store.settings`" **falló el gate**. Se
reescribió el comentario. Queda dicho porque es una trampa que volverá a aparecer: en esa
sección, citar el patrón prohibido es violarlo.

**Cableado de Ajustes: por la app, no por el store de sesión.** `SettingsStore` llega a
`RootView` desde `WalkTrackerApp` (`root.settingsStore`), no a través de `SessionStore`. No es
estilo: la sección 6 del gate prohíbe a `UI/` alcanzar `…Store.settings`, y con razón — son dos
dueños distintos del mismo puerto (AD-16). Con ello viaja `formulas.defaultStrideM`, que la
pantalla solo usa de marcador de posición del campo.

**La trampa de la sección 12, resuelta con layout.** Estrechar el `TextField` con
`.frame(width:)` está prohibido y no hay token para ese rol. La pantalla usa `LabeledContent`
dentro de un `Form`: etiqueta a la izquierda, valor alineado a la derecha con su "m" al lado.
Es lo que hace Ajustes del sistema, es lo que aguanta Dynamic Type grande, y no inventa ningún
número. El único marco es `minHeight: LayoutMetrics.touchTargetMin`. El mensaje de rechazo usa
`Color.red` —permitido: el color que este vocabulario sustituye es `.orange`— y el aviso de
rango no usa color, sino jerarquía: el rango no es un error.

**El rango humano se escribe una sola vez.** `AppSettings.humanStrideRangeM` (0,3…1,2) es la
fuente; el mensaje de la pantalla interpola sus dos extremos formateados en lugar de teclear
"0,3–1,2". Cambiar el rango cambia el aviso y los tests a la vez.

**Lo que se quitó del String Catalog.** "Sin ajustes" y "Todavía no hay nada que ajustar." eran
del `EmptyTabView` de Ajustes, que ya no existe. Historial y Logros conservan los suyos. La
revisión quitó además "Longitud de zancada en metros": era una `accessibilityLabel` del
`TextField` dentro de un `LabeledContent` cuya etiqueta visible ya decía "Longitud de zancada",
así que VoiceOver leía las dos. Queda **una sola** etiqueta, la visible, que ahora lleva la
unidad: "Longitud de zancada, en metros".

**El ida y vuelta del campo, sostenido por construcción.** Lo que la pantalla escribe en el
campo tiene que ser lo que su propio parser lee, y no lo era de tres maneras a la vez —las tres
verificadas ejecutando Swift, no deducidas—: `decimalText` formateaba con el locale del sistema
(en `ar_EG`, `(0,655)` salía `٠٫٦٥٥` y el parser solo acepta dígitos ASCII, así que **pulsar
Guardar sin tocar nada** respondía "Escribe la longitud en metros"), con separador de millares
(`10.000,000`: dos separadores, `nil`) y con tres decimales fijos (un valor guardado con más se
sembraba redondeado y Guardar lo **sobrescribía en silencio**).

Se arregla el que **escribe**, no el que lee: se fija la numeración `latn`, se desactiva el
agrupamiento y se siembra la precisión real del valor (los decimales que hacen falta para que
vuelva a ser él mismo). Enseñar al parser a entender cada locale era la otra salida, y se
descarta a propósito: el parser vive en el dominio, y hacerlo depender del locale del sistema lo
volvería no determinista y le metería una dependencia que AD-3 no quiere. Lo cierra
`SettingsViewTests`, que empareja las dos mitades —`strideMeters(fromText: decimalText(x, L)) ==
x`— sobre diez regiones, con numeración no latina (`ar_EG`, `fa_IR`, `ne_NP`, `my_MM`) y con
agrupamiento de tres formas distintas (punto, espacio y lakh). Para eso `decimalText` es
**interno** y no privado: el precedente exacto es `MotionBlockedView.settingsURL`, interno para
que su test lo fije sin renderizar.

**El aviso de rango, con dos marcadores.** `humanRangeText` devolvía `"0,3 y 1,2"` de una pieza:
el traductor recibía un token opaco y no podía ni reordenar los extremos ni cambiar la "y". Ahora
son `humanRangeBounds(locale:)` y dos marcadores en el mensaje. Y recibe locale, como
`decimalText`: era la misma decisión tomada de dos formas a un palmo.

**El teclado decimal y su salida.** `.decimalPad` no tiene tecla de retorno, así que la única
forma de cerrarlo era pulsar Guardar —y con el teclado abierto, el mensaje y el propio botón
pueden quedar debajo—. Se resuelve aquí y no en la épica 3 porque este es el primer `TextField`
del producto y fija el patrón: barra de teclado con "Listo" y `.scrollDismissesKeyboard(.interactively)`.

**Lo que VoiceOver no oía.** El mensaje en línea aparece debajo del botón y el foco se queda en
Guardar: un usuario ciego pulsaba y no oía nada. Se anuncia con
`AccessibilityNotification.Announcement`, el mismo recurso que "Sesión recuperada" (1.6). Para
que el texto se escriba **una sola vez** —lo pinta la fila y lo anuncia VoiceOver—,
`SettingsView.message(for:)` devuelve `String(localized:)` en lugar de `Text` por caso.

**El objetivo táctil, en el control y no en la fila.** `.frame(minHeight:)` estaba en el
`LabeledContent`: hacía alta la **fila**, pero el área tocable del campo seguía siendo la del
texto, así que tocar el hueco de la fila no enfocaba nada. El marco y el `.contentShape` van
ahora en el `TextField`, que además se estira a lo ancho del contenido.

**El mensaje no sobrevive a la pantalla.** `strideOutcome` solo se apagaba al volver a escribir,
así que salir de Ajustes y volver enseñaba otra vez el "Zancada guardada" —o el error— de hace
diez minutos. Hay una segunda intención, `strideScreenDidDisappear()`, atada al `.onDisappear`.
Y la señal de "esto lo está tecleando Paul" dejó de ser un `.onChange(of: text)` para vivir en el
binding del campo: el botón de volver al default también vacía el campo, y con `.onChange` ese
vaciado apagaba el mensaje que el propio botón acababa de encender.

**Lo que no hacía falta escribir.** `SettingsFileAdapter.File` declaraba `CodingKeys` a mano:
Swift la sintetiza igual aunque `init(from:)` sea propio —lo que la suprime es declararla—, así
que eran tres líneas que habría que mantener cada vez que una épica futura añadiera un campo. El
init por miembros sí hay que restaurarlo, y ese se queda.

## Spec Change Log

**2026-09-19 · Decisión nueva de Paul, renegociada durante la revisión: "Usar el valor por
defecto".** Es la **única** edición del bloque congelado, y está hecha donde corresponde, en
"Decisiones de Paul".

*Qué faltaba.* La historia dejaba entrar el override pero no salir. La matriz rechaza el campo
vacío, así que borrar lo escrito no sirve para volver atrás: un dedazo guardado —0,067 por
0,67, el mismo ejemplo que justifica el aviso de rango— dejaba a Paul usando una zancada mala
para siempre, sin más salida que reinstalar la app. El aviso decía "compruébala", y comprobarla
no llevaba a ninguna parte.

*Qué se decide.* Una acción explícita y aparte —botón "Usar el valor por defecto"— que **borra
el override** y devuelve la zancada al 0,655 de `formulas.json`. No es un caso más de "Guardar"
a propósito: mezclarlos habría exigido darle al campo vacío un significado que la matriz le
niega.

*Qué NO cambia.* La fila congelada del campo vacío: vaciar y pulsar Guardar se sigue rechazando
con mensaje, y hay test que lo fija junto al botón (`clearingIsTheOnlyWayBack`).

*Dónde vive.* `AppSettings.clearStrideM()` en el dominio, `SettingsStore.clearStride()` como
intención con su resultado observable `.clearedToDefault`, el botón en `SettingsView` —visible
solo cuando hay algo que quitar— y seis casos nuevos en `SettingsStoreStrideTests` más dos en
`AppSettingsTests`.

*Fila nueva en la matriz.* "Volver al valor por defecto | hay 0,067 guardado y se pulsa 'Usar el
valor por defecto' | se **borra** el override y la siguiente sesión vuelve a 0,655; el campo
vacío se sigue rechazando | —".

## Review Triage Log

**2026-09-19 · Tres lentes de revisión sobre la implementación de la 2.3.** 20 puntos, uno de
ellos una decisión nueva de Paul. Veredicto: **19 aplicados**, 1 rechazado por precedente, 1
diferido re-verificado (el contrato vista↔store, que sigue exigiendo target de UI tests).

### A · Decisión nueva de Paul (aplicada)

| # | Hallazgo | Veredicto |
|---|---|---|
| 1 | No había forma de volver al valor por defecto: la matriz rechaza el campo vacío, así que un dedazo guardado (0,067) dejaba a Paul sin salida salvo reinstalar | **Aplicado.** `AppSettings.clearStrideM()`, `SettingsStore.clearStride()` con `.clearedToDefault`, botón "Usar el valor por defecto" visible solo si hay override, y tests. La fila congelada del campo vacío **no se toca**: hay test que la fija junto al botón. Registrado en el Spec Change Log, con la decisión añadida a "Decisiones de Paul" y una fila nueva en la matriz |

### B · El texto que la app escribía y su propio parser rechazaba (aplicados)

Los tres son el mismo sitio, `SettingsView.decimalText`, y los tres se verificaron **ejecutando
Swift**, no deduciendo.

| # | Hallazgo | Veredicto |
|---|---|---|
| 2 | Numeración no latina: en `ar_EG` el campo nacía con `٠٫٦٥٥` y pulsar Guardar **sin tocar nada** respondía "Escribe la longitud en metros" | **Aplicado.** Se fija la numeración `latn` en el locale de formato; el separador decimal sigue siendo el de cada región |
| 3 | Separador de millares: `10.000,000` lleva dos separadores y el parser devuelve `nil` | **Aplicado.** `.grouping(.never)` |
| 4 | Precisión: el campo se sembraba con tres decimales y Guardar **sobrescribía en silencio** un valor guardado con más | **Aplicado.** Se siembran los decimales que el valor necesita para volver a ser él mismo |
| 2-4 | Y no existía test que emparejara las dos mitades, porque `decimalText` era privado | **Aplicado.** `decimalText` pasa a interno —precedente exacto: `MotionBlockedView.settingsURL`— y `WalkTrackerTests/UI/SettingsViewTests.swift` afirma `strideMeters(fromText: decimalText(x, L)) == x` sobre diez regiones, incluidas cuatro de numeración no latina y tres formas de agrupamiento. **Se arregla el que escribe, no el que lee**: enseñar al parser a entender cada locale lo haría depender del locale del sistema, y el parser vive en el dominio (AD-3) |

### C · Mensajes que mentían (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 5 | 400 dígitos desbordan a `inf` y `validateStride` los rechazaba con el motivo del cero: "La zancada tiene que ser mayor que cero", para un número que no es ni cero ni negativo | **Aplicado.** `AppSettings.isRepresentableStride(_:)` separa el motivo en el dominio y `rejected(.tooLarge)` le da su texto. Con test en los dos niveles |
| 6 | Con el disco caído, el resultado seguía siendo `.saved` y la pantalla decía "Zancada guardada. La siguiente caminata la usará." de un valor que desaparecía al relanzar | **Aplicado.** `save()` devuelve si escribió —sin propagar el error— y `.notPersisted` tiene su mensaje: se usa ahora, no quedó guardado. `diskFailureKeepsTheValueInMemory` **se conserva**; lo que cambia es lo que afirma del mensaje |
| 7 | `strideOutcome` solo se apagaba al escribir: salir de Ajustes y volver enseñaba el mensaje de hace diez minutos | **Aplicado.** `strideScreenDidDisappear()` atada al `.onDisappear`, con test |

### D · Accesibilidad y uso (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 8 | Nada anunciaba el mensaje: el foco se queda en Guardar y un usuario ciego no oía nada | **Aplicado.** `AccessibilityNotification.Announcement`, el precedente de "Sesión recuperada" (1.6). El texto se escribe una sola vez: `message(for:)` devuelve `String(localized:)` y lo usan la fila y el anuncio |
| 9 | El objetivo táctil estaba en el `LabeledContent`: hacía alta la fila, no el área tocable del campo | **Aplicado.** El marco y el `.contentShape` van en el `TextField`, que además se estira a lo ancho del contenido |
| 10 | Etiqueta de accesibilidad duplicada: VoiceOver leía la del `TextField` y la visible del `LabeledContent` | **Aplicado.** Queda **una**, la visible, que ahora lleva la unidad ("Longitud de zancada, en metros"); fuera la `accessibilityLabel` y su entrada del catálogo |
| 11 | El `.decimalPad` no tiene tecla de retorno: la única forma de cerrarlo era pulsar Guardar, y con el teclado abierto el mensaje y el botón pueden quedar debajo | **Aplicado aquí, no en la épica 3**: es el primer `TextField` del producto y fija el patrón. Barra de teclado con "Listo" y `.scrollDismissesKeyboard(.interactively)` |

### E · Gates y coherencia (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 12 | `SettingsStore.save()` dejó de ser privado y **ningún gate lo cubría**; el comentario del fichero afirmaba en falso que "la sección 9 lo comprueba", cuando la 9 solo mira llamadas al puerto | **Aplicado.** `save` entra en la lista de la sección 6 (casos rojo en `UI/` y `App/`, y verde para `saveStride`/`clearStride`); el comentario dice ahora qué comprueba cada sección. Y el hueco equivalente dentro de `Application/` —`settings.settings = …`, `settings.save()` desde `SessionStore*.swift`, que la sección 6 no mira— se cierra con la **sección 9b**, con tres casos rojos y dos verdes |
| 13 | La 2.3 metió `SettingsStoreStrideTests`, un suite de `Application/`, en `verify-domain.sh`, que hasta ahora solo llevaba `Domain/` y `Vectors/` | **Aplicado: se saca.** El criterio no cambia, y está escrito desde la 1.1 (B3, rechazado): el gate es de dominio (AD-6) y la suite completa los ejecuta. El comentario del script lo dice ahora explícitamente. `AppSettingsTests` se queda: es de `Domain/` |
| 14 | Deriva en el String Catalog: el comentario de la entrada con `%@` era más rico que el `comment:` del código, y `SWIFT_EMIT_LOC_STRINGS` lo habría perdido al regenerar | **Aplicado.** Los dos textos son idénticos, comprobado sobre las 14 cadenas de la pantalla |
| 15 | El aviso de rango metía la conjunción dentro del marcador (`"0,3 y 1,2"`), y `humanRangeText` formateaba sin locale mientras `decimalText` sí lo recibía | **Aplicado.** Dos marcadores en el mensaje y `humanRangeBounds(locale:)`, con test de los dos extremos en dos regiones |
| 16 | Parámetro muerto: nadie pasaba `locale` a `decimalText` | **Aplicado.** Queda en uso de verdad: lo pasa `SettingsViewTests` en cada región, y es el parámetro sobre el que se apoya el arreglo del punto 2 |
| 17 | `CodingKeys` redundante en `SettingsFileAdapter.File` | **Aplicado.** Fuera: Swift la sintetiza aunque `init(from:)` sea propio. El init por miembros se queda, que ese sí hay que restaurarlo |

### F · Contabilidad (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 18 | Frontmatter y `sprint-status.yaml` | **Aplicado.** `status: in-review`, `review_loop_iteration: 1`, y la 2.3 a `review` como sus hermanas |
| 19 | Review Triage Log vacío | **Aplicado**: esta sección |
| 20 | Spec Change Log vacío | **Aplicado**: la decisión del punto 1 y la fila nueva de la matriz |

### Rechazado

| # | Hallazgo | Veredicto |
|---|---|---|
| — | "Los tests de `SessionStore` no están en `verify-domain.sh`" | **Rechazado por precedente.** Es literalmente el hallazgo B3 (resto) de la `spec-1-1`, rechazado allí con la misma razón: el gate es de dominio (AD-6) y la suite completa los ejecuta. Añadirlos convertiría un gate de dominio en un segundo runner de la suite, y es justo el criterio que el punto 13 aplica en el otro sentido |

### Diferido (registrado en `deferred-work.md`, no arreglado)

- **El contrato vista↔store.** Que Guardar llame a la intención, que editar limpie el mensaje,
  que salir la apague y que cada resultado pinte **su** texto no lo fija ningún test: borrar la
  línea de Guardar de `SettingsView` o intercambiar dos ramas del `switch` deja toda la suite
  verde. Exige renderizar una vista, y A-4 sigue abierto. La entrada ya registrada se revisó y
  se corrigió: citaba un `.onChange(of: text)` y un `.frame` de la fila que esta pasada cambió
  de sitio. Lo que sí queda cubierto ahora sin renderizar: que cada resultado tenga un texto
  **distinto** y que el del disco fallido no diga "guardada" (`SettingsViewTests`).

## Design Notes

**Por qué override opcional y no campo con valor.** `domain-model.md:95` modela `config.strideM` con
el 0,655 dentro. Seguirlo al pie de la letra duplica el default en `formulas.json` y en
`settings.json`, y dos copias divergen en cuanto alguien toque una. Con `nil` = "sin configurar", el
default vive en un solo sitio y quien nunca tocó el ajuste se beneficia si mejora. La divergencia con
el modelo es deliberada y queda aquí escrita.

**Por qué el rango avisa y no bloquea.** El dominio acepta 0,001 m y 50 m: los dos son "válidos" y
los dos falsean toda distancia futura en silencio. Pero 0,3–1,2 m es una regla de producto, no del
dominio, y bloquear inventaría un límite que el modelo no tiene. Avisar cubre el dedazo real —0,067
por 0,67— sin quitarle a Paul el control de su propia app.

**Lo que no se puede verificar y por qué** (va a `deferred-work.md`): que el historial no cambie al
recalibrar **no es demostrable en esta historia** — no existe registro de sesiones cerradas hasta la
5.1, así que un test solo comprobaría que un `let` es un `let`, cosa que ya garantiza el compilador.
Y lo que exige renderizar una vista: que el campo se vea, que Guardar guarde, que el mensaje aparezca
y desaparezca, el teclado decimal y su descarte, los 44 pt reales, VoiceOver y Dynamic Type. A-4
sigue abierto. Mitigación con precedente: la decisión vive en el store y **eso** se prueba.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — verde (227 tests en 15 suites); el inventario no cambia (los
  vectores `recalibrate` siguen muertos). La lista de `-only-testing:` suma `AppSettingsTests`,
  de `Domain/`, y **no** `SettingsStoreStrideTests`, que es de `Application/`: el gate es de
  dominio y la suite completa lo ejecuta (precedente `spec-1-1`, B3).
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes, con la sección 9
  reconociendo `SettingsStore+Stride.swift` y la 12 sin violaciones en la pantalla nueva.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED,
  609 tests en 49 suites, sin warnings propios.
- `bash Scripts/check-project-shape-tests.sh` — 161 casos verdes (9 nuevos: `save` en la sección
  6 y la sección 9b, con sus verdes).
- **Mutación obligatoria:** dejar que `openSession()` siga leyendo el `let` del store debe hacer
  fallar el test del criterio central. Si no falla, el test no vale. **Comprobada otra vez en la
  revisión** (2026-09-19): `let strideM = defaultStrideM` deja en rojo
  `recalibratedStrideAppliesToTheNextSession` (0,655 donde esperaba 0,670) y
  `strideFromDiskAppliesToTheFirstSession`, y nada más.
- **Mutaciones de la revisión**, cada una comprobada y revertida:
  - Formatear con el locale del sistema, sin fijar numeración ni quitar agrupamiento y con tres
    decimales → `SettingsViewTests` en rojo con los tres defectos reproducidos: `٠٫٦٥٥` y
    `۰٫۶۵۵` sin parsear, `10.000,000` → `nil`, y `0,6789` sembrado como `0,679`.
  - Volver a contar el fallo de disco como `.saved` → `diskFailureKeepsTheValueInMemory` en rojo.
  - `settingsStore.save()` escrito en `SettingsView` → el gate lo caza por la sección 6.
  - Vaciar el cuerpo de `clearStride()` dejando solo el resultado → cuatro tests del botón en
    rojo, entre ellos el que exige que el fichero cambie.

**Manual checks (iPhone, no hay target de UI tests):**
- Ajustes → zancada: escribir `0,670` con coma, Guardar, y que la siguiente caminata la use sin
  reiniciar la app.
- Escribir `0`, vaciar el campo y escribir letras: mensaje en línea y nada guardado.
- Escribir `0,067`: se guarda y avisa de que está fuera de lo normal.
- Con el texto al máximo y con VoiceOver: etiqueta, valor y error se leen y no se recortan, y el
  mensaje del último Guardar **se anuncia** sin tener que buscarlo con el foco.
- Con el teclado decimal abierto: "Listo" lo cierra, y desplazar la pantalla también.
- Guardar un dedazo (`0,067`), pulsar "Usar el valor por defecto" y comprobar que la siguiente
  caminata vuelve al 0,655 sin reiniciar; y que al salir de Ajustes y volver no queda ningún
  mensaje en pantalla.
