---
title: '2.2 — Frase motivacional al iniciar sesión'
type: 'feature'
created: '2026-09-19'
baseline_commit: '54f6785b2219991cb7b1f25247ff390c7a918b97'
status: 'done'
route: 'dispatch'
review_loop_iteration: 1
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
  - '{project-root}/_bmad-output/specs/spec-walktracker-ios/domain-model.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** al empezar una caminata no pasa nada entre pulsar "Iniciar caminata" y verse la pantalla de
sesión. CAP-6 pide un empujón mental: una frase del banco de 100, distinta de las últimas 20, durante
unos segundos y saltable con un tap.

**Ojo — esto no es una portación.** El `quoteId` **nunca llegó a escribirse en la v3**:
`createV3Session` no lo declara y nada en `index.html` lo asigna; la única aparición lo *lee* al
persistir, así que siempre guardó `undefined`. `domain-model.md` lo lista en los shapes como si
existiera. Hay motor v3 que portar (`motivation.js`: selección y ventana de 20) pero **no hay conducta
previa que replicar para el `quoteId` ni datos históricos que la validen**: esa parte es nueva.

**Enfoque:** un `MotivationEngine` puro en el dominio que elige frase con `RandomPort` excluyendo las
recientes; el banco se lee del bundle como ya se leen `achievements.json` y `formulas.json`; la frase
se adjunta a la sesión y viaja en el snapshot; y la ventana de 20 persiste en un `settings.json`
nuevo, cuya infraestructura crea esta historia. El overlay vive sobre la sesión ya corriendo.

## Boundaries & Constraints

**Always:**
- **La sesión arranca primero y el overlay va encima.** Cuando la frase aparece, el cronómetro ya
  cuenta y los pasos ya se cuentan (CAP-6). Nunca al revés.
- **El dominio no conoce el azar ni el reloj:** la elección entra por `RandomPort` (AD-3, AD-10, que ya
  nombra a `MotivationEngine` como su motivo de existir). El motor es puro y vectorizable.
- **Ventana de 20, con su regla heredada:** se excluyen las últimas 20; si eso vacía el banco, se
  ignora el filtro y se elige de todo. Máximo 20 ids, FIFO.
- **`quotes.json` es contenido congelado:** las 100 frases se reutilizan íntegras, sin cambios de texto.
- **El overlay cumple la sección 12 del gate desde el primer commit**: tokens de `UI/Style/`, nada de
  radios, hexadecimales, `.orange` ni valores de la escala cableados.
- **La vista no escribe el estado** (sección 6 del gate): el tap es una intención del store
  (`dismissQuote()`), como `dismissRecoveredNotice()`.
- Accesibilidad: VoiceOver anuncia la frase como contenido modal; Dynamic Type sin recortes con la
  frase más larga; con Reduce Motion aparece sin fundido.

**Decisiones de Paul (2026-09-19):**
- **La 2.2 crea `settings.json` y su dueño**, con lo que eso arrastra: ampliar el puerto de
  almacenamiento, declarar el dueño nuevo en la sección 9 de `check-project-shape.sh` (no saltársela) y
  cerrar el diferido del "Ahora no" de la 2.1, que esperaba exactamente esta pieza.
- **Duración del overlay: 3 segundos**, como la v3, con holgura frente al criterio "antes de los 4 s".
- **Banco ausente o inválido: se degrada.** No hay frase y la caminata sigue, con registro en el log.
  **No** se mata el arranque, a diferencia del catálogo de logros (AD-5).

**Never:**
- Bloquear, retrasar o condicionar el arranque de la sesión a que haya frase.
- Guardar `recentQuoteIds` dentro de `activeSession.json`: no es estado de sesión viva.
- Un botón de cerrar en el overlay, el fondo acento a pantalla completa de la v3 (derogado), o guiarse
  por los mockups v3 en lugar de por el contexto del épico.
- Tocar el texto de las 100 frases, el clima (2.1), ni la extensión de Live Activity.
- Recategorizar los sitios `math-random` del inventario de vectores: toca `baseline` y `totals`, y es
  trabajo aparte.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Caso normal | banco de 100, `recentQuoteIds` con 20 | se elige una de las 80 restantes; `quoteId` en la sesión; la ventana pasa a contenerla | — |
