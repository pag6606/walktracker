---
title: '4.1 — Canal de feedback: los cuatro disparos cableados'
type: 'feature'
created: '2026-09-22'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '5ca090d076d990c08492e5e239e7ce5aa24c85f2'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-3-3-pantalla-logros.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-3-2-achievement-engine.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** El `FeedbackPort`, el enum `FeedbackEvent` con sus cuatro casos y el
`FeedbackAdapter` con su háptica por evento **ya existen desde la 8.6** — y **nadie los dispara**.
El único consumidor es `NativeLayerDiagnosticsView`, que solo existe en DEBUG y los lanza a mano
con un `Toggle`. Ningún store tiene el puerto inyectado. O sea: el canal está construido y
desconectado.

**Approach:** Cablear los cuatro disparos a los sucesos reales —inicio de sesión, cruce de km,
meta cumplida y logro desbloqueado—, cada uno en el punto que ya existe y que la historia dueña
de ese suceso dejó señalado. Más la única pieza de lógica que falta: **detectar el cruce de
kilómetro**, que hoy no existe en ninguna parte.

## Boundaries & Constraints

**Always:**
- El disparo vive en la **capa de aplicación**, nunca en una vista: la sección 10 del gate
  prohíbe `CoreHaptics` en `WalkTracker/UI/`, y la háptica entra por puerto y adapter.
- **Un suceso, un evento.** Desbloquear tres logros a la vez vibra **una** vez, no tres. Cruzar
  varios kilómetros de golpe vibra **una** vez, no una por kilómetro.
- El cruce de km se decide con una **función pura del dominio** —dada la distancia anterior y la
  nueva, ¿se cruzó al menos un múltiplo de 1.000 m?— probada sin store ni vista.
