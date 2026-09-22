---
title: '3.2 — Evaluación de logros al cierre de sesión (AchievementEngine)'
type: 'feature'
created: '2026-09-21'
status: 'in-progress'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '3b30d94ba57ee84606b260607c26302cafe3c01e'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-3-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-3-1-meta-semanal-anillo.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-5-1-persistencia-sesiones.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** El catálogo de 14 logros está congelado y validado desde la 8.7, `AchievementMetric`
declara sus nueve métricas, `AchievementComparison` declara sus seis comparadores y
`AchievementsStore` sabe persistir desbloqueos — **y nadie evalúa nada**. La comparación no está
implementada en ninguna parte: `Domain/Engines/` solo contiene `WeeklyProgress.swift`. Los **57
vectores** de equivalencia que cubren los 14 logros en los dos sentidos (`evaluateAchievements` 51,
`checkTimeOfDay` 5, `achievementCatalog` 1) llevan escritos desde la 8.7 sin runtime Swift contra
el que correr, más los **8 de `checkStreak`** que la 3.1 dejó deliberadamente fuera.

**Approach:** Un motor puro en `Domain/`, con el molde exacto de `GoalEngine` —enum sin casos,
todo `static func`, reloj y calendario **por parámetro**—, que recibe el registro que cierra, el
historial y los desbloqueos actuales, y devuelve **qué logros se desbloquean ahora**. Se engancha
en el punto que AD-17 señala, y los vectores pendientes pasan a ejecutarse.

## Boundaries & Constraints

**Always:**
- El motor es **puro y vive en `Domain/`**: los vectores lo ejecutan y no pueden importar
  `WalkTracker`. Reloj y calendario entran por parámetro (AD-3, AD-19).
- El `switch` sobre `AchievementMetric` es **exhaustivo y sin `default`**. Su doc ya lo promete:
  una métrica nueva sin rama **no compila**. Un `default` lo rompería en silencio.
- **Una huérfana no cuenta**: el filtro es `SessionRecord.countsForAchievements` (`!recovered`),
  que ya existe. Y ojo, es la pregunta contraria a la del anillo: una huérfana **sí** suma
  kilómetros en el anillo semanal y **no** cuenta para logros.
- **`weekly_goal` no lo evalúa este motor y no produce celebración propia** (AD-25). Es la
  excepción declarada: lo desbloquea `GoalEngine` a través de `unlockWeeklyGoal(at:)`, que la 3.1
  ya dejó idempotente. Existe el vector `weekly-goal-no-se-evalua-al-cierre` que lo fija.
- **Un logro ya desbloqueado no se re-dispara.** La entrada `alreadyUnlocked` del vector es eso.
- **`unlockedAt` nunca vuelve a nulo** y un desbloqueo **no se revoca**, ni al borrar la sesión
  que lo desbloqueó (AD-17, CAP-15).
- Las horas y las rachas se calculan en **hora local**, con `ClockPort.calendar`. Es la
  divergencia `localTime` ya declarada: en Swift el vector divergente **debe pasar**; es
  `domain.js` quien lo falla.
- `between` es **inclusiva en los dos extremos**. `[5, 7]` es 05:00–07:59 y `[21, 23]` es
  21:00–23:59.
- La categoría de clima se deriva **del código WMO, no del texto**. La lista ya existe y cuadra
  con los vectores; lo que falta es el puente a `WeatherCategory`.
- **Sin clima, los logros climáticos no se cumplen** — no se cumplen como falsos ni como
  verdaderos: no se evalúan.

**Never:**
- No se toca el catálogo: ni claves, ni umbrales, ni comparadores, ni textos. AD-5, y la única
  excepción declarada (`early_bird` · `description`) ya está aplicada y cerrada.
- No se evalúa al abrir el historial, ni al pintar el grid, ni al borrar (AD-17).
- No se escribe `achievements.json` desde ningún sitio que no sea `AchievementsStore` (AD-16), y
  sus intenciones nuevas viven en `AchievementsStore+*.swift`.
- No se implementa la **pantalla** de logros (3.3) ni la **celebración** visible (3.4). Esta
  historia produce el desbloqueo y la señal.
- No se añade `case other` a `WeatherCategory` si no hace falta: hoy el único umbral de categoría
  del catálogo es `"rain"`.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Salida esperada | Error |
|---|---|---|---|
| Primera caminata | historial vacío, 500 m, sin clima | `first_session` y nada más | N/A |
| Umbral exacto de sesión | 1.000 m exactos, meta `gte 1000` | `first_km` se desbloquea | N/A |
| Ya desbloqueado | `first_km` en `alreadyUnlocked`, 2.000 m | **no** vuelve a salir | N/A |
| Acumulado con la que cierra | Σ historial 40.000 m + 2.000 m ahora | `marathon_42km` (incluye la que cierra) | N/A |
| Huérfana | `recovered == true` | **ningún** logro se evalúa | N/A |
| Sin clima | `weather == nil` | ni `rain_walker`, ni `hot_walker`, ni `cold_walker` | N/A |
| Lluvia por WMO | `wmoCode` 61 / 80 / 95 | `rain_walker` | N/A |
| No lluvia por WMO | `wmoCode` 3 / 71 / 85 | **no** `rain_walker` | N/A |
| Franja alta inclusiva | inicio 07:59:59 local | `early_bird` **sí** | N/A |
| Justo fuera | inicio 08:00:00 local | `early_bird` **no** | N/A |
| Ritmo ausente | `paceSecPerKm == nil` (< 100 m, AD-4) | **no** `speed_walker` | N/A |
| Racha de 7 | 7 días locales consecutivos con sesión | `7_days_streak` | N/A |
| Racha con hueco | 6 días, hueco, 1 día | **no** | N/A |
| `weekly_goal` al cierre | la semana está cumplida | este motor **no** lo desbloquea | N/A |
| Logros no persistidos | `achievements.json` no escribible | ver Open Question 1 | — |


## Decisiones de Paul (2026-09-21)

**D1 — Sesión primero, logros después. Nunca se pierde la caminata.** Es la prioridad que fijó la
5.1 y no se renegocia: perder el historial es perder meses de caminatas irreconstruibles; perder
un logro es perder un reconocimiento que se puede volver a ganar. Si la app muere en la ventana
entre las dos escrituras, los **4 logros acumulados se curan solos** en el siguiente cierre
—`first_session`, `7_days_streak`, `marathon_42km`, `consistency_30`, porque el historial ya
incluye la caminata anterior y la evaluación es determinista— y los **9 de sesión se pierden**.
Se acepta a sabiendas: la alternativa era un logro fantasma **irrevocable**, y un logro que miente
es peor que uno que falta, porque el que falta se puede volver a ganar y el fantasma no se puede
quitar.