| Ventana vacía | `recentQuoteIds` vacío | se elige de las 100 | — |
| Todas excluidas | banco de 3, ventana con esos 3 | se ignora el filtro y se elige de los 3, **con `log.info`**: el fallback no puede ser silencioso | — |
| Banco vacío | `quotes.json` con `[]` | no hay frase, no hay overlay, la sesión sigue | — |
| Banco ausente o corrupto | fichero borrado o JSON inválido | no hay frase, la sesión sigue, `log.error` | no se mata el arranque |
| Ventana con ids fantasma | `recentQuoteIds` con ids que no están en el banco | se ignoran; la selección funciona igual | — |
| 20 sesiones seguidas | 20 arranques consecutivos | ninguna frase repetida en la secuencia | — |
| Tap antes de tiempo | overlay visible, tap | se descarta ya; la sesión seguía corriendo debajo | — |
| Auto-descarte | overlay visible, 3 s sin tocar | se descarta solo | — |
| Relanzar tras force-quit | snapshot con `quoteId` ya guardado | la sesión se recupera **sin volver a mostrar el overlay**: "ya mostrada" no es lo mismo que "hay quoteId" | — |
| Snapshot antiguo | fichero de esquema 1 o 2 | se lee sin frase, no se aparta | — |
| Ajustes ausentes | sin `settings.json` (primera vez) | ventana vacía, se elige de las 100, y el fichero se crea al guardar | — |
| Ajustes corruptos | `settings.json` inválido | se parte de ventana vacía; no se pierde la sesión | se aparta como hace el snapshot |

</frozen-after-approval>

## Code Map

**Dominio**
- `Domain/Session/Session.swift:212-220` `attachWeather(_:)` — **el molde exacto** para `attachQuote(_:)`:
  congela al primer valor y lanza si la sesión está `finished`. Su rama en `restore(…)` (`:101,117`).
- `Domain/Ports/` — `RandomPort` es nuevo pero **ya está en el conjunto cerrado de 11** de AD-10
  (`ARCHITECTURE-SPINE.md:188-190`), que lo justifica nombrando a `MotivationEngine`. Es el único puerto
  del conjunto sin consumidor previo: su firma fija cómo se vectoriza todo lo aleatorio futuro.
- El motor v3 a portar: `motivation.js:28` `selectQuote` y `:48` `updateRecentIds`
  (`new Set(recentQuoteIds.slice(-20))`, filtro, y si no queda nada elige del banco entero).
- `domain-model.md:63-66` (MotivationEngine) y `:94-103` (shapes). **No hay §27**: el fichero tiene 9
  secciones; lo que la historia cita como §27 son §5 y §8.

**Vectores (AD-6)**
- `WalkTrackerTests/Vectors/selectQuote.json` (1 vector: banco vacío → nil) y `updateRecentIds.json`
  (1 vector: tope de 20). **Ya escritos**; en Swift figuran como *pending*.
- `WalkTrackerTests/Support/VectorHarness.swift:188-194` — registrar ahí las dos funciones y sus
  traductores; luego un test `…IsPorted()` por función, como `DomainVectorTests.swift:161-169`.
- `Scripts/verify-domain.sh:69-80` — **la lista de `-only-testing:` es explícita**: un suite nuevo que
  no se añada a mano no se ejecuta en el gate y nadie se entera.

**Aplicación**
- `WalkTracker/Application/SessionStore+StartFlow.swift:90-103` `openSession()` — el orden es el
  contrato: `Session.start` → `session` → `metrics` → `hasSession = true` → `countSteps` →
  `measureTransition(.start)` → `persist()` → `beginWeatherForNewSession()`. La frase entra **después de
  `hasSession = true`** y **antes de `persist()`**, o el `quoteId` se pierde si hay force-quit temprano.
- `WalkTracker/Application/SessionStore+Weather.swift` — el precedente de forma (extensión propia,
  nunca bloquea, el store valida y escribe en el agregado). La frase es **síncrona y local**: no
  necesita `Task`, ni `FirstResult`, ni timeout.
- `WalkTracker/App/CompositionRoot.swift:80-103` — `loadAchievementCatalog(from:)` y
  `bundledAchievementCatalogOrTerminate()`: el patrón para leer del bundle. **La política de fallo
  diverge** por decisión de Paul: aquí se degrada, no se termina.

