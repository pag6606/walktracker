---
title: 'R1 — la consulta del sistema manda: fin de los pasos estimados fantasma'
type: 'bugfix'
created: '2026-09-17'
baseline_commit: '5675acb2d89c2b1bc838a396d43af8a0a0238012'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-5-reconstruccion-background.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-retro-2026-09-14.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** en el iPhone 14, `CMPedometer` devuelve por consulta de rango **6 pasos menos** que el acumulado
que ya entregó su stream, siempre. La 1.5 trata "menos de lo visto" como "sin dato", así que estima por
cadencia: en la caminata del 2026-09-17 (build 86) eso añadió **1.796** y **433** pasos fantasma, que Paul
descartó a mano. La cadencia usada iba al doble de la real, porque mezcla los pasos de ahora con el tiempo
hasta el inicio del hueco, y los pasos del hueco ya estaban contados por el stream, así que se contaban dos
veces.

Evidencia (registro `WTM1`, sesión `1789649385424`):

| Hora | ms | Ya visto | Resultado | Desenlace | Estimación |
|---|---|---|---|---|---|
| 07:50 | 2 | 59 | 53 | belowSeen | 0 (hueco de 0,5 min) |
| 08:00 | 6 | 1147 | 1141 | belowSeen | 0 (sin muestra previa) |
| 08:09 | 2 | 2149 | 2143 | belowSeen | **1796** (hueco de 8,8 min) |
| 08:12 | 5 | 2581 | 2575 | belowSeen | **433** (hueco de 3,3 min) |

**Enfoque:** la respuesta del sistema manda. Si la consulta responde algo, el sistema tiene el dato y no se
estima. La estimación queda solo para cuando no hay respuesta, y con tres defensas: no estimar si el stream ya
trajo los pasos del hueco, cadencia tomada en el inicio del hueco, y un tope de hueco estimable.

## Boundaries & Constraints

**Always:**
- **Cualquier respuesta no nula cuenta como dato.** Con una muestra del sistema se aplica por `record(_:fromQuery:)`
  —que nunca resta, así que un acumulado menor no baja nada— y **no se estima**. Sustituye la regla de la 1.5
  "un resultado menor que lo visto es incoherente y cuenta como sin dato" [fuente: spec-1-5 Design Notes; retro
  R1 y Q-5; registro del 2026-09-17].
- **Se estima solo sin respuesta:** `nil`, error, timeout o hueco de más de 7 días (AD-8).
- **Tres defensas de la estimación:**
  - **Pasos ya contados:** si `stepsMeasured` creció desde el inicio del hueco, el stream ya trajo esos pasos y no se estima.
  - **Cadencia del inicio del hueco:** se calcula con los pasos medidos que había en el inicio del hueco sobre el tiempo de sesión en ese instante, nunca con los de ahora.
  - **Tope de hueco:** por encima de `maxEstimableGapS` no se estima nada.
- **Lo que no cambia:** el desglose "~", el descarte con confirmación, el registro `WTM1` (los desenlaces siguen
  nombrándose igual, `belowSeen` incluido) ni el tope de reconciliación de 1 s.
- `verify-domain.sh`, los gates y la suite completa en verde.

**Decisiones de Paul (2026-09-17):**
- **Tope de hueco estimable:** 20 min, en `formulas.json` como `maxEstimableGapS: 1200`, sin marca de provisional.
  Por encima no se estima nada: la cadencia pasada ya no dice gran cosa.