**D1a — Consecuencia: el hook de AD-17 se mueve, y la 5.1 lo había marcado suponiendo lo
contrario.** El comentario de `SessionStore+History.swift:38-39` sitúa la evaluación **antes** del
`append`, que es el orden de "logros primero". Con D1 va **después de un `append` con éxito**. El
comentario se corrige, citando esta decisión: no es una desviación de la spec de la 5.1, es una
pregunta que la 5.1 no podía responder y dejó señalada.

**D1b — Consecuencia: los dos caminos de persistencia evalúan, y el "único punto" se hace
literal.** Con sesión primero, si el `append` falló **la evaluación no ocurrió**, así que
`retrySavingFinishedWalk()` —el camino de `leaveSummary()`— también tiene que evaluar. Para que
"la evaluación ocurre en un único punto" sea verdad y no una frase, la evaluación se extrae a
**un solo sitio al que llamen los dos caminos**, en vez de copiarla en ambos. `HistoryStore.append`
es idempotente por `startedAt` y devuelve `true` si el registro ya estaba, así que el reintento no
duplica nada.

**D1c — AD-17 no se enmienda, y conviene decir por qué.** Su letra dice "dentro de la misma
transacción que la persiste", y **esa transacción conjunta no existe**: AD-9 hace la escritura
atómica por fichero y AD-16 les da dueños distintos. Lo que AD-17 previene —que un logro se
evalúe al abrir el historial, al pintar el grid o al borrar, y se dispare dos veces— **se cumple
íntegro**: hay un único punto, en el cierre. La imposibilidad de atomicidad conjunta sigue
registrada en `deferred-work.md` como lo que es: un límite conocido, no un pendiente.

**D2 — La deriva del paquete SPEC se cierra en esta historia.** Tres ediciones: acotar la
assumption **A-3** de `SPEC.md:119` a *"íntegro salvo la divergencia declarada de
`early_bird`·`description`, ver AD-6"*, lo mismo en la cabecera de `achievements.md:3`, y corregir
la **columna de descripción** de la fila 10 de `achievements.md:18`, que hoy se contradice con su
propia columna de regla. *Razón:* el compilador de contexto de cada épica **lee ese paquete**, así
que dejarlo desfasado contamina el contexto de todas las historias que vengan — y una fila que se
contradice a sí misma es justo lo que en esta sesión hemos encontrado tres veces y cuesta caro
cuando alguien la lee como verdad.

</frozen-after-approval>

## Code Map

**Campos compartidos de `SessionStore` que toca este cambio** (lección L3, regla (b) del A-7):
`unsavedFinishedRecord` y `finishedWalkNotPersisted`, los dos que la 5.1 usa para recordar una
caminata que no se pudo guardar. **Su invariante: van juntos.** `unsavedFinishedRecord` no nulo
implica `finishedWalkNotPersisted == true`, y se limpian a la vez en los dos caminos de éxito
(`SessionStore+History.swift:45-46` y `:61-62`). Un tercer sitio que toque uno sin el otro rompe
el resumen. La evaluación de logros entra **entre** materializar el registro y persistirlo, así
que corre con esos dos campos en su estado intermedio.

**El molde del motor — copiar, no inventar**
- `Domain/Engines/WeeklyProgress.swift` — `public enum GoalEngine` (L93-164): namespace **sin
  casos**, todo `static func`, reloj y calendario **por parámetro**
  (`weeklyProgress(records:goalKm:now:calendar:)`, L105-110), no lanza, devuelve un struct de
  valor cuyo `init` **normaliza en vez de lanzar** (L48). Auxiliares privados salvo el que hace
  falta exponer para poder ejercitar un suelo (L139). Esa es la forma.

**El catálogo, congelado y ya validado**
- `WalkTracker/Resources/achievements.json` — las 14 entradas con `metric`, `threshold` y
  `comparison`. `early_bird.description` ya dice *"Camina antes de las 8:00"*, con su divergencia
  declarada y fijada por valor en `Scripts/vectors/run-js.js`.
- `Domain/Achievements/AchievementCatalog.swift` — `decode(from:)` (L104), `validate()` (L119),
  `definition(for:)` (L141), y `hasCoherentThreshold` (L146-161), que valida **forma** y no
  compara valores: `case (_, .between, .range(min, max))` exige `min <= max` y admite `min == max`.
- `Domain/Achievements/AchievementMetric.swift` — `AchievementMetric` con sus nueve casos (L8-24,
  cada uno documentando **sobre qué dato** se mide), `AchievementComparison` con `gte, lte, eq,
  gt, lt, between` (L30) —`lte` no lo usa ningún logro—, `WeatherCategory` con **solo** `case rain`
  (L34-36), y `AchievementThreshold` (L40-67) con `number`/`range`/`category`.
  **La comparación no está implementada en ningún sitio.**

**La tabla métrica → dato, con los tres que no son directos**
- Directos desde `SessionRecord`: `sessionDistanceM` ← `distanceM`; `tempC` ← `weather?.tempC`;
  `paceSecPerKm` ← `paceSecPerKm` (`Int?`, ausente bajo 100 m por AD-4).
- Agregados sobre historial **+ la que cierra**: `totalDistanceM`, `sessionCount`.
- **No directos:** `startHourLocal` y `consecutiveDays` necesitan el calendario local;
  `weatherCategory` necesita el puente que falta.

**El clima: la mitad que existe y la que falta**
- `Domain/Weather/WeatherSnapshot.swift` — `WeatherCondition` (L8-21) con
  **`init(wmoCode:)`** ya escrito: `case 51...67, 80...82, 95...99: .rain`, resto `.other`. Es la
  **única lista de códigos de lluvia en Swift** y **cuadra con los vectores** (61/51/67/95/99/80/81/82
  son lluvia; 3, 71 y 85 no). `WeatherSnapshot` lleva `wmoCode` (L36) y deriva `condition` (L38).
- **Falta el puente `WeatherCondition` → `WeatherCategory`.** Son dos enums distintos y
  `WeatherCategory` no tiene productor. El comentario de `WeatherSnapshot.swift:6` ya lo anticipa.
- La v3 hace otra cosa —regex sobre el **texto localizado** (`motivation.js:116`)— y de ahí sale
  la divergencia `wmoCategory` de los tres chubascos 80/81/82.