**Ajustes (infraestructura nueva de esta historia)**
- `Domain/Ports/StoragePort.swift:17-18` — dice literalmente que los ajustes llegan con la 5.1: hay que
  ampliar su alcance (o añadir un puerto hermano) y **actualizar ese comentario**.
- `Scripts/check-project-shape.sh:354-381` (sección 9) — limita las llamadas de almacenamiento a
  `SessionStore*.swift` y al adapter. El dueño nuevo **se declara ahí**, no se esquiva.
- No hay `UserDefaults` en ningún punto del árbol Swift, ni `settings.json`, ni `SettingsStore`.
- `_bmad-output/implementation-artifacts/deferred-work.md` — el diferido del "Ahora no" de la 2.1
  apunta a "la historia que cree `settings.json`": **es esta**. Ciérralo o re-apúntalo explícitamente.

**Persistencia**
- `WalkTracker/Adapters/Persistence/ActiveSessionFileAdapter.swift:28-30` — esquema **2** hoy, lee
  `1...2`. Sube a **3** leyendo `1...3`, con `quoteId` opcional al decodificar, igual que
  `weather: version >= 2 ? … : nil` (`:203`). Tocar `File` (`:131-147`), `decode` (`:189-204`) y
  `encode` (`:224-250`).
- `Domain/Ports/ActiveSessionSnapshot.swift:7` — su doc comment **ya anuncia esta historia**.

**UI**
- `WalkTracker/UI/Session/SessionView.swift:141-146` — `.task(id:)` del aviso "Sesión recuperada": el
  molde del temporizador de 3 s con su anuncio de VoiceOver. **Trampa conocida:** se re-dispara con el
  `id`; si el `id` fuera `store.quote`, una sesión recuperada con `quoteId` volvería a mostrar el
  overlay. El estado "ya mostrada" es distinto de "hay quoteId".
- `SessionView.swift:156-167` — `.safeAreaInset` con `LocationPermissionView` y su transición atada a
  `reduceMotion` (`:62`): cómo se presenta una capa y cómo se respeta Reduce Motion.
- **No hay ningún `.sheet` en el proyecto.** El overlay va sobre `SessionView`, que ya es el
  `fullScreenCover` de `RootView.swift:60-62` (AD-14).
- `WalkTracker/UI/Style/DesignTokens.swift` — `Spacing` (4/8/12/16/24), `LayoutMetrics`
  (margin 16, touchTargetMin 44, heroSize 88), `Radius.card` 20, `Surface`, `Typography`, `Colors`.
  La **sección 12** del gate prohíbe reteclear cualquiera de esos valores; los tres patrones más
  probables en un overlay —`.frame(maxWidth: 320)`, `cornerRadius: 24`, `.padding(24)`— caen los tres.
