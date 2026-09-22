---
title: '3.4 — Celebración de meta y logros, no bloqueante'
type: 'feature'
created: '2026-09-22'
status: 'in-progress'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '6c1fffcb5ae20a548482588f2c3f4e670825c232'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-4-1-canal-feedback.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-3-2-achievement-engine.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** La meta se cumple y los logros se desbloquean **en silencio visual**. La 4.1 ya
vibra en los dos sucesos, pero no se ve nada: `goalRingDidUpdate()` devuelve un `Bool` que se
**descarta**, y `SessionStore.unlockedAchievements` se rellena y nadie lo pinta — su propia doc
dice *"Es la señal, no la celebración… la celebración visible es de la 3.4"*.

**Approach:** La mitad visible, y **solo** la visible: un aviso transitorio con el molde que este
proyecto ya tiene —estado observable en el store, duración como constante de vista, `.task(id:)`
con anuncio de VoiceOver y una intención para descartarlo—. La háptica **no se toca**: ya la
dispara la 4.1, y el gate impide repetirla desde una vista.

## Boundaries & Constraints

**Always:**
- **No bloquea nada.** No es modal, no detiene el cronómetro, no impide seguir caminando ni tocar
  otra cosa. Se descarta al tocarlo o al vencer su tiempo.
- **Varios logros se encolan**, uno tras otro, sin solaparse. Hoy **no existe ninguna cola** en el
  proyecto: `store.quote` es un opcional único.
- La vista **no escribe estado del store**: llama a una intención, como hace
  `dismissRecoveredNotice()`. Lo exige la sección 6 del gate y es el patrón de la 1.6.
- Anuncio de VoiceOver desde el mismo `.task(id:)` que gobierna la aparición, con
  `AccessibilityNotification.Announcement`, que es el recurso que ya usan la 1.6, la frase y
  Ajustes.
- **Reduce Motion sin animación**: el dialecto `nil`/`.identity`, no un fundido más corto. Lo pide
  el criterio de aceptación —*"Reduce Motion sin animación"*— y es lo que ya hacen el overlay de
  la frase, el anillo y la insignia.
- Todo número visual nuevo entra en `DesignTokens.swift` (sección 12 del gate).

**Never:**
- **No se dispara háptica ni sonido.** Es de la 4.1 y del Epic 4. `store.feedback.fire(...)` desde
  `UI/` es error de la sección 6, y `import CoreHaptics`/`AVFoundation` lo es de la sección 10.
- No se toca `FeedbackAdapter`, ni `goalRingDidUpdate()` más allá de publicar su señal, ni
  `evaluateAchievements`.
- No se implementa el resumen completo (3.5) ni se añaden logros al `SessionSummaryView`: su doc
  dice hoy *"Sin logros ni celebración"*, y esa frase la cambia la 3.5, no ésta.
- No se unifican los dos dialectos de Reduce Motion que conviven en el árbol: se usa el correcto
  y se registra la unificación con destino.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Salida esperada | Error |
|---|---|---|---|
| Meta cumplida | `goalRingDidUpdate()` devuelve `true` | **un** aviso de meta | N/A |
| Meta ya celebrada | devuelve `false` | **ningún** aviso | N/A |
| Meta fuera de Inicio | la semana cambia con la app en otra pestaña | el aviso **no se pierde**: espera a que haya dónde mostrarlo | N/A |
| Un logro | el cierre escribe uno | **un** aviso con su nombre | N/A |
| Varios logros | el cierre escribe tres | **tres** avisos, uno tras otro, sin solaparse | N/A |
| Toque | aviso visible, Paul lo toca | se descarta **sin** detener la sesión ni el cronómetro | N/A |
| Vencimiento | nadie lo toca | se descarta solo, y pasa al siguiente si lo hay | N/A |
| Ninguno escrito | `achievements.json` ilegible | **ningún** aviso: no se celebra lo que no se guardó | N/A |
| Reduce Motion | activado | aparece **sin animación**, no con un fundido más corto | N/A |
| VoiceOver | aviso aparece | se anuncia, y el aviso es alcanzable y descartable | N/A |
| Camino del reintento | `leaveSummary()` reintenta y resetea | **ningún** aviso: la señal muere a propósito (4.1) | N/A |

</frozen-after-approval>

## Decisiones (2026-09-22)