**Las rachas, y por qué divergen**
- `motivation.js:154-176` (`checkStreak`) — agrupa por clave `YYYY-MM-DD` construida con
  `getUTCMonth/Date/FullYear`, deduplica con `Set`, ordena descendente y cuenta diferencias
  exactas de un día. Dos guardas: `sessions.length < days` y `dates.length < days`. El relleno de
  ceros está comentado en el propio JS porque sin él `"2026-9-25"` ordenaba después de
  `"2026-10-1"`. **En Swift la agrupación es por día local**: de ahí `localTime`.

**Los dos caminos de persistencia, que hoy no están cubiertos igual**
- `WalkTracker/Application/SessionStore+History.swift` — `history.append` en **L40**
  (`saveFinishedWalk`, con el hueco de AD-17 marcado en L38-39) y en **L57**
  (`retrySavingFinishedWalk`, **sin** pasar por ahí). Tres entrantes:
  `SessionStore.swift:431` (`confirmFinish`) y `SessionStore+Recovery.swift:154` (`closeOrphan`)
  por el primero, `SessionStore.swift:482` (`leaveSummary`) por el segundo.
- `WalkTracker/Application/HistoryStore.swift:116-122` — `append` es **idempotente por
  `startedAt`** y devuelve `true` si el registro ya estaba, sin reescribir. Importa para el
  reintento.

**Dónde se escribe el desbloqueo**
- `WalkTracker/Application/AchievementsStore.swift` — `unlocks` (L37), `unlock(forKey:)` (L81),
  `save(applying:)` (L95) con la puerta "sin lectura buena no se escribe" y un reintento.
- `WalkTracker/Application/AchievementsStore+Goal.swift` — `unlockWeeklyGoal(at:)` (L34),
  **idempotente**, es el molde de una intención de desbloqueo.
- `Domain/Ports/AchievementUnlock.swift` — `key`, `unlockedAt: Date?`, `progress: Double`, con
  `init` que lanza si `key` está vacía o `progress` es negativo o no finito.

**Registrar los vectores**
- `WalkTrackerTests/Vectors/VectorHarness.swift:190-199` — `swiftDomain.implementations`, hoy con
  8 entradas. `knownFunctions` (L175-179) **ya lista** `evaluateAchievements`, `checkStreak` y
  `checkTimeOfDay`, así que hoy salen `.pending`. Añadirlas aquí es lo que las pone a romper.
- `SwiftDomainPorts.weeklyProgress` (L383-425) es el molde de una implementación: lee
  `vector.timeZone`, construye el calendario ISO-8601 con `firstWeekday = 2`, materializa
  `SessionRecord` reales desde el JSON y lanza `VectorInputError` prefijado con el nombre.
- `VectorDivergence` (L63-68) con sus dos casos y la regla: **en Swift el divergente debe pasar**.
  Nota de L524-527: un divergente de `evaluateAchievements` **no** lleva `expectedJs`.