- `quotes.json` está ya en la raíz del repo: hay que **moverlo a `WalkTracker/Resources/`**, junto a
  `achievements.json` y `formulas.json`, para que entre en el bundle por `project.yml:98`.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Ports/RandomPort.swift` — puerto nuevo, firma mínima y vectorizable.
- [x] `Domain/Motivation/QuoteBank.swift` + `MotivationEngine.swift` — decodificación del banco y la
      selección pura (exclusión, fallback con log, ventana FIFO de 20).
- [x] `Domain/Session/Session.swift` — `quoteId` y `attachQuote(_:)` con el molde de `attachWeather`.
- [x] `WalkTracker/Resources/quotes.json` — mover el banco desde la raíz del repo.
- [x] `Domain/Ports/StoragePort.swift` + `Domain/Ports/AppSettings.swift` + `Adapters/Persistence/`
      — ajustes persistentes (`settings.json`), con escritura atómica y apartado de ficheros
      corruptos como ya hace el snapshot.
- [x] `WalkTracker/Application/SettingsStore.swift` — el dueño único de los ajustes.
- [x] `Scripts/check-project-shape.sh` (sección 9) — declarar el dueño nuevo; y sus casos en
      `check-project-shape-tests.sh`.
- [x] `Adapters/Persistence/ActiveSessionFileAdapter.swift` — esquema 3 con `quoteId`, leyendo 1…3.
- [x] `WalkTracker/Application/SessionStore+Motivation.swift` — elegir y adjuntar en `openSession()`,
      el estado del overlay y `dismissQuote()`.
- [x] `WalkTracker/UI/Session/QuoteOverlay.swift` — la vista, escrita contra la sección 12 del gate.
- [x] `WalkTrackerTests/Support/VectorHarness.swift` + `DomainVectorTests` — registrar `selectQuote` y
      `updateRecentIds` y su test `…IsPorted()`.
- [x] `Scripts/verify-domain.sh` — añadir a mano los suites nuevos a la lista de `-only-testing:`.
- [x] Tests de la matriz, incluido el de **20 sesiones consecutivas sin repetición** con stubs.
- [x] `deferred-work.md` — cerrar o re-apuntar el diferido del "Ahora no"; registrar lo no verificable.

**Acceptance Criteria:**
- Dada una sesión que arranca, cuando aparece la frase, entonces el cronómetro ya corre por debajo.
- Dadas 20 sesiones consecutivas, cuando se revisa la secuencia, entonces no hay frase repetida — y
  esto se comprueba **en un test**, no a ojo.
- Dado un relanzamiento tras force-quit con sesión viva, cuando se recupera, entonces el overlay **no**
  vuelve a salir.
- Dado `verify-domain.sh`, cuando se ejecuta, entonces `selectQuote` y `updateRecentIds` ya no aparecen
  en la línea de pendientes de AD-6.

## Implementation Notes

**Un puerto, dos ficheros, dos dueños.** `StoragePort` se amplió en vez de añadir un puerto
hermano: AD-10 fija un conjunto cerrado de **11** y `RandomPort` ya era el undécimo, así que un
`SettingsPort` habría hecho doce. Lo que el compilador deja de separar —los dos dueños ven el
mismo protocolo— lo separa la sección 9 del gate, que ahora es una función parametrizada
(`storage_owner_rule`) con un caso por fichero: `(load|save|clear|setAside)ActiveSession` solo en
`SessionStore*.swift`, `(load|save)Settings` solo en `SettingsStore.swift`. Va en los dos
sentidos, y hay caso rojo de cada uno.

**Reparto en `Adapters/Persistence/`.** Las garantías de disco (escritura atómica por `rename(2)`,
apartado con `RENAME_EXCL`, directorio creado al vuelo) eran idénticas para los dos ficheros, así
que salieron a `JSONFileStore`; el formato —esquemas, milisegundos, saneado— sigue en cada
adapter. `ActiveSessionFileAdapter` **dejó de conformar `StoragePort`** (solo cubre uno de los dos
ficheros) y quien lo conforma es `FileStorageAdapter`, que solo reparte. Sus métodos siguen
existiendo con la misma firma, así que ningún test suyo cambió por esto.

**El azar entra por su puerto, y por eso "20 sin repetir" es un test.** `RandomPort` tiene una
sola operación —`index(below:)`—: cubre toda elección sobre una colección y un doble determinista
cabe en tres líneas. El test de las 20 caminatas usa el azar **más adverso posible**, siempre el
índice 0: sin la ventana de recientes las 20 serían la misma frase. Lo mismo a nivel de store,
montando 20 fixtures sobre un único `StorageStub` para que la ventana sobreviva a cada cierre.

**El fallback ya no es silencioso.** `MotivationEngine.selectQuote` devuelve
`Selection { quote, ignoredRecentWindow }` en vez de la frase pelada, siguiendo el precedente de
`GapEstimator.Outcome`: el dominio no registra nada, señala, y `SessionStore+Motivation` escribe el
`log.info` con el tamaño de la ventana que provocó el fallback.

**La trampa del `.task(id:)`, resuelta por construcción.** `store.quote` solo lo enciende
`openSession()`; `restoreOnLaunch()` devuelve el `quoteId` al agregado y lo deja en `nil`. Como el
`.task(id:)` vive **dentro** del `if let quote` del overlay, una sesión recuperada no lo monta y no
hay temporizador que redisparar. Hay test de los dos lados: el `quoteId` vuelve y el overlay no.

**Saneado de la ventana en la frontera.** `recentQuoteIds` se recorta a las **últimas** 20 tanto al
leer como al escribir `settings.json`, y `selectQuote` aplica `suffix(20)` otra vez sobre lo que
reciba. Unos ajustes manipulados con 500 ids no pueden dejar al motor excluyendo medio banco.

**`quotes.json` se movió con sus referencias.** Además de entrar en `WalkTracker/Resources/`, se
actualizaron las tres rutas de la referencia v3 que lo cargaban (`test/motivation-tests.js`,
`sw.js`, `index.html`): mover el fichero sin ellas habría dejado la suite legacy y la PWA con un
404 que ningún gate mira. El contenido no se tocó — sigue siendo el banco congelado de 100.

**El invariante de la ventana vive en `AppSettings`, no en cada frontera.** La revisión encontró
que unos ajustes con 20 ids **repetidos** (`[5, 5, 5, …]`) pasaban todos los topes y dejaban la
exclusión real en **una** frase, sin disparar `ignoredRecentWindow`. El arreglo no fue añadir un
tercer saneado: `recentQuoteIds` pasó a `private(set)` y el único `init` —más un
`setRecentQuoteIds(_:)`— **normaliza**, deduplicando por la aparición más reciente y recortando a
`MotivationEngine.recentWindow`. Con eso el tope deja de vivir por convención en tres sitios
(motor, `decode`, `encode`) y la 2.3 puede colgar ahí el "> 0 y finita" de `strideM` sin repetir
la historia. **`MotivationEngine.updateRecentIds` no se tocó**: que no deduplique es paridad
deliberada con la v3 y está en el bloque congelado; quien deduplica es el tipo que lo guarda.

**El banco no se puede construir sin validar.** `QuoteBank(quotes:)` era un init por miembros y
`validate()` era pública y esquivable, así que un banco con ids repetidos dejaba un gemelo
seleccionable y la ventana excluía solo a uno de los dos. Ahora el único init público lanza,
`validate()` es privada y el único camino sin validar es un init privado que solo usa `.empty`.

**Un fichero del futuro no es un fichero corrupto.** `SettingsFileAdapter` apartaba cualquier
`schemaVersion` desconocida, también una **mayor** que la que escribe: instalar un build anterior
habría costado la ventana —y mañana el `strideM` de la 2.3— al volver a la versión nueva. Ahora
una versión mayor devuelve `AppSettings.defaults` y **deja el fichero donde está**; solo se aparta
lo que de verdad no se puede leer. Y si el apartado falla tras un fallo de decodificación, se
registra el fallo de apartado y se propaga el error **original**, que es el que explica algo.
Esto **afina** la fila "Ajustes corruptos" de la matriz congelada, no la contradice: un fichero de
un esquema mayor no es un fichero *inválido*, es uno que esta versión no sabe leer todavía.

**La lectura y la escritura síncronas de ajustes se quedan como están, y por qué.** Leer
`settings.json` en el `init` de `SettingsStore` y escribirlo dentro de `openSession()` son
coherentes con el diseño que ya existía, no un descuido: `persist()` ya es síncrono y ya se
llamaba desde `openSession()`, y `CompositionRoot` ya lee `achievements.json` y `formulas.json`
del bundle en su propio `init`. Los dos ficheros ocupan unos cientos de bytes y la alternativa
—un `load()` asíncrono que alguien pueda olvidarse de llamar— cambiaría el contrato de arranque
de la sesión por un beneficio que nadie ha medido. Se deja dicho para que la 2.3 no lo redescubra.

**Decisión sobre el diferido del "Ahora no".** Se **re-apuntó a la 2.3**, no se cerró. La 2.2
entregó la pieza que bloqueaba (`settings.json` + `SettingsStore`), pero lo que queda del diferido
es tocar el flujo del clima de la 2.1 —que la Intent congelada pone fuera de alcance ("Never: …
tocar el clima (2.1)")— y ofrecer el permiso desde Ajustes, que necesita la pantalla de la 2.3.
Queda con destino explícito y con la razón escrita en `deferred-work.md`.

## Spec Change Log

**2026-09-19 · Corrección de hecho en la Intent (del autor de la spec, no del implementador).**
La Intent congelada afirma que en la v3 "la única aparición [del `quoteId`] lo *lee* al
persistir". Es **inexacto**: `migration.js:50` también lo **escribe** —`quoteId: v1.quoteId ||
null`— al migrar una sesión v1 a v3. El fondo de la afirmación se sostiene y la decisión de
alcance no cambia: la v1 nunca tuvo `quoteId`, así que esa línea siempre escribió `null`, y
sigue sin haber **conducta previa que portar** ni datos históricos que la validen. El error es
mío al redactar la Intent, no del implementador, que trabajó sobre lo que la Intent decía.
**El texto congelado no se edita** —eso exigiría renegociarlo con el humano que lo firmó—: queda
aquí la corrección, y cualquier lectura futura de esa frase debe leerse con esta nota al lado.

## Review Triage Log

**2026-09-19 · Tres lentes de revisión sobre la implementación de la 2.2.** 26 hallazgos.
Veredicto: **24 aplicados**, 2 aceptados sin cambio con su razón escrita, 3 registrados como
diferidos. Ninguno rechazado.

### A · Huecos de verificación (aplicados, con mutación comprobada)

| # | Hallazgo | Veredicto |
|---|---|---|
| 1 | El cableado de `quotes`/`random`/`settings` en `CompositionRoot` no lo fijaba ningún test: borrar `quotes: quotes` compila (el `init` tiene `quotes: .empty`) y la suite seguía verde — la app publicada no habría enseñado ni una frase | **Aplicado.** Cuarto caso en `CompositionRootTests`, comportamental como los tres anteriores: arranca una sesión del root y exige frase, `quoteId`, banco de 100, `random.counts == [100]` y la ventana escrita por el `settingsStore` cableado |
| 2 | `QuoteBankTests.compositionRootDegrades` afirmaba en su título algo que su cuerpo no comprobaba: montaba un `SessionStoreFixture(quotes: .empty)` y nunca tocaba `CompositionRoot` ni `bundledQuoteBankOrEmpty()` | **Aplicado.** `bundledQuoteBankOrEmpty(from:)` pasa a interno con parámetro de bundle, como su vecino `loadQuoteBank`; el test nuevo comprueba la degradación de verdad contra un bundle sin `quotes.json`, y el caso viejo se **renombró** para que su título diga lo que hace |
| 3 | `SystemRandom` no tenía ni un test, siendo el único `RandomPort` de producción | **Aplicado.** `WalkTrackerTests/Adapters/SystemRandomTests.swift`: `nil` sin colección, el índice siempre en `0..<count` en cientos de tiradas, los dos extremos alcanzados, y el banco real de 100 |
| 4 | El fallback de la ventana no se ejercitaba a nivel de store: convertir el `if` en un `return` dejaba todo verde y al usuario sin frase | **Aplicado.** Caso nuevo con `bank(3)` y ventana `[1, 2, 3]`: hay frase, se adjunta, el id cae en la ventana y entra en el primer snapshot |

### B · Defectos de comportamiento (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 5 | El tap "en cualquier punto" no funcionaba en el centro: el `ScrollView` se comía el toque sobre el propio texto, que es la salida principal | **Aplicado.** `.contentShape(.rect)` + `onTapGesture` también en el contenido del scroll, además del que ya había en el `ZStack` |
| 6 | `confirmFinish()` paraba el podómetro y cancelaba el clima pero dejaba `store.quote` puesto | **Aplicado**, junto a lo demás, con test propio |
| 7 | Un `settings.json` de un esquema **más nuevo** se apartaba y perdía la ventana | **Aplicado.** Devuelve los ajustes por omisión y deja el fichero donde está; se aparta solo lo ilegible de verdad |
| 8 | Un fallo de `setAside()` tras un fallo de decodificación enmascaraba el error real | **Aplicado** en los dos adapters hermanos: se registra el fallo de apartado y se propaga el error de decodificación original |
| 9 | `QuoteBank(quotes:)` se podía construir saltándose `validate()`, dejando un gemelo seleccionable con ids duplicados | **Aplicado.** Init único que valida y lanza; `validate()` privada; el camino sin validar es privado y solo lo usa `.empty` |

### C · Coherencia del vocabulario y de los ajustes (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 10 | Una ventana de 20 ids **repetidos** pasaba todos los guardias y dejaba la exclusión real en una frase, sin disparar `ignoredRecentWindow` | **Aplicado.** Se deduplica al leer —conservando el orden y la aparición más reciente—, y `MotivationEngine.updateRecentIds` **no se toca**: su "no deduplica" es paridad deliberada con la v3 y está congelado |
| 11 | `AppSettings.recentQuoteIds` no tenía invariante y el tope de 20 vivía por convención en tres sitios | **Aplicado.** `private(set)` + init normalizador + `setRecentQuoteIds(_:)`; el tope y el dedup dejan de repetirse en `decode`/`encode`. Suite nueva `AppSettingsTests` |
| 12 | El gate de propiedad de ajustes usaba un glob y no el "fichero exacto" de su comentario: eximía de más y **bloqueaba `SettingsStore+Stride.swift`**, el patrón que usará la 2.3 | **Aplicado.** La regla pasa a "el fichero del dueño **y sus extensiones**" (`DUEÑO.swift` \| `DUEÑO+Algo.swift`), el comentario lo dice, y hay caso verde para `SettingsStore+Stride.swift` y rojo para `SettingsStoreKit.swift` |
| 13 | Dos fuentes de verdad para los nombres de fichero: los estáticos eran literales mientras la instancia los derivaba de `JSONFileStore(base:)` | **Aplicado.** Los nombres salen de `JSONFileStore.fileName(base:)` / `setAsideFilePrefix(base:)`, y cada adapter solo elige su `base`. Test que ata los estáticos al fichero en disco |
| 14 | `SessionStoreTestSupport.bank(_:)` hacía `max(1, count)`: `bank(0)` habría devuelto un banco de una frase | **Aplicado.** Fuera el `max`; `bank(0)` es el banco vacío |
| 15 | `RandomStub` tenía dos miembros sin usar y `MotivationEngineTests` declaraba conformancias locales equivalentes | **Aplicado.** Una sola forma: estrategias `.none` y `.outOfRange` en `RandomStub`; fuera `NoRandomStub`, `setStrategy` y los dos structs locales |

### D · Diagnóstico y accesibilidad (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 16 | El log del fallback registraba solo el tamaño de la ventana, que está topado a 20 y es casi constante: no distinguía "la ventana se corrompe" de "el banco encoge" | **Aplicado.** Registra también el tamaño del banco |
| 17 | Con `selectQuote` devolviendo `nil` por el puerto de azar, el log culpaba al banco vacío | **Aplicado.** Banco vacío → `log.info` (degradación esperada); puerto sin índice → `log.error` (fallo de verdad) |
| 18 | VoiceOver diría la frase dos veces: `Announcement` con el texto completo **y** el mismo texto como `accessibilityLabel` del modal | **Aplicado.** El anuncio pasa a una señal corta ("Frase motivacional") y la frase la lee el foco del modal, como el precedente, que anunciaba dos palabras |

### E · Documentación y contenido (aplicados)

| # | Hallazgo | Veredicto |
|---|---|---|
| 19 | Faltaban las cadenas nuevas en `Localizable.xcstrings` | **Aplicado.** Tres entradas con su `comment` ("Toca para continuar", la pista de VoiceOver y el anuncio corto), y los `comment:` puestos también en el código |
| 20 | `sw.js` cambió su lista de shell y dejó `CACHE = 'walktracker-v3.2'`: la ruta vieja sobrevivía en los clientes instalados | **Aplicado.** `v3.3` |
| 21 | `epic-2-context.md` perdió identificadores al recompilarse y dos puntos concretos de la retro del Epic 1 | **Aplicado.** Vuelven AR-1/10/12, UX-DR1/2/3/5/6/7, NFR-7, AD-3/5/6/7/9/10/11/13/14/16/19/22/24 y los punteros a `epics.md`, `ARCHITECTURE-SPINE.md`, `DEROGACIONES.md`, `deferred-work.md`, `DesignTokens.swift` y `release-testflight.sh`; y los dos huecos de S6 (`DegradationPolicy` ausente, `PermissionStatus.unavailable` bloqueante) vuelven como bullets propios |
| 22 | `quotes.json` es el único recurso empaquetado sin `schemaVersion` | **Aceptado sin cambiarlo** (es el fichero congelado de la v3) y **la asimetría queda escrita con su porqué** donde se decodifica, en `QuoteBank` |
| 23 | `QuoteBank.quote(id:)` no tiene llamador de producción y su comentario describía un sitio de render que no existe | **Aplicado.** Se conserva y el comentario se corrige: hoy solo lo ejercitan los tests, existe para el sentido inverso `quoteId` → texto que necesitarán el historial y el export del Epic 5 |
| 24 | Un riesgo conocido del gate (`verify-domain.sh`: lista de `-only-testing:` explícita, un suite nuevo no se ejecuta y nadie se entera) quedó como comentario en vez de registrarse | **Aplicado.** Registrado en `deferred-work.md` con destino, como manda la convención del repo |
| 25 | Error de hecho en la Intent sobre la única aparición del `quoteId` en la v3 | **Registrado** en el Spec Change Log; el bloque congelado no se edita |
| 26 | Review Triage Log vacío | **Aplicado**: esta sección |

### Aceptado con razón, sin cambio

- **La lectura síncrona de ajustes en el arranque y la escritura síncrona dentro de
  `openSession()`.** Coherentes con el diseño que ya existía —`persist()` ya era síncrono y ya se
  llamaba desde `openSession()`, y `CompositionRoot` ya lee `achievements.json` y `formulas.json`
  del bundle en su `init`—. No se cambia ahora; el porqué queda en Implementation Notes.
- **`updateRecentIds` no deduplica.** Paridad deliberada con la v3, y está en el bloque
  congelado. El riesgo que señalaba la revisión se mitiga en el punto 10: se deduplica al leer.

### Diferidos (registrados en `deferred-work.md`, no arreglados)

- La **presentación** del overlay: que se presente sobre la sesión en curso, que se auto-descarte
  a los 3 s y que el tap lo adelante, VoiceOver como modal, Reduce Motion sin fundido y Dynamic
  Type con la frase más larga. Exige renderizar una vista (A-4 abierto). La entrada ya registrada
  se **revisó y se dejó correcta**, con el tap sobre el texto y el "una sola vez" de VoiceOver.
- Que la **referencia v3 archivada** (`index.html`, `sw.js`, `test/motivation-tests.js`) dependa
  ahora de una ruta dentro del árbol de la app iOS: funciona y `test/motivation-tests.js` sí está
  cubierto por `check-inventory`, pero acopla dos cosas que deberían moverse por separado.
- El **riesgo del gate** de `verify-domain.sh` (hallazgo 24).

## Design Notes

**Por qué la frase no imita al clima.** La 2.1 necesitaba `Task`, topes y `FirstResult` porque la red
puede tardar o no volver. Elegir una frase es leer un array y pedir un número: síncrono y local. Copiar
la maquinaria asíncrona del clima sería cargar complejidad sin causa.

**El fallback silencioso es el riesgo sutil.** "Si todas están excluidas, ignora el filtro" es correcta
con 100 frases y ventana de 20 —inalcanzable— pero si la ventana se corrompe o el banco encoge, el
fallback se dispara **sin señal** y la promesa de "20 sin repetir" se rompe en silencio. La v3 lo hacía
sin log. Aquí lleva `log.info`.

**Lo que no se puede verificar hoy** y va a `deferred-work.md` con su evidencia: que el overlay se
presenta y que la sesión corre debajo; que se auto-descarta a los 3 s y que el tap lo adelanta; que
VoiceOver lo anuncia como modal; que con Reduce Motion no hay fundido; y Dynamic Type sin recortes con
la frase más larga. Todo eso exige renderizar una vista y sigue sin haber target de UI tests (A-4,
abierto). Mitigación con precedente: la decisión vive en el store (`store.quote`, `dismissQuote()`) y
**eso** sí se prueba; la presentación queda para el check manual en el iPhone.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — verde, y sin `selectQuote`/`updateRecentIds` en la línea de
  pendientes de AD-6.
- `bash Scripts/check-project-shape.sh` y `check-project-shape-tests.sh` — verdes, con la sección 9
  reconociendo al dueño nuevo de los ajustes.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO` — TEST SUCCEEDED, sin
  warnings propios.

**Manual checks (iPhone, no hay target de UI tests):**
- Iniciar caminata: la frase aparece con la sesión ya corriendo por debajo, y se va sola a los 3 s.
- Tocarla antes: se va al instante y el tiempo no se ha perdido.
- Con Reduce Motion activo: aparece sin fundido. Con VoiceOver: se anuncia como contenido modal.
- Con el texto al máximo: la frase más larga no se recorta.
- Forzar cierre con la sesión viva y relanzar: la sesión vuelve y **el overlay no reaparece**.