**Never:**
- Retirar el `GapEstimator`: sigue siendo la degradación cuando el sistema no responde (CAP-3).
- Tocar el conteo del stream, la persistencia, el clima (2.1) ni nada del Epic 2.
- Reescribir la spec de la 1.5: esta corrección la sustituye y queda registrada aquí.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Consulta menor que lo visto (caso real) | visto 2149, consulta → 2143 tras un hueco de 8,8 min | se aplica como dato: medidos siguen en 2149; **estimados 0** | — |
| Consulta mayor | visto 820, consulta → 900 | medidos 900, estimados 0 | — |
| Consulta sin datos | consulta → nil, hueco de 5 min, cadencia 80 spm, pasos sin crecer | estimados +400, marcados "~" | — |
| Timeout | consulta agotada, mismas condiciones | igual que sin datos | — |
| El stream ya trajo el hueco | consulta → nil y `stepsMeasured` creció desde el inicio del hueco | estimados 0, con `skipped=streamAdvanced` | — |
| Cadencia del inicio del hueco (**estimador**) | `GapEstimator`: 1.156 pasos medidos y 631 s de sesión al empezar el hueco; consulta → nil; hueco de 528 s | cadencia 109,9 spm → **967** estimados (redondeo al entero más cercano de 967,04), frente a 1.798 con la cadencia de ahora | — |
| El mismo caso **a nivel de store** | el stream entregó 2.149 pasos antes de volver, con 1.156 al abrir el hueco | estimados **0**: cae en `streamAdvanced`. Los 967 solo se observan en el test unitario del estimador, no de extremo a extremo | — |
| Hueco por encima del tope | consulta → nil y hueco de 25 min (tope 20 min) | estimados 0, con `skipped=gapAboveCap` | — |
| Hueco justo en el tope | consulta → nil y hueco de 20 min exactos | se estima | — |
| Cobertura parcial del hueco | consulta → nil, hueco de 20 min y **un solo** paso medido entregado por el stream durante el hueco | estimados 0: un paso basta para suprimir la estimación entera. **Subconteo deliberado**, no un descuido: la alternativa es volver a estimar sobre pasos ya contados | — |
| Descartar | estimados > 0 y confirmar | vuelven a 0 y se recalculan distancia y ritmo | — |

</frozen-after-approval>

## Code Map

- `WalkTracker/Application/SessionStore+Reconciliation.swift`:
  - `:58` `if let sample, sample.steps >= seen { record(sample, fromQuery: true); return }` es la regla a cambiar.
  - `:65` `guard highestCumulativeSteps == seen else { … }` ya evita estimar si el stream se movió **durante** la
    consulta; el caso real es que se movió **antes**.
  - `:71` llama a `GapEstimator.steps(for:gapStart:gapEnd:)`, que pasa a ser
    `GapEstimator.outcome(for:measuredAtGapStart:gapStart:gapEnd:maxEstimableGapS:)` y devuelve
    `Outcome` (`.estimated(Int)` o `.skipped(Skip)`) en lugar de un `Int`: el store solo traduce la
    razón al registro. La defensa `stepsMeasured > measuredAtGapStart` vive en el dominio, no aquí.
  - `seen` se toma al empezar la reconciliación; `record(_:fromQuery:)` solo sube el máximo y nunca resta.
- `Domain/Session/GapEstimator.swift`:
  - `:19` `minPriorSampleS = 120`;
  - `:48-59` `steps(for:gapStart:gapEnd:)` calcula la cadencia con `session.metrics(at: gapStart)`, que usa los
    pasos **actuales**: de ahí el doble;
  - `:31` `estimateSteps(cadenceSpm:gapS:)` tiene vectores de AD-6 y **no cambia**.
- **Campos compartidos del store** (lección L3): `backgroundedAt` (inicio del hueco), `highestCumulativeSteps`,
  `lastSampleAt` y su tope, `segmentStart`. Un campo nuevo con los pasos medidos al empezar el hueco se fija
  donde se fija `backgroundedAt` (`SessionStore.swift`, fases de la escena) y al restaurar
  (`SessionStore+Recovery.swift`), y se limpia en `resetSessionState()`.
- `Domain/Formulas/Formulas.swift` + `WalkTracker/Resources/formulas.json`: `constantNames`, `provisional` (hoy
  vacío) y las constantes ya fijadas (`reconciliationTimeoutS` 1, `orphanSessionThresholdS` 21600).
- `WalkTrackerTests/Application/SessionStoreReconciliationTests.swift`: `queryBelowSeenIsNoData` afirma hoy la
  regla vieja y hay que darle la vuelta; `gapWithoutData`, `timeoutDegrades` y
  `streamDuringTimeoutDoesNotEstimate` deben seguir pasando.
- `WalkTrackerTests/Scenarios/GapReconstructionScenarios.swift`: escenarios del estimador (120 s, pausa, cadencia
  solo de medidos) y los sitios portados de la v3.