- `Scripts/verify-domain.sh` — `DOMAIN_SUITES` es lista explícita: un `@Suite` nuevo de dominio
  **debe añadirse** o el gate rompe nombrándolo (B-6). Es lo que pasó en la 3.1 con
  `GoalEngineTests`.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Achievements/WeatherCategory` -- el puente desde `WeatherCondition` (o desde
  `wmoCode`), sin duplicar la lista de códigos -- hay **una** lista de lluvia y debe seguir
  habiendo una.
- [x] `Domain/Engines/AchievementEngine.swift` -- el motor: `switch` exhaustivo sobre
  `AchievementMetric`, comparación por `AchievementComparison`, reloj y calendario por parámetro
  -- es lo que ejecutan los 51 vectores.
- [x] `Domain/Engines/AchievementEngine.swift` -- la racha por días **locales** consecutivos --
  `checkStreak` y sus 8 vectores.
- [x] `WalkTrackerTests/Vectors/VectorHarness.swift` -- registrar `evaluateAchievements`,
  `checkStreak`, `checkTimeOfDay` y `achievementCatalog` en `swiftDomain` -- sin esto los 65
  vectores siguen `.pending` y el gate lo dice.
- [x] `WalkTracker/Application/AchievementsStore+Evaluation.swift` -- la intención que persiste
  los desbloqueos nuevos -- AD-16: un solo escritor.
- [x] `WalkTracker/Application/SessionStore+History.swift` -- la evaluación **después de un
  `append` con éxito**, extraída a **un solo sitio** al que llamen los dos caminos (D1, D1b), y
  corregir el comentario de L38-39, que la situaba antes (D1a).
- [x] `_bmad-output/specs/spec-walktracker-ios/SPEC.md` y `achievements.md` -- las tres ediciones
  de D2 -- el paquete que se compila como contexto deja de mentir.
- [x] `Scripts/verify-domain.sh` -- añadir el `@Suite` nuevo a `DOMAIN_SUITES` -- o el gate rompe
  nombrándolo.

**Acceptance Criteria:**
- Dado `bash Scripts/verify-domain.sh`, entonces la línea de pendientes de AD-6 **queda vacía o
  solo con lo que esta historia no porta**, y los 65 vectores pasan — los divergentes contra su
  `expected`, nunca contra `expectedJs`.
- Dado un divergente de `wmoCategory` ejecutado contra el texto de la v3, entonces **falla**.
- Dado que se añade un caso a `AchievementMetric` sin rama en el motor, entonces **no compila**.
- Dado un registro con `recovered == true`, entonces **ningún** logro se desbloquea.
- Dado `bash Scripts/check-project-shape.sh` y `check-spec-shape.sh`, entonces verdes.
- Dada la suite completa, entonces el número de casos ejecutados **crece**, contado en el
  `.xcresult`.

## Implementation Notes

**Tres tipos en `Domain/Engines/AchievementEngine.swift`, y ninguno es una clave de logro.**
`AchievementEngine` es el motor, `AchievementMeasurement` el valor de una métrica ya leída, y
nada más. El motor **no sabe qué logros existen**: recibe el `AchievementCatalog` y, para cada
entrada, lee la métrica que la entrada nombra y la compara con su umbral por el comparador que la
entrada declara. En todo el fichero no hay ni una clave escrita —ni `first_km`, ni
`weekly_goal`—, y eso es lo que hace verdad "catálogo en datos, evaluación en Swift" (AD-5):
cambiar un umbral es cambiar `Resources/achievements.json`, no el motor. `weekly_goal` sale igual
porque su **métrica** (`weeklyGoalMet`) no se mide aquí, no porque su clave esté en una lista
negra; la diferencia importa el día que alguien renumere algo.

**Los dos `switch` sin `default`, y por qué son dos.** El de `AchievementMetric` es el que la doc
del enum prometía: una métrica nueva sin rama no compila. Se añadió el mismo trato al de la
**comparación** —`satisfies(_:_:_:)` cubre los seis casos de `AchievementComparison` y las formas
de umbral, con la misma estructura de tuplas que `AchievementDefinition.hasCoherentThreshold`—
porque el agujero era simétrico: un comparador nuevo sin rama habría caído en un `false`
silencioso, que es un logro que no se desbloquea nunca. Las combinaciones incoherentes (una
categoría con `gte`, un `between` sin intervalo) devuelven `false` a propósito: son la **segunda**
puerta, porque `AchievementCatalog.validate()` ya las rechaza al arrancar y la app no arranca.

**La ausencia se representa con `nil`, y es una sola regla para cinco casos.** Sin clima, sin
ritmo (AD-4), con un clima que no es lluvia, y con `weeklyGoalMet`, la métrica **no se puede
medir** y el logro **no se evalúa**: ni se cumple ni se incumple. Un `case .absent` dentro de
`AchievementMeasurement` habría obligado a decidir qué hacer con él en cada comparación —seis
ramas más, y la que se olvidara lo haría en silencio—. Así, "sin clima los climáticos no se
cumplen" no es una guarda escrita tres veces: es la forma del tipo.

**`speed_walker`: la decisión pendiente, resuelta donde el epic la dejó.** La regla es
*"paceSecPerKm > 0 y < 480"* y el catálogo solo expresa `lt 480`. De las tres salidas registradas
se toma la primera —la guarda vive en el evaluador—, porque las otras dos tocan el catálogo, que
esta historia tiene en su bloque "Never" y AD-5 congela: cambiar el umbral de un logro cuyos
desbloqueos son **irrevocables** por una limitación de esquema es desproporcionado.
`AchievementEngine.paceMetric(_:)` está **expuesta** —como `GoalEngine.week(from:containing:)`—
porque sus dos ramas son inalcanzables desde un `SessionRecord`: su frontera ya rechaza un ritmo
≤ 0. La guarda se conserva de todos modos en vez de apoyarse en ese invariante, que vive en otro
fichero y puede cambiar sin que nadie mire aquí.

**La racha es una magnitud, no un booleano, y por eso cabe en el catálogo.** `checkStreak` de la
referencia responde `true`/`false`; el catálogo compara `consecutiveDays gte 7`. `consecutiveDays`
devuelve **la tirada más larga** de días locales del conjunto, que da exactamente la misma
respuesta —la referencia recorre las fechas ordenadas y devuelve `true` en cuanto una tirada llega
a `days`— y además es un número que el esquema de AD-5 sabe comparar. Las dos guardas del JS
(`sessions.length < days`, `dates.length < days`) quedan implicadas: una tirada de *n* días
necesita *n* días distintos y al menos *n* sesiones. El día siguiente se calcula **con el
calendario** (`date(byAdding: .day, value: 1,)`), no sumando 86 400 s: en la noche de un cambio de
hora un día local no tiene 24 h y la racha se rompería sola — es el mismo argumento por el que
`GoalEngine` no cierra la semana sumando 7 × 24 h, y tiene test propio en `Europe/Madrid`.

**El puente de clima no copia la lista, la compone.** `WeatherCategory` se mudó de
`AchievementMetric.swift` a `Domain/Achievements/WeatherCategory.swift`, con
`init?(_ condition: WeatherCondition)` y `init?(wmoCode:)` encima de `WeatherCondition.init(wmoCode:)`.
**Sigue habiendo una sola lista de códigos de lluvia** (`51...67`, `80...82`, `95...99`, en
`Domain/Weather/`) y el motor no la ve. No hizo falta `case other`: un clima que no es lluvia
**no tiene categoría**, y "no hay categoría" y "no hay clima" son la misma respuesta para el
catálogo, que solo compara `"rain"`. El `switch` del puente es exhaustivo, así que una condición
nueva obliga a decidir si tiene categoría de logro en vez de caer en un `nil` mudo.

**El orden al cerrar, y lo que cuesta.** D1 se aplicó tal cual: `evaluateAchievements(for:)` se
llama **después** de un `history.append` con éxito, desde los **dos** caminos de persistencia
(D1b). El comentario `↓ AD-17` de la 5.1, que situaba el hueco antes del `append`, se corrigió
citando la decisión. Lo que esto cuesta está probado en los dos sentidos: con el disco caído no se
evalúa **nada** ("Si la caminata no se pudo guardar, NO se evalúa ningún logro" — es la mutación
"logros primero"), y un logro acumulado perdido por un corte **se cura solo** en el cierre
siguiente ("Un logro perdido por un corte se cura solo…"). Los 9 de sesión no se curan, y eso es
lo que D1 acepta a sabiendas.

**"Un único punto" es una función, no una frase.** La evaluación vive en un solo
`private func evaluateAchievements(for:)` al que llaman `saveFinishedWalk` y
`retrySavingFinishedWalk`. Copiarla en los dos habría dejado dos sitios que se van a separar: es
el mismo argumento por el que la 5.1 puso `saveFinishedWalk` en un solo sitio para los dos que
cierran sesión. La idempotencia la sostienen las dos capas de abajo —`HistoryStore.append` por
`startedAt`, `AchievementsStore.unlock(_:at:)` por clave—, así que llamar dos veces por la misma
caminata no duplica ni re-dispara nada.

**El historial que ve el store ya trae la caminata que cierra, y el motor lo sabe.** Después del
`append`, `history.records` la incluye; los vectores, en cambio, dan `history` **sin** ella. El
motor acepta las dos formas y la cuenta **una vez**, con la clave natural `startedAt` —la misma
que usa `HistoryStore.contains(startedAt:)`—. La alternativa era filtrarla en el store antes de
llamar, y eso es justo el tipo de off-by-one que adelanta `consistency_30` una sesión entera sin
que nada lo diga. Tiene test propio ("La que cierra cuenta UNA vez, esté o no ya en el historial").

**El instante del desbloqueo es `record.endedAt`, no `clock.now`.** Es cuando Paul se lo ganó. La
diferencia solo se ve por el camino del reintento —si el disco falla al cerrar y se recupera al
salir del resumen, "ahora" es cuando Paul pulsa un botón— y por eso el test que lo fija usa ese
camino y comprueba además que los dos instantes son distintos.

**La señal, y el sitio donde muere.** `SessionStore.unlockedAchievements` lleva las
**definiciones** del catálogo (nombre y emoji incluidos) de lo que **quedó escrito**, no de lo que
el motor dio por cumplido: un logro celebrado que no está en disco volvería a desbloquearse en el
cierre siguiente y Paul lo vería dos veces. Se limpia en `resetSessionState()`, que es el único
punto de reset. **Consecuencia conocida:** los desbloqueos del **reintento** se escriben en disco
pero su señal se borra un instante después, porque `leaveSummary()` reintenta y **acto seguido**
resetea. No se arregla aquí: esa caminata ya está saliendo del resumen y no hay dónde celebrarla;
los logros están en `achievements.json` y el grid de la 3.3 los enseña.

**Una sola escritura para todos los logros de un cierre.** Una primera caminata de 1,2 km
desbloquea `first_session` y `first_km` a la vez; escribir el fichero una vez por logro
multiplicaría las ventanas en las que un corte deja el estado a medias. `progress` va a `1` en
todos, igual que en `unlockWeeklyGoal(at:)`: un logro **conseguido** no tiene barra que pintar, y
la unidad de la métrica solo importa en la fila de un logro **en curso**, que es de la 3.3. Dos
intenciones escribiendo `progress` con criterios distintos sería la incoherencia de verdad.

**`SessionStore` gana dos colaboradores, los dos obligatorios.** `achievements: AchievementsStore`
y `achievementCatalog: AchievementCatalog`, sin valor por omisión, por la misma razón que los tres
de `SettingsStore` en la 3.1: un fichero, un dueño, **y una sola instancia**. Un segundo
`AchievementsStore` sobre el mismo almacenamiento sería un segundo lector, y el desbloqueo que
escribe el cierre no lo vería el anillo —`unlockWeeklyGoal(at:)` dejaría de ser idempotente contra
lo ya escrito—. Compila igual, así que hay test en `CompositionRootTests` que lo ata por
identidad, al molde del que la 3.1 escribió para el historial. **Los campos compartidos del store
que esto toca** siguen siendo los dos de la 5.1 (`unsavedFinishedRecord` y
`finishedWalkNotPersisted`, que van juntos) más el nuevo `unlockedAchievements`; los tres se
limpian en `resetSessionState()` y nadie más los escribe.

**Los vectores ejecutan el motor, no una copia.** `checkTimeOfDay` no compara la hora a mano:
arma una `AchievementDefinition` **sintética** con `startHourLocal`, `between` y el intervalo del
vector, y la pasa por `AchievementEngine.isEarned`, de modo que sus 5 vectores ejercitan la misma
extracción de hora local y la misma inclusividad que desbloquean `early_bird` y `night_walker`.
`checkStreak` compone `consecutiveDays(...) >= days` sobre la misma función que usa la métrica. Y
`achievementCatalog` lee el catálogo **del bundle de la app**: declararlo en Swift habría dejado
pasar el vector contra una copia mientras el fichero de datos se iba a la deriva, que es
literalmente el incidente de AD-5.

**Dos tests nuevos que cierran agujeros del propio arnés.** (1) "Los divergentes de hora local
fallan si el calendario se fuerza a UTC" ejecuta los 12 divergentes `localTime` de las tres
funciones con el calendario de `motivation.js`: sin él, AD-19 podría dejar de ejecutarse sin que
nada se pusiera en rojo. (2) `equalJSON` del arnés comparaba **como diccionario**, así que dos
booleanos distintos salían iguales — un verde falso justo en el test que comprueba que la
divergencia existe, y que solo se veía al extenderlo a `checkStreak` y `checkTimeOfDay`, cuyos
valores son booleanos. Pasa por `NSObject.isEqual`.

**El gate de forma gana una palabra, no una regla.** `achievements` entra en la lista de pasos
internos de la sección 6, junto a `settings` y `history`: desde que `SessionStore` lo guarda en
una propiedad con ese nombre, `store.achievements.unlock(...)` compilaría desde una vista. La
sección 9b ya lo cubría dentro de `Application/` y su mensaje pasa de "las que estrene la 3.2" a
nombrar `unlock(_:at:)`. El arnés sigue en 220/220: no hay regla nueva que probar.

## Spec Change Log

**2026-09-21 · La fila "Logros no persistidos" de la matriz congelada remite a una `Open Question 1`
que no existe en esta spec. El bloque congelado NO se edita; se registra aquí con lo que se
decidió.**

*Qué dice la matriz.* `| Logros no persistidos | achievements.json no escribible | ver Open
Question 1 | — |`. La spec no tiene sección `## Open Questions`, así que la fila apunta a un sitio
vacío: no es una pregunta abierta, es una referencia rota.

