---
title: '1.4 — Pausar, reanudar y finalizar la sesión (controles)'
type: 'feature'
created: '2026-09-13'
baseline_commit: '19af94c358676d16545c5d651ceef664a9c7944b'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-3-metricas-en-vivo.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** una sesión abierta no se puede pausar ni cerrar: la única salida es matar la app. El agregado
no conoce `paused` ni `finished`, aunque el ciclo `active → paused → active → finished` es CAP-1
[fuente: domain-model.md#13].

**Enfoque:** portar al agregado pausar, reanudar y finalizar, con el cronómetro descontando la pausa
abierta y la sesión finalizada inmutable. `SessionStore` expone las intenciones y la pantalla de sesión
muestra los controles, con confirmación explícita al finalizar (AD-20).

## Boundaries & Constraints

**Always:**
- **Transiciones:** pausar solo desde `active`, reanudar solo desde `paused`, finalizar desde `active` o
  `paused` [fuente: domain-model.md#30]. Lo demás lanza `invalidTransition`. Pausar una sesión pausada
  también lanza, a diferencia de la v3.
- **Finalizar desde pausa:** acumula primero la pausa abierta y después cierra [fuente: domain-model.md#30].
- **Sesión finalizada:** inmutable; toda mutación lanza error de dominio [fuente: domain-model.md#13].
- **Cronómetro:** `elapsedS = (now − startedAt) − totalPausesS − pausa abierta` [fuente: domain-model.md#35;
  `domain.js:69-77`]. En pausa el tiempo no avanza. Una sesión finalizada queda congelada en su
  `durationS`.
- **Al cerrar:** `durationS` y `pausesS` son enteros redondeados [fuente: domain-model.md#23]. Ritmo y
  cadencia se calculan sobre `durationS`, sin volver a restar las pausas (`domain.js:351-358`).
- **Pausa solo explícita:** pasar a segundo plano o bloquear la pantalla nunca pausa [fuente:
  capabilities.md#CAP-1].
- **Controles:** con la sesión activa, Pausar y Finalizar; en pausa, Reanudar y Finalizar. Objetivo táctil
  ≥ 44 pt y SF Symbols, sin emoji [fuente: ARCHITECTURE-SPINE.md#AD-20].
- **Finalizar:** exige confirmación explícita y no hay un segundo botón "✕" [fuente:
  ARCHITECTURE-SPINE.md#AD-20].
- **Señal de estado:** una sola, "Caminata en curso" o "En pausa". En pausa la distancia se atenúa.

**Never:**
- Persistir la sesión (1.6 y 5.1), logros o celebración (3.x), Salud (6.x), Live Activity (7.x) ni feedback
  (4.x).
- Auto-pausa por quietud o por pasar a segundo plano.
- Reconstruir por consulta los pasos del intervalo en pausa (1.5).
- En el resumen: Salud, logros, kcal, "Nueva caminata" o cualquier magnitud que el dominio no produzca (AD-22).

**Decisiones de Paul (2026-09-13):**
- **Resumen mínimo tras finalizar:** la sesión pasa a un resumen con distancia, tiempo, pasos, ritmo y
  cadencia finales y un único botón "Volver a Inicio". Solo avanza, sin volver a la sesión. La sesión
  finalizada se descarta al salir del resumen, porque aún no hay persistencia.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Pausar | activa, 50 pasos, pausa a +300 s | `paused`, `pausedAt` fijado; el tiempo se congela en 300 s | — |
| Reanudar | pausada desde +300 s, reanuda a +420 s | `active`, `totalPausesS` = 120, `pausedAt` nil, 50 pasos | — |
| Pasos tras reanudar | 50 pasos, +30 | 80 pasos | — |
| Finalizar sin pausas | 4980 pasos, fin a +3720 s | `finished`, `endedAt`, `durationS` 3720, ritmo 1140, cadencia 80,3 | — |
| Finalizar desde pausa | pausa +600→+780, pausa abierta desde +3800, fin a +3900 | `pausesS` 280 y `durationS` 3620; la pausa abierta cuenta | — |
| Transición inválida | pausar pausada, reanudar activa, finalizar finalizada | no muta | `invalidTransition` |
| Mutar finalizada | pasos o distancia del sistema | no muta | `invalidTransition` |
| Segundo plano | activa, la app pasa a background | sigue `active` | — |
| Pasos durante la pausa | caminar 200 pasos en pausa y reanudar | no se suman | — |
| Cancelar el cierre | "Finalizar" → cancelar en la confirmación | la sesión sigue en su estado | — |
| Confirmar el cierre | "Finalizar" → confirmar | resumen con las métricas finales congeladas | — |
| Salir del resumen | "Volver a Inicio" | Inicio sin sesión; "Iniciar caminata" abre una nueva desde cero | — |

</frozen-after-approval>

## Code Map

- `domain.js:69-77` `elapsedS` (resta la pausa abierta solo si `pausedAtMs > startedAtMs`); `:176-183`
  `pause`; `:187-199` `resume`; `:344-372` `finishV3` (acumula la pausa abierta en `:348-350`,
  `durS = round(elapsedS)`, ritmo con umbral 100 y `pace(durS, 0, dist)`, cadencia sobre `durS`,
  `pausesS = round(totalPausesMs/1000)`); `:540-546` `assertMutable`.
- `Domain/Session/Session.swift`: tiene `endedAt: Date?` (sin uso) y `totalPausesS`, pero no pausa
  abierta, `pause`, `resume` ni `finish`. `addMeasuredSteps` (`:70`) y `recordSystemDistance` (`:89`) ya
  lanzan `invalidTransition` fuera de `active`. `metrics(at:)` (`:110-130`) calcula en vivo.
- `Domain/Session/SessionStatus.swift`: casos `active`, `paused` y `finished`, con `rawValue` igual al
  nombre. `Domain/Session/Chronometer.swift`: `elapsedS(startedAt:totalPausesS:now:)`, nunca negativo y sin
  pausa abierta.
- `WalkTrackerTests/Vectors/VectorHarness.swift:249-254`: `SwiftDomainPorts.elapsedS` rechaza `pausedAtMs`.
  `DomainVectorTests.swift:234-244` `elapsedSRejectsOpenPause` exige que un vector con pausa abierta
  (0 → 60000, pausa en 30000, espera 30) **falle**. `elapsedS.json` solo tiene `pausedAtMs: null`.
- `WalkTrackerTests/Vectors/inventory.json`: 23 sitios de la 1.4 en `test/session-v3-tests.js` — `:131`,
  `:132`, `:133`, `:155`, `:156`, `:181`, `:183`, `:186`, `:198`–`:202`, `:215`, `:216`, `:218`–`:220`,
  `:222`, `:224`, `:296`, `:297` y `:351`. `:200` y `:297` afirman `addEstimatedSteps`, que es de la 1.5.
- `WalkTracker/Application/SessionStore.swift`:
  - `start()` solo abre si `session == nil`.
  - `hasSession` es una propiedad guardada, `true` al abrir y nunca `false` hoy.
  - `countSteps(from:)` pone `highestCumulativeSteps = 0` y guarda la tarea en `stepCounting`, que nadie
    cancela.
  - `record(_:)` aplica pasos y distancia y recalcula `metrics`.
  - `stepCountingEnded()` no registra nada si la tarea está cancelada.
- `WalkTracker/Adapters/Motion/MotionAdapter.swift`: un stream a la vez, con muestras acumuladas desde
  `from`. Cancelar la iteración llama a `stopUpdates`, y un `updates(from:)` nuevo sustituye al anterior.
  No se toca.
- `WalkTracker/UI/RootView.swift:53-62`: el `fullScreenCover` usa `Binding(get: store.hasSession, set: {})`,
  así que se cierra cuando `hasSession` pasa a `false`. No se toca.
- `WalkTracker/UI/Session/SessionView.swift`: título fijo "Caminata en curso", distancia a 88 con
  `@ScaledMetric`, `Grid` 2×2 (el tiempo en `TimelineView`) y `ScrollView`.
- `WalkTrackerTests/Support/MotionStub.swift`: cada `updates(from:)` añade una entrada a `updateStarts` y
  sustituye la continuación sin terminar la anterior. `cancelledStreams` cuenta las cancelaciones, y
  `emit`/`finishUpdates` actúan sobre el último stream.
- `SessionStoreTests.swift`: `Fixture` de `SessionStoreMetricsTests` y `waitUntil` a nivel de fichero.
  `ClockStub` tiene `advance(by:)` y `set(_:)`.
- Mockups `ux-walktracker-native/mock-02` y `mock-03` como dirección visual: pausa con la distancia en
  gris. Tienen dos pegas registradas, M-6 (doble indicador) y M-7 ("✕" sin confirmar).

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Session/Chronometer.swift`: añadir `pausedAt: Date?` y restar la pausa abierta como
      `domain.js:69-77`, sin devolver nunca un negativo.
- [x] `Domain/Session/Session.swift`:
      - `pausedAt: Date?`, `durationS: Int?`, `pausesS: Int?` (entero, calculado al cerrar).
      - `pause(at:)`, `resume(at:)` y `finish(at:)`, todas `throws(DomainError)`.
      - `elapsedS(at:)`: en pausa se congela; finalizada devuelve `durationS`.
      - `metrics(at:)`: en una sesión finalizada usa `durationS`.
- [x] `WalkTrackerTests/Vectors/VectorHarness.swift` + `DomainVectorTests.swift`: `elapsedS` acepta
      `pausedAtMs`, y `elapsedSRejectsOpenPause` pasa a afirmar que el vector con pausa abierta **pasa**.
- [x] `WalkTracker/Application/SessionStore.swift`:
      - Intenciones `pause()`, `resume()`, `requestFinish()`, `cancelFinish()` y `confirmFinish()`, más
        el estado `isConfirmingFinish`.
      - Al pausar, cancelar el stream. Al reanudar, abrir otro desde el instante de reanudación,
        conservando pasos y distancia previos: la distancia del sistema del tramo nuevo se suma a la base
        acumulada.
      - Al confirmar, finalizar y cancelar el stream. La sesión finalizada se queda en `session` para el
        resumen, y `hasSession` sigue en `true`, así que el cover no se cierra.
      - `leaveSummary()`: solo con la sesión finalizada. Pone `session` y `metrics` a `nil` y `hasSession`
        a `false`.
- [x] `WalkTracker/UI/Session/SessionView.swift`: título según el estado, distancia atenuada en pausa, botones
      Pausar/Reanudar y Finalizar (≥ 44 pt), y `confirmationDialog` destructivo para finalizar. Con la
      sesión finalizada, muestra el resumen dentro del mismo cover.
- [x] `WalkTracker/UI/Session/SessionSummaryView.swift`: "Caminata completada", las cinco métricas finales
      con los formatos de `UI/Format/` y lectura de VoiceOver, y "Volver a Inicio" (≥ 44 pt).
- [x] `_bmad-output/implementation-artifacts/deferred-work.md`: registrar que el resumen completo (Salud,
      logros, celebración) no tiene historia dueña en `epics.md` (UX-DR4), como hueco para un correct course.
- [x] `WalkTrackerTests/Scenarios/SessionLifecycleScenarios.swift`:
      - Portar los 21 sitios de la 1.4, salvo `:200` y `:297`, que pasan a la 1.5 en `inventory.json`.
      - Añadir la suite a `Scripts/verify-domain.sh`.
- [x] `SessionStoreTests.swift`: la matriz entera en el store, incluidos un stream nuevo al reanudar, los
      pasos de la pausa excluidos y la distancia sumada entre tramos.
- [x] `Localizable.xcstrings`: textos nuevos con `comment`. Después, `xcodegen generate`.

**Acceptance Criteria:**
- Given el iPhone 14 caminando con la sesión abierta, when pulso Pausar, then el tiempo se detiene, veo
  "En pausa" con la distancia atenuada y el botón pasa a Reanudar.
- Given la sesión en pausa, when camino un poco y pulso Reanudar, then el tiempo sigue desde donde se
  detuvo y los pasos dados durante la pausa no se suman.
- Given la sesión abierta, when pulso Finalizar y confirmo, then veo el resumen con las métricas
  finales; si cancelo, la sesión sigue igual.
- Given el resumen, when pulso "Volver a Inicio", then estoy en Inicio y puedo iniciar una caminata nueva
  desde cero.

## Implementation Notes

- `Chronometer.elapsedS(startedAt:totalPausesS:pausedAt:now:)`: `pausedAt` con valor por defecto `nil`; resta
  `now − pausedAt` solo si `pausedAt > startedAt` (`domain.js:75`) y sigue sin devolver negativos.
- `Session`: `pausedAt`, `durationS` y `pausesS`; `pause(at:)`, `resume(at:)` y `finish(at:)` lanzan
  `invalidTransition(from: estado, to: "paused" | "active" | "finished")` y no mutan. En pausa, `elapsedS(at:)` mide
  en `pausedAt` en lugar de restar la pausa abierta: así una pausa en el mismo instante del inicio también congela
  (la guarda `pausedAt > startedAt` del cronómetro la ignoraría). Finalizada, devuelve `durationS`, y
  `metrics(at:)` hereda ese tiempo sin más cambios. Una pausa negativa (reloj hacia atrás) cuenta como 0.
  `durationS` y `pausesS` redondean con `.toNearestOrAwayFromZero`, que es `Math.round` para valores ≥ 0.
- `SessionStore`: `pause()`, `resume()`, `requestFinish()`, `cancelFinish()`, `confirmFinish()`, `leaveSummary()`
  e `isConfirmingFinish`. Cada intención comprueba el estado antes de llamar al dominio, así que una transición
  inválida no hace nada. Al pausar y al finalizar se cancela la tarea del stream; al reanudar, `countSteps(from:)`
  abre otro desde `clock.now` con `highestCumulativeSteps = 0` y `distanceBaseM = systemDistanceM ?? 0`.
  El bucle sale si su tarea está cancelada, de modo que una muestra ya encolada del tramo anterior no se aplica al
  nuevo. `stepCountingEnded()` no toca `isCountingSteps` si la tarea está cancelada, porque puede haber otro tramo
  contando. `confirmFinish()` no exige `isConfirmingFinish`: SwiftUI puede cerrar el diálogo (y cancelar) antes
  de ejecutar la acción del botón.
- `SessionView`: título "Caminata en curso" / "En pausa", distancia en `.secondary` en pausa y controles
  Pausar/Reanudar (un solo botón, para no perder el foco de VoiceOver) + Finalizar (`Label` con SF Symbols, `minHeight: 44`, apilados con tamaños de accesibilidad).
  `confirmationDialog` "¿Finalizar la caminata?" con "Finalizar caminata" destructivo y "Cancelar". La celda
  y la distancia pasan a `MetricCell` y `DistanceHero`, compartidas con el resumen. Con la sesión finalizada se
  pinta `SessionSummaryView`, y la vista guarda el último `FinishedWalk` para seguir mostrándolo mientras el
  cover se cierra.
- `SessionSummaryView`: "Caminata completada", distancia, rejilla 2×2 (pasos · tiempo / ritmo · cadencia) y
  "Volver al inicio" (reutiliza la clave de la pantalla bloqueante). `RootView` no se ha tocado, aunque sus comentarios aún dicen que no hay salida hasta la 1.4.
- `SessionLifecycleScenarios` porta los 21 sitios y añade escenarios nativos (congelado en pausa, pausa en el
  instante del inicio, 280/3620, redondeos, reloj hacia atrás, transiciones inválidas). En `inventory.json`,
  `:200` y `:297` pasan a la 1.5. `elapsedSRejectsOpenPause` pasa a llamarse `elapsedSAcceptsOpenPause`: el
  vector con pausa abierta pasa y uno que la ignora (60 s) falla.
- Verificado: `bash Scripts/verify-domain.sh` en verde (inventario completo con la 1.4 portada, 19 vectores
  Swift pasan). `xcodegen generate && xcodebuild … iPhone 16e CODE_SIGNING_ALLOWED=NO test` → `TEST SUCCEEDED`,
  207 tests y sin warnings propios. Mutaciones comprobadas: quitar la guarda de cancelación rompe
  `staleSampleIsIgnored` (450 pasos en vez de 80) y quitar la base de distancia rompe
  `distanceAddsAcrossStretches` (70 m en vez de 90). **Pendiente:** los checks manuales en el iPhone 14.

- Revisión (pasada 1): 5 parches (test de `store.metrics` tras pausar, `TimelineView` alineado con
  `startedAt + totalPausesS`, `lastFinished` solo sin sesión, un único botón Pausar/Reanudar y la clave
  reutilizada "Volver al inicio") y 2 diferidos (distancia entre tramos con fuentes mezcladas; tests de
  vista). Tras los parches: `verify-domain.sh` verde y 207 tests, `TEST SUCCEEDED`, sin warnings propios.
  **Pendiente:** los checks manuales en el iPhone 14.

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH/EC/VG · La distancia puede bajar o congelarse al reanudar si un tramo trae distancia del sistema y otro no (`distanceBaseM = systemDistanceM ?? 0`) | maybe-false | Misma causa que el diferido de la 1.3 (fuentes mezcladas), ahora alcanzable en cada reanudación porque cada tramo es un stream nuevo. En un iPhone con distancia disponible CoreMotion la da en todas las muestras. Lo zanja registrar muestras de tramos reales en el iPhone 14 | defer |
| 2 | EC/BH · Al pausar o finalizar se pierden los pasos entre la última muestra y la cancelación del stream | low | Real, pero el retraso del podómetro es de ~2,5 s (3–5 pasos por pausa, muy dentro del ±10 %). Recuperarlos exige la consulta por rango y la reconciliación de la 1.5 | rechazado |
| 3 | EC · El `TimelineView` del tiempo se alinea con `startedAt` y, tras pausas fraccionarias, el valor va hasta ~1 s por detrás | low | Real y visible; alinear con `startedAt + totalPausesS` es directo | patch |
| 4 | EC · `lastFinished` puede tapar una sesión nueva si el `@State` sobrevive a un cierre y reapertura rápidos del cover | low | El respaldo se usaba aunque el store tuviera otra sesión, contra su propio comentario; limitarlo a `session == nil` es directo | patch |
| 5 | EC · (afirmación) "conservando pasos y distancia previos" no se cumple con distancia derivada de pasos | maybe-false | Misma causa que la 1 | defer (con 1) |
| 6 | BH · `Chronometer` suma tiempo si `now < pausedAt` con la pausa abierta | false | En la app no se alcanza: `Session.elapsedS` en pausa mide en `pausedAt` sin pasar la pausa abierta; en el arnés coincide con `domain.js:69-77`, que tampoco acota | rechazado |
| 7 | BH · La pausa abierta de `Chronometer` solo la ejercen los vectores, no la sesión | low | Dos caminos dan el mismo valor con `pausedAt ≥ startedAt` y `now ≥ pausedAt`; sin consumidor que diverja hoy | rechazado |
| 8 | BH · `confirmFinish()` finaliza sin exigir `isConfirmingFinish` | low | Decisión documentada por el orden de SwiftUI (cierra el diálogo antes de la acción); el único llamante es el botón del diálogo (AD-20) | rechazado |
| 9 | BH · VoiceOver pierde el foco al alternar Pausar/Reanudar (dos botones en `if/else`) | low | Real; un solo botón con título, icono y acción variables es directo | patch |
| 10 | BH · La distancia del resumen y de la pausa lleva `.updatesFrequently` | low | Cosmético para VoiceOver; exige un parámetro nuevo | rechazado |
| 11 | BH · El `TimelineView` sigue repintando a 1 Hz en pausa | low | Una celda a 1 Hz entra en la cadencia de UI de AD-21; coste despreciable | rechazado |
| 12 | BH · El resumen se arma en la vista; quedaría en blanco si `durationS` o `metrics` fueran nil | false | `finish(at:)` fija `durationS` y `confirmFinish` fija `metrics` en la misma operación | rechazado |
| 13 | BH · `finishedMetricsAreFrozen` no llega a `record(_:)`; `backgroundNeverPauses` pasa por construcción; los `catch` de transición no se alcanzan | low | La guarda de estado de `record` es redundante con los `throws` del agregado (no muta); no hay entrada de segundo plano que probar | rechazado |
| 14 | BH · Comentarios de `RootView` desfasados ("no hay salida antes de la 1.4") | low | Real; la spec fija no tocar `RootView`, y es solo un comentario | rechazado |
| 15 | BH · "Volver a Inicio" duplica la clave "Volver al inicio" con otra capitalización | low | Real; reutilizar la clave existente es directo | patch |
| 16 | BH · Estado de la spec y del sprint no coinciden; "21 sitios salvo `:200` y `:297`" ambiguo | false | Es el orden del flujo (el sprint se sincroniza al presentar); el arreglo del texto editaría la spec | rechazado |
| 17 | BH · La confirmación no avisa de que la caminata no se guarda | low | Decisión de Paul: la finalizada se descarta al salir del resumen hasta la 1.6/5.1 | rechazado |
| 18 | VG · Ningún test afirma `store.metrics` tras `pause()` | low | Verificado por la capa: quitar el recálculo deja todo en verde | patch |
| 19 | VG · Qué pantalla muestra `SessionView` (en curso, pausa, resumen) solo se verifica a mano | low | Verificado por la capa; el proyecto no tiene arnés de tests de vista | defer |

## Design Notes

- **Pasos durante la pausa:** no cuentan, como en la v3 (`assertMutable` rechaza `addSteps` en pausa).
  El podómetro se detiene al pausar (AD-21, energía) y al reanudar abre un stream nuevo; sus muestras
  acumuladas empiezan de cero, así que la pausa queda fuera por construcción.
- **Distancia entre tramos:** `recordSystemDistance` recibe `base + distancia del tramo`, donde `base` es
  `systemDistanceM` al pausar. Así sigue siendo acumulada desde el inicio y nunca baja.
- **Pausar una sesión pausada:** lanza. Es una divergencia deliberada de la v3, que la reescribía y
  perdía la pausa en curso; el modelo de dominio manda.
- **Duración al cerrar:** `durationS = round(elapsedS)` con la pausa abierta ya acumulada, y
  `pausesS = round(totalPausesS)`. Ritmo y cadencia finales salen de `durationS`, igual que `finishV3`
  (los sitios `:183` y `:186` lo afirman).
- **Confirmación:** `confirmationDialog` con "Finalizar caminata" destructivo y "Cancelar". Sale de la
  única superficie declarada, el botón Finalizar de la sesión (AD-20).

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh`: esperado verde, con las citas de 1.1–1.4 completas y el vector de pausa
  abierta de `elapsedS` pasando.
- `xcodegen generate && xcodebuild … iPhone 16e CODE_SIGNING_ALLOWED=NO test`: esperado `TEST SUCCEEDED`,
  sin warnings propios.

**Manual checks (iPhone 14):**
- Pausar: el tiempo se detiene y la distancia se atenúa. Reanudar: el tiempo continúa y los pasos de la
  pausa no se suman.
- Bloquear la pantalla sin pausar: al volver, la sesión sigue activa y el tiempo contó el intervalo.
- Finalizar → cancelar: la sesión sigue. Finalizar → confirmar: resumen con las métricas finales, que no
  cambian aunque siga caminando. "Volver a Inicio" → iniciar otra caminata empieza en 0.