- `_bmad-output/implementation-artifacts/8-4-medicion-referencia.md`: el veredicto del gate dice que R1 "no
  apareció"; hay que añadir lo que sí apareció el 2026-09-17.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Application/SessionStore+Reconciliation.swift`: cualquier muestra no nula se aplica y corta la
      estimación; estimar solo sin respuesta, y solo si los pasos medidos no crecieron desde el inicio del hueco.
- [x] `Domain/Session/GapEstimator.swift`: la cadencia se calcula con los pasos medidos al inicio del hueco, y el
      tope de hueco según la Open Question. `estimateSteps` y sus vectores no cambian.
- [x] `Domain/Session/GapEstimator.swift`: `steps(...) -> Int` pasa a `outcome(...) -> Outcome`, con `Skip`
      (`notActive`, `streamAdvanced`, `noPriorSample`, `gapAboveCap`, `noCadence`) y la defensa del avance del
      stream movida del store al dominio. `MeasurementLog.EstimateSkip` copia los cinco casos con el mismo
      `rawValue` y el store escribe en el registro `WTM1` **qué** defensa actuó, no solo un 0.
- [x] `WalkTracker/Application/SessionStore.swift` + `SessionStore+Recovery.swift`: pasos medidos al inicio del
      hueco, fijados junto a `backgroundedAt` y al restaurar, limpiados en el reset.
- [x] `Domain/Formulas/Formulas.swift` + `formulas.json` + `FormulasTests`: `maxEstimableGapS: 1200` (> 0 y finito),
      en `constantNames` y fuera de `provisional`; el store se lo pasa al `GapEstimator`.
- [x] `WalkTrackerTests/`: la matriz entera, incluido el caso real con las cifras del registro, y dar la vuelta a
      `queryBelowSeenIsNoData`.
- [x] `_bmad-output/implementation-artifacts/8-4-medicion-referencia.md`: registrar la evidencia del 2026-09-17
      (las 4 consultas `belowSeen`, las estimaciones de 1.796 y 433, los descartes) y que el criterio
      `stepsEstimated = 0` falla en condiciones reales con la regla vieja.

**Acceptance Criteria:**
- Given una consulta que devuelve menos pasos de los ya contados, when se reconcilia, then no se estima nada y los
  pasos medidos no bajan.
- Given el iPhone 14 con una caminata de al menos 20 min y varios ratos con la pantalla bloqueada, when vuelvo a la
  app, then no aparece ningún paso estimado y los pasos siguen cuadrando con Salud.

## Implementation Notes

- **`SessionStore+Reconciliation.swift`:** `if let sample { record(sample, fromQuery: true); return }`. Cualquier
  muestra no nula corta la estimación; `record` solo sube el máximo, así que un acumulado menor no baja nada. La
  guarda vieja `highestCumulativeSteps == seen` se sustituye por `session.stepsMeasured <= measuredAtGapStart`, que
  la subsume (los medidos son monótonos y el tramo no cambia durante un gap) y cubre además el caso real: el stream
  entregó **antes** de volver, no durante la consulta. Su desenlace en el registro sigue siendo `skipped=streamAdvanced`.
- **`GapEstimator.outcome(for:measuredAtGapStart:gapStart:gapEnd:maxEstimableGapS:)`:** sustituye a
  `steps(...) -> Int` y devuelve `Outcome` —`.estimated(Int)` o `.skipped(Skip)`— para que el registro pueda
  decir **por qué** no se estimó. Las cinco razones de `Skip`, en el orden en que se comprueban:
  `notActive`, `streamAdvanced`, `noPriorSample`, `gapAboveCap`, `noCadence`. La cadencia sale de
  `MetricsCalculator.cadenceSpm(stepsMeasured: measuredAtGapStart, activeSeconds: session.elapsedS(at: gapStart))`, no de
  `session.metrics(at: gapStart)`, que usaba los pasos de ahora. Un gap por encima de `maxEstimableGapS` no
  estima. `estimateSteps(cadenceSpm:gapS:)` y sus 8 vectores de AD-6 no cambian.
- **`streamAdvanced` vive en el dominio.** La comprobación `session.stepsMeasured <= measuredAtGapStart` está
  dentro de `outcome(...)`, no en el store: la función recibe `session` y `measuredAtGapStart`, que pueden
  contradecirse, y quien decide con esos dos datos es quien debe comprobarlos. El store solo traduce la razón
  a `MeasurementLog.EstimateSkip` y la escribe.