*Qué se decidió, y por qué es lo único coherente con el resto del bloque congelado.* Con
`achievements.json` ilegible o no escribible **no se escribe encima** (es la puerta B-1 que
`AchievementsStore.save(applying:)` ya tenía) y **no se anuncia nada**: `unlock(_:at:)` devuelve la
lista vacía y `SessionStore.unlockedAchievements` se queda vacía. Anunciar un logro que no llegó
al disco sería peor que no anunciarlo, porque en el cierre siguiente volvería a desbloquearse y
Paul lo vería dos veces. **La caminata no se pierde por ello**: el registro ya está en
`sessions.json` —ése es todo el sentido de D1— y `finishedWalkNotPersisted` sigue en `false`. Es
la misma asimetría que la 3.1 dejó escrita para la celebración de la meta: el fallo de un logro no
cancela lo que ya está a salvo.

*Dónde vive.* `SessionStoreAchievementsTests`, "Con achievements.json ilegible no se escribe
encima, no se anuncia nada y la caminata SÍ se guarda", y `AchievementsStore.unlock(_:at:)`, que
lo documenta en su `- Returns:`.

*Qué NO cambia.* La fila de la matriz se queda como está: el bloque está congelado y la
referencia rota es del enunciado, no de lo construido.

## Review Triage Log

**2026-09-21 · Revisión de tres lentes sobre la implementación de la 3.2.** 21 hallazgos.
Veredicto: **21 aplicados, 0 rechazados**. Una fila por hallazgo y sin agrupar, que es la lección
que la 3.1 dejó escrita: la primera versión de su tabla metió tres menores en una fila, y así es
exactamente como un hallazgo desaparece sin dejar rastro.

### A · El invariante de irrevocabilidad, roto por dos caminos (dos lentes por separado)