**D1 — La señal de meta necesita estado observable; hoy el `Bool` se tira.**
`goalRingDidUpdate()` es `@discardableResult` y sus dos llamadores descartan el valor:
`HomeView.swift:91` y `weekMayHaveChanged()` (`SettingsStore+Goal.swift:199`, invocado desde
`RootView.swift:113` al volver a primer plano). Si la celebración dependiera de estar mirando
Inicio, **cumplir la meta con la app en otra pestaña se perdería sin celebrar**. Así que la señal
se publica como **estado observable en `SettingsStore`**, encendido cuando la función devuelve
`true` y apagado por una intención — exactamente el molde de `showsRecoveredNotice` de la 1.6.

**D2 — Dos puntos de enganche, no uno, y no es un parche.** El `fullScreenCover` de la sesión se
presenta **en su propia escena por encima del `TabView`** (`RootView.swift:104-106`), así que un
`.overlay` colgado del `TabView` no se ve dentro de la sesión. El precedente lo confirma: el
overlay de la frase cuelga **dentro** de `SessionView`, no arriba. Y encaja con dónde ocurre cada
suceso: la **meta** se cumple mirando Inicio o al volver a primer plano, y los **logros** al
cerrar la sesión, que es la superficie de `SessionView`.

**D3 — La cola es estado de presentación, no del store.** Varios logros se muestran uno tras
otro; la lista de los que faltan por enseñar es **de la vista**, como `showsReconcilingNotice`.
El store publica *qué se desbloqueó*; cuántos quedan por enseñar es una cuestión de pintado. Así
la sección 6 del gate se cumple sin excepciones y el store no crece con estado de UI.

**D4 — Reduce Motion: sin animación.** El criterio de aceptación lo dice y hay dos dialectos en
el árbol: `nil`/`.identity` (overlay de la frase, anillo, insignia) y `.easeInOut(0.2)` + fundido
(avisos en línea de `SessionView`). Se usa el primero. **La unificación de los dos se registra
con destino**: no es trabajo de esta historia decidir por las otras seis.

## Code Map

**Campos compartidos de `SessionStore` que toca este cambio** (regla (b) del A-7):
`unlockedAchievements` — **solo se lee**, nunca se escribe desde la vista. Su invariante: la
rellena `evaluateAchievements` con lo que **quedó escrito en disco** (`SessionStore+History.swift:144`)
y la vacía `resetSessionState()` (`SessionStore.swift:592`), al que llama `leaveSummary()`. **De
ahí sale la última fila de la matriz:** el camino del reintento la rellena y `leaveSummary()` la
vacía acto seguido, así que ahí no hay aviso — y **es deliberado**, está escrito en
`SessionStore+History.swift:152-161` como divergencia entre canales, porque la háptica sí suena.

**Las dos señales**
- **Meta:** `WalkTracker/Application/SettingsStore+Goal.swift:221-254` — `goalRingDidUpdate()`
  devuelve `true` la primera vez de cada semana; su doc (L216-220) ya dice que es *"la señal a la
  que se engancha la celebración visible de la 3.4"*, y en L251 ya dispara
  `feedback.fire(.goal, soundEnabled: false)`. **No es observable**: es un valor de retorno.
  Llamadores: `HomeView.swift:91` y `weekMayHaveChanged()` (L197-200) desde `RootView.swift:113`.
- **Logros:** `WalkTracker/Application/SessionStore.swift:164-177` — `unlockedAchievements`, **sí
  observable** (propiedad almacenada de un `@Observable`). Se rellena en
  `SessionStore+History.swift:144` con `written` —lo que **quedó escrito**, no lo evaluado—, y en
  L163 ya dispara `feedback.fire(.achievement, …)`.

**El molde del transitorio — copiarlo entero**
- `WalkTracker/UI/Session/SessionView.swift` — el "Sesión recuperada" de la 1.6 es el patrón del
  proyecto: estado observable en el store (`SessionStore.swift:139-142`), duración como constante
  **de vista** (`:64-65`, `.seconds(3)`), render condicional (`:115-117`), y el temporizador con
  su anuncio en un solo sitio (`:150-155`): `.task(id:)` → `Announcement(...).post()` →
  `Task.sleep` → `if !Task.isCancelled { store.dismissRecoveredNotice() }`. **La vista no escribe
  estado: llama a la intención.**