- **Campo nuevo `stepsMeasuredAtGapStart: Int?`** (lección L3): se fija junto a `backgroundedAt` en
  `appDidEnterBackground()` (conservando el del gap más temprano, como el propio `backgroundedAt`) y al restaurar
  (`snapshot.stepsMeasured`); se limpia en `appDidBecomeActive()`, en `confirmFinish()`, tras la restauración y en
  `resetSessionState()`. Sin él no se estima.
- **`maxEstimableGapS: 1200`** en `formulas.json` y en `Formulas` (> 0 y finito, en `constantNames`, fuera de
  `provisional`); `CompositionRoot` se lo pasa al store y el store al `GapEstimator`.
- **Registro `WTM1` sin cambios de formato:** `belowSeen` sigue existiendo y ahora significa "dato que va por detrás
  del stream". En `Scripts/walk-report/report.js` sale de `DEGRADED` (ya no degrada, así que no puede disparar un
  falso R2) y su aviso dice que se aplica; el aviso de `skipped` se reescribe en los mismos términos.
- **Efecto colateral aceptado:** un tramo de más de 7 días con un gap largo ya no estima, porque su gap supera el
  tope de 20 min. La rama sigue viva para una sesión larga con un gap corto, y tiene su test
  (`stretchOlderThanSevenDaysWithShortGapIsEstimated`). El `log.info` de esa rama dice lo que pasa de verdad: no
  se consulta, y se estima **solo si el gap cabe en el tope**.
- **Tests:** `queryBelowSeenIsNoData` → `queryBelowSeenIsStillData` (se aplica, medidos no bajan, estimados 0) más
  `queryBelowSeenDoesNotLowerSystemDistance` (tampoco baja `systemDistanceM`),
  `realBelowSeenWalkHasNoPhantomSteps` con las cifras del registro (1156 → 2149, consulta 2143, gap de 8,8 min),
  `zeroSampleCountsAsData`, `streamDuringGapDoesNotEstimate`, `secondBackgroundKeepsTheFirstGapSteps` (dos
  backgrounds con el stream avanzando en medio), `gapAboveTheCapIsNotEstimated`, `gapAtTheCapIsEstimated` y
  `stretchOlderThanSevenDaysWithShortGapIsEstimated`; en recuperación,
  `relaunchUsesSnapshotStepsAsGapBase`; en el composition root, `storeGetsMaxEstimableGap` (el tope llega de
  `formulas.json` al store). En los escenarios, `estimatorUsesCadenceAtGapStart` (**967** con la cadencia del
  inicio del gap frente a 1798 con la de ahora), `estimatorSkipsWhenStreamAdvanced` y `estimatorCapsTheGap`, todos
  sobre `Outcome`, así que cada 0 se afirma con su razón. `gapWithoutData` pierde el argumento
  `.sample(steps: 0)`, que ahora es dato. `FormulasTests` valida la constante nueva; `MeasurementLogTests` separa
  `belowSeen` de las consultas sin respuesta.

## Spec Change Log