| # | Hallazgo | Veredicto |
|---|---|---|
| 1 | `unlock(_:at:)` calculaba `pending` contra los `unlocks` **en memoria**, pero `save(applying:)` puede **releer el fichero** antes de aplicar; el closure reescribía filas que la relectura acababa de destapar como ya conseguidas, **moviéndoles el `unlockedAt`** y devolviéndolas como nuevas — es decir, **se volvían a celebrar** | **Aplicado.** La guarda pasa a vivir **dentro del closure**, en `AchievementsStore.upsert(_:into:)`: una fila ya desbloqueada no se toca y devuelve `false`. Lo que se anuncia sale de `writtenKeys`, que se llena dentro del closure, no de la decisión tomada contra el estado viejo. Con test que monta exactamente esa secuencia (lectura fallida transitoria → disco recuperado → `unlock`) y comprueba que el instante no se mueve y que solo se anuncia lo nuevo |
| 2 | Con `achievements.readOutcome == .unreadable`, `unlocks` está vacío, así que el motor recibía `alreadyUnlocked` vacío y daba por **nuevos los catorce**: los reescribía y los anunciaba todos | **Aplicado.** `evaluateAchievements(for:)` sale antes con `guard !achievements.readOutcome.isUnreadable`: **no se evalúa contra un estado que no se pudo leer**. Es la doctrina de B-1 un paso antes de la escritura. Con test del caso peor —fallo **transitorio**, el fichero entero en disco y la escritura no bloqueada por nada— que afirma que no se escribe ni se anuncia nada, que lo que había sigue intacto y que la caminata sí se guarda |

### B · El hueco de verificación más grave: el calendario local, sin pinchar en su costura

| # | Hallazgo | Veredicto |
|---|---|---|
| 3 | Sustituir `calendar: clock.calendar` por un `Calendar` en UTC —lo que hace `motivation.js` y lo que AD-19 prohíbe— dejaba **los 834 tests, los 65 vectores y los cuatro gates en verde**, porque `ClockStub.calendar` estaba clavado en UTC y las únicas zonas no-UTC llamaban al motor **directamente**. En Ecuador `early_bird` no se desbloquearía **nunca** | **Aplicado.** `ClockStub` gana `timeZone: String = "UTC"` (ningún test existente cambia) y `SessionStoreFixture` lo pasa. Dos casos nuevos, uno por costura: `SessionStoreAchievementsTests` cierra a las **11:30 UTC = 06:30 en `America/Guayaquil`** y espera `early_bird`; `SettingsStoreGoalTests` pone "ahora" en el **domingo 20:00 local = lunes 01:00 UTC** con una caminata del sábado, y el anillo suma 7,5 km donde con UTC sumaría 0 — esa segunda exposición viene de la 3.1 y arrastraba igual |
| 4 | La regla que este cambio añadió al gate (`achievements` en `store_props`) **no tenía caso en su arnés**: borrarla dejaba `check-project-shape-tests.sh` en 220/220, porque su único caso con esa palabra es de la sección **9b** | **Aplicado.** Tres llamadas nuevas en la lista de la sección 6: `store.achievements.unlock([], at: now)`, `store.history.append(record)` —que la 5.1 dejó igual de descubierta— y `store.achievementCatalog.achievements.count`, que llega con el hallazgo 18 |

### C · Conducta y honestidad

| # | Hallazgo | Veredicto |
|---|---|---|
| 5 | `leaveSummary()` reintenta y acto seguido resetea, así que **la señal del camino de reintento siempre se descarta**; estaba en las Implementation Notes pero no en el código, y la 3.4 iba a cablearse a esa señal creyendo que el reintento celebra | **Aplicado, decidiendo: se deja morir.** El único destino de `leaveSummary()` es Inicio, así que el resumen ya no está en pantalla y no hay dónde celebrar; inventar una celebración fuera del resumen sería decidir por la 3.4, que es su dueña. La decisión está **en el punto de llamada** y hay test: "El reintento escribe los logros pero NO los anuncia" |
| 6 | `calendar.date(byAdding:)` devolviendo `nil` se trataba igual que un hueco de días: la racha se reiniciaba en silencio por un fallo de calendario | **Aplicado.** Las dos causas se distinguen: con `nil` se **corta el recuento** y se devuelve lo contado, porque reiniciar afirmaría que Paul no caminó ese día, que es lo que nadie sabe (AD-22); el hueco de verdad sigue reiniciando, con su comentario |
| 7 | El filtro de deduplicación de `unlockedAchievements` y su comentario describían un estado **inalcanzable**: el reintento solo corre si el `append` del cierre falló, y entonces no se evaluó nada | **Aplicado.** Filtro fuera y asignación directa, con el comentario diciendo por qué una caminata pasa por ahí una sola vez. Afirmar una concurrencia inventada es peor que no comentar |

### D · Afirmaciones que no se sostenían

| # | Hallazgo | Veredicto |
|---|---|---|
| 8 | El diferido de la 2.1 se cerró diciendo que "el test ya no lleva lista propia", y el test que ese diferido nombraba **seguía igual**: `WeatherSnapshotTests` mantenía a mano ocho códigos que el fichero no tiene (56, 45, 50, 68, 77, 79, 83, 94), que era **literalmente la evidencia del diferido** | **Aplicado: se arregla el test, no la nota.** `WeatherSnapshotTests` saca ahora los códigos del propio `evaluateAchievements.json` —cada vector con clima contra lo que su `expected` dice de `rain_walker`—, y la nota de cierre se corrige para nombrar ese test y no otro. El de 0–99 exhaustivo (`wmoTable`) se queda: es el autoritativo para `WeatherCondition` |
| 9 | `nothingIsPendingAnyMore` afirmaba que un fichero de vectores de una función nueva sin registrar saldría en rojo. **Es falso**: `VectorBundle.files()` itera `knownFunctions` y descarta lo que no tenga fichero | **Aplicado, las dos mitades.** El comentario dice ahora qué **no** alcanza y quién sí lo caza (`run-js.js`, que recorre el directorio), y se añade la aserción que sí es verdad desde aquí: el registro de Swift y `knownFunctions` son el **mismo conjunto**, sin sobras ni faltas |
| 10 | Dos tests de divergencia afirmaban `!= .passed`, que se cumple también con `.pending` y con un `.failed` por error de decodificación | **Aplicado.** Los dos afirman `.failed` por patrón y además que la **razón** nombre el desajuste de valor (`esperado …, Swift da …`), no un fallo al leer la entrada |
| 11 | `epic-3-context.md` **añadía** bullets diciendo que las tres afirmaciones del paquete SPEC siguen desfasadas —las que este mismo commit reescribe— y un encabezado de "dos decisiones pendientes" que esta historia acaba de decidir | **Aplicado.** La deriva pasa a "CERRADA por la 3.2, su decisión D2", con lo que dice ahora cada sitio; el encabezado pasa a "dos decisiones que la 3.2 CERRÓ" y cada una lleva su resolución y **qué heredan la 3.3 y la 3.4** de ella. Ese fichero se compila como contexto de las tres historias que quedan |
| 12 | La spec tenía **dos** bloques "Manual checks (iPhone 14, tras el build)", uno dándolos por hechos y otro declarándolos pendientes | **Aplicado.** Se borra el del enunciado y se queda el que dice la verdad: **pendientes**, con la advertencia de que el primero solo se puede comprobar a medias hasta la 3.4 |
| 13 | `sprint-status.yaml` dejaba la 3.2 en `in-progress` con todas las tareas `[x]` y la verificación completa registrada | **Aplicado.** Pasa a `review`, con el comentario al molde de la 2.1 y la 3.1: qué checks manuales faltan y por qué no es `done` |