- El feedback **nunca falla hacia fuera**: el puerto ya lo promete ("un feedback perdido no es un
  fallo de sesión") y el cableado lo respeta. Nada de `try`, nada que aborte un cierre.
- Cada punto de disparo lleva su test con un **espía del puerto**, que hoy no existe.

**Never:**
- **No se toca el `FeedbackAdapter`**, ni su háptica, ni sus sonidos, ni su mapa de parámetros.
  Es de la 8.6 y su test lo fija.
- No se dispara feedback en **reconciliación ni recuperación** — ver D2.
- No se añade la preferencia de sonido ni su interruptor en Ajustes: es de la **4.2**, dueña
  declarada de la preferencia (`deferred-work.md:7`).
- No se implementa la celebración visible (3.4). Esta historia entrega el canal; la 3.4 pinta.
- No se toca `SessionStore.unlockedAchievements` ni `goalRingDidUpdate()`: se **consumen**.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Salida esperada | Error |
|---|---|---|---|
| Inicio | se abre una sesión | **un** `.sessionStart` | N/A |
| Primer km | distancia pasa de 980 a 1.020 m | **un** `.kilometer` | N/A |
| Sin cruzar | de 1.100 a 1.900 m | **ningún** evento | N/A |
| Justo en el múltiplo | de 999 a 1.000 m exactos | **un** `.kilometer` | N/A |
| Varios km de golpe | de 800 a 4.200 m | **un** `.kilometer`, no tres | N/A |
| Reconstrucción de background | la reconciliación suma 3 km | **ningún** evento | N/A |
| Recuperación al relanzar | se restaura una sesión con 5 km | **ningún** evento | N/A |
| Meta cumplida | `goalRingDidUpdate()` devuelve `true` | **un** `.goal` | N/A |
| Meta ya celebrada | devuelve `false` | **ningún** evento | N/A |
| Logros desbloqueados | el cierre escribe 3 logros | **un** `.achievement` | N/A |
| Ninguno desbloqueado | el cierre no escribe nada | **ningún** evento | N/A |
| Logros no persistidos | `achievements.json` ilegible | **ningún** evento: no se celebra lo que no se guardó | N/A |
| El adapter falla | la háptica no arranca | la sesión sigue; solo se registra | tragado |

</frozen-after-approval>

## Decisiones (2026-09-22)

**D1 — Solo háptica; el sonido llega con la 4.2.** Todos los disparos pasan
`soundEnabled: false`. *Razón de producto, no técnica:* la preferencia de sonido **no existe**
—`AppSettings` no la tiene y `deferred-work.md:7` declara a la 4.2 dueña de ella— y publicar un
sonido que Paul no puede apagar es una molestia sin salida. La háptica sola es discreta y se
siente completa. Cuando la 4.2 traiga la preferencia y su interruptor, esto es **cambiar un
argumento**. Queda registrado con destino para que no se quede olvidado en `false`.

**D2 — Ni reconciliación ni recuperación disparan nada.** Al reconstruir un hueco de background
la distancia puede saltar varios kilómetros de una vez, y al relanzar se restaura una sesión
entera. Vibrar ahí sería **buzz al desbloquear el móvil por kilómetros andados hace media hora**.
El evento de km es una **travesía en vivo**; una reconstrucción no lo es. Por eso el disparo se
engancha **solo** donde la distancia avanza en vivo (`record(_:fromQuery:)` con `fromQuery ==
false`), y no en los otros once sitios que reasignan `metrics`.

**D3 — Un suceso, un evento.** Tres logros a la vez son **una** vibración, y saltar de 800 a
4.200 m también. La alternativa —una por logro, una por kilómetro— convierte una confirmación
discreta en una ráfaga.

## Code Map

**Campos compartidos de `SessionStore` que toca este cambio** (regla (b) del A-7): **ninguno se
lee ni se escribe**. Esta historia **añade** una dependencia (`feedback`) y un campo privado para
recordar la última distancia con la que se evaluó el cruce de km. No toca `session`, `metrics`,
`hasSession`, `isReconciling`, `unsavedFinishedRecord` ni `finishedWalkNotPersisted`. El campo
nuevo se limpia en `resetSessionState()`, como todos los de sesión — **si no, el primer km de la
caminata siguiente no suena**.

**Lo que ya existe y no se toca**
- `Domain/Ports/FeedbackPort.swift:8-11` — `fire(_ event: FeedbackEvent, soundEnabled: Bool)`,
  con su promesa: *"Nunca falla hacia fuera: un feedback perdido no es un fallo de sesión."*
- `Domain/Ports/FeedbackEvent.swift:6-15` — `sessionStart`, `kilometer`, `goal`, `achievement`.
  Son **exactamente** los cuatro que pide la historia.
- `WalkTracker/Adapters/Feedback/FeedbackAdapter.swift` — `parameters(for:)` (L46-52) con la
  intensidad, la nitidez y el `SystemSoundID` de cada evento; `fire` (L54-60); motor perezoso
  bajo `Mutex` (L62-94). `init()` **sin parámetros: no hay costura inyectable**, y eso no se
  arregla aquí (está en `deferred-work.md` con destino 4.2).
- `WalkTrackerTests/Adapters/FeedbackAdapterTests.swift` — su único test fija el mapa de
  parámetros. **No ejercita `fire`**, y no hay ningún doble del puerto en todo el árbol.

**Los cuatro puntos de enganche**
- **Inicio:** `WalkTracker/Application/SessionStore+StartFlow.swift:100-115` — `openSession()` es
  el **punto único** donde nace una sesión; lo llaman L22 y L41. Ahí ya viven `countSteps`,
  `measureTransition(.start,…)`, `attachQuoteForNewSession()` y `persist()`.
- **Kilómetro:** `WalkTracker/Application/SessionStore+StepCounting.swift:64-92` —
  `record(_ sample:fromQuery:)`, donde entra cada muestra: la distancia se fija en L84 y las
  métricas se recalculan en L89. **Ojo:** hay **once sitios más** que reasignan `metrics`
  (reconciliación, recuperación, clima, motivación…). D2 explica por qué el disparo va solo aquí.
  **No existe hoy ninguna comparación de distancia anterior con nueva** en la capa de aplicación;
  lo único parecido es la monotonía del dominio en `Domain/Session/Session.swift:228-235`.
- **Meta:** `WalkTracker/Application/SettingsStore+Goal.swift:221-246` —
  `goalRingDidUpdate() -> Bool` devuelve `true` **la primera vez de cada semana** que la meta
  aparece cumplida, y su doc ya dice que es *"la señal a la que se engancha la celebración de la
  3.4"*. Lo llaman `HomeView.swift:91` y `weekMayHaveChanged()` (L197-200).
- **Logro:** `WalkTracker/Application/SessionStore+History.swift:118-145` —
  `evaluateAchievements(for:)`: sale sin hacer nada si el fichero es ilegible (L119-122) o si no
  se escribió ninguno (L135), y publica `unlockedAchievements = written` en **L144**. Ese guard
  de "no se escribió" es lo que hace verdadera la fila "logros no persistidos" de la matriz.

**Lo que hay que inyectar**
- `WalkTracker/App/CompositionRoot.swift:18` `feedback`, ya construido (L53, L66) y hoy pasado
  **solo** a la UI de diagnóstico (`WalkTrackerApp.swift:38`). **Ningún store lo recibe.**
- `SessionStore.init` (`SessionStore.swift:317-335`) y `SettingsStore.init`
  (`SettingsStore.swift:140-145`) — las dos listas de parámetros crecen en uno.
- Precedente de qué pasa al añadir un colaborador con valor por omisión: la 3.1 lo hizo y la
  revisión lo cazó —`clock:` con defecto permitía construir el root sin cablearlo y nada fallaba—,
  así que **el parámetro nuevo va sin valor por omisión** y `CompositionRootTests` gana su caso.

**El gate**
- `Scripts/check-project-shape.sh` **no tiene ninguna regla sobre `feedback`** (cero coincidencias
  de `fire`/`Feedback`). Sí tiene la sección 10 (L552-559): `WalkTracker/UI/` no importa
  `CoreHaptics` ni `AVFoundation` — por eso el disparo no puede vivir en una vista.
- Sección 4 (L214-227): `Domain/` solo Foundation. La función pura del cruce de km cumple.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Session/` -- función pura del cruce de kilómetro: dada la distancia anterior y la
  nueva, si se cruzó al menos un múltiplo de 1.000 m -- probada sin store.
- [x] `WalkTracker/Application/SessionStore+StepCounting.swift` -- disparo de `.kilometer` en
  `record(...)` **solo con `fromQuery == false`** (D2), un evento por lote (D3).
- [x] `WalkTracker/Application/SessionStore+StartFlow.swift` -- disparo de `.sessionStart` en
  `openSession()`.
- [x] `WalkTracker/Application/SessionStore+History.swift` -- disparo de `.achievement` cuando
  `evaluateAchievements` escribió al menos uno, **uno solo** aunque sean varios.
- [x] `WalkTracker/Application/SettingsStore+Goal.swift` -- disparo de `.goal` cuando
  `goalRingDidUpdate()` devuelve `true`.
- [x] `WalkTracker/Application/SessionStore.swift` -- el campo de la última distancia evaluada,
  limpiado en `resetSessionState()` -- si no, el primer km de la siguiente caminata no suena.
- [x] `WalkTracker/App/CompositionRoot.swift` -- inyectar `feedback` a los dos stores, **sin
  valor por omisión**, con su caso en `CompositionRootTests`.
- [x] `WalkTrackerTests/Support/` -- espía del `FeedbackPort` que registre los eventos recibidos
  -- hoy no existe ningún doble.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- registrar con `Destino:` la 4.2
  que `soundEnabled` está clavado en `false` (D1).

**Acceptance Criteria:**
- Dada una sesión que arranca, entonces el espía recibe **exactamente un** `.sessionStart`.
- Dada una muestra que lleva la distancia de 800 a 4.200 m, entonces **un solo** `.kilometer`.
- Dada una muestra con `fromQuery == true` que suma 3 km, entonces **ningún** evento.
- Dado un cierre que desbloquea tres logros, entonces **un solo** `.achievement`.
- Dado un cierre con `achievements.json` ilegible, entonces **ningún** evento.
- Dado que se quita el cableado de cualquiera de los cuatro disparos, entonces **algún test
  falla** — es la comprobación de que el espía sirve de algo.
- Dado `bash Scripts/check-project-shape.sh`, `check-spec-shape.sh` y `verify-domain.sh`,
  entonces verdes, y la suite completa **crece**, contada en el `.xcresult`.

## Implementation Notes

**`KilometerCrossing.didCross(from:to:)` responde `Bool`, y eso es la decisión D3 hecha tipo.**
La función pura no dice *cuántos* múltiplos se cruzaron: dice **si** se cruzó alguno. Devolver un
número habría dejado la decisión suelta en el punto de llamada, que es exactamente donde nace la
ráfaga —una vibración por kilómetro al reconstruir un salto de 800 a 4.200 m—. Vive en
`Domain/Session/` con el molde de `Chronometer`: `enum` sin casos, todo `static func`, solo
`Foundation` (sección 4 del gate). Cruzar es **alcanzar** el múltiplo, no pasarlo: de 999 a 1.000 m
exactos se ha cruzado el primero, y tiene caso propio porque un `>` en vez de un `>=` dentro de la
división habría retrasado el primer kilómetro sin que nada se cayera. La frontera **no lanza**:
`.nan`, `inf` y un negativo devuelven `false`, porque el puerto promete que un feedback perdido no
es un fallo de sesión y esta función es lo primero que hay detrás de esa promesa.

**La marca de la última distancia es `Double?`, y el `nil` no es "cero metros".** Esa diferencia es
la que hace verdaderas **dos** filas de la matriz. Sin distancia anterior no hay con qué comparar,
así que la **primera** muestra de una sesión solo siembra la marca y no dispara: una sesión
restaurada al relanzar con 5 km andados no vibra cuando llega su primera muestra en vivo, que es
justo lo que un cero inicial habría hecho —cinco múltiplos cruzados de golpe al desbloquear el
móvil—. Con la mutación "la marca no se siembra" (`lastKilometerDistanceM ?? 0`) caen dos tests.
La marca además **nunca baja** (`max`): ver la nota siguiente, que es donde eso se paga.

**La monotonía de la marca tiene su propio test porque la suite entera la dejaba pasar.**
Sustituir `max(lastKilometerDistanceM ?? 0, distanceM)` por una asignación directa dejaba los 900
tests **en verde**: nada fijaba la propiedad. Y lo que protege es real y es feo. `metrics(at:)`
devuelve `distanceM: 0` con `degraded: true` cuando un cálculo no cuadra (B-3), y ese `catch` **no
es inalcanzable** —`MetricsScenarios` lo alcanza, y darlo por imposible ya costó un crash en cada
caminata—: si la marca siguiera esa caída a cero, el cálculo bueno siguiente volvería a cruzar
todos los kilómetros ya cruzados y vibraría **una vez por cada uno**, que es la ráfaga que D3
existe para impedir y encima en el momento en que algo ya ha ido mal. Para poder pincharlo,
`noteKilometerCrossing(upTo:live:)` pasa de `private` a **acceso de módulo**, que es lo que ya son
`record`, `countSteps`, `capLastSampleAt` y `persist`: un paso interno que llaman su fichero y los
tests, y que la **sección 6 del gate** impide alcanzar desde una vista (entra en `store_props` con
su caso en el arnés, que pasa a **225**). El cero que el test le pasa no es un literal elegido a
mano: sale de unas métricas **degradadas de verdad**, construidas con la receta de
`MetricsScenarios`, así que es exactamente lo que `record(...)` le pasaría.

**La consulta de la reconciliación mueve la marca aunque no dispare, y ésa es la mitad difícil de
D2.** El disparo va **solo** con `fromQuery == false`, como pedía la spec; pero si la consulta no
moviera la marca, la primera muestra **en vivo** posterior al hueco compararía con la distancia de
antes de irse a background y vibraría por los tres kilómetros que la reconciliación acaba de
reconstruir: el mismo buzz, un instante más tarde. Por eso `noteKilometerCrossing(upTo:live:)`
recibe `live` y no un `guard` de salida temprana, y hay **dos** tests seguidos —la reconciliación y
la muestra siguiente— en vez de uno.

**La distancia que se mide es la de `metrics`, la que Paul está viendo.** No la del sistema en
crudo: así la vibración cae en el mismo instante en que el cuentakilómetros de la pantalla marca el
kilómetro, y no un decimal antes o después. Es también la única que existe en los doce sitios que
reasignan `metrics`, así que no introduce una segunda fuente de verdad para la distancia.

**El disparo del logro cuelga de `written`, no de `newlyUnlocked`.** No se celebra lo que no se
guardó: es la fila "logros no persistidos" de la matriz, y la misma doctrina que la 3.2 escribió
para la señal visible —un logro anunciado que no llegó al disco volvería a desbloquearse en el
cierre siguiente—. Con `achievements.json` ilegible el `guard` de `readOutcome` ya saca del método
antes de evaluar, así que tampoco hay vibración. Y **es uno solo aunque sean varios**: una primera
caminata de 2,6 km desbloquea `first_session` y `first_km` a la vez y vibra una vez. La mutación
"una vibración por logro" (`for _ in written`) cae con un solo test.

**El reintento del resumen SÍ vibra: es una DIVERGENCIA DELIBERADA entre los dos canales, no un
descuido.** La 3.2 decidió dejar morir la señal **visible** del camino de
`retrySavingFinishedWalk()` —`unlockedAchievements` se llena y `leaveSummary()` lo vacía acto
seguido— porque el resumen ya está saliendo de pantalla y no hay dónde pintar una celebración. La
háptica **no necesita pantalla**, y el desbloqueo que la provoca es igual de real y queda escrito
en `achievements.json`, así que por ese camino sí se dispara. Por eso el disparo vive en el
**único punto** (`evaluateAchievements(for:)`) al que llaman los dos caminos, en vez de copiarse en
uno solo con una condición. Es la única diferencia entre los dos canales para el mismo suceso, y
está escrita **en el punto de llamada y aquí** para que la 3.4 —que se va a cablear a la señal
visible— no la descubra con extrañeza y la lea como un olvido que hay que "arreglar".

**La meta vibra donde se decide que se celebra, no donde se pinta.** `goalRingDidUpdate()` devuelve
`true` la primera vez de cada semana, y el disparo cuelga de ese mismo `return true`: sus **dos**
entrantes —`HomeView` al pintar el anillo y `weekMayHaveChanged()` al volver de background—
comparten el punto, así que repintar, volver a Inicio o relanzar no vuelven a vibrar. Ponerlo en la
vista era imposible además de incorrecto: la sección 10 del gate prohíbe `CoreHaptics` en
`WalkTracker/UI/`.

**Los dos `init` crecen sin valor por omisión, y el root pasa el MISMO adapter.** Es la lección que
la 3.1 dejó escrita con `clock:`: un colaborador con defecto se olvida en el composition root y
nada falla. Aquí el olvido sería una app sin una sola vibración. El compilador cubre el olvido; lo
que no puede decir es que el root cablee **su** adapter y no construya otro por el camino —dos
instancias serían dos motores de háptica perezosos—, y eso lo ata el caso nuevo de
`CompositionRootTests`, que arranca una sesión y cumple la meta contra el mismo espía.

**El gate gana una palabra, no una regla.** `feedback` entra en la lista de pasos internos de la
sección 6, junto a `settings`, `history` y `achievements`: desde que los dos stores lo guardan en
una propiedad con ese nombre, `store.feedback.fire(...)` compilaría desde una vista y esquivaría la
sección 10 por completo —la vista no importaría `CoreHaptics`, lo haría el adapter—. Con su caso en
el arnés, que pasa de 223 a **224**, y con su camino rojo comprobado: quitando `|feedback` de
`store_props` el arnés baja a 223/224 y el caso que cae es exactamente el nuevo.

**El espía no existía, y sin él "un suceso, un evento" no se puede afirmar.** No había ningún doble
de `FeedbackPort` en todo el árbol. `FeedbackSpy` guarda cada disparo **con su `soundEnabled`**,
porque la decisión D1 se afirma sobre ese argumento y no sobre el evento, y expone `count(of:)`:
`contains` no distingue una vibración de tres, que es justo la diferencia que D3 decide.

## Spec Change Log

## Review Triage Log

## Design Notes

**Por qué el cruce de km no puede vivir donde se recalculan las métricas.** Hay doce sitios que
reasignan `metrics`, y la mayoría no son travesías: la reconciliación reconstruye un hueco, la
recuperación restaura una sesión entera, el clima y la frase solo refrescan. Enganchar ahí daría
vibraciones por kilómetros andados hace media hora, al desbloquear el móvil. El único sitio donde
la distancia avanza **porque Paul está caminando ahora** es `record(...)` con una muestra del
stream, y por eso el disparo va ahí y solo ahí.

**Por qué el parámetro nuevo no lleva valor por omisión.** La 3.1 añadió colaboradores con
defecto y la revisión demostró el agujero: quitar `clock:` del root **compilaba** y nada fallaba,
mientras el anillo calculaba la semana con el reloj de pared. Un colaborador obligatorio convierte
ese olvido en un error de compilación.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` -- esperado: verde, AD-6 sin pendientes.
- `bash Scripts/check-project-shape.sh` y su arnés -- esperado: verde, el conteo no baja.
- `bash Scripts/check-spec-shape.sh` -- esperado: verde.
- `xcodebuild test` completo -- esperado: casos ejecutados **crecen**, contados en el `.xcresult`.

**Ejecutado (2026-09-22):**
- `bash Scripts/verify-domain.sh` -> **verde**. **329 tests en 22 suites** (321 en 21 antes) y la
  línea de pendientes de AD-6 sigue en **`ninguna`**: esta historia no porta vectores nuevos —no
  hay función de referencia en `domain.js`/`motivation.js` para el cruce de kilómetro, que es
  lógica de la app v4 y no de la v3— y no destapa ninguno. Los 109 vectores siguen pasando. El
  suite nuevo `KilometerCrossingTests` entra en `DOMAIN_SUITES` en el mismo commit; sin eso el
  propio gate lo habría dicho (B-6).
- `bash Scripts/check-project-shape.sh` -> **verde**. `bash Scripts/check-project-shape-tests.sh`
  -> **225/225** (223 antes): dos casos nuevos en la sección 6, uno por cada palabra que esta
  historia añade a `store_props` — `store.feedback.fire(...)` y
  `store.noteKilometerCrossing(...)` desde `UI/` deben fallar.
- **Camino rojo del propio gate** en las dos, porque un caso que no rompe no demuestra nada:
  quitando `|feedback` el arnés baja a **224/225** y quitando `|noteKilometerCrossing` también, y
  en cada caso el único que cae es su propio caso nuevo.
- `bash Scripts/check-spec-shape.sh` -> **verde**, con **65** entradas de `deferred-work.md` (63
  antes). *Corregido el 2026-09-22: esta sección decía **64** y una sola entrada nueva. Son **dos**:
  la de `soundEnabled` clavado en `false` (D1) y la de la **rama de estimación de la
  reconciliación**, que puede disparar por un kilómetro cuyo último tercio nadie midió. La
  segunda estaba escrita y el gate la aceptaba, pero no estaba contada ni nombrada aquí. Lo
  encontró el agente de seguimiento al cuadrar las cifras del tablero.*
- `xcodegen generate && xcodebuild test ... iPhone 16e CODE_SIGNING_ALLOWED=NO` -> **TEST
  SUCCEEDED**, **901 tests en 69 suites** (870 en 67 antes): **31 casos y 2 suites nuevos**,
  contados por nombre sobre el `.xcresult` y no por `TEST SUCCEEDED` — `Cruce de kilómetro` **8** y
  `SessionStore · el canal de feedback` **18**, más los ampliados: `SettingsStore · la meta semanal
  y el anillo` pasa de 26 a **30** y `CompositionRoot · cableado del store` de 8 a **9**. Sin
  errores ni warnings propios nuevos: el build de test sale con **0** warnings. Ningún suite
  existente cambia de conducta; lo único que cambia en los ya existentes son las listas de
  parámetros de los dos `init`.

**Mutaciones (cada una aplicada, ejecutada contra `SessionStoreFeedbackTests`,
`SettingsStoreGoalTests`, `CompositionRootTests` y `SessionStoreAchievementsTests`, y revertida).
Las cuatro primeras son el criterio de aceptación "si se quita el cableado de cualquiera de los
cuatro disparos, algún test falla":**
- **Sin el disparo de inicio** -> fallan **5 tests**, entre ellos "La sesión que nace tras conceder
  el permiso también vibra" (el segundo entrante de `openSession()`) y el de `CompositionRoot`.
- **Sin el disparo de kilómetro** -> fallan **5 tests**, los cinco del cruce.
- **Sin el disparo de logro** -> falla **1 test**: "Un cierre que desbloquea dos logros vibra una
  sola vez".
- **Sin el disparo de meta** -> fallan **4 tests**, incluido el de `CompositionRoot`: sin él, el
  store de ajustes podría recibir el canal y no usarlo.
- **La reconciliación también vibra** (`live` forzado a `true`, que es enganchar el disparo donde
  D2 lo prohíbe) -> falla **1 test**: "La reconciliación suma 3 km y no dispara ningún evento".
- **La marca no se limpia en el reset** -> falla **1 test**: "La caminata siguiente vuelve a sonar
  en su primer kilómetro". Es exactamente lo que la spec avisaba: sin limpiarla, el primer
  kilómetro de la caminata siguiente **no suena**, y nada más se cae.
- **Una vibración por logro** (`for _ in written`) -> falla **1 test**: el de los dos logros en un
  cierre. Es D3 ejecutándose.
- **La marca no se siembra** (`lastKilometerDistanceM ?? 0` en vez del `let` opcional) -> fallan
  **2 tests**: "La primera muestra de la sesión siembra la marca y no vibra" y "Recuperar una
  sesión con 5 km no vibra". Es la fila de recuperación de la matriz.
- **La marca no es monótona** (`lastKilometerDistanceM = distanceM`, sin el `max`) -> falla **1
  test**: "Una distancia que CAE no reinicia la marca". **Esta mutación sobrevivía a la suite
  entera** —los 900 casos en verde— hasta que se añadió su test: la encontró el coordinador, no
  este trabajo, y es el hueco de verificación de esta historia. Ejecutada contra la suite
  **completa**, no contra las cuatro suites de las otras ocho, para comprobar que el rojo es de
  verdad y que ningún otro test la tapaba.
- Árbol restaurado y la suite completa vuelve a **TEST SUCCEEDED** después de las nueve.

**Manual checks (iPhone, tras el build): PENDIENTES.** No se han ejecutado, y **son la única
verificación posible de que algo vibra de verdad**: los tests fijan qué evento se dispara, cuántas
veces y con qué `soundEnabled`, pero el `FeedbackAdapter` no tiene costura inyectable
(`init()` sin parámetros, registrado en `deferred-work.md` con destino 4.2), así que ningún test
llega a CoreHaptics. Los tres de la spec:
- Iniciar una caminata: se siente una vibración corta.
- Cruzar el primer kilómetro: una vibración, una sola.
- Volver a primer plano tras andar con el móvil bloqueado: **ninguna** vibración por los
  kilómetros reconstruidos.

Y dos más que esta historia añade al mismo hueco: cerrar una caminata que desbloquea **dos** logros
y sentir **una** vibración, y cumplir la meta semanal y sentir la suya sin que repintar Inicio la
repita. Ojo con el segundo: la celebración **visible** de la meta es de la 3.4, así que hoy lo que
se comprueba en el dispositivo es la vibración, no un toast.
