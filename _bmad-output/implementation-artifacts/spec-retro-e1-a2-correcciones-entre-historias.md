---
title: 'Retro Epic 1 · A-2 — correcciones y tests entre historias'
type: 'chore'
created: '2026-09-14'
baseline_commit: 'acf4b6849547f21fe4ab42b1804adca720f0514f'
status: 'done'
route: 'dispatch'
review_loop_iteration: 1
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-retro-2026-09-14.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-6-recuperacion-foreground.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la retrospectiva del Epic 1 dejó defectos y huecos que solo aparecen cuando se combinan historias:
- el parche de `lastSampleAt` de la 1.6 está incompleto (R4);
- el stub de almacenamiento no se comporta como el adapter (R7);
- un segundo snapshot apartado destruye el primero, en contra de "se aparta, no se destruye" (R8);
- cuatro caminos entre historias no tienen test (V1–V4);
- los escenarios de la 1.5 y la 1.6 abandonaron la convención `Nativo ·`.

[fuente: epic-1-retro-2026-09-14.md, action item A-2]

**Enfoque:** corregir lo mínimo en el store, el adapter y el stub, y añadir los tests que cierran V1–V4, sin
refactor. El refactor de `SessionStore` es el A-1, otra entrega.

## Boundaries & Constraints

**Always:**
- **R4.**
  - **Cuándo se fija el tope:** al pasar a segundo plano con la sesión activa, en `backgroundedAt`, y al restaurar
    una sesión activa, en `savedAt`.
  - **Cuándo se libera:** con la **primera muestra del stream recibida después, sume pasos o no**.
  - **Qué hace con esa muestra:** si suma pasos, mueve `lastSampleAt` a `min(end, tope)`, sin hacerlo retroceder.
  - **Después:** las muestras siguientes lo mueven con su `end` real.
  - **Varios gaps sin muestra entre medias:** se conserva el tope más temprano.
  - **Pausar o finalizar:** liberan el tope.

  [fuente: retro R4; spec-1-6 Triage #1; decisión de Paul 2026-09-14, pasada 1]
- **R8.** Un snapshot apartado nunca sobrescribe otro ya apartado. Cada uno queda con un nombre único.
  [fuente: spec-1-6 Never "se aparta, no se destruye"]
- **R7.** `StorageStub` aparta solo con `malformed` y `unsupportedSchemaVersion`, igual que el adapter. Con
  `failed`, el snapshot sigue en su sitio.
- **Sin cambios de comportamiento** fuera de R4 y R8. La medición `WTM1` de la 8.4 no cambia de formato.
- `verify-domain.sh` y la suite completa en verde.

**Decisiones de Paul (2026-09-14):**
- **Alcance:** una sola entrega, como la definió la retro.
- **R4 (renegociada tras la revisión, pasada 1):** el tope se fija al ir a background (o al restaurar) y lo libera la primera muestra del stream recibida después, sume pasos o no. La redacción anterior ("la primera que suma pasos") recortaba la siguiente muestra real cuando la consulta ya había cubierto el gap.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

**Never:**
- Refactor de `SessionStore` o de `SessionStoreTests` (A-1).
- Reglas de dominio abiertas en la retro: R1, S10, cadencia o `WakeLockPort`.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| R4 · vuelta con gap sin consulta previa | último dato +60 s, background +600 s, vuelta +5 h, primera muestra del stream 900 pasos con `end` +5 h | `lastSampleAt` = +600 s; la muestra siguiente, con `end` +5 h 0 min 30 s, lo lleva ahí | — |
| R4 · la consulta ya cubrió el gap | background +600 s, vuelta +5 h con consulta → 900, muestra de puesta al día 900 con `end` +5 h y después 930 con `end` +5 h 0 min 30 s | la muestra de 900 libera el tope sin mover `lastSampleAt`; la de 930 lo lleva a +5 h 0 min 30 s | — |
| R4 · muestra durante la consulta | vuelta con la consulta colgada; llega una muestra del stream que suma pasos con `end` = ahora | `lastSampleAt` = `backgroundedAt` | — |
| R4 · nunca retrocede | una muestra real con `end` +700 s procesada **antes** de pasar a background, con el reloj en +600 s (el `end` de CoreMotion va por delante del reloj); background en +600 s y vuelta | tras la vuelta, `lastSampleAt` sigue en +700 s: el tope (+600 s) no lo hace retroceder | — |
| R4 · restaurar | snapshot con `lastSampleAt` +19 min y `savedAt` +20 min; primera muestra tras restaurar con `end` = ahora, y otra después | `lastSampleAt` = +20 min; la siguiente lo mueve con su `end` | — |
| R4 · pausa libera | tope pendiente, pausar, reanudar, muestra con `end` real | `lastSampleAt` = ese `end` | — |
| R8 | dos snapshots ilegibles apartados uno tras otro | los dos ficheros apartados existen con su contenido | — |
| R7 | stub con `failLoad(.failed)` | lanza, y el snapshot sigue en el stub (no apartado) | `failed` |
| V1 | 800 medidos, distancia del sistema 500 m, 400 estimados | distancia 762 m (500 + 400 × 0,655); tras descartar, 500 m | — |
| V2 | huérfana cerrada al arrancar | `store.metrics` es igual a `session.metrics(at: endedAt)`, no nil | — |
| V3 | 1000 pasos y 700 m, pausar, reanudar, 200 y 140 m, background | snapshot `segmentSteps` 200 y `distanceBaseM` 700; relanzar y muestra 250/175 → 1250 pasos y 875 m | — |
| V4 | restaurar sin dato (~400), background, +60 s, volver | solo el gap de 60 s se estima de nuevo, no `[savedAt, ahora]` | — |

</frozen-after-approval>

## Code Map

- **Campos compartidos de `SessionStore` que toca este cambio (lección L3 de la retro):**
  - `lastSampleAt`: `end` de la última muestra del stream que sumó pasos. Con R4 puede quedarse en el inicio del gap. Nunca lo mueve la consulta.
  - `backgroundedAt`: gap pendiente. Se fija al ir a background con la sesión activa y se limpia al terminar la reconciliación y en `leaveSummary()`.
  - `highestCumulativeSteps`: máximo acumulado del tramo. Lo suben la consulta y el stream.
  - `lastSampleAtCap`: nuevo, el tope de R4. Solo existe con la sesión activa y se libera con la primera muestra del stream, en `stopCountingSteps()` y en `leaveSummary()`.
  - La medición `WTM1` y el formato del snapshot no cambian.

- `WalkTracker/Application/SessionStore.swift`:
  - `lastSampleAt` (`:125`); se asigna en `record(_:fromQuery:)` (`:749`, solo si `!fromQuery`).
  - `backgroundedAt` se fija en `appDidEnterBackground()` y se limpia tras `reconcile`.
  - `restoreOnLaunch()` (`:517`) copia `snapshot.lastSampleAt` y reabre el stream con `countSteps(from:restoring:)`.
  - Las líneas `WTM1` (`measure`) no se tocan.
- `WalkTracker/Adapters/Persistence/ActiveSessionFileAdapter.swift`: `setAsideFileName` y `setAsideURL`
  (`:26`, `:36`), y `setAside()` (`:92-97`) hace `rename(2)` sobre un nombre fijo.
- `WalkTrackerTests/Adapters/ActiveSessionFileAdapterTests.swift:157,210-238`: afirman sobre `setAsideURL`.
- `WalkTrackerTests/Support/StorageStub.swift:31-42`: aparta con cualquier `loadError`.
- `Domain/Session/Session.swift:306-308`: distancia = sistema + estimados × zancada (V1).
- `WalkTrackerTests/Application/SessionStoreTests.swift`: suites `SessionStoreReconciliationTests` y
  `SessionStoreRecoveryTests`, con el `Fixture` y el builder `snapshot(...)` de la 1.6. Tests de huérfana en
  `:1691-1780`.
- `WalkTrackerTests/Scenarios/GapReconstructionScenarios.swift` y `SessionRecoveryScenarios.swift`: títulos sin cita
  ni prefijo. La convención es `@Test("Nativo · …")` (p. ej. `SessionLifecycleScenarios.swift:214`).
  `MetricsScenarios.swift` sirve para el escenario de dominio de V1.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTracker/Application/SessionStore.swift`: tope de R4 según Always. Se fija al ir a background o al restaurar;
      lo libera la primera muestra del stream recibida; nunca retrocede; pausar, finalizar y salir del resumen lo liberan.
- [x] `WalkTracker/Adapters/Persistence/ActiveSessionFileAdapter.swift` + sus tests: nombre único al apartar
      (`activeSession.corrupt.<marca>.json`), sin sobrescribir uno existente, y tests de dos apartados seguidos.
- [x] `WalkTrackerTests/Support/StorageStub.swift`: apartar solo con `malformed` o `unsupportedSchemaVersion`, más un
      test del store con `failed` que afirme que el snapshot sigue en su sitio.
- [x] `WalkTrackerTests/Application/SessionStoreTests.swift`: tests de R4 (vuelta y restaurar), V1 (store), V2, V3 y V4
      según la matriz.
- [x] `WalkTrackerTests/Scenarios/MetricsScenarios.swift` (o `GapReconstructionScenarios.swift`): escenario de dominio
      de V1.
- [x] `WalkTrackerTests/Scenarios/GapReconstructionScenarios.swift` + `SessionRecoveryScenarios.swift`: prefijo
      `Nativo · ` en los títulos que no citan `session-v3-tests.js`.

**Acceptance Criteria:**
- Given cada fila de la matriz, when corre su test, then pasa. Y si se deshace su corrección (R4, R7, R8), el test
  correspondiente falla.

## Implementation Notes

> **Pasada 1: código revertido** tras la revisión (intent_gap en R4, ver Spec Change Log). Las notas siguientes describen ese intento y quedan como referencia; la pasada 2 añade las suyas debajo.

- **R4 (`SessionStore`):** estado nuevo `lastSampleAtCap`.
  - Se fija antes de reconciliar en `appDidBecomeActive()`, con `backgroundedAt` y la sesión activa. En
    `restoreOnLaunch()` se fija con `savedAt` antes de reabrir el stream.
  - Con un tope ya pendiente se conserva el más temprano.
  - La primera muestra del stream que suma pasos deja `lastSampleAt = max(lastSampleAt, min(end, tope))` y libera
    el tope. Nunca retrocede: una muestra entregada en background con `end` real no se pierde.
  - `stopCountingSteps()` (pausar, finalizar) y `leaveSummary()` lo limpian: el stream de un tramo nuevo trae `end`
    reales.
  - La consulta sigue sin mover `lastSampleAt` ni liberar el tope. `WTM1` y el formato del snapshot no cambian.
- **R8 (`ActiveSessionFileAdapter`):**
  - Se aparta a `activeSession.corrupt.<UUID>.json` con `renamex_np(RENAME_EXCL)`. Aunque la marca repitiera,
    falla con `failed(setAside)` en vez de sustituir el apartado anterior.
  - `setAsideFileName`/`setAsideURL` pasan a `setAsideFilePrefix`/`setAsideFileExtension`. Los tests listan el
    directorio.
- **R7 (`StorageStub`):** `malformed` y `unsupportedSchemaVersion` apartan; `failed` lanza y deja el snapshot.
- **Tests nuevos:**
  - Adapter: dos ilegibles seguidos y dos apartados seguidos.
  - Store: `failedReadKeepsSnapshot` (R7), `firstStreamSampleAfterReturnIsCapped` y
    `firstStreamSampleAfterRestoreIsCapped` (R4), `systemDistancePlusEstimated` (V1), `orphanPublishesMetrics`
    (V2), `pausedAndResumedSegmentSurvivesRelaunch` (V3) y `backgroundAfterRestoreEstimatesOnlyNewGap` (V4:
    400 + 59, no 880).
  - Escenario de dominio de V1 en `MetricsScenarios`.
  - Prefijo `Nativo · ` en los 18 títulos de la 1.5 y la 1.6 que no citan la v3.
- **Verificado:**
  - `bash Scripts/verify-domain.sh` verde, 158 tests en 11 suites.
  - `xcodegen generate && xcodebuild test … iPhone 16e` → `TEST SUCCEEDED`, 348 tests en 31 suites, sin warnings
    propios.
  - **Mutaciones, una a una:** en cada caso fallan exactamente los tests indicados y ningún otro.
    - Quitar el tope de R4: los dos tests de R4.
    - Stub apartando con `failed`: el de R7.
    - Nombre fijo con `rename(2)`: los dos de R8.
    - Sin `metrics` al cerrar la huérfana: V2.
    - `distanceBaseM: 0` en el snapshot: V3.
    - Sin `backgroundedAt = nil` al restaurar: V4.
    - Distancia sin estimados en `Session.metrics`: V1 en el store y en el dominio.

### Pasada 2

- **R4 (`SessionStore`):** `lastSampleAtCap`.
  - **Se fija** en `appDidEnterBackground()` con la sesión activa (en `backgroundedAt`; si el gap ya estaba pendiente, en el suyo) y en `restoreOnLaunch()` con `savedAt`, antes de reabrir el stream. `capLastSampleAt` conserva el más temprano. `appDidBecomeActive()` ya no lo toca.
  - **Se libera** en `record(_:)` con la primera muestra del stream con `end` > tope, sume pasos o no. Una con `end` ≤ tope (encolada antes del gap y consumida después) mueve `lastSampleAt` como siempre y deja el tope pendiente (revisión de la pasada 2). Si suma, `lastSampleAt = max(lastSampleAt, min(end, tope))`. La consulta (`fromQuery`) ni lo usa ni lo libera.
  - `stopCountingSteps()` (pausar, finalizar) y `leaveSummary()` lo limpian. Docs de `lastSampleAt`, `lastSampleAtCap`, `backgroundedAt` y `highestCumulativeSteps` al día.
- **R8:** marca `<ms con 13 cifras>-<8 hex>` (`activeSession.corrupt.1800000000000-1a2b3c4d.json`) con `renamex_np(RENAME_EXCL)`.
- **R7:** `StorageStub.setAside` pasa a lista (`setAsideCount` = su tamaño); `malformed`/`unsupportedSchemaVersion` apartan detrás de los anteriores, `failed` no.
- **Tests:**
  - Store R4 (9): puesta al día antes de la vuelta, consulta que ya cubrió el gap, consulta que no libera el tope, muestra durante la consulta colgada, nunca retrocede, dos gaps, pausar libera, finalizar libera, restaurar (con la muestra siguiente).
  - V2 con 2400 s / 4000 pasos → 2620 m, 916 s/km, 100 spm.
  - Adapter: helpers ordenados sin `Set<Data>`, cuentan ocurrencias, comprueban que `fileURL` desaparece, la forma del nombre y que la marca del primero no es posterior a la del segundo.
  - Se conservan R7, V1 (store y dominio), V3, V4 y el prefijo `Nativo · ` de la pasada 1.
  - Revisión de la pasada 2: muestra previa al gap (`end` +590 s) que no libera el tope; pausada en background y pausada restaurada que no fijan tope; `failedReadKeepsSnapshot` afirma que la lectura lanza `.failed`; fuera `StorageStub.setAsideCount`. Cada test nuevo falla con su mutación (liberar con cualquier muestra; fijar el tope sin `status == .active` en background o al restaurar).
- **Desvío en la fila "R4 · nunca retrocede":** tal como está redactada (muestra con `end` +700 s **entregada tras** ir a background) contradice la regla Always, porque esa muestra es la primera tras fijar el tope y lo libera en `min(700, 600)` = +600 s. El test sigue la regla Always: la muestra de +700 s se procesa justo **antes** de la salida a background, fechada con el reloj en +600 s. Así `lastSampleAt` es posterior al tope y el `max` se ejercita. Una muestra real entregada en background queda recortada al inicio del gap, lo que es conservador para la huérfana.
- **Liberación en `leaveSummary()`:** redundante hoy, porque todo camino a `finished` con stream pasa por `stopCountingSteps()`. No se puede observar sola: quitar solo esa línea deja todo en verde.
- **Verificado:**
  - `bash Scripts/verify-domain.sh` verde, 158 tests en 11 suites.
  - `xcodegen generate && xcodebuild test … iPhone 16e` → `TEST SUCCEEDED`, 355 tests en 31 suites, sin warnings propios.
  - **Mutaciones, una a una** (fallan exactamente estos tests):
    - Sin tope: 6 de R4 (puesta al día antes de la vuelta, consulta no libera, durante la consulta, nunca retrocede, dos gaps, restaurar).
    - Sin `max`: nunca retrocede.
    - Sin `min` de dos topes: dos gaps.
    - Sin liberar en `stopCountingSteps`: pausar libera.
    - Sin liberar en `stopCountingSteps` ni en `leaveSummary`: pausar y finalizar.
    - Tope fijado al volver en vez de al ir a background: puesta al día antes de la vuelta y nunca retrocede.
    - Liberar solo si suma pasos: consulta que ya cubrió el gap.
    - La consulta libera: consulta no libera, dos gaps y restaurar.
    - Sin tope al restaurar: restaurar.
    - Stub apartando con `failed`: R7.
    - Nombre fijo con `rename(2)`: los dos de R8.
    - Sin `metrics` en la huérfana: V2.
    - `distanceBaseM: 0`: V3.
    - Sin `backgroundedAt = nil` al restaurar: V4.
    - Distancia sin estimados: V1 en el store y en el dominio.

## Spec Change Log

- **Pasada 2 → ajuste de la fila "R4 · nunca retrocede" (decisión de Paul).** La fila describía una muestra entregada *después* de pasar a background y esperaba conservar su `end`, lo que contradice la R4 renegociada: esa muestra es la primera tras fijarse el tope y se recorta a él. La fila pasa a una muestra procesada *antes* de pasar a background cuyo `end` va por delante del reloj, que es lo que prueba `capNeverMovesLastSampleAtBack`. El código no cambia. KEEP: la implementación y los tests de la pasada 2.

- **Pasada 1 → intent_gap (hallazgos 1–3 del triage).**
  - **Enmienda:** R4 (Always, dentro del bloque congelado, renegociada por Paul) y sus filas de la matriz. El tope se fija al ir a background o al restaurar y lo libera la primera muestra del stream recibida, sume pasos o no. La matriz añade los casos "la consulta ya cubrió el gap", "muestra durante la consulta", "nunca retrocede" y "pausa libera". El Code Map lista los campos compartidos.
  - **Estado malo evitado:** con la consulta cubriendo el gap, la siguiente muestra real se recortaba al inicio del gap; y la muestra de puesta al día podía entrar sin tope si llegaba antes de la `Task` de vuelta.
  - **KEEP**, de la pasada 1 (diff de la pasada 1 en `/private/tmp/claude-501/-Users-paul-Dev-walktracker/fec4d90f-16c4-4795-8db0-5dd7ba47906a/scratchpad/diff-a2-pasada1-KEEP.patch`):
    - R7 en `StorageStub` (aparta solo con `malformed`/`unsupportedSchemaVersion`), pero con **lista** de apartados, para que un segundo no pise al primero.
    - R8 con `renamex_np(RENAME_EXCL)` y una marca **ordenable** (ms + sufijo aleatorio) en vez de un UUID solo.
    - Los tests de V1 (store 762 → 500 m y el escenario de dominio en `MetricsScenarios`), V3 (1250 pasos / 875 m) y V4 (400 + 59).
    - V2 con **valores concretos** (2400 s, 4000 pasos).
    - Helpers del adapter que cuenten ficheros en vez de un `Set<Data>`.
    - El prefijo `Nativo · ` en los 18 títulos.
    - Doc de `lastSampleAt` actualizado.
    - Tests que rompan al quitar el `max`, el `min` de dos topes, la liberación en `stopCountingSteps`/`leaveSummary` y el tope fijado al ir a background.

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH/EC/VG · El tope de R4 solo se libera con una muestra del stream **que suma pasos**. En el caso normal, la consulta de vuelta ya sube `highestCumulativeSteps` al acumulado del gap, la muestra de puesta al día no suma, el tope queda pendiente y **la siguiente muestra real** se recorta al inicio del gap | medium | Real al leer `record(_:fromQuery:)`: la consulta pasa antes por `record(sample, fromQuery: true)`. El test lo esquivaba a propósito (consulta 820 < stream 900). Lo exige la redacción congelada de R4 ("la primera muestra del stream que suma pasos") | intent_gap |
| 2 | EC · El tope se fija dentro de la `Task` de `appDidBecomeActive`, creada al volver; la muestra de puesta al día puede procesarse antes y entrar sin tope | maybe-false, medium | El orden entre el `onChange(scenePhase)` de `RootView` y la entrega del stream en el main actor no está garantizado. La redacción congelada ata el tope a "al volver" | intent_gap (con 1) |
| 3 | EC · Con un tope pendiente, un segundo viaje a background mantiene el más temprano y recorta muestras reales tras la segunda vuelta | medium | Consecuencia de 1: el tope no se libera cuando la consulta ya cubrió el gap | intent_gap (con 1) |
| 4 | VG/BH · Partes de R4 sin test: el `max` (nunca retrocede), el `min` de dos topes, la liberación en `stopCountingSteps` y `leaveSummary`, y el tope fijado antes de la consulta | medium | Pre-verificado: sustituir cualquiera deja todo en verde | moot por la vuelta; KEEP: exigir esos tests |
| 5 | BH · El doc de `lastSampleAt` sigue diciendo "último dato real", pero con el tope puede adelantarse al inicio del gap | low | Real (`SessionStore.swift:123-125`) | moot por la vuelta; KEEP: documentarlo |
| 6 | BH/EC · `StorageStub` guarda un solo apartado y un segundo pisa al primero: reintroduce en el stub el defecto R8 que el adapter acaba de perder | low | Real (`StorageStub.swift`, `State.setAside` único) | moot por la vuelta; KEEP: lista de apartados |
| 7 | BH · `RENAME_EXCL` sin test (la colisión de UUID nunca ocurre) | low | El arreglo exige inyectar el generador de nombres; la colisión es improbable | rechazado |
| 8 | BH/EC · Los apartados se acumulan sin límite | low | Solo con snapshots ilegibles repetidos, un caso excepcional | rechazado |
| 9 | BH · Un nombre con UUID pierde el orden de los apartados | low | Real; una marca de tiempo en ms más un sufijo es igual de única y ordenable | moot por la vuelta; KEEP |
| 10 | BH · Si apartar falla, se pierden `errno` y la causa del decode | low | Ruta excepcional; solo afecta al diagnóstico | rechazado |
| 11 | BH/EC · Helpers de test débiles: `Set<Data>` colapsa duplicados, condición muerta en `setAsideNames` y sin comprobar que `fileURL` desaparece | low | Real (`ActiveSessionFileAdapterTests.swift:169-171,199,208`) | moot por la vuelta; KEEP |
| 12 | BH · V2 compara el store contra la misma función en vez de valores concretos | low | Real; se fija con 2400 s y 4000 pasos | moot por la vuelta; KEEP |
| 13 | BH · El test de restaurar de R4 no comprueba que la muestra siguiente vuelve a mover `lastSampleAt` | low | Real | moot por la vuelta; KEEP |
| 14 | BH · El Code Map no lista los campos compartidos de `SessionStore` y sus invariantes (lección L3 de la retro) | low | Real; la spec añade un campo compartido nuevo | se aplica al re-planificar |
| 15 | BH · El diferido de retirar el registro `WTM1` "encaja en el A-2" | false | Retirarlo ahora rompería la caminata del gate 8.4, que aún no se ha hecho; A-2 no lo incluye | rechazado |
| 16 | BH · El action item A-2 sigue `open` en `sprint-status.yaml` | false | Se actualiza al presentar y con la confirmación de Paul; no es un defecto del diff | rechazado |

Pasada 2 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 17 | BH/EC · Una muestra ya encolada antes de pasar a background puede procesarse después de `appDidEnterBackground()` y consumir el tope. La de puesta al día entra sin tope | low | Real en teoría: el consumo del stream y el `scenePhase` corren en el main actor sin orden fijo, y el adapter guarda una muestra con `.bufferingNewest(1)`. Ventana estrecha. Parche coherente con la intención de R4: una muestra con `end <= tope` (dato anterior al gap) no libera el tope | patch |
| 18 | VG · "El tope solo se fija con la sesión activa" sin test en `appDidEnterBackground()` ni en `restoreOnLaunch()` | medium | Pre-verificado: sacar el `capLastSampleAt` del `status == .active` deja todo verde, y el tope recortaría la primera muestra tras reanudar | patch |
| 19 | BH/VG · Si CoreMotion no manda muestra de puesta al día (nada cambió en el gap), el tope sigue pendiente y recorta la primera muestra real en primer plano | low | Real: el stream solo entrega cuando cambian los datos. `lastSampleAt` queda una muestra por detrás, hacia el lado corto de la huérfana; lo corrige la muestra siguiente. Arreglarlo exige estado nuevo | rechazado |
| 20 | BH · Recortar una huérfana al inicio del gap conservando sus pasos infla ritmo y cadencia | low | Consecuencia aceptada de R4 (decisión de Paul): el recorte va hacia el lado corto. Documentarlo editaría la spec | rechazado |
| 21 | BH/EC · El tope no se guarda en el snapshot, y volver a background durante la reconciliación deja un inicio de gap desfasado | low | Misma clase que la 1.5 #4 y la 1.6 #4 (volver a salir durante una reconciliación de milisegundos), ya rechazada | rechazado (arrastrado) |
| 22 | BH/EC · La marca del apartado usa `Date()`: con el reloj hacia atrás, el orden alfabético deja de ser cronológico y la aserción de orden podría fallar | low | Ajustes de reloj de milisegundos entre dos apartados consecutivos de un test; en producción, un apartado es excepcional | rechazado |
| 23 | BH · Una colisión `EEXIST` no reintenta, y el error sustituye al `malformed` en el log | low | Misma clase que la pasada 1 #7 y #10 (colisión improbable, diagnóstico) | rechazado (arrastrado) |
| 24 | BH · El stub no puede simular que apartar falle | low | Ruta excepcional que solo registra el error | rechazado |
| 25 | BH · `StorageStub.setAsideCount` quedó sin uso | low | Real; se borra directamente | patch |
| 26 | BH · Los ficheros apartados con el nombre fijo antiguo siguen en disco | low | Solo en dispositivos con builds anteriores y apartados reales; los tests usan directorios temporales | rechazado |
| 27 | BH · Referencias de la spec que caducan: ruta del scratchpad, `review_loop_iteration` y líneas del Code Map | false | Se arreglaría editando la spec; la ruta del KEEP solo sirve durante la pasada 2 | rechazado |
| 28 | BH · El test de la fila R7 no afirma que la lectura lanza | low | Real (`failedReadKeepsSnapshot`) | patch |
| 29 | BH · Tests de R4 que se quedan cortos (muestra durante la consulta, restaurar → background antes de la muestra) | low | La regla del `min` y el tope al restaurar ya fallan con sus mutaciones (15/15) | rechazado |
| 30 | BH · `emitAndAutosave` se colgaría en vez de fallar si cambia el intervalo de autosave | low | Calidad del test; `waitUntil` agota su timeout y el test falla | rechazado |
| 31 | BH · La liberación del tope en `leaveSummary()` no tiene test propio | low | Redundante con `stopCountingSteps()`, e inofensiva; quitarla no aporta nada | rechazado |
| 32 | EC · Si la puesta al día llega en varias muestras, la segunda lleva `lastSampleAt` a la hora de vuelta | false | La segunda muestra ya es de primer plano, y su `end` es un instante real con la app activa | rechazado |
| 33 | EC · `RENAME_EXCL` sin test | low | Carried: pasada 1 #7 | rechazado (arrastrado) |

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh`: esperado verde.
- `xcodegen generate && xcodebuild test -project WalkTracker.xcodeproj -scheme WalkTracker -destination
  'platform=iOS Simulator,name=iPhone 16e' CODE_SIGNING_ALLOWED=NO`: esperado `TEST SUCCEEDED`, sin warnings propios.