### E · Duplicación y superficie

| # | Hallazgo | Veredicto |
|---|---|---|
| 14 | El bloque de upsert de `+Evaluation` era **carácter por carácter** el de `+Goal`, comentario incluido — y son justo los dos sitios que no pueden divergir al arreglar el hallazgo 1 | **Aplicado.** `AchievementsStore.upsert(_:into:)`, privado del store y llamado por las dos intenciones. Dos copias de la guarda serían dos sitios donde se puede arreglar solo uno, que es exactamente lo que el hallazgo 1 describe |
| 15 | `AchievementsStore+Evaluation.swift` no tenía tests propios, al revés que su hermano `+Goal` | **Aplicado.** Suite nueva `AchievementsStore · los desbloqueos del cierre`, con siete casos: la escritura única, la sustitución en su sitio de una fila con `progress` y sin `unlockedAt` —la rama que el hallazgo 1 podía corromper—, el ya desbloqueado en memoria, **el que la relectura destapa**, el fichero ilegible, el fallo de escritura, y el mismo invariante por el camino de `unlockWeeklyGoal` |
| 16 | `night_walker` no tenía test de frontera aunque `early_bird` sí, y su borde de arriba **cruza el cambio de día local** | **Aplicado.** Cuatro casos en `America/Guayaquil`: 20:59:59 fuera, 21:00:00 dentro, 23:59:59 dentro y 00:00:00 del día siguiente fuera — que es el que distingue una franja inclusiva de un "menor que 24" |
| 17 | `AchievementMeasurement` era `public` sin ningún consumidor fuera de su fichero | **Aplicado.** Baja a `internal`: no aparece en ninguna firma que salga de `Domain`. La API pública del motor habla de logros y de números |
| 18 | Se añadió `achievements` a `store_props` pero no `achievementCatalog`, el otro colaborador nuevo de `SessionStore` | **Aplicado, añadiéndolo.** No hay razón para que una vista lea el catálogo a través del store: quien lo necesite (la 3.3) lo recibirá por su propio camino, no colándose por `SessionStore`. Con su caso rojo en el arnés |
| 19 | `AchievementEngine.satisfies` decía reflejar `AchievementDefinition.hasCoherentThreshold`, que es privado en otro fichero: dos `switch` paralelos sobre el mismo espacio sin nada que los ate | **Aplicado.** Test parametrizado sobre `AchievementComparison.allCases` × las tres formas de umbral × dos métricas, **por la API pública**: `validate()` dice si el catálogo admite la forma e `isEarned` si el motor la sabe decidir, con umbrales elegidos para que una forma coherente siempre se cumpla y las dos respuestas tengan que coincidir |
| 20 | La mitad abierta del diferido de la 8.7 nombraba **un** `fatalError`; este commit añade un segundo, el de `AchievementCatalogFixture.bundled`, para la misma condición | **Aplicado.** La entrada nombra los dos y dice que la costura tiene que cubrirlos o el segundo seguirá matando el proceso de test |
| 21 | Dos cargadores del catálogo empaquetado en el target de tests con comportamientos distintos ante el fallo | **Aplicado: la duplicación es deliberada y ahora está dicha, en los dos ficheros.** El arnés de vectores importa **solo `Domain`** a propósito —la misma regla que impide que los vectores importen `WalkTracker` (AD-6)—, así que no puede llamar a `CompositionRoot`. Y el fallo tiene que tratarse distinto: allí rompe **el vector que lo necesita**, con su motivo, porque el arnés existe para nombrar lo que falla; aquí mata el proceso, porque un catálogo inválido deja sin significado a todos los tests que dependen de él |

## Design Notes

**Por qué el `switch` sin `default` es una decisión y no un estilo.** La doc de
`AchievementMetric` promete que una métrica nueva sin rama no compila. Un `default: return false`
convertiría ese error de compilación en un logro que nunca se desbloquea, y nadie se enteraría:
el catálogo está congelado, así que el día que se amplíe será por una decisión deliberada que
merece romper el build.

**Por qué la lista de códigos de lluvia no se copia.** Ya existe una, en
`WeatherCondition.init(wmoCode:)`, y cuadra con los vectores. Una segunda lista en el motor sería
dos fuentes de verdad para la misma pregunta, y la que se quedara atrás lo haría en silencio —es
la lección L2 del Epic 1, y el diferido que la 2.1 dejó apuntado a esta historia pedía justo
esto: *"unificar `WeatherCondition.rain` con `WeatherCategory.rain` cuando el Epic 3 evalúe
`rain_walker`"*.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` -- esperado: verde, con los 65 vectores ejecutándose y la línea
  de pendientes reducida.
- `bash Scripts/vectors/red-path-tests.sh` -- esperado: sigue en 27/27.
- `bash Scripts/check-project-shape.sh` y su arnés -- esperado: verde, 220/220.
- `bash Scripts/check-spec-shape.sh` -- esperado: verde.
- `xcodebuild test` completo -- esperado: casos ejecutados **crecen**, contados en el `.xcresult`.

**Ejecutado (2026-09-21):**
- `bash Scripts/verify-domain.sh` -> **verde**. **308 tests en 20 suites** (279 en 19 antes). La
  línea de pendientes de AD-6 pasa a `ninguna`: `achievementCatalog (1)`, `checkStreak (8)`,
  `checkTimeOfDay (5)` y `evaluateAchievements (51)` ya no están, y los vectores que pasan en
  Swift suben de 44 a **109** — los 65 de esta historia más los 44 que ya corrían. El suite nuevo
  `AchievementEngineTests` entra en `DOMAIN_SUITES` en el mismo commit; sin eso el propio gate lo
  habría dicho (B-6).
- `node Scripts/vectors/run-js.js` (dentro del gate) -> 109 vectores, **91 pasan en `domain.js`**
  y **18 divergencias esperadas** (`localTime` 15, `wmoCategory` 3), con la divergencia de TEXTO
  del catálogo impresa en verde, como debe.
- `bash Scripts/vectors/red-path-tests.sh` -> **27/27**, sin cambios: esta historia no toca el
  arnés JS.
- `bash Scripts/check-project-shape.sh` -> verde. `bash Scripts/check-project-shape-tests.sh` ->
  **220/220**, sin reglas nuevas: `achievements` entra en la lista de pasos internos de la
  sección 6 y el mensaje de la 9b nombra `unlock(_:at:)`, pero ninguna regla cambia.
