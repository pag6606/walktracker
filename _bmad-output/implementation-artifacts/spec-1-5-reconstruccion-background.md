---
title: '1.5 — Reconstrucción de intervalos en background por query al sistema'
type: 'feature'
created: '2026-09-14'
baseline_commit: '6d2a3aa500f305da048b886a518d9cad5ae8681a'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-4-pausar-reanudar-finalizar.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** al volver de background, los pasos del intervalo solo entran cuando el podómetro emite su
siguiente muestra, y al finalizar se pierden los que aún no llegaron. No hay degradación si el sistema no
tiene el dato, ni forma de ver o descartar pasos estimados [fuente: capabilities.md#CAP-3].

**Enfoque:** al volver a foreground con la sesión activa, y al finalizar desde activa, el store reconcilia
de forma atómica y acotada por timeout (AD-8): consulta por rango al `MotionPort`. Si no hay dato, el
`GapEstimator` del dominio estima el gap. Lo estimado se muestra desglosado con "~" y es descartable.

## Boundaries & Constraints

**Always:**
- **Consulta primero:** los pasos del gap salen de `MotionPort.query`; con dato, `stepsEstimated` sigue en
  0 [fuente: capabilities.md#CAP-3].
- **GapEstimator solo sin dato** (nil, vacío, error o timeout): `stepsEstimated += round(cadenceSpm ×
  gapS/60)`. Solo con la sesión activa y ≥ 120 s de muestra previa; si no, gap = 0. La cadencia es solo
  de pasos medidos [fuente: domain-model.md#49, #73].
- **Atómica (AD-8):** durante la reconciliación el store rechaza todo comando y la UI los deshabilita.
  `SessionStatus` no cambia. Un rango que empieza hace más de 7 días no se consulta: pasa directo a
  estimación [fuente: ARCHITECTURE-SPINE.md#AD-8].
- **Timeout:** `reconciliationTimeoutS` en `formulas.json`, con valor **provisional marcado**. Al agotarse,
  degrada y libera los comandos. La 8.4 lo sustituye [fuente: epics.md Story 1.5; AD-8].
- **Estimados:** siempre desglosados y marcados "~". Descartarlos es irreversible y exige confirmación
  (AD-20). Al descartar, distancia y ritmo se recalculan [fuente: domain-model.md#20; epics.md Story 1.5].
- `Domain/` sigue puro y `verify-domain.sh` en verde.

**Never:**
- Persistir `activeSession.json`, recuperar tras force-quit, "Sesión recuperada" o sesión huérfana (1.6).
- Estimar en pausa, al finalizar sin gap pendiente o sobre pasos estimados.
- Combinar el stream continuo con consultas periódicas (AD-21): la consulta solo reconcilia.
- Tocar `MotionAdapter`: `query(from:to:)` ya existe.

**Decisiones de Paul (2026-09-14):**
- **Superficie de descarte:** la 1.5 entrega el Estimated Banner en la sesión: "~N pasos estimados" +
  "Descartar" con confirmación. Sigue visible mientras haya estimados, sin ocultarse a los 30 s de la v3.
  La celda de pasos muestra el desglose ("4.100 ~236"). La 1.6 lo reutiliza tras la recuperación.
- **Mientras reconcilia:** los controles se deshabilitan siempre. El texto del mockup v4
  (`SesionReconciliando`) aparece solo si la reconciliación dura más de 0,5 s, para evitar el parpadeo.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Gap con dato | activa, tramo desde t0, 300 pasos vistos; background 5 min; query → 820 | medidos = 820, estimados 0 | — |
| Query nil / error / timeout | activa 10 min a 80 spm; gap 300 s | estimados +400 ("~400") | — |
| Sin muestra previa | activa 90 s; query nil | estimados 0 | — |
| Tramo > 7 días | tramo abierto hace 8 días | no se consulta; estima | — |
| Query menor que lo visto | 300 pasos vistos; query → 120 | se trata como sin dato | — |
| Comandos durante | reconciliando; pausar / finalizar / descartar | no hacen nada | — |
| Finalizar desde activa | query → 830 | cierra con 830 medidos | — |
| Finalizar sin dato | activa, query nil | cierra sin estimar | — |
| Pausada al volver | pausada en background | no consulta ni estima | — |
| Descartar | 400 estimados; confirmar | estimados 0; distancia y ritmo recalculados | — |
| Mutar finalizada | `addEstimatedSteps` / descartar en finalizada | no muta | `invalidTransition` |

</frozen-after-approval>

## Code Map

- `Domain/Session/Session.swift`: `stepsEstimated` ya existe (siempre 0). `addMeasuredSteps` (`:85`) es el
  patrón a seguir: solo en `active`, `invalidTransition` y sin mutar. `metrics(at:)` (`:205`) ya suma
  estimados × zancada a la distancia y excluye los estimados de la cadencia. No cambia.
- `domain.js:330-339` `addEstimatedSteps`; `:508-517` `estimateSteps` (≤ 0 → 0, `Math.round`, NaN → TypeError).
- `WalkTrackerTests/Vectors/estimateSteps.json`: 8 vectores, hoy `pending`. `VectorHarness.swift:185`
  `swiftDomain` es el registro de funciones portadas; seguir el patrón de `SwiftDomainPorts.calculateCadence`.
- `inventory.json`: escenarios 1.5 en `test/session-v3-tests.js` `:114`, `:200`, `:297`, `:308`, `:309` y
  `:311`. `check-inventory.js:141-144` exige un `@Test` en `Scenarios/` que cite cada uno.
- `Domain/Formulas/Formulas.swift` + `WalkTracker/Resources/formulas.json`: hoy solo `defaultStrideM`,
  validada al arrancar (`FormulasTests.swift`). `CompositionRoot.swift:47` construye `SessionStore`.
- `WalkTracker/Application/SessionStore.swift`:
  - `countSteps(from:)` (`:273`) abre el tramo, con `highestCumulativeSteps` y `distanceBaseM`.
  - `record(_:)` (`:299`) aplica una muestra acumulada del tramo sin restar nunca; se reutiliza tal cual
    para el resultado de la consulta.
  - `confirmFinish()` (`:159`) es síncrono.
- `WalkTrackerTests/Support/MotionStub.swift:64`: `query` devuelve siempre `nil`.
- `WalkTracker/UI/RootView.swift`: siempre montada. Sus comentarios sobre "sin salida hasta la 1.4" están
  desfasados (hallazgo 14 de la 1.4). `HomeView.swift:24-37` usa el patrón `scenePhase`
  `.background → .active`.
- `WalkTracker/UI/Session/SessionView.swift`: `MetricCell.steps` (`:198`), `controls` (`:118`) y
  `confirmationDialog` de finalizar (patrón para descartar). `SessionSummaryView.swift` muestra solo
  `stepsMeasured` (vía `FinishedWalk`).
- `.design-v4/SesionReconciliando.dc.html`: celda "4.100 ~236 pasos" y el texto "Recuperando los pasos del
  rato en segundo plano. Los controles vuelven en un momento."
- `Scripts/verify-domain.sh`: lista `-only-testing` de suites.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Session/GapEstimator.swift` (nuevo): `estimateSteps(cadenceSpm:gapS:) throws(DomainError) -> Int`,
      portado de `domain.js:508`; NaN lanza `invalidValue`. Añadir `steps(for:gapStart:gapEnd:)`, que
      devuelve 0 salvo con la sesión `active` y `elapsedS(at: gapStart) ≥ minPriorSampleS` (120); la
      cadencia sale de `metrics(at: gapStart)`.
- [x] `Domain/Session/Session.swift`: `addEstimatedSteps(_:)` (solo `active`; valida el conteo y el
      desbordamiento) y `discardEstimatedSteps()` (`active` o `paused`; lanza en `finished`).
- [x] `Domain/Formulas/Formulas.swift` + `formulas.json`: `reconciliationTimeoutS` (> 0 y finito; valor
      provisional 3) y `provisional: [String]`, donde cada nombre debe ser una constante conocida.
- [x] `WalkTracker/App/CompositionRoot.swift`: pasar el timeout al store.
- [x] `WalkTracker/Application/SessionStore.swift`:
      - Estado `isReconciling` y el inicio del tramo (`segmentStart`).
      - Intenciones `appDidEnterBackground()` y `appDidBecomeActive() async`.
      - `confirmFinish() async`: reconcilia antes de cerrar si la sesión está activa.
      - Descarte con confirmación: `requestDiscardEstimated()`, `cancelDiscardEstimated()`,
        `confirmDiscardEstimated()` e `isConfirmingDiscard`.
      - Todas las intenciones de comando salen sin hacer nada mientras reconcilia.
- [x] `WalkTracker/UI/RootView.swift`: `scenePhase` → intenciones del store; actualizar comentarios.
- [x] `WalkTracker/UI/Session/SessionView.swift` + `SessionSummaryView.swift`: "~N" desglosado en la celda
      de pasos (VoiceOver: "N pasos, M estimados"); Estimated Banner bajo la rejilla con "Descartar"
      (≥ 44 pt) y `confirmationDialog` destructivo; controles deshabilitados con `isReconciling`, y el texto
      de v4 solo tras 0,5 s reconciliando. El resumen muestra "~N" sin descarte.
- [x] `WalkTrackerTests/Support/MotionStub.swift`: respuesta de `query` configurable (muestra, nil, error,
      colgada hasta resolver) y registro de rangos consultados.
- [x] `WalkTrackerTests/Vectors/VectorHarness.swift`: registrar `estimateSteps`.
- [x] `WalkTrackerTests/Scenarios/GapReconstructionScenarios.swift` (nuevo): portar los 6 sitios de la 1.5
      y los escenarios del estimador (pausada, < 120 s, 80 spm × 300 s, descarte); añadir la suite a
      `verify-domain.sh`.
- [x] `WalkTrackerTests/Application/SessionStoreTests.swift` + `FormulasTests.swift`: toda la matriz en el
      store (con timeout de test ~0,05 s y query colgada) y la validación de las constantes nuevas.
- [x] `Localizable.xcstrings`: textos nuevos con `comment`. Después, `xcodegen generate`.

**Acceptance Criteria:**
- Given el iPhone 14 con la sesión activa, when bloqueo 5 min caminando con música y vuelvo, then los pasos
  aparecen al instante sin "~" y sin esperar a dar otro paso.
- Given la sesión activa, when finalizo justo después de caminar, then el resumen incluye los últimos pasos.
- Given pasos estimados en pantalla, when descarto y confirmo, then desaparece el "~" y la distancia baja.

## Implementation Notes

- `GapEstimator` (enum): `minPriorSampleS = 120`, `estimateSteps(cadenceSpm:gapS:)` y `steps(for:gapStart:gapEnd:)`.
  NaN lanza `invalidValue` con su campo. Divergencia deliberada: una entrada infinita > 0 lanza con su campo y un
  producto que no cabe en `Int` lanza `invalidValue(steps)`, donde `domain.js` devuelve `Infinity`. Un gap negativo da 0.
- `Session`: `addEstimatedSteps(_:)` (solo `active`; `invalidTransition(to: "addEstimatedSteps")`, `invalidValue(steps)`
  con negativo o desbordamiento) y `discardEstimatedSteps()` (`active`/`paused`; `invalidTransition` en `finished`).
- `Formulas`: `reconciliationTimeoutS` (> 0 y finito) y `provisional` (cada nombre en `Formulas.constantNames`; si no,
  `invalidValue(provisional)`). Los dos campos son obligatorios en el JSON; `schemaVersion` sigue en 1. `formulas.json`:
  `reconciliationTimeoutS: 3` con `provisional: ["reconciliationTimeoutS"]`.
- `SessionStore(clock:motion:strideM:reconciliationTimeoutS:)`: `isReconciling`, `isConfirmingDiscard`, `segmentStart`
  (lo fija `countSteps(from:)`) y `backgroundedAt`. `reconcile(until:)` es el único camino: consulta `[segmentStart, end]`
  si el tramo tiene ≤ 7 días, aplica la muestra por `record(_:)` si `steps ≥` el máximo visto **al empezar** la
  reconciliación y, sin dato, estima solo si hay `backgroundedAt`. Comparar con el máximo del inicio (y no con el
  actual) evita que una muestra del stream entregada durante la consulta convierta una consulta válida en
  "sin dato" y estime por duplicado. `confirmFinish()` reconcilia hasta el instante del toque si está activa y cierra
  en ese instante; con un gap pendiente también podría estimar (no se alcanza desde la UI, que reconcilia al volver).
  El timeout compite con `Task.detached` y un `FirstResult` (Mutex + continuación) que resuelve el primero.
  `pause`, `resume`, `requestFinish`, `confirmFinish`, `requestDiscardEstimated`, `confirmDiscardEstimated`,
  `leaveSummary` y `appDidBecomeActive` salen sin hacer nada mientras reconcilia; `cancel*` solo cierran el diálogo.
- `RootView`: `scenePhase` `.background` → `appDidEnterBackground()`, `.active` → `appDidBecomeActive()` (el store ignora
  las fases sin gap pendiente). Comentarios desfasados de la 1.4 actualizados.
- `SessionView`: celda "4.100 ~236" (el "~N" en `.orange`), VoiceOver "N pasos, M estimados"; Estimated Banner bajo la
  rejilla ("~N pasos estimados", "Del intervalo que el sistema no pudo reconstruir", "Descartar" ≥ 44 pt con
  `confirmationDialog` destructivo); controles y "Descartar" `.disabled(isReconciling)`; aviso de v4 tras 0,5 s con
  `.task(id: isReconciling)`. `SessionSummaryView` muestra "~N" sin descarte (`FinishedWalk.estimatedSteps`).
- `MotionStub`: `setQueryResponse(.sample/.none/.failure/.hang)`, `queriedRanges`, `hasPendingQuery` y
  `resolvePendingQueries(with:)`.
- Tests: `GapReconstructionScenarios` porta `:114`, `:200`, `:297`, `:308`, `:309`, `:311` y añade agregado y estimador;
  en `verify-domain.sh`. `estimateSteps` registrado (`estimateStepsIsPorted`). `SessionStoreReconciliationTests` (23 tests,
  timeout 0,05 s) cubre la matriz entera más tramo de justo 7 días, distancia sobre la base del tramo, stream durante la
  consulta, salir otra vez a background mientras reconcilia y finalizar con consulta lenta. `FormulasTests` valida las
  constantes nuevas. Los tests de la 1.4 esperan ahora `await confirmFinish()`.
- Verificado: `bash Scripts/verify-domain.sh` verde (inventario completo con la 1.5 citada; 27 vectores Swift pasan,
  `estimateSteps` sin pendientes). `xcodegen generate && xcodebuild test … iPhone 16e` → `TEST SUCCEEDED`, 252 tests, sin
  warnings propios. Mutaciones: comparar con el máximo actual rompe `streamDuringReconciliation`; quitar la guarda de
  `pause` rompe `commandsAreRejectedWhileReconciling` y `finishWaitsForSlowQuery`; estimar al finalizar sin gap rompe
  `finishWithoutDataDoesNotEstimate`. **Pendiente:** los checks manuales en el iPhone 14.
- Revisión (pasada 1): 5 parches, 2 diferidos y 14 rechazados.
  - **Parches:**
    - Solo se estima si el stream no avanzó durante la consulta.
    - Los diálogos abiertos se cierran al empezar la reconciliación.
    - Los tests esperan a que el stub registre la consulta, con timeout de 5 s por defecto.
    - Nuevo `MetricCellStepsTests`.
    - Comentarios de `Localizable` igualados.
  - **Diferidos:** el test del cableado de `RootView` y la doble cuenta posterior a una consulta nil, en `deferred-work.md`.
  - Los dos tests nuevos del store fallan sin su parche.

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH · `estimateSteps` calcula `cadenceSpm * (gapS / 60)` y no coincide con JS en redondeos `.5` (15 spm × 246 s) | false | `domain.js:516` usa el mismo orden, `cadenceSpm * (gapS / 60)`; `node` da 61 para 15 × 246, igual que Swift | rechazado |
| 2 | BH/EC · Con la consulta sin dato usable pero el stream entregando durante la reconciliación, se estima igual: el gap cuenta doble y la cadencia sale inflada | medium | Real: `record` sube `highestCumulativeSteps` durante el `await` y la rama de estimación no lo miraba. Parche: estimar solo si `highestCumulativeSteps == seen` + `streamDuringTimeoutDoesNotEstimate` | patch |
| 3 | BH · Tras una consulta nil o con error, el stream puede entregar DESPUÉS el acumulado con el gap: cuenta doble | maybe-false | Depende de CoreMotion: si el sistema no tiene el dato para la consulta, tampoco debería tenerlo para el stream. Lo zanja registrar muestras tras una consulta nil en el iPhone 14 | defer |
| 4 | BH/EC · Una segunda salida a background durante la reconciliación pierde el gap (`backgroundedAt = nil` al acabar la primera) | low | Real, pero la reconciliación dura milisegundos y el stream sigue entregando esos pasos en su siguiente muestra; el arreglo añade estado | rechazado |
| 5 | EC · La `Task` de `.active` puede correr ya en background tras un `background → active → background` rápido | low | Misma clase que el 4: ventana de milisegundos y el stream recupera los pasos; exige leer la fase en el store | rechazado |
| 6 | BH · La estimación no tiene tope (8 días → 920.800 pasos) | low | Es lo que fija la spec (sin dato, estimar); siempre "~" y descartable, y la sesión huérfana de la 1.6 cierra antes. Un tope añade una regla que la spec no tiene | rechazado |
| 7 | BH/EC · Con el diálogo de Finalizar o Descartar abierto al empezar la reconciliación, confirmar se pierde en silencio o descarta estimados no vistos | low | Real (abrir diálogo → background → volver). Parche directo: cerrar ambos diálogos al empezar la reconciliación + `reconciliationClosesDialogs` | patch |
| 8 | BH · Al finalizar con la consulta lenta (> 0,5 s) aparece el aviso "del rato en segundo plano" sin haber salido | low | Real solo con una consulta de más de 0,5 s al finalizar; distinguir el origen exige estado nuevo | rechazado |
| 9 | BH · El aviso de reconciliación no se anuncia a VoiceOver | low | Solo aparece si pasan 0,5 s; los controles deshabilitados ya se leen como atenuados | rechazado |
| 10 | BH/EC · Carreras de tiempo real en los tests: se resuelve la consulta antes de que el stub la registre, y el timeout de 0,05 s puede ganar a una consulta inmediata | medium | Real: `isReconciling` pasa a `true` antes de que la `Task.detached` llegue al stub. Parche: esperar `hasPendingQuery`, timeout por defecto 5 s y cortos solo en los tests de timeout | patch |
| 11 | BH/EC · Una muestra de 0 pasos con `seen == 0` cuenta como dato y no estima | maybe-false | Un 0 del sistema puede ser legítimo (teléfono quieto); tratarlo como sin dato estimaría pasos que no se dieron. Aunque fuera real, sería low | rechazado |
| 12 | BH/EC · `provisional` no tiene lector, `constantNames` puede quedar desfasado y acepta duplicados | low | Si se desfasa, marcar una constante nueva como provisional falla ruidosamente al arrancar; un duplicado no causa daño | rechazado |
| 13 | BH · La spec y el código no coinciden sobre estimar al finalizar; el estado de la spec y el del sprint difieren | false | La spec solo prohíbe estimar "al finalizar sin gap pendiente", y el código estima solo con gap; el estado del sprint se sincroniza al presentar | rechazado |
| 14 | BH/VG · Los comentarios de "%lld estimados" y "%lld pasos" no coinciden entre el catálogo y el código | low | Real; igualarlos es directo | patch |
| 15 | BH · La lectura de VoiceOver "N pasos, M estimados" se concatena y no es traducible | low | La app solo está en español | rechazado |
| 16 | VG/BH · Sin test del cableado de `scenePhase` en `RootView` ni de lo que pinta la vista al reconciliar | medium | Pre-verificado: quitar el `.onChange` deja todo en verde. No hay arnés de tests de vista (mismo hueco diferido en la 1.1, 1.2 y 1.4) | defer |
| 17 | VG · Sin test del desglose "~N" de `MetricCell.steps` | low | Pre-verificado; `MetricCell` es un `struct` con `value`/`estimate` que se pueden probar. Parche: `MetricCellStepsTests` | patch |
| 18 | VG · Sin test de que `CompositionRoot` pasa `reconciliationTimeoutS` al store | low | Real e igual que la `strideM` de la línea anterior; probarlo exige exponer el timeout privado | rechazado |
| 19 | EC · Un `reconciliationTimeoutS` enorme hace trap en `Duration.seconds`; uno diminuto agota todas las consultas | low | `formulas.json` va en el bundle y lo controla el proyecto (3 s); sin entrada externa | rechazado |
| 20 | EC · Al finalizar desde activa, las muestras del stream que llegan durante la consulta entran en una sesión que cierra en el instante del toque | low | La ventana es el tiempo de la consulta (milisegundos) y son pocos pasos; parar el stream antes perdería los atrasados si la consulta falla | rechazado |
| 21 | EC (afirmación) · El criterio "sin '~'" no se cumple si la consulta pasa de 3 s | false | Con el parche 2, si el stream entregó no se estima; lo que queda es la degradación que manda la spec | rechazado |

## Design Notes

- **Se consulta el tramo, no el gap:** `query(from: segmentStart, to: now)` da el acumulado del tramo, con
  la misma semántica que el stream, y entra por `record(_:)`. El máximo de `highestCumulativeSteps` evita
  contar dos veces lo que el stream entregue después, y recupera también los pasos atrasados de antes del
  gap. Un resultado menor que `highestCumulativeSteps` es incoherente y cuenta como sin dato. El límite de 7
  días se mide sobre `segmentStart`, que es el inicio real del rango consultado.
- **Gap:** `backgroundedAt` se fija en `.background`, solo si la sesión está activa y aún no hay uno
  pendiente, y se limpia al terminar la reconciliación. Volver mientras ya reconcilia no abre otra.
- **Timeout sin `withTaskGroup`:** el grupo espera a sus hijos al salir, y la consulta de CoreMotion no se
  puede cancelar, así que una consulta colgada bloquearía. Hay que competir con una `Task` no estructurada
  y una continuación que resuelve el primero; el resultado tardío se ignora.
- **Finalizar:** consulta hasta el instante del toque y cierra en ese instante. Sin dato no estima, porque
  no hay gap. Desde pausa no consulta: el tramo ya se cerró al pausar.
- **Riesgo conocido:** si la consulta agota el timeout pero el stream entrega después el acumulado, los
  pasos del gap cuentan como medidos y como estimados. Es visible ("~") y descartable. La 8.4 mide el timeout.
- **Descartar en pausa:** se permite, a diferencia de la v3 (`addEstimatedSteps(-n)` lanzaba en pausa), porque
  el banner también se ve en pausa.
- **Color de "~":** `.orange` del sistema, sin hex (epic-1-context, UX).

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh`: esperado verde, con los sitios de la 1.5 citados y `estimateSteps` sin
  pendientes.
- `xcodegen generate && xcodebuild test -project WalkTracker.xcodeproj -scheme WalkTracker -destination
  'platform=iOS Simulator,name=iPhone 16e' CODE_SIGNING_ALLOWED=NO`: esperado `TEST SUCCEEDED`, sin
  warnings propios.

**Manual checks (iPhone 14):**
- Bloquear 5 min caminando con música → al volver, pasos exactos al instante; comparar con Salud; nunca "~".
- Finalizar justo tras caminar → el resumen incluye los últimos pasos.
- Pausar, bloquear, volver → nada cambia y no aparece "~".