- `WalkTracker/UI/Session/QuoteOverlay.swift` — vista tonta: recibe el texto y un `onDismiss`, no
  temporiza ni escribe. Dos salidas hacia la **misma** intención: tocar (L57-58, L63-64) y vencer
  (`SessionView.swift:191-192`). Accesibilidad: `.accessibilityElement(children: .ignore)` (L65),
  etiqueta (L66), pista (L67), `.accessibilityAction(.default, onDismiss)` (L69). **Ojo con el
  `id` del `.task`:** usa `quote.id`, no el opcional entero (`SessionView.swift:182-185`), para no
  redispararse.

**Dónde cuelga cada uno**
- `WalkTracker/UI/RootView.swift:75-103` el `TabView`; `:104-106` el
  `.fullScreenCover(...) { SessionView(store:) }` **sobre** él, con binding de solo lectura
  (`:119-121`) porque el cover lo cierra el store y no la vista (AD-20); `:107-114` el
  `.onChange(of: scenePhase)` que llama a `weekMayHaveChanged()`.
- `WalkTracker/UI/Session/SessionView.swift:72-84` — conmuta entre `SessionSummaryView` (L75) y
  `live(...)`; `.interactiveDismissDisabled()` (L80). El overlay de la frase cuelga **dentro**
  (L177-195): ése es el precedente de dónde va algo que debe verse sobre la sesión.

**Accesibilidad, el recurso que ya se usa**
- `AccessibilityNotification.Announcement(String(localized:comment:)).post()` en
  `SessionView.swift:152` y `:190`, y en `SettingsView.swift:111` y `:115`, éste último con el
  comentario que dice *"mismo recurso que el 'Sesión recuperada' de la 1.6"*.

**Tokens**
- Existen `Spacing` (4/8/12/16/24), `LayoutMetrics.margin` 16 / `touchTargetMin` 44,
  `Radius.card` 20 —*"esquina de toda superficie propia con relleno"*—, `Surface.*`,
  `Typography.*` y los tres `Colors`. **No existe** ningún token de duración de aviso ni de
  material de toast: los 3 s de la 1.6 viven como constante privada de vista
  (`SessionView.swift:63,65,68`). La regla de admisión (`DesignTokens.swift:19-34`) pide rol
  repetido en ≥2 sitios o normatividad — con dos avisos nuevos, la duración pasa a serlo.

**El gate**
- Sección 6 (L248-317): prohíbe asignar propiedades del store desde `UI/` y llamar sus pasos
  internos; `store_props` (L285) incluye **`feedback`**, así que un `store.feedback.fire(...)`
  desde la vista es error — **es lo que impide el doble disparo**. Leer estado y llamar
  intenciones sí se puede.
- Sección 10 (L545-571): `UI/` no importa `CoreHaptics`, `AVFoundation` ni `AudioToolbox`.
- Sección 12 (L591-674): nada de `frame(height:<n>)`, `cornerRadius(<n>)`, hexadecimales, colores
  cromáticos del sistema, ni los peldaños 4/8/12/16/24 en `spacing:`/`padding`.
