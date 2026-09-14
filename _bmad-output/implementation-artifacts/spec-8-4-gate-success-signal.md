---
title: '8.4 — Gate del Success signal: batería y precisión en el iPhone 14'
type: 'chore'
created: '2026-09-14'
baseline_commit: 'cb3d6aa65302cb92e346b5f344cc874da5e62882'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-retro-2026-09-14.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** nada demuestra en hardware que una caminata real se registre con precisión y sin castigar la
batería. Las dos constantes de `formulas.json` siguen siendo provisionales, y cuatro dudas de CoreMotion llevan
todo el Epic 1 diferidas por falta de datos. Los epics 2–7 no arrancan sin este gate [fuente: epics.md Story 8.4;
epic-1-retro A-3].

**Enfoque:** instrumentar la sesión para que la caminata deje un registro medible y exportable a mano. Después:
- publicar por TestFlight;
- Paul camina 30 min;
- extraer un informe con un script;
- registrar la medición de referencia y fijar las constantes con valores medidos o decididos.

## Boundaries & Constraints

**Always:**
- **Criterios del gate:**
  - pasos y distancia a ≤ 10 % de Apple Salud;
  - batería ≤ 5 % en 30 min y WalkTracker no destacado en Ajustes → Batería;
  - `stepsEstimated = 0` sin tocar la pantalla.

  [fuente: epics.md Story 8.4; SPEC Success signal; NFR-8; CAP-3]
- **Si falla un criterio, se para:** se registra y se revisa antes de los epics 2–7 (`bmad-correct-course`), sin
  maquillar el umbral.
- **Registro de medición.** `OSLog` con subsistema propio, sin red ni telemetría (Privacidad del SPEC). Registra:
  - cada muestra del stream (`steps`, `distance`, `end`);
  - cada consulta de reconciliación (rango, resultado, acumulado visto, duración, desenlace);
  - cada estimación;
  - las transiciones de la sesión.

  [fuente: epic-1-retro A-3]
- **La instrumentación no cambia el comportamiento:** ni la cadencia del stream ni la del autosave, y los tests
  existentes siguen en verde (AD-21).
- **El build del gate sale por `Scripts/release-testflight.sh` desde `main`,** con la confirmación explícita de Paul
  en ese momento (la subida gasta un número de build) [fuente: README.md Releases].
- `verify-domain.sh` y la suite completa en verde.

**Never:**
- **Nada del chore y del refactor de la retro (A-1, A-2).** Tampoco cambiar reglas de dominio del Epic 1 (R1, S10):
  esta historia **aporta los datos** con los que se deciden.
- **La Live Activity** (la 7.2 recomprueba la batería con ella).
- **Subir a TestFlight, empujar etiquetas o mergear sin la confirmación de Paul.**
- **Registrar ubicación ni nada que no sea conteo, distancia y tiempos de la sesión.**

**Decisiones de Paul (2026-09-14):**
- **Extracción del registro:** solo `OSLog` en nivel `notice`, sin UI ni fichero propio. Tras la caminata, el iPhone
  se conecta al Mac y se ejecuta `sudo log collect --device --last 2h`; el script lee el `.logarchive`. Los pasos y
  la distancia van como `public` en el log del sistema.
- **Constantes:**
  - `reconciliationTimeoutS` = max(1 s, 5 × duración máxima observada de la consulta), redondeado hacia arriba al
    segundo;
  - `orphanSessionThresholdS` se queda en 6 h como **valor decidido, no medido**, y sale de `provisional` con esa
    nota en la medición de referencia.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Muestra del stream | activa, muestra 820 pasos, 540 m | una línea de medición `sample` con steps, distance y end | — |
| Consulta con dato | vuelta de background, query → 900 en 40 ms, visto 820 | línea `query` con rango, 900, seen 820, 40 ms y desenlace `data` | — |
| Consulta degradada | query nil, timeout o menor que lo visto | línea `query` con su desenlace (`nil` / `timeout` / `belowSeen`) y línea `estimate` con los pasos | — |
| Informe | registro exportado de una caminata | el script da duración, pasos y distancia finales, `stepsEstimated`, nº de consultas, duración máx. y p95, desenlaces, muestras con y sin distancia, y avisos de R1/R2 | — |
| Registro vacío o ajeno | archivo sin líneas de medición | el script falla con un mensaje claro | exit ≠ 0 |

</frozen-after-approval>

## Code Map