- **2026-09-18 · triaje de las tres lentes de revisión sobre el diff.** Cambios en el bloque congelado, todos
  para que la matriz describa lo que el código hace y a qué nivel se observa, sin renegociar el
  comportamiento acordado: la fila "cadencia del inicio del hueco" queda marcada como **del estimador** y se
  parte en dos, con la fila nueva del mismo caso **a nivel de store** (cae en `streamAdvanced`, da 0); el
  "~968" pasa a **967** con su redondeo; y se añade la fila de **cobertura parcial** (un solo paso medido
  durante un hueco de 20 min suprime la estimación entera: subconteo deliberado). Fuera del bloque congelado:
  `steps(...)` pasa a `outcome(...)` con las cinco razones de `Skip` en el Code Map, las tareas y las notas de
  implementación; y las notas de diseño dejan por escrito el redondeo del 967 y por qué `schemaVersion` de
  `formulas.json` no sube.

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH/VG/EC · Un `steps=0` en el registro no dice **qué defensa actuó**: el tope de 20 min, `minPriorSampleS` y "estimó y salió 0" salen iguales | high | Real, y es justo lo que hay que leer en el iPhone: la aceptación que queda se juzga sobre ese log. `EstimateSkip` solo tenía `streamAdvanced` | patch (`outcome(...)` con `Skip` de 5 razones) |
| 2 | VG · El cableado de `maxEstimableGapS` de `formulas.json` al store no lo fija ningún test | high | Pre-verificado: `CompositionRoot:68` → `orphanSessionThresholdS` compila y deja los 437 tests en verde, con el tope real en 6 h | patch (`storeGetsMaxEstimableGap`) |
| 3 | VG · Conservar la base del primer hueco en el segundo background (`?? `) no lo fija ningún test | high | Pre-verificado: quitar el `??` reintroduce la cadencia doblada (204 spm) en la forma exacta de la caminata real, sin romper nada | patch (`secondBackgroundKeepsTheFirstGapSteps`) |
| 4 | BH · `GapEstimator.outcome` recibe `session` y `measuredAtGapStart`, que pueden contradecirse, y no lo comprueba | medium | Real; el bug original fue un llamador mezclando "pasos de ahora" con "tiempo de entonces" | patch (la defensa `streamAdvanced` se muda del store al dominio) |
| 5 | VG · Que `belowSeen` haya salido de `DEGRADED` no lo ejercita ningún fixture | medium | Pre-verificado: devolverlo al conjunto deja los 27 casos en verde; el único fixture `belowSeen` no lleva muestra detrás | patch (fixture (a)) |
| 6 | EC · El informe afirma "se aplica como dato y no se estima" también para un log de build ≤ 86, que **sí** estimó | medium | Real: el propio log del 2026-09-17 que motivó el arreglo | patch (coletilla condicional + fixture de log antiguo) |
| 7 | BH/EC · La columna "Pasos de menos" de la medición 8.4 tiene 2/6/2/5, que son los **ms** de cada consulta | medium | Real: `seen − result` vale 6 en las cuatro filas, como dice el texto de arriba. La tabla se contradecía a sí misma | patch (columna renombrada + delta real) |
| 8 | BH · El `log.info` del tramo de más de 7 días sigue diciendo "no se consulta **y se estima**" | medium | Real: con el tope, un hueco largo ya no estima | patch |
| 9 | BH/VG · Faltan tests: base del snapshot tras `restore`, tramo viejo con hueco corto (que sí estima), distancia rezagada que no baja | medium | El caso superviviente del tramo de 7 días se quedó sin ningún test al pasar `stretchOlderThanSevenDays` a esperar 0 | patch (4 tests) |
| 10 | BH/EC · La matriz describe "~968 estimados" en un escenario que la app **no puede producir** extremo a extremo | medium | Real: a nivel de store cae en `streamAdvanced` y da 0; los 967 solo salen del test unitario | patch (fila partida por nivel) |
| 11 | BH · 968 en la matriz, 967 en las notas y en el test | low | Real; error de redondeo arrastrado | patch (967 con su redondeo) |
| 12 | BH · La supresión total por cobertura parcial (un paso medido mata la estimación de un hueco de 20 min) no está pesada en ningún sitio | low | Real; es subconteo deliberado, no un descuido | patch (fila de matriz) |
| 13 | BH · README con la redacción vieja de `skipped=streamAdvanced` y del aviso R1 | low | Real; el README documenta el contrato WTM1 y la salida del informe | patch |
| 14 | BH · `domain-model.md` §4, autoridad que cita `GapEstimator.swift`, no recoge las dos reglas nuevas | low | Real | patch |
| 15 | BH · `backgroundedAt` y `stepsMeasuredAtGapStart` son un invariante emparejado sostenido por comentarios en seis sitios; desincronizados, `reconcile` sale **sin una sola línea de log** | medium | Real. Un `struct PendingGap` lo haría irrepresentable roto, pero es un refactor de la familia A-1, no del arreglo | defer (`deferred-work.md`, enlaza L3 y A-1) |
| 16 | BH · `schemaVersion` de `formulas.json` no sube pese a que `maxEstimableGapS` es una clave obligatoria nueva | low | El fichero viaja siempre dentro del binario: no existe copia antigua que decodificar, así que no hay superficie de compatibilidad que versionar | rechazado (razón en Design Notes) |
| 17 | BH · El aviso `belowSeen` se emite una vez por consulta (4 de 4 en la caminata real) y debería ser una estadística | low | Se corrige la parte falsa del aviso (hallazgo 6), pero la línea por consulta **se conserva**: es la evidencia por la que este chore existe y la que hay que leer en la prueba pendiente | patch parcial · resto rechazado |
| 18 | VG · El fixture `below-seen.txt` modela una secuencia que la app ya no produce | low | Es un log de build anterior, y sigue siendo válido como tal; el informe ahora lo etiqueta como registro previo a la corrección | cubierto por 6 |

