---
title: '1.6 — Recuperación foreground: wall-clock y sesión huérfana'
type: 'feature'
created: '2026-09-14'
baseline_commit: 'a8da31a20759170eb091284f3c7f0f7af0f1738a'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-5-reconstruccion-background.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la sesión vive solo en memoria. Un force-quit o que el sistema mate la app en background la
pierde entera, aunque CAP-1 exige recuperarla con el tiempo real [fuente: capabilities.md#CAP-1; epics.md
Story 1.6].

**Enfoque:** `SessionStore` guarda un snapshot de la sesión viva en `activeSession.json` por un
`StoragePort` nuevo. Al arrancar la restaura en silencio: reconcilia el hueco con la consulta de la 1.5,
presenta la sesión y muestra "Sesión recuperada" durante 3 s. Si la sesión supera el umbral de sesión
huérfana, la cierra recortada al último dato real y la marca `recovered` (AD-18).

## Boundaries & Constraints

**Always:**
- **Snapshot (AD-9, AD-16):** JSON `Codable` en Application Support, `schemaVersion`, escritura atómica
  (temporal + rename). Su único escritor es `SessionStore`. El formato va en **milisegundos** (§8) y la
  conversión a segundos vive en el adapter; el dominio nunca ve milisegundos [fuente: ARCHITECTURE-SPINE.md#AD-9;
  domain-model.md#98].
- **Cuándo se guarda:** al iniciar, pausar, reanudar y pasar a background, y como mucho cada 10 s mientras
  lleguen muestras. Se borra al finalizar [fuente: AD-9; epics.md Story 5.1 And 2].
- **Restaurar:** el tiempo se recalcula desde `startedAt` (el tiempo cerrado cuenta). Una sesión activa se
  reconcilia **antes** de presentarse, sin pantalla de carga. La pausada vuelve pausada y no consulta
  [fuente: epics.md Story 1.6; domain-model.md#38].
- **"Sesión recuperada":** 3 s, no bloquea, solo al relanzar la app. Volver de background no lo muestra
  [fuente: capabilities.md#CAP-1; EXPERIENCE.md#95 frente a #84].
- **Sesión huérfana (AD-18):** con `now − startedAt` > `orphanSessionThresholdS` (en `formulas.json`, valor
  **provisional marcado**, lo sustituye la 8.4) no se restaura: se cierra en el último dato real del
  coprocesador, con `recovered: true`, sin consultar ni estimar.
- Los estimados restaurados reutilizan el Estimated Banner de la 1.5 con su descarte [fuente: epics.md Story 1.6 AC 2–3].
- `Domain/` sigue puro y `verify-domain.sh` en verde.

**Never:**
- `sessions.json`, historial, logros, ajustes o el resto del `StoragePort` de la 5.1.
- Logros o celebración de la sesión huérfana (Epic 3); Live Activity (7.x); wake lock.
- Un temporizador de autosave que despierte la app sin muestras nuevas (AD-21).
- Borrar un snapshot ilegible: se aparta, no se destruye.

**Decisiones de Paul (2026-09-14):**
- **Sesión huérfana cerrada:** al abrir la app se muestra una vez su resumen como "Caminata recuperada", con una
  nota de que se cerró sola en el último paso registrado y "Volver al inicio". Al salir se descarta, como la
  finalizada de la 1.4; la 5.1 la archivará en lugar de descartarla.
- **Umbral de sesión huérfana:** 6 h (`orphanSessionThresholdS: 21600`), provisional hasta la 8.4.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Relanzar activa | snapshot activo de hace 20 min, 1500 pasos, 60 s de pausas | activa, `elapsedS` = 1140 desde `startedAt`, 1500 + lo que dé la consulta, "Sesión recuperada" 3 s | — |
| Relanzar sin dato | igual, consulta nil, gap desde el último guardado 300 s a 80 spm | `stepsEstimated` +400 y banner "~400" | — |
| Relanzar pausada | snapshot pausado | pausada, sin consulta, tiempo congelado en `pausedAt` | — |
| Huérfana | `startedAt` hace más que el umbral; último dato +40 min | `finished` en +40 min, `recovered`, sin consulta | — |
| Sin snapshot | primer arranque | Inicio normal, nada que restaurar | — |
| Snapshot ilegible | JSON roto o `schemaVersion` desconocido | se aparta, Inicio normal, log `fault` | — |
| Snapshot inválido | zancada ≤ 0, pasos < 0, pausada sin `pausedAt` | ídem, rechazado en la frontera | `invalidValue` |
| Autosave | activa, muestras cada 2,5 s durante 25 s | 2 guardados por muestras (≥ 10 s), no 10 | — |
| Finalizar | confirmar | snapshot borrado; relanzar no restaura | — |
| Restaurar v3 | `{2450, 320, 60000, activa, 0.655}` | pasos, zancada y estado restaurados; distancia (2450+320)×0,655 | — |

</frozen-after-approval>

## Code Map

- `Domain/Session/Session.swift`: `init` privado; `start(at:strideM:)` y `validateStride` son la frontera.
  `finish(at:)` (`:184`) acumula la pausa abierta (una negativa cuenta 0). No existe restaurar ni `recovered`.
- `domain.js:378-403` `restoreV3Session`: exige `startedAtMs` y `strideM`, zancada finita > 0, pasos ausentes
  = 0, `pausedAtMs` si está pausada. `inventory.json`: los 10 escenarios de la 1.6 son
  `test/session-v3-tests.js:257-262` (restaurar) y `:270-274` (snapshot inválido).
- `domain-model.md` §8 (`:98`): `activeSession → {startedAtMs, stepsMeasured, stepsEstimated, totalPausesMs,
  paused, pausedAtMs, strideM, weather|null, quoteId}`. Clima y frase son del Epic 2: no se escriben.
- `WalkTracker/Application/SessionStore.swift` (tras la 1.5):
  - `openSession()` (`:344`); `countSteps(from:)` (`:359`) fija `segmentStart` y **pone
    `highestCumulativeSteps` a 0**; `distanceBaseM` (`:107`).
  - `reconcile(until:)` (`:389`) consulta `[segmentStart, end]`; con `backgroundedAt` y sin dato, estima.
  - `record(_:)` (`:469`); `confirmFinish()` (`:189`); `appDidEnterBackground()` (`:241`); `leaveSummary()` (`:259`).
- `Domain/Formulas/Formulas.swift`: `reconciliationTimeoutS`, `provisional` y `constantNames` (`:33`). Hay que
  añadir la constante nueva a la lista.
- `WalkTracker/App/CompositionRoot.swift:47` construye el store; `WalkTrackerApp.swift` monta `RootView`.
- `Domain/Ports/`: patrón de puerto + DTO `Sendable` (`MotionPort`, `PedometerSample`). `StoragePort` es uno
  de los 11 de AD-10 y aún no existe; las carpetas son `Adapters/Persistence/` y `Application/`.
- `WalkTracker/UI/Session/SessionView.swift`: título, aviso de reconciliación con `.task(id:)` (patrón para
  el indicador de 3 s) y `SessionSummaryView`/`FinishedWalk` para el resumen.
- `WalkTrackerTests/Support/MotionStub.swift`: `emit` crea muestras con `end = start`.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Session/Session.swift`: `restore(...)` valida en la frontera (zancada, pasos ≥ 0, pausas ≥ 0
      finitas, distancia del sistema ≥ 0 finita, `pausedAt` si y solo si está pausada) y crea `active` o
      `paused`. `recovered: Bool` y `closeOrphan(at:)`: finaliza como `finish` y marca `recovered`.
- [x] `Domain/Ports/StoragePort.swift` + `ActiveSessionSnapshot.swift`: `loadActiveSession()`,
      `saveActiveSession(_:)` y `clearActiveSession()`, con errores tipados. El DTO va en segundos y `Date`:
      campos de la sesión más `savedAt`, `lastSampleAt?`, `segmentStart`, `segmentSteps` y `distanceBaseM`.
- [x] `WalkTracker/Adapters/Persistence/ActiveSessionFileAdapter.swift`: JSON en ms con `schemaVersion` y
      escritura atómica en Application Support. `decode`/`encode` puros y comprobables. Un fichero ilegible
      se renombra a `activeSession.corrupt.json`.
- [x] `Domain/Formulas/Formulas.swift` + `formulas.json`: `orphanSessionThresholdS` (> 0 y finito, valor
      provisional 21600 = 6 h), en `constantNames` y en `provisional`.
- [x] `WalkTracker/Application/SessionStore.swift`:
      - `restoreOnLaunch() async`.
      - Guardar en los momentos de las Boundaries y borrar al finalizar.
      - `lastSampleAt` = `end` de la última muestra que sumó pasos.
      - Restaurar el tramo sin poner `highestCumulativeSteps` a 0.
      - Gap pendiente = `savedAt`.
      - Estado `showsRecoveredNotice`; la huérfana cerrada queda en `session` para su resumen y se descarta al salir.
- [x] `WalkTracker/App/CompositionRoot.swift` + `WalkTrackerApp.swift`: cablear el adapter y lanzar la
      restauración al arrancar.
- [x] `WalkTracker/UI/Session/SessionView.swift` + `SessionSummaryView.swift`: indicador
      "Sesión recuperada" 3 s, anunciado a VoiceOver y respetando Reduce Motion.
- [x] `WalkTrackerTests/Support/StorageStub.swift` (nuevo) + `MotionStub.swift`: guardar y leer en memoria y
      fallar a demanda; `emit` con un `end` opcional.
- [x] `WalkTrackerTests/Scenarios/SessionRecoveryScenarios.swift` (nuevo): los 10 sitios de la 1.6 y la
      huérfana en el dominio. Añadirla a `verify-domain.sh`.
- [x] `WalkTrackerTests/Application/SessionStoreTests.swift`, `Adapters/ActiveSessionFileAdapterTests.swift` y
      `FormulasTests.swift`: la matriz en el store, ida y vuelta ms ↔ s, escritura atómica en un directorio
      temporal, el fichero ilegible y la constante nueva.
- [x] `Localizable.xcstrings`: textos con `comment`. Después, `xcodegen generate`.

**Acceptance Criteria:**
- Given una caminata activa en el iPhone 14, when fuerzo el cierre y reabro, then vuelvo a la sesión con el
  tiempo real, los pasos al día y "Sesión recuperada" durante 3 s.
- Given una caminata pausada, when fuerzo el cierre y reabro, then sigue pausada y con el tiempo congelado.
- Given una sesión finalizada, when fuerzo el cierre y reabro, then estoy en Inicio sin sesión.

## Implementation Notes

- `Session`: `restore(startedAt:stepsMeasured:stepsEstimated:totalPausesS:paused:pausedAt:strideM:systemDistanceM:)` valida
  `strideM`, `stepsMeasured`/`stepsEstimated` ≥ 0, `totalPausesS` ≥ 0 finito, `distanceM` ≥ 0 finita y `pausedAt` si y solo si
  `paused` (cada uno con su campo en `invalidValue`). `recovered: Bool` (false salvo `closeOrphan(at:)`, que llama a `finish`).
- `StoragePort` + `StorageError` (`malformed`, `unsupportedSchemaVersion`, `failed(operation:)`) + `ActiveSessionSnapshot` (s y
  `Date`; incluye `systemDistanceM`). **Desviación:** el puerto tiene un cuarto método, `setAsideActiveSession()`. Sin él, un
  snapshot que el dominio rechaza (rangos) solo podía borrarse o pisarse, y la spec prohíbe destruirlo. Síncrono: son
  unos cientos de bytes y así cada transición queda guardada antes de la siguiente.
- `ActiveSessionFileAdapter`: `schemaVersion` 1, instantes y pausas en **ms enteros** (`startedAtMs`, `totalPausesMs`,
  `pausedAtMs`, `savedAtMs`, `lastSampleAtMs`, `segmentStartMs`); redondear al ms es la única pérdida. Como la v3, pasos,
  pausas y `paused` ausentes valen 0/false; `startedAtMs`, `strideM`, `savedAtMs`, `segmentStartMs`, `segmentSteps` y
  `distanceBaseM` son obligatorios. Escritura: temporal en el mismo directorio + `rename(2)`. Ilegible → renombrado a
  `activeSession.corrupt.json` (sustituye a un apartado anterior) y la lectura lanza.
- `Formulas.orphanSessionThresholdS` (obligatorio, > 0 y finito), en `constantNames`; `formulas.json`: 21600 y
  `provisional: ["reconciliationTimeoutS", "orphanSessionThresholdS"]`. `schemaVersion` sigue en 1, como en la 1.5.
- `SessionStore(clock:motion:storage:strideM:reconciliationTimeoutS:orphanSessionThresholdS:)`:
  - `persist()` guarda al iniciar, pausar, reanudar, pasar a background (también en pausa), tras reconciliar al volver,
    tras descartar estimados y tras restaurar; y en `record(_:)` si pasaron ≥ `autosaveIntervalS` (10 s) desde el último
    guardado correcto. Nunca durante una reconciliación (el snapshot aún no tiene los pasos del gap). `confirmFinish()`
    borra el snapshot. Un fallo se registra y el siguiente evento reintenta.
  - `lastSampleAt` = `end` de la muestra **del stream** que sumó pasos; la de la consulta no lo mueve (su `end` es el instante pedido).
  - `restoreOnLaunch()` (una sola vez, sin sesión abierta): leer → fallo = `fault` (el adapter ya apartó) → validar
    (`segmentSteps` ≥ 0 y `distanceBaseM` ≥ 0 finita en el store, el resto en `Session.restore`) → inválido = `fault` +
    `setAsideActiveSession()` → huérfana (`now − startedAt` > umbral, estricto) = `closeOrphan(at: max(lastSampleAt ?? startedAt, segmentStart))` (toda pausa cerrada queda antes del recorte),
    `hasSession = true` y snapshot borrado → si no, restaura el tramo con `countSteps(from:restoring:)` (conserva
    `highestCumulativeSteps` y `distanceBaseM`), `backgroundedAt = savedAt`, `reconcile(until: now)` y solo entonces
    `showsRecoveredNotice = true`, `hasSession = true` y guarda. La pausada no abre stream ni consulta.
  - `dismissRecoveredNotice()`; `leaveSummary()` limpia además `lastSampleAt`, `lastSavedAt` y el aviso.
- `CompositionRoot` crea `ActiveSessionFileAdapter()` (Application Support) y pasa el umbral; `WalkTrackerApp` lanza
  `restoreOnLaunch()` en el `.task` de la raíz.
- UI: `SessionView` muestra "Sesión recuperada" (`Label`, `.secondary`) bajo el título; `.task(id: showsRecoveredNotice)`
  lo anuncia a VoiceOver, espera 3 s y llama a `dismissRecoveredNotice()`. Con Reduce Motion, fundido en vez de
  desplazamiento. `FinishedWalk.recovered` → `SessionSummaryView` titula "Caminata recuperada" con la nota "Se cerró sola
  en el último paso registrado." y el mismo "Volver al inicio". Tres textos nuevos con `comment` en `Localizable.xcstrings`.
- Tests: `SessionRecoveryScenarios` (en `verify-domain.sh`) porta `:257-262` sobre `Session.restore` y `:270-274` repartidos
  en su frontera (`:270-272` forma → `ActiveSessionFileAdapter.decode`, `:273-274` rangos → dominio), más restaurar, rangos
  inválidos y huérfana activa/pausada/finalizada. `ActiveSessionFileAdapterTests` (ida y vuelta, ms en el JSON, defaults
  v3, versión desconocida, malformados, escritura atómica en directorio temporal sin temporales sobrantes, fallo que
  conserva el anterior, borrado, ilegible apartado con su contenido). `SessionStoreRecoveryTests` (20 tests): la matriz
  entera más tramo con máximo conservado, presentación solo tras reconciliar (consulta colgada), umbral exacto, una sola
  restauración, quieto sin escrituras, force-quit de ida y vuelta entre dos stores y guardado fallido que se reintenta.
  `StorageStub` nuevo; `MotionStub.emit(steps:distance:end:)`. `FormulasTests` cubre la constante nueva.
- Verificado: `bash Scripts/verify-domain.sh` verde (inventario 186 sitios con los 10 de la 1.6 citados; 157 tests en 11
  suites). `xcodegen generate && xcodebuild test … iPhone 16e` → `TEST SUCCEEDED`, 310 tests, sin warnings propios.
  Mutaciones (juntas): poner `highestCumulativeSteps` a 0 al restaurar, guardar en cada muestra y no fijar el gap
  pendiente en `savedAt` rompen 6 tests del store. **Pendiente:** los checks manuales en el iPhone 14.
- Riesgos: el aviso "Sesión recuperada" y el resumen recuperado no tienen test de vista (mismo hueco que las historias
  anteriores). Si el sistema entrega por el stream reabierto un acumulado distinto del de la consulta (p. ej. el stream
  desde una fecha pasada no incluye lo histórico), el máximo del tramo evita contar dos veces, pero solo el iPhone 14 lo
  confirma.
- Revisión (pasada 1): 22 hallazgos — 8 parches, 1 diferido y 13 rechazados.
  - **Parches:**
    - `lastSampleAt` solo con muestras del stream (`record(_:fromQuery:)`).
    - La huérfana se recorta en `max(lastSampleAt ?? startedAt, segmentStart)`.
    - El log de la lectura fallida distingue apartado de no leído.
  - **Tests nuevos:**
    - El guardado tras volver y tras descartar.
    - `leaveSummary()` limpia el estado de recuperación.
    - `CompositionRootTests` comprueba el cableado del umbral y del storage.
  - **Otros:** nombre de `autosaveBySamples` y doc comment de `Session` reajustados.
  - Cada test nuevo falla sin su parche.
- **Verificación en el iPhone 14 (2026-09-14, Paul): funciona.** Build de desarrollo de `e146a60` instalado y
  lanzado con `devicectl`. Paul hizo los tres checks manuales (force-quit desde el selector de apps con la sesión
  activa, pausada y finalizada) y los dio por buenos. El diferido sigue abierto.

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH/EC · La muestra de la consulta de reconciliación mueve `lastSampleAt` al `end` pedido (volver o relanzar): una huérfana posterior se recorta ahí y cuenta horas quietas | medium | Real: `reconcile` pasa la muestra por `record`, que fijaba `lastSampleAt = sample.end`, y ese `end` es el de la consulta. Parche: solo el stream lo mueve + `queryDoesNotMoveLastSampleAt` | patch |
| 2 | BH/VG · La huérfana resta pausas cerradas DESPUÉS del último dato: 0–40 caminando, pausa 50–60, reanudar → 30 min | medium | Real: `finish(at: lastSampleAt)` resta todo `totalPausesS`. `segmentStart` es la última reanudación, así que recortar en `max(lastSampleAt, segmentStart)` deja toda pausa cerrada antes del corte. Parche + `orphanWithPauseAfterLastData` (fin +60 min, 3000 s) | patch |
| 3 | BH/EC · No se valida el orden de los instantes del snapshot (`pausedAt < startedAt`, `savedAt > now`, `segmentStart` fuera de rango) | low | Solo lo produce un fichero manipulado o un reloj hacia atrás. `GapEstimator` da 0 con un gap negativo y `finish` nunca da tiempo negativo; el arreglo añade guardas nuevas | rechazado |
| 4 | BH/EC · Salir a background durante la reconciliación del arranque borra ese gap (`backgroundedAt = nil`) | low | Misma clase que el hallazgo 4 de la 1.5: ventana de milisegundos, y el stream reabierto entrega esos pasos en su siguiente muestra | rechazado |
| 5 | BH/EC · Mientras reconcilia al arrancar se ve Inicio y "Iniciar caminata" no hace nada | low | Real durante lo que dura la consulta (milisegundos, tope 3 s) justo al abrir la app; arreglarlo exige un estado nuevo | rechazado |
| 6 | BH/EC · Restaurar no comprueba el permiso de Motion: revocado entre el force-quit y el relanzamiento, se estima todo el gap | low | Revocar el permiso con una caminata viva y la app cerrada es excepcional; AD-11 solo bloquea al iniciar y lo estimado se ve con "~" y es descartable | rechazado |
| 7 | BH · El log dice "ilegible, apartado" también cuando la lectura falló (`failed`) y el fichero sigue en su sitio | low | Real; distinguirlo en el mensaje es directo | patch |
| 8 | EC · Si la lectura falla con `failed` (p. ej. protección de datos antes del primer desbloqueo) no se reintenta y el siguiente inicio sobrescribe el snapshot | low | La app no se lanza en background antes del primer desbloqueo, y un fallo de E/S en un fichero propio de cientos de bytes es excepcional; el reintento añade estado | rechazado |
| 9 | BH · Sin `fsync` antes del `rename`, un corte de corriente puede dejar un snapshot vacío; el snapshot entra en las copias de iCloud | low | Con un corte, el fichero vacío se aparta como ilegible, no se destruye. Una copia restaurada solo trae una huérfana (> 6 h), que se muestra una vez | rechazado |
| 10 | BH · El umbral mira `now − startedAt` y no la actividad reciente: una ruta de 6 h 5 min relanzada al minuto se cierra | false | Es exactamente la regla de AD-18 (`now − startedAt` contra el umbral); el valor es provisional hasta la 8.4 | rechazado |
| 11 | BH · El anuncio de VoiceOver puede perderse al presentarse la cubierta a la vez | maybe-false | Depende del orden de anuncios de UIKit al presentar; lo zanja probarlo con VoiceOver en el iPhone 14. Aunque fuera real, sería low | rechazado |
| 12 | EC · Una huérfana con estimados de gaps posteriores al recorte los conserva y la distancia sale inflada | low | Los estimados se ven con "~" en el resumen, y una huérfana con gaps estimados después de su último dato es un caso doblemente raro | rechazado |
| 13 | EC · Si `clearActiveSession` falla al finalizar, relanzar resucita la caminata ya finalizada | low | Real, pero borrar un fichero propio en Application Support prácticamente no falla; el arreglo (apartar o marcar finalizada) añade una ruta nueva | rechazado |
| 14 | VG · Sin test de que `appDidBecomeActive()` y `confirmDiscardEstimated()` guarden el snapshot | medium | Pre-verificado: quitar cualquiera de los dos `persist()` deja todo verde; un crash en primer plano resucitaría estimados descartados. Parche: `becomeActiveSavesReconciled` + `discardSavesSnapshot` | patch |
| 15 | VG · Sin test de que `leaveSummary()` limpie `showsRecoveredNotice` y `lastSampleAt` antes de otra sesión | low | Pre-verificado. Parche: `leaveSummaryResetsRecoveryState` | patch |
| 16 | VG · Sin test del cableado de `CompositionRoot` (storage y umbral) | medium | Pre-verificado: pasar `reconciliationTimeoutS` como umbral cerraría como huérfana toda sesión relanzada y nada fallaría. Parche: `CompositionRootTests` | patch |
| 17 | VG · Sin test del `.task` de arranque, del aviso de 3 s ni del resumen "Caminata recuperada" | medium | Pre-verificado; no hay arnés de tests de vista ni de arranque (mismo hueco diferido en la 1.1, 1.2, 1.4 y 1.5) | defer |
| 18 | BH · Estado de la vista duplicado: `restoreOnLaunch()` fija el tramo y `countSteps(from:restoring:)` lo vuelve a fijar | low | Inofensivo: los mismos valores, y la asignación manual es la que usa la sesión pausada | rechazado |
| 19 | BH · La spec lista tres métodos de `StoragePort` (el cuarto está solo en las notas), números de línea previos al cambio y estado distinto del sprint | false | El cuarto método (`setAsideActiveSession`) está justificado en las Implementation Notes por la regla "se aparta, no se destruye"; el estado del sprint se sincroniza al presentar; arreglarlo editaría la spec | rechazado |
| 20 | BH · El doc comment de `Session` quedó sin reajustar | low | Real; reajustarlo es directo | patch |
| 21 | VG · El nombre de `autosaveBySamples` dice 2 guardados y afirma 3 | low | Real (el tercero es el del inicio); renombrarlo es directo | patch |
| 22 | BH · Faltan tests de `failClear`, `failed(read)` y del apartado fallido del adapter | low | Rutas de fallo de E/S excepcionales (ver 8 y 13), cuyo comportamiento es solo registrar el error | rechazado |

## Design Notes

- **El snapshot guarda también el tramo:** `segmentStart`, `segmentSteps` (el `highestCumulativeSteps`) y
  `distanceBaseM`. Al restaurar, el stream se reabre desde `segmentStart` con ese máximo. Así sus acumulados
  (que incluyen lo andado con la app muerta) solo suman lo nuevo, y la reconciliación de la 1.5 funciona sin
  cambios, con `backgroundedAt = savedAt`.
- **Autosave por muestras, no por reloj:** los datos solo cambian cuando llega una muestra o una transición.
  Se guarda en cada transición y en la muestra que llega ≥ 10 s después del último guardado. Quieto no hay
  muestras ni escrituras (AD-21).
- **Recorte de la huérfana:** fin = `lastSampleAt ?? startedAt`. Desde pausa, `finish` cuenta 0 la pausa que
  "termina" antes de `pausedAt`, así que la duración queda en el tramo real.
- **Orden al arrancar:** leer → validar → huérfana o restaurar → reconciliar (activa) → `hasSession = true`.
  La cubierta de la sesión aparece ya consolidada: el bloqueo está acotado por el timeout de la 1.5 y no hay
  pantalla de carga.
- **Frontera:** `restore` recibe `Date` y segundos; el adapter valida la forma del JSON (TypeError de la v3)
  y el dominio los rangos (RangeError de la v3 → `invalidValue`).

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh`: esperado verde, con los 10 sitios de la 1.6 citados.
- `xcodegen generate && xcodebuild test -project WalkTracker.xcodeproj -scheme WalkTracker -destination
  'platform=iOS Simulator,name=iPhone 16e' CODE_SIGNING_ALLOWED=NO`: esperado `TEST SUCCEEDED`, sin warnings
  propios.

**Manual checks (iPhone 14):**
- Caminar 5 min, force-quit, caminar 2 min y reabrir → sesión activa, tiempo real, pasos de los 7 min sin "~"
  y "Sesión recuperada" 3 s.
- Pausar, force-quit y reabrir → pausada. Finalizar, force-quit y reabrir → Inicio.