- `WalkTracker/Application/SessionStore.swift` (750 líneas, clase dios según la retro A1; tocar lo mínimo):
  - `record(_:fromQuery:)` (`:676`) aplica cada muestra: punto para `sample`.
  - `reconcile(until:)` (`:592`): `seen` al empezar, la rama `sample.steps >= seen` y la de estimación con `GapEstimator`.
  - `queryWithinTimeout` (`:635-660`): la carrera consulta/timeout; aquí se mide la duración y se sabe si ganó el timeout.
  - Transiciones: `openSession` (`:394`), `pause` (`:172`), `resume` (`:189`), `confirmFinish` (`:226`),
    `appDidEnterBackground`/`appDidBecomeActive` (`:280-298`), `restoreOnLaunch` (`:450`).
  - Logger actual: `category: "SessionStore"` (`:132`), con `.info` (no persistente) y `.error`/`.fault`.
- `WalkTracker/Adapters/Motion/MotionAdapter.swift`: el stream usa `.bufferingNewest(1)`, así que una muestra
  descartada por el buffer no llega al store. No se toca.
- `Scripts/release-testflight.sh` + `README.md` "Releases a TestFlight": precondiciones (`main`, árbol limpio,
  HEAD == origin/main), `--confirm <etiqueta>` sin terminal, etiqueta `v4.0.0-build.N` (la última es
  `v4.0.0-build.38`).
- `Scripts/vectors/*.js` y `Scripts/*.sh`: estilo de los scripts del repo (bash con `set -uo pipefail`, `node`
  para el parseo, tests de camino rojo como `release-testflight-tests.sh`).
- `WalkTracker/Resources/formulas.json` + `Domain/Formulas/Formulas.swift`: `reconciliationTimeoutS`,
  `orphanSessionThresholdS` y `provisional` (validado: los nombres deben ser constantes conocidas; la lista puede
  quedar vacía).