## Design Notes

- **Por qué la consulta puede dar menos:** el stream acumula desde el inicio y el sistema consolida su histórico
  con retraso, así que la consulta va unos pasos por detrás. En la caminata medida fueron exactamente 6 en las 4
  consultas. Aplicar la muestra es seguro porque `record` solo sube el máximo.
- **Cuántos pasos son:** la cadencia del inicio del gap da **967** pasos (109,9 spm × 528 s ÷ 60 = 967,04,
  redondeado al entero más cercano). Es el único número de esta spec para ese escenario: donde antes aparecía
  "~968", era el mismo cálculo mal redondeado. Y solo se observa en el test unitario del estimador: a nivel de
  store ese mismo escenario cae en `streamAdvanced` y da 0.
- **Por qué `schemaVersion` de `formulas.json` no sube** aunque `maxEstimableGapS` sea una clave obligatoria
  nueva: el fichero viaja **siempre dentro del binario** y se lee del bundle (`CompositionRoot`), así que la
  única versión que existe en un dispositivo es la que trae ese mismo build. No hay copia antigua en disco, ni
  descargada, ni migrable: no hay superficie de compatibilidad que versionar. `schemaVersion` subiría si el
  fichero pasara a viajar por fuera del binario (Remote Config, fichero de usuario, snapshot persistido).
- **Por qué las tres defensas y no solo la primera:** la primera arregla el caso real. Las otras dos evitan que,
  sin respuesta del sistema, la estimación vuelva a doblarse o a dispararse en un hueco largo.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh`: esperado verde, con los vectores de `estimateSteps` intactos.
- `bash Scripts/check-project-shape.sh` y `xcodegen generate && xcodebuild test … iPhone 16e
  CODE_SIGNING_ALLOWED=NO`: esperado verde, sin warnings propios.

**Resultado (2026-09-17):**
- `bash Scripts/verify-domain.sh`: **verde** (inventario, camino rojo, 109 vectores JS con sus 18 divergencias
  declaradas, 27 vectores Swift y 173 tests en 12 suites).
- `bash Scripts/check-project-shape.sh`: **verde**. `bash Scripts/walk-report-tests.sh`: 27/27.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO`: **TEST SUCCEEDED**, 437 tests en
  39 suites, sin warnings propios.
**Resultado (2026-09-18, tras el triaje de la pasada 1):**
- `bash Scripts/verify-domain.sh`: **verde** (inventario 19/19, 109 vectores JS, 27 vectores Swift, 174 tests en
  12 suites).
- `bash Scripts/check-project-shape.sh`: **verde**, con sus tests 81/81. `bash Scripts/walk-report-tests.sh`:
  **34/34**.
- `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO`: **TEST SUCCEEDED**, 444 tests en
  39 suites, sin warnings propios.
- **Mutación** de los cinco tests nuevos y del fixture (a): cada uno cae por la suya y solo por la suya
  (`DEGRADED` con `belowSeen`, `CompositionRoot:68` mal cableado, `SessionStore:490` sin el `??`, la rama de
  más de 7 días con `return`, la base del snapshot desplazada, y la guarda de "nunca baja" de la distancia).
- **Pendiente:** los checks manuales en el iPhone 14 con el build nuevo.

**Manual checks (iPhone 14, build nuevo):**
- Caminata de 20 min o más con varios ratos bloqueada: sin pasos estimados, y los pasos y la distancia cuadrando
  con Salud.
- El registro nuevo debe mostrar las consultas como `data`, aunque devuelvan menos que lo visto.
- Si alguna línea `estimate` aparece con `steps=0`, su `skipped=` debe decir qué defensa actuó
  (`streamAdvanced`, `gapAboveCap`, `noPriorSample`, `notActive`, `noCadence`).