- Sección 3 (L170-213): un `.swift` nuevo fuera de `project.yml` **se ignora en silencio** en el
  build. Hay que regenerar.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Application/SettingsStore+Goal.swift` -- publicar la señal de meta como estado
  observable con su intención de descarte (D1) -- molde: `showsRecoveredNotice` de la 1.6.
- [x] `WalkTracker/UI/Components/CelebrationToast.swift` -- la vista tonta: texto, `onDismiss`,
  accesibilidad y Reduce Motion sin animación -- molde: `QuoteOverlay`.
- [x] `WalkTracker/UI/RootView.swift` -- el aviso de meta sobre el `TabView` (D2).
- [x] `WalkTracker/UI/Session/SessionView.swift` -- el aviso de logros dentro de la sesión, con la
  **cola** de los que faltan como estado de vista (D2, D3).
- [x] `WalkTracker/UI/Style/DesignTokens.swift` -- la duración del aviso, ahora que son dos sitios.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- registrar con `Destino:` la
  unificación de los dos dialectos de Reduce Motion (D4).

**Acceptance Criteria:**
- Dado un cierre que desbloquea tres logros, entonces se muestran **tres** avisos, uno tras otro,
  y **nunca dos a la vez**.
- Dado un aviso visible, cuando se toca, entonces se descarta y **el cronómetro sigue corriendo**.
- Dada la meta cumplida con la app fuera de Inicio, entonces el aviso **no se pierde**.
- Dado `achievements.json` ilegible, entonces **ningún** aviso.
- Dado que se quita el cableado de cualquiera de los dos avisos, entonces **algún test falla**.
- Dado `check-project-shape.sh`, `check-spec-shape.sh` y `verify-domain.sh`, entonces verdes, y
  la suite completa **crece**, contada en el `.xcresult`.

## Implementation Notes

**El aviso de logros NO cuelga de `live(...)`, y ahí se habría perdido entero.** El precedente
que la spec señala —el overlay de la frase dentro de `SessionView`— está colgado de la **sesión
en curso**, y los logros se desbloquean al **cerrar**: en ese instante `session.status` ya es
`.finished`, así que lo que `body` está pintando es `SessionSummaryView` y la rama `live(...)` no
existe. El aviso va por tanto sobre **todo** el `Group`, después de
`.interactiveDismissDisabled()`. Eso además hace verdadera la fila "toque" de la matriz en el
único caso en que los dos pueden convivir: el aviso tapa el resumen sin impedir "Volver al
inicio", porque es un `.overlay` del tamaño de su contenido y no una capa a pantalla completa
como `QuoteOverlay`. Y **no toca `SessionSummaryView`**: la sección de logros del resumen sigue
siendo de la 3.5, que es lo que el bloque "Never" exige.

**La cola es un valor y vive en un `@State`, no un `@Observable` en el store.** `CelebrationQueue`
tiene tres operaciones —`receive`, `current`, `advance`— y ninguna sabe de SwiftUI, así que los
cinco casos que fijan "tres avisos, uno tras otro, y nunca dos a la vez" se ejecutan sin
renderizar nada. `receive` **sustituye** y no acumula, y eso tiene test propio porque la mutación
`pending += unlocked` es silenciosa: `unlockedAchievements` se asigna entero por cierre y el reset
lo vacía, así que acumular duplicaría los avisos de la misma caminata cada vez que la vista
releyera la señal. `advance` sobre una cola vacía no hace nada, porque el toque y el vencimiento
pueden llegar los dos.

**Sin `.id()` en el aviso, y es la diferencia entre "uno tras otro" y "dos a la vez".** Con
identidad propia por logro, el relevo sería una salida y una entrada **simultáneas**: durante la
animación habría dos avisos en pantalla, que es literalmente lo que el criterio de aceptación
prohíbe. Sin ella SwiftUI sustituye el contenido en su sitio y solo hay uno; el temporizador y el
anuncio sí se reinician, porque de eso se encarga el `.task(id: definition.key)` — la misma
precaución que `QuoteOverlay` tiene con `quote.id`, y por la misma razón: el `id` es el contenido
y no el opcional entero.

**La señal de meta sube al store y la de logros no, y no es una incoherencia.** La de logros ya
era observable (`SessionStore.unlockedAchievements`) y lo único que faltaba era pintarla; la de
meta **era un valor de retorno que sus dos llamadores tiran** (`HomeView.swift:91` y
`weekMayHaveChanged()`), así que colgar de él la celebración habría perdido el aviso justo en el
caso más probable — `weekMayHaveChanged()` se llama al volver a primer plano, cuando la pantalla
delante rara vez es Inicio. `showsGoalCelebration` es el molde exacto de `showsRecoveredNotice`:
lo enciende quien decide que se celebra, lo apaga una intención y **no se persiste**, porque quien
impide celebrar dos veces es `lastGoalCelebratedWeek`, que sí vive en `settings.json`. Descartar
el aviso, por tanto, **no descelebra la semana**, y eso tiene aserción propia.

**El aviso de meta cuelga del `TabView` y no de Inicio.** Con `weekMayHaveChanged()` disparando
desde `RootView.onChange(of: scenePhase)`, la meta puede cumplirse con Historial, Logros o Ajustes
delante; colgado de Inicio, el aviso se habría mostrado solo si Paul estaba mirando el anillo. El
temporizador vive en un `.task(id:)` **sobre el `TabView`**, que está montado siempre, y no dentro
del `if` del aviso: es el molde de la 1.6 —`guard`, anuncio, `Task.sleep`, `if !Task.isCancelled`
e **intención**— porque aquí el estado que gobierna la aparición es un `Bool` del store y no un
contenido variable. Consecuencia conocida y correcta: **dentro de la sesión ese aviso no se ve**,
porque el `fullScreenCover` se presenta por encima (`RootView.swift:104-106`); la sesión tiene su
propio aviso, el de los logros, que es lo que ahí se desbloquea.

**Cero háptica nueva, y el gate lo garantiza sin depender de que alguien mire.** Los dos avisos
solo **leen** estado y llaman intenciones; `feedback` está en `store_props` de la sección 6 desde
la 4.1, así que un `store.feedback.fire(...)` desde `UI/` sería un error del build, y la sección 10
impide el atajo de importar `CoreHaptics`. Por eso la 3.4 no añade ninguna regla al gate: el arnés
sigue en **225/225**.

**Reduce Motion es una DECISIÓN con test, no un ternario repetido en dos vistas — y eso lo
corrigió el coordinador.** La primera versión escribía `reduceMotion ? nil : .default` en
`RootView` y en `SessionView`, y la fila *"Reduce Motion → sin animación, no un fundido más
corto"* de la matriz **se quedaba sin ningún test que la ejecutara**: sustituir el ternario por la
constante dejaba las 914 en verde. Ahora la decisión vive en dos funciones puras de
`CelebrationToast` —`animation(reduceMotion:)` y `transition(reduceMotion:)`— que **consumen los
dos avisos**, y sus dos ramas están fijadas. Es la salida que la decisión D1 del 2026-09-20 dejó
escrita para esto —*extraer a un tipo probable qué presenta la pantalla y con qué estado*— y el
mismo recurso con el que `GoalRingView` prueba lo que VoiceOver dice del anillo sin montar una
vista. `Animation?` es `Equatable`, así que el `nil` se afirma directamente; `AnyTransition` no lo
es, así que se compara la **forma** (`String(describing:)`) contra `.identity` y `.opacity` **del
propio SDK**, nunca contra una cadena escrita a mano, que es lo que hace
`MotionBlockedViewTests` con su URL. Hay un tercer caso que afirma que las dos ramas **se
diferencian**, para que una implementación que devolviera lo mismo para los dos valores no pasara
los otros dos.

Esto **no unifica los dos dialectos del árbol** y no contradice a D4: los cuatro sitios de la 1.6,
la 2.1 y la 2.2 que usan el fundido corto siguen exactamente como estaban y su entrada de
`deferred-work.md` se queda como está. Lo que comparten una sola decisión son los **dos** avisos
que esta historia añade.

**Lo que VoiceOver lee sale de funciones puras, no de la vista.** `spokenAchievement(_:)` y
`spokenWeeklyGoal` son estáticas e internas —el molde de `GoalRingView.spokenValue(_:locale:)` y
`AchievementBadgeView.progressText(_:metric:)`— y las usan **las dos** salidas: la etiqueta del
elemento y el `Announcement` que lo anuncia. Así el aviso no puede decir una cosa y anunciar otra.
El anuncio es el texto **entero**, al revés que el de la frase (que anuncia dos palabras porque su
modal ya se lee solo al recibir el foco): este aviso no es modal, no roba el foco y nadie lo leería
si no se anunciara.

**El emoji del logro no entra en la etiqueta hablada.** Es dato del catálogo (AD-5) y se pinta
`verbatim`, pero leerlo haría que VoiceOver dijera "medalla deportiva" antes del nombre del logro.
Lo que se lee es *"Logro desbloqueado: Tu primer kilómetro. Completa 1 km en una sesión"*, con el
prefijo delante: el nombre solo no diría que se acaba de ganar.

**El criterio "si se quita el cableado, algún test falla" se cumple con un test de TIPO, y hay que
leerlo por lo que es.** Ningún test renderiza una vista —XCUITest está descartado desde la decisión
D1 del 2026-09-20— así que los dos casos nuevos comprueban que el **tipo** del cuerpo de cada
pantalla contenga `CelebrationToast`, que es lo que deja de ser verdad en cuanto alguien borra el
`.overlay`. Comprobado en rojo: quitando el de `SessionView` cae **exactamente** "La sesión tiene
cableado el aviso de logros", y quitando el de `RootView`, "Las pestañas tienen cableado el aviso
de meta".

**Lo que demuestra: que el aviso está MONTADO. Lo que NO demuestra: que se VEA.** No dice nada de
si se pinta, dónde queda, si tapa los controles o "Volver al inicio", si VoiceOver lo alcanza y lo
anuncia, ni si SwiftUI honra de verdad la animación que la decisión le pide. **Tampoco cubre que
cada vista USE la decisión compartida**: un `.animation(.default, …)` escrito a mano en el sitio de
la llamada compila, se salta las funciones probadas y **la suite entera sigue en verde** —
comprobado, no supuesto (ver Verification, la tercera mutación de Reduce Motion)—. Es el mismo
residuo que ya está registrado para el anillo (3.1), los avisos de la 5.1 y el grid (3.3): **nada
que sustituya a mirar la pantalla**. Quien lea estos dos casos como cobertura de presentación los
está leyendo mal.

**Las dos preguntas que la 3.1 dejó apuntadas a esta historia siguen abiertas, a propósito.** Ni el
nombre de `SettingsStore` —que lleva la lógica del anillo— ni el cruce de semana con la app en
primer plano sin cambio de fase de escena los decide esta spec: su lista de tareas no los nombra y
su bloque "Never" acota el trabajo a la mitad visible. Las dos entradas siguen vivas en
`deferred-work.md` y ahora apuntan a una historia que se cierra sin tomarlas; quien recoja el Epic 3
en su retro tiene ahí el dato.

## Spec Change Log

## Review Triage Log

## Design Notes

**Por qué la cola no vive en el store.** El store publica un hecho —*estos logros se
desbloquearon y quedaron escritos*—; cuántos quedan por enseñar y en qué orden es una decisión de
pintado que cambia si mañana se enseñan en fila, apilados o en una sola tarjeta. Meterla en el
store obligaría a la vista a escribir estado ajeno, que es justo lo que la sección 6 del gate
prohíbe desde el A-1.

**Por qué la señal de meta sí sube al store.** Es el caso contrario: si vive en la vista, se
pierde cuando la meta se cumple sin que Inicio esté delante — y `weekMayHaveChanged()` se llama
precisamente **al volver a primer plano**, que es cuando es más probable que la pantalla visible
sea otra.

## Verification

**Commands:**
- `bash Scripts/check-project-shape.sh` y su arnés -- esperado: verde, el conteo no baja.
- `bash Scripts/check-spec-shape.sh` -- esperado: verde.
- `bash Scripts/verify-domain.sh` -- esperado: verde, AD-6 sin pendientes.
- `xcodebuild test` completo -- esperado: casos ejecutados **crecen**, contados en el `.xcresult`.

**Ejecutado (2026-09-22):**
- `bash Scripts/check-project-shape.sh` -> **verde**. `bash Scripts/check-project-shape-tests.sh`
  -> **225/225**, sin cambios: esta historia **no añade ninguna regla al gate**, y no le hace
  falta — `feedback` entró en `store_props` con la 4.1 y la sección 10 ya prohíbe `CoreHaptics` en
  `UI/`, que son las dos puertas por las que un aviso podría haber duplicado la háptica.
- `bash Scripts/check-spec-shape.sh` -> **verde**, con **66** entradas de `deferred-work.md` (65
  antes) y 11 cerradas. La nueva es la de los dos dialectos de Reduce Motion (D4).
- `bash Scripts/verify-domain.sh` -> **verde**. **329 tests en 22 suites**, los mismos que tras la
  4.1: esta historia no toca `Domain/` ni porta vectores, y la línea de pendientes de AD-6 sigue
  en **`ninguna`**. Los 109 vectores siguen pasando.
- `xcodegen generate && xcodebuild test ... iPhone 16e CODE_SIGNING_ALLOWED=NO` -> **TEST
  SUCCEEDED**, **917 tests en 70 suites** (901 en 69 antes): **16 casos y 1 suite nuevos**,
  contados por nombre sobre el `.xcresult` y no por `TEST SUCCEEDED` — `Celebración · la cola de
  avisos y lo que se lee` **12** (cinco de la cola, dos de lo que se lee, **tres de Reduce Motion**
  y los dos del cableado), más `SettingsStore · la meta semanal y el anillo`, que pasa de 30 a
  **34**. El fichero nuevo
  entra en el target con `xcodegen generate` en el mismo commit; sin eso el propio gate lo habría
  dicho (sección 3). Sin warnings propios nuevos: los 124 del build de test son los de antes, todos
  en expansiones de macro de `AboutSectionTests` y `SettingsViewTests`.

- `WalkTracker/Resources/Localizable.xcstrings` gana **6 claves** con su comentario, las de los
  dos avisos: los dos titulares, las dos segundas líneas, la pista compartida y las dos lecturas de
  VoiceOver (la del logro con sus dos marcadores). El catálogo se versiona y lo actualiza cada
  historia de UI, como hizo la 3.3; el nombre y la descripción del logro **no** entran: son dato
  del catálogo congelado (AD-5) y viajan interpolados.

**Mutaciones (cada una aplicada, compilada, ejecutada y revertida; las dos últimas contra la
**suite completa**, no contra una suite suelta — leer un `TEST SUCCEEDED` de la suite equivocada es
el fallo D10 de la retro del Epic 2 y ya se ha repetido). Las dos primeras son el criterio de
aceptación "si se quita el cableado de cualquiera de los dos avisos, algún test falla":**
- **Sin el `.overlay` del aviso de logros** en `SessionView` -> falla **1 test**: "La sesión tiene
  cableado el aviso de logros". Ningún otro, que es justo lo que había que comprobar: antes de este
  caso, borrar ese overlay dejaba las 914 en verde.
- **Sin el `.overlay` del aviso de meta** en `RootView` -> falla **1 test**: "Las pestañas tienen
  cableado el aviso de meta".
- **Sin `showsGoalCelebration = true`** (la señal se queda en el `return` que nadie lee) -> fallan
  **2 tests**: "Cumplir la meta enciende el aviso visible, y descartarlo lo apaga" y "La meta que se
  cumple con la app en otra pestaña deja su aviso esperando". El segundo es la fila "meta fuera de
  Inicio" de la matriz.
- **La cola acumula** (`pending += unlocked` en vez de `pending = unlocked`) -> falla **1 test**:
  "Recibir otra señal sustituye la cola, no la acumula".
- **`advance()` vacía la cola entera** (`pending = []`) -> falla **1 test** con **dos** aserciones:
  "Tres logros en un cierre: tres avisos, uno tras otro, y NUNCA dos a la vez". Es la mutación que
  convierte tres avisos en uno.
- **La decisión de Reduce Motion deja de mirar la preferencia** (`animation(reduceMotion:)`
  devolviendo siempre `.default` y `transition(reduceMotion:)` siempre `.opacity`, que es el
  fundido más corto que la fila de la matriz prohíbe) -> **ejecutada contra la SUITE COMPLETA**:
  917 casos, **2 tests en rojo con 4 aserciones** — "Con Reduce Motion el aviso aparece SIN
  animación" y "Las dos ramas no son la misma". Es la fila que **no tenía cobertura** hasta que la
  decisión salió de las dos vistas: la encontró el coordinador, no este trabajo, y antes de
  extraerla la misma mutación escrita en `RootView` dejaba las 914 **en verde**.
- **Un aviso se salta la decisión compartida** (`.animation(.default, …)` y `.transition(.opacity)`
  escritos a mano en `RootView`, con las funciones intactas) -> **la suite completa sigue en
  verde**, 917 pasados. Se deja escrito porque es el límite honesto de lo que estos tests cubren:
  fijan **qué decide** la celebración sobre Reduce Motion, no que cada vista se lo pregunte. Es la
  misma clase de hueco que "el aviso está montado, no que se vea", y va con los checks manuales.
- Árbol restaurado y la suite completa vuelve a **TEST SUCCEEDED** (917) después de las siete.

**Manual checks (iPhone, tras el build): PENDIENTES.** No se han ejecutado, y son **la única
verificación de lo que solo se ve renderizando**: que el aviso se pinte arriba, que no tape los
controles ni "Volver al inicio", que VoiceOver lo **anuncie** y lo pueda alcanzar, y que con Reduce
Motion aparezca sin animación. Los tres de la spec:
- Cerrar una caminata que desbloquee dos logros: dos avisos, uno tras otro.
- Tocar un aviso durante una sesión: se va y el cronómetro no se para.
- Con Reduce Motion: el aviso aparece **sin** animación.

Y uno más que esta historia añade al mismo hueco, porque es el que ningún test alcanza: cumplir la
meta con **otra pestaña delante** y ver que el aviso aparece igual. Van con los checks pendientes
de la 2.1 (B-8), la 2.3, B-9, la 5.1, la 3.1, la 3.2 y la 3.3.