- Retro del Epic 1: R1 (consulta < visto), R2 (doble cuenta tras degradar), R11 y la alternancia de distancia
  (deferred-work 1.3 y 1.4), S10.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Application/MeasurementLog.swift` (nuevo): `Logger` con `category: "Medicion"` en nivel
      `notice`. Una línea por evento con prefijo fijo y campos `clave=valor` estables: `sample`, `query`,
      `estimate` y `session`. Funciones puras de formateo, probables sin `OSLog`.
- [x] `WalkTracker/Application/SessionStore.swift`: llamadas a `MeasurementLog` en los puntos del Code Map. En
      `queryWithinTimeout`, devolver también la duración y si agotó el timeout, sin cambiar la decisión.
- [x] `Scripts/walk-report.sh` + `Scripts/walk-report/report.js` (nuevo): leen un `.logarchive` (con
      `log show --archive … --predicate 'subsystem == "com.walktracker.app" AND category == "Medicion"'`) o un
      texto ya exportado, y escriben el informe de la matriz, con avisos si hay `belowSeen`, estimaciones, o una
      muestra del stream que sube tras una consulta degradada (R2).
- [x] `Scripts/walk-report-tests.sh` (nuevo): fixtures de texto para caminata limpia, degradada, `belowSeen`,
      R2 y registro vacío.
- [x] `WalkTrackerTests/Application/MeasurementLogTests.swift` (nuevo): formato de cada línea, y que el informe y
      la app hablan el mismo formato (una fixture compartida).
- [x] `README.md`: sección "Gate 8.4" con el protocolo de la caminata, cómo extraer el registro y cómo leer el
      informe.
- [x] `_bmad-output/implementation-artifacts/8-4-medicion-referencia.md` (plantilla nueva): criterios, valores
      de Salud, batería, informe del script, decisión sobre R1/R2/R11 y constantes fijadas. Se rellena tras la
      caminata.

**Tras mergear (con Paul, en orden):**
1. Release a TestFlight desde `main` con `--confirm`, empujar la etiqueta e instalarlo en el iPhone 14.
2. Paul camina 30 min según el protocolo; se extrae el registro y se ejecuta el informe.
3. Rellenar la medición de referencia, fijar las constantes en `formulas.json` según la regla de las Decisiones de Paul y
   actualizar `FormulasTests`.
4. Si pasa, 8.4 `done` y Epic 8 `done`. Si falla, `bmad-correct-course`.

**Acceptance Criteria:**
- Given el build de TestFlight en el iPhone 14, when camino 30 min en el bolsillo con música y sin tocar la
  pantalla, then pasos y distancia quedan a ≤ 10 % de Salud y `stepsEstimated` es 0.
- Given la misma caminata, when miro Ajustes → Batería, then la caída es ≤ 5 % y WalkTracker no destaca.
- Given el registro extraído, when ejecuto el informe, then tengo la duración real de las consultas y la respuesta
  a R1/R2 con datos, y las constantes quedan fijadas sin `provisional` pendiente de medición.

## Implementation Notes

Parte de código hecha el 2026-09-14; los pasos "Tras mergear" siguen pendientes con Paul.

- **Formato `WTM1`:** toda línea lleva `sid=<startedAt ms>` tras `event=`, para que el informe separe
  sesiones si el registro de `--last 2h` trae más de una. Instantes en ms Unix, metros con dos decimales,
  `nil` para lo ausente. Claves por evento en `MeasurementLog.swift` y `report.js` (`SCHEMA`).
- **Añadidos a la spec, sin cambiar comportamiento:**
  - desenlace `error` además de `data`/`nil`/`timeout`/`belowSeen`;
  - evento `queryLate`: la respuesta que llega tras el timeout se sigue descartando, pero deja su duración
    real. El informe la usa en lugar de la espera censurada; con un timeout sin `queryLate` no propone valor;
  - `estimate` siempre lleva `skipped` (`nil` o `streamAdvanced`, cuando el stream avanzó durante la
    consulta degradada y no se estima);
  - transiciones `discardEstimated` y `streamEnded` (R5); `start` y `restore` llevan `version` y `build`;
  - `SessionStore.init` recibe `measure:` (`@Sendable`) con `MeasurementLog.record` por defecto, para que los
    tests lean las líneas. `CompositionRoot` no cambia.
- **Duración de la consulta:** `ContinuousClock`, tomada en la tarea que gana la carrera (respuesta o
  temporizador), no tras volver al hilo principal.
- **Informe:** propuesta de timeout por sesión; criterio `stepsEstimated` "cumple" solo con sesión finalizada,
  0 final, sin estimaciones con pasos y sin descarte; R2 casa el tramo con tolerancia de 1 s, busca solo hasta
  la consulta siguiente y marca "posible doble cuenta" solo si hubo estimación y el salto es ≥ la mitad.
- **Fixture compartida:** `WalkTrackerTests/Application/MeasurementLogFixture.txt` (estilo
  `log show --style compact`). `MeasurementLogTests.sharedFixtureMatchesApp` la regenera con los formateadores
  y `walk-report-tests.sh` la pasa por el informe. Verificado su camino rojo: cambiar un desenlace en la
  fixture pone rojo el test de Swift.
- **No verificado:** `log collect --device` sobre el iPhone (necesita el dispositivo y `sudo`).
- **Revisión (pasada 1):** 10 parches, 2 diferidos y el resto rechazados. Los parches:
  - La respuesta tardía queda como `queryLate`, y la propuesta de timeout es por sesión y sin valores censurados.
  - `ms` se toma en la tarea que gana la carrera.
  - El criterio de estimados es estricto.
  - R2 casa el tramo con tolerancia y no confunde el caminar normal con doble cuenta.
  - Hay `skipped=streamAdvanced`.
  - `version` y `build` van en `start` y `restore`.
  - Hay tests de las transiciones `restore`, `orphan`, `discardEstimated` y `streamEnded`.
  - El protocolo cubre Watch, intervalo exacto, cargador y bajo consumo.
  - Robustez del script.

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH/EC · Con timeout, `ms` es la espera del temporizador y la respuesta tardía se descarta sin registrar. La propuesta `5 × max` sale de un valor censurado | medium | Real: la fixture degradada proponía 16 s = 5 × 3001 ms. Es justo el valor que el gate fija. Parche: `queryLate` con la duración real; un timeout sin `queryLate` no propone | patch |
| 2 | BH · `durationMs` incluye la espera del main actor al volver de background | low | Real: se medía tras `await race.value()`. Se infla ×5 en la regla. Parche: se toma el instante en la tarea que resuelve | patch |
| 3 | BH/EC · "cumple" en `stepsEstimated` tras descartar estimados o sin finalizar, y "NO CUMPLE" con `null` | medium | Real: `render` solo miraba `estimated` de la última transición. Es un criterio del gate. Parche: criterio estricto y "sin datos" | patch |
| 4 | BH/EC · Con varias sesiones en `--last 2h`, la propuesta de timeout mezcla sesiones de prueba | medium | Real: `allMs` recorría todos los informes. Parche: propuesta por sesión | patch |
| 5 | BH/EC · Una duración negativa se imprime como "-135 min 00 s" | low | Real en `clock()`; es directo | patch |
| 6 | BH/EC · R2 exige `start` idéntico al ms, atribuye una muestra a dos consultas y llama doble cuenta al caminar normal | medium | Real en `report.js:160`. Si CoreMotion no devuelve `startDate` exacto, R2 no salta nunca en el iPhone. R2 es una de las preguntas del gate | patch |
| 7 | EC · Con consulta degradada y el stream avanzado, se sale sin estimar y sin registrar | low | Real (`SessionStore.swift:645`); es la evidencia de R2 que el gate busca. Parche: `estimate steps=0 skipped=streamAdvanced` | patch |
| 8 | BH · Ninguna línea dice qué build escribió el registro | medium | Real: no se puede comprobar que se caminó con el build de TestFlight, que es condición del gate. Parche: `version` y `build` en `start` y `restore` | patch |
| 9 | BH · Faltan controles del protocolo: Apple Watch, intervalo exacto en Salud, cargador, bajo consumo | medium | Real: Salud mezcla las fuentes de Watch e iPhone y distorsiona el ≤ 10 %; cargar o el modo de bajo consumo distorsionan el ≤ 5 %. Parche en el README y la plantilla | patch |
| 10 | VG · Sin test de las transiciones `restore`, `orphan`, `discardEstimated` y `streamEnded`, ni de que una consulta aplicada no dé `sample` | medium | Pre-verificado: quitar cualquiera deja todo en verde, y el informe decide "Finalizada" y R5 con ellas. Parche: tests Swift y del script | patch |
| 11 | BH/EC · "Cualquier estilo" de `log show` es falso: JSON/NDJSON rompen el parseo. `event=toString` provoca un TypeError. Una interrupción deja el `.err` | low | Real; arreglos directos (error claro, `Object.hasOwn`, `trap`) | patch |
| 12 | BH · Faltan `distance` en la lista de campos de `query` y la aclaración de `.bufferingNewest(1)` | low | Real en el README; directo | patch (con 9) |
| 13 | BH · El registro público queda en todos los builds Release, sin plan para retirarlo tras el gate | medium | Real: la decisión de Paul fija `OSLog` público para extraer la caminata, pero no dice qué pasa después. Retirarlo antes de caminar anularía el gate | defer |
| 14 | VG · Sin test de store para una `estimate` con `steps=0`, ni un p95 distinto del máximo | low | Pre-verificado; informativo: la caminata del gate da 2 consultas (p95 = máx.) y la regla usa el máximo | defer |
| 15 | BH/EC · El formateador escribe `nil` para instantes no finitos y el lector los rechaza | low | Inalcanzable: los `Date` de la sesión y de CoreMotion son finitos y están en rango | rechazado |
| 16 | BH · El desenlace de la consulta se recalcula en vez de salir del punto de decisión | low | Es la misma comparación `steps >= seen` que decide en `reconcile`, sin rama intermedia que diverja hoy | rechazado |
| 17 | BH · `estimateLine` se escribe antes de `addEstimatedSteps`, que puede lanzar | low | Inalcanzable: la sesión está activa y el conteo es > 0 y acotado | rechazado |
| 18 | BH · `background`/`active` se registran tras `finish` | false | `appDidEnterBackground` sale con la sesión finalizada (`guard … status != .finished`), y `appDidBecomeActive` exige `backgroundedAt`, que `confirmFinish` limpia | rechazado |
| 19 | EC · Un tramo de más de 7 días no deja línea `query` | low | Imposible en una caminata de 30 min | rechazado |
| 20 | EC · `sid` fuera de rango de `Date`, y una línea ajena con "WTM" en texto crudo | low | Entradas fabricadas; el script ya filtra por categoría al leer el `.logarchive` | rechazado |
| 21 | BH · Code Map con líneas desfasadas, estado de la spec distinto del sprint y `epic-8-context.md` fuera del diff | false | El Code Map describe el estado previo; el sprint se sincroniza al presentar; el contexto recompilado se excluyó a propósito del diff revisado. Arreglarlo editaría la spec | rechazado |

## Design Notes

- **Qué puede zanjar una caminata sin tocar la pantalla:** con la pantalla bloqueada todo el rato hay
  reconciliación al volver y al finalizar, pero no gaps intermedios. R1 queda medido en esas consultas. R2 solo
  aparece si alguna degrada, y la matriz del informe lo detecta si ocurre. Una segunda pasada opcional (bloquear
  y desbloquear varias veces) daría más consultas, pero no entra en el gate.
- **Formato:** líneas `WTM1 event=query start=… end=… result=900 seen=820 ms=40 outcome=data`. El prefijo con
  versión permite que el informe rechace formatos que no conoce.
- **Por qué `notice`:** `info` no se persiste en el dispositivo y se perdería al extraer después de caminar.

## Verification

**Commands:**
- `bash Scripts/walk-report-tests.sh`: esperado verde.
- `bash Scripts/verify-domain.sh` y `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO`:
  esperado verde, sin warnings propios.

**Manual checks (iPhone 14, tras el release):**
- La caminata del gate con sus tres criterios.
- `sudo log collect --device --last 2h`, después `bash Scripts/walk-report.sh <archivo>`: el informe sale completo.