- `bash Scripts/check-spec-shape.sh` -> verde, con 61 entradas de `deferred-work.md` y 7 cerradas.
- `xcodegen generate && xcodebuild test ... iPhone 16e CODE_SIGNING_ALLOWED=NO` -> **TEST
  SUCCEEDED**, **834 tests en 64 suites** (781 en 62 antes): **53 casos y 2 suites nuevos**,
  contados por nombre sobre el `.xcresult` y no por `TEST SUCCEEDED` — `AchievementEngine · los
  logros del cierre` **17**, `SessionStore · los logros del cierre` **12**, más los ampliados:
  `Arnés de vectores` pasa de 22 a **29** y `CompositionRoot · cableado del store` de 7 a **8**.
  Sin errores ni warnings propios nuevos: los tres de `SettingsViewTests` son los de antes.

**Mutaciones (cada una aplicada, ejecutada contra `AchievementEngineTests`, `DomainVectorTests`,
`VectorHarnessTests` y `SessionStoreAchievementsTests`, y revertida):**
- **Logros primero** (la evaluación **antes** del `append`, que es donde la 5.1 marcó el hueco)
  -> fallan **2 tests**: "Si la caminata no se pudo guardar, NO se evalúa ningún logro" —con los
  logros escritos de una caminata que no está en el historial, que es el logro fantasma
  irrevocable que D1 evita— y "El reintento del resumen guarda la caminata Y evalúa sus logros",
  que se cae en su propia precondición. Es la mutación obligatoria de esta historia.
- **La huérfana premia** (quitar `guard record.countsForAchievements`) -> fallan **2 tests**, uno
  en el dominio y otro en el store: la huérfana de 13,1 km desbloquearía siete logros, entre
  ellos `first_10km` y `speed_walker`. AD-18 ejecutándose, no escrito.
- **`between` exclusiva en los dos extremos** -> fallan **4 tests** y **8 vectores**: "early_bird
  llega a las 07:59:59 locales y se corta a las 08:00:00", los de franja horaria de
  `evaluateAchievements.json` y los dos tests del arnés que afirman que no queda nada pendiente.
- **La racha agrupada en UTC** (forzar `timeZone = UTC` en `consecutiveDays`, que es literalmente
  lo que hace `motivation.js` con `getUTCFullYear/Month/Date`) -> fallan **6 tests** y **4
  vectores**: "Los mismos instantes dan una racha en local y otra en UTC", los divergentes de
  `checkStreak` y de la racha de `evaluateAchievements`, y el test que comprueba que los
  divergentes fallan contra su `expectedJs`. Es AD-19 **ejecutándose**, no escrito.
- **La que cierra contada dos veces** (quitar la guarda por `startedAt` y hacer siempre
  `history + [record]`) -> falla **1 test**, "La que cierra cuenta UNA vez, esté o no ya en el
  historial". Ningún vector la caza —los vectores dan el historial **sin** la que cierra— y por
  eso ese caso existe: es exactamente el off-by-one que adelantaría `consistency_30` una sesión.
- Árbol restaurado y las cinco revertidas; la suite completa vuelve a **TEST SUCCEEDED** después.

**Ejecutado tras la revisión de las tres lentes (2026-09-22):**
- `bash Scripts/check-project-shape.sh` -> verde. `bash Scripts/check-project-shape-tests.sh` ->
  **223/223** (220 antes): tres casos nuevos en la sección 6, uno por colaborador inyectado que no
  tenía ninguno (`store.achievements.unlock(...)`, `store.achievementCatalog...`,
  `store.history.append(...)`).
- **Camino rojo del propio gate**, porque un caso que no rompe no demuestra nada: quitando
  `|achievements|achievementCatalog` de `store_props`, el arnés baja a **221/223** — fallan
  exactamente los dos casos nuevos cuyas reglas se borraron. El de `history` sigue verde, porque
  esa regla ya existía y lo que le faltaba era el caso.
- `bash Scripts/check-spec-shape.sh` -> verde.
- `xcodebuild test` sobre las 13 suites tocadas -> **TEST SUCCEEDED**, **175 tests en 13 suites**.

**Mutaciones de los arreglos de la revisión (aplicadas, ejecutadas y revertidas):**
- **Sin la guarda de irrevocabilidad dentro de `upsert(_:into:)`** -> fallan **2 tests**, uno por
  cada intención: "Si la relectura destapa un logro ya conseguido, su instante NO se mueve ni se
  re-anuncia" y "unlockWeeklyGoal tampoco mueve el instante cuando la relectura lo destapa". Que
  caigan **las dos** es lo que demuestra que extraer el bloque compartido era el arreglo y no un
  adorno: con la guarda copiada en dos sitios, arreglar uno habría dejado el otro roto en verde.
- **Evaluando contra un estado que no se pudo leer** (quitar el `guard` de `readOutcome`) -> falla
  "Con el estado de los logros sin leer NO se evalúa, aunque el disco se recupere después": los
  catorce logros se darían por nuevos.
- **El calendario cableado en UTC** (sustituir `clock.calendar` por un `Calendar` fijo en UTC en
  `SessionStore+History.swift` y en `SettingsStore+Goal.swift`, que es lo que hace `motivation.js`
  y lo que AD-19 prohíbe) -> fallan **los dos** tests nuevos de costura: "early_bird se decide en
  hora LOCAL: 11:30 UTC son las 06:30 en Guayaquil" y "El anillo suma la semana LOCAL: el domingo
  por la noche en Guayaquil sigue en su semana". **Antes de la revisión esta mutación salía en
  verde** con los 834 tests, los 65 vectores y los cuatro gates: los vectores llaman al motor
  directamente con la zona que declaran y por la costura donde el calendario se cablea no pasaba
  ninguno. Es el hueco más grave que la revisión encontró y ahora está pinchado en los dos sitios.
- Árbol restaurado después de las tres.

**Manual checks (iPhone 14, tras el build): PENDIENTES.** No se han ejecutado. Son los dos de la
spec —caminar 1 km y ver el desbloqueo de `first_km`; cerrar una caminata de menos de 100 m y
comprobar que **no** aparece `speed_walker`—. Ojo con el primero: esta historia produce el
desbloqueo y la señal, **no la celebración visible** (3.4) ni la sección del resumen (3.5), así
que lo que se puede comprobar hoy en el dispositivo es que `achievements.json` del sandbox lleva
la fila, no que salga un toast. Lo que sí queda cubierto sin renderizar es todo lo demás: el
desbloqueo, su instante, su idempotencia y que la huérfana no premia.
