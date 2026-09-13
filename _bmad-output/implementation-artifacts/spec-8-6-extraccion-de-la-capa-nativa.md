---
title: '8.6 — Extracción de la capa nativa desde feature/flutter-substrate'
type: 'feature'
created: '2026-09-12'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '65212730eee64de4649698f5efa7bacb06b19f26'
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la única implementación nativa del proyecto (podómetro, háptica, escritura de workout
en Salud, Live Activity) son 446 líneas de `ios/Runner/AppDelegate.swift` en `feature/flutter-substrate`
(`d9d3fbc`), rama que no es ancestro de `HEAD`. Están atadas a canales de Flutter y **nunca se
ejecutaron en un dispositivo**.

**Enfoque:** extraer ese único fichero con `git checkout feature/flutter-substrate --
ios/Runner/AppDelegate.swift`, trocearlo en cuatro adapters —Motion, Feedback, Health,
LiveActivity— cada uno detrás de su puerto, retirar el fichero extraído, y verificar en el iPhone 14
que cada capacidad funciona de verdad.

## Boundaries & Constraints

**Always:**
- Sin merge de `feature/flutter-substrate`: solo checkout de ese fichero (AD-23).
- Puertos en `Domain/Ports/`, solo `Foundation`, con DTOs `Sendable` propios; adapters en
  `WalkTracker/Adapters/{Motion,Feedback,Health,LiveActivity}/` como `XxxAdapter` (AD-10).
- El handler de CoreMotion corre en su cola serie y extrae los valores a un DTO **dentro del
  handler**; `CMPedometerData` y sus `NSNumber` no cruzan la frontera (AD-7, AD-12).
- Cada adapter posee y expone el estado de su permiso (AD-11).
- Metros y segundos en los DTOs; la distancia no se trunca a entero.
- Se construyen solo en `CompositionRoot` (AD-10).

**Never:**
- Ningún `if #available`: los `#available(iOS 16.2)` del original desaparecen (AD-2).
- Sin `SessionStore`, sin disparo de eventos de sesión, sin pre-pantallas de permiso, sin
  persistencia de `soundEnabled`: son de las historias 1.2, 4.1/4.2, 6.1 y 7.x.
- Ni el `WalktrackerActivityAttributes` ni el `ContentState` del original: el contrato es
  `Shared/WalkTrackerActivityAttributes` + `ActivitySnapshot` (AD-15).
- No queda lógica de sistema en ningún delegado de app ni en vistas.
- No se tocan `project.yml` salvo `DEVELOPMENT_TEAM`, ni el gate de forma del proyecto.

**Decisiones de Paul (2026-09-12):**
- **`LiveActivityPort` vive en `Domain/Ports/`** y recibe un DTO de magnitudes crudas (pasos,
  metros, ritmo, `timerStart`, `frozenElapsed`). El adapter lo convierte en `ActivitySnapshot`
  formateado. AD-3 y AD-10 quedan intactos; el formateo vive en el adapter hasta que el Epic 7 lo
  lleve a `Shared`.
- **La verificación en el iPhone se hace desde una pantalla de diagnóstico solo en `DEBUG`**,
  accesible desde `RootView`: pasos en vivo, un botón por evento háptico, escritura de un workout de
  prueba (1 min, 100 pasos, 80 m) y start/stop de Live Activity. Se borra cuando exista la UI de
  sesión, con entrada en `deferred-work.md`.
- **La spec se mantiene completa** pese a superar el tamaño recomendado: los cuatro adapters salen del
  mismo fichero y el criterio de la historia exige los cuatro.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Muestra de podómetro | `CMPedometerData` con `distance` 812,4 m | DTO con `distance == 812.4` | — |
| Podómetro sin distancia | `distance == nil` | DTO con `distance == nil`, nunca `0` | — |
| Query sin datos | el sistema devuelve `nil` sin error | `nil` | — |
| Salud no disponible o denegada | `writeWorkout` | lanza error tipado del puerto | nunca un error crudo de HealthKit |
| Fallo intermedio del builder | `addSamples` o `endCollection` fallan | lanza; no se llama a `finishWorkout` | el original los ignoraba |
| Live Activities desactivadas | `start` | lanza error tipado; nada más se rompe | fila "Live Activity no disponible" (AD-11) |

</frozen-after-approval>

## Code Map

- `git show feature/flutter-substrate:ios/Runner/AppDelegate.swift` — origen. Pedómetro 89-162 +
  `PedometerStreamHandler` 419-446; feedback 164-238 (`feedbackParams`: inicio 0,8/0,5, km 0,6/0,5,
  meta/logro 1,0/0,8, resto 0,4/0,3; `SystemSoundID` 1054/1057/1025/1052); Salud 240-325; Live
  Activity 327-414.
- **Defectos del original que no se portan:** `distance.intValue` (trunca metros, 133 y 433);
  resultados de `builder.add`/`endCollection` ignorados (311-312); `quantityType(forIdentifier:)!`;
  `#available(iOS 16.2)`; `startStepTracking` que no arranca nada (el stream lo hacía por su cuenta).
- `Domain/Ports/ClockPort.swift` — patrón de puerto a imitar (doc-comments con AD, `Sendable`).
- `Shared/ActivitySnapshot.swift`, `Shared/WalkTrackerActivityAttributes.swift` — contrato de la Live
  Activity; se reutilizan tal cual.
- `WalkTracker/App/CompositionRoot.swift`, `WalkTrackerApp.swift`, `UI/RootView.swift` — cableado.
- `WalkTracker/App/Info.plist` y `.entitlements` — usage strings, `NSSupportsLiveActivities` y
  HealthKit ya presentes; no se tocan.
- `Scripts/check-project-shape.sh` — marca como error todo `.swift` versionado fuera de target:
  `ios/Runner/AppDelegate.swift` rompe el build mientras exista, así que se retira en el mismo cambio.
- `.gitignore` — las reglas de `ios/Runner/` se quedan (ignoran restos locales de Flutter); su
  comentario sobre la 8.6 se actualiza.
- Firma: equipo de pago `Z3M45B4K6D`; iPhone 14 emparejado (`5C7E4401-278C-57F6-9514-239C7B0FBC19`).

## Tasks & Acceptance

**Execution:**
- [x] `ios/Runner/AppDelegate.swift` — `git checkout feature/flutter-substrate -- …` como punto de
      partida; se elimina al terminar el troceado.
- [x] `Domain/Ports/` — `PermissionStatus`, `CapabilityError`, `MotionPort` + `PedometerSample`,
      `FeedbackPort` + `FeedbackEvent` (inicio, km, meta, logro), `HealthPort` + `WorkoutRecord`,
      `LiveActivityPort` + `LiveActivityState`. Un tipo por fichero.
- [x] `WalkTracker/Adapters/Motion/MotionAdapter.swift` — updates continuos como `AsyncStream`,
      query por rango, permiso; conversión a DTO dentro del handler, expuesta para test.
- [x] `WalkTracker/Adapters/Feedback/FeedbackAdapter.swift` — CoreHaptics con reinicio del motor,
      sonido de sistema si `soundEnabled`; mismos parámetros que el original.
- [x] `WalkTracker/Adapters/Health/HealthAdapter.swift` — autorización de escritura y `HKWorkoutBuilder`
      con las APIs `async`, propagando cada fallo.
- [x] `WalkTracker/Adapters/LiveActivity/LiveActivityAdapter.swift` — `Activity.request/update/end`
      sobre `WalkTrackerActivityAttributes`.
- [x] `WalkTracker/App/CompositionRoot.swift` — construye los cuatro adapters y los expone por puerto.
- [x] `WalkTracker/UI/Diagnostics/NativeLayerDiagnosticsView.swift` — pantalla `#if DEBUG` que usa
      los cuatro puertos; enlazada desde `RootView`. Entrada en `deferred-work.md` para retirarla.
- [x] `project.yml` — `DEVELOPMENT_TEAM: Z3M45B4K6D` en la base (el ID de equipo va en todo binario
      firmado; no es secreto).
- [x] `WalkTrackerTests/Adapters/` — tests de la matriz que no requieren hardware: conversión a
      `PedometerSample`, mapa de `FeedbackEvent` a parámetros.

**Acceptance Criteria:**
- Given el cambio, when se busca `ios/Runner/AppDelegate.swift`, `import Flutter` o `#available`
  en el árbol versionado, then no existe ninguno; y `git log main..HEAD --merges` está vacío.
- Given `Domain/`, when se busca `CMPedometer`, `CHHaptic`, `HKHealthStore`, `HKWorkout` o `Activity<`, then no aparece.
- Given el build para simulador sin firma, then compila sin warnings de aislamiento y los tests pasan.
- Given la app instalada en el iPhone 14, when se usa la superficie de verificación, then el podómetro
  reporta pasos al caminar, la háptica se siente en los cuatro eventos, y el workout de prueba aparece
  en la app Salud. Lo que falle se registra como coste adicional de Epic 6 o Epic 7 y no bloquea el
  cierre.

## Implementation Notes

- **Sendable sin `@unchecked` en producción.** `CMPedometer` y `CHHapticEngine` viven tras un
  `Mutex` de `Synchronization`; `Activity` no es `Sendable` y no se guarda: el adapter guarda su
  `id` y la busca en `Activity.activities`. El único `@unchecked Sendable` es el doble de
  `CMPedometerData` del test, justificado en línea.
- **`MotionAdapter.updates`**: un solo stream vivo; uno nuevo termina el anterior. La parada del
  podómetro en `onTermination` se difiere a otra cola porque el `Mutex` no es reentrante y un
  handler podría disparar la terminación con el lock tomado. Un error de CoreMotion termina el
  stream; el motivo se lee en `status`.
- **Contratos de puerto elegidos:** `CapabilityError` = `unavailable · notAuthorized ·
  failed(operation:)`. `WorkoutRecord` valida en su `init` (`throws(DomainError)`) que `end > start`
  y que pasos y metros no son negativos: `HKQuantitySample` con intervalo invertido lanza una
  excepción de Objective-C, no un error. `FeedbackPort` no expone `status`: háptica y sonido no
  tienen permiso.
- **No portado del original, a propósito:** el respaldo `UIImpactFeedbackGenerator` (todo iPhone con
  iOS 26 soporta CoreHaptics) y la rama "resto" 0,4/0,3 · 1052 (el `FeedbackEvent` cerrado no la
  admite). `HealthAdapter` llama a `discardWorkout()` si falla `addSamples` o `endCollection`.
- **Formateo de la Live Activity** (`es_ES`): distancia en km con dos decimales desde metros sin
  truncar; pasos con el agrupado del locale. Provisional hasta el Epic 7.
- **`#available` en el árbol versionado:** cero en código. Solo aparece como prosa en artefactos de
  planificación de `_bmad-output/` que citan la prohibición.
- **Verificado:** `xcodegen generate` + gate en verde; `check-project-shape-tests.sh` 9/9; `clean
  test` en iPhone 16e sin firma → `TEST SUCCEEDED`, 10 tests, cero warnings propios; build firmado
  para el iPhone 14 e instalación con `devicectl` correctos. **Pendiente:** los checks manuales en el
  iPhone (el dispositivo estaba bloqueado; no se pudo lanzar).
- **Costuras de test para tres filas de la matriz** (pedidas tras auditar el diff; contratos de
  puerto y comportamiento de producción intactos, sin `@unchecked` en producción):
  `HealthAdapter.requireWritePermission(_:)` (puerta de permiso previa a escribir) y
  `HealthAdapter.write(_:from:to:using:)` sobre el protocolo interno `WorkoutBuilding`, que en
  producción implementa `HealthKitWorkoutBuilder` envolviendo `HKWorkoutBuilder`;
  `LiveActivityAdapter.init(areActivitiesEnabled:requestActivity:)` con valores por defecto del
  sistema. Filas cubiertas: *Salud no disponible o denegada* y *Fallo intermedio del builder*
  (`HealthAdapterTests`), *Live Activities desactivadas* (`LiveActivityDisabledTests`). `clean test`
  en iPhone 16e sin firma: 18 tests en 6 suites, `TEST SUCCEEDED`, cero warnings propios.

- **Tras la revisión (17 correcciones, ver Review Triage Log).** `HealthAdapter` escribe solo las
  muestras de los tipos permitidos (permiso parcial ya no descarta el workout); `requestPermission`
  de Motion solo da `.denied` ante un rechazo de permiso; el motor háptico se apaga solo en reposo
  (`isAutoShutdownEnabled`, AD-21). Estado, permisos por tipo y builder de Salud son inyectables
  para test. Verificación final: `clean test` en iPhone 16e → 30 tests en 8 suites, cero warnings
  propios; build firmado para el iPhone 14 `BUILD SUCCEEDED` e instalada (`com.walktracker.app` 4.0.0).

- **Verificación en el iPhone 14 (2026-09-12, Paul): todo funcionó.** Podómetro contando pasos al
  caminar, háptica en los cuatro eventos, workout de prueba visible en Salud, y Live Activity iniciada
  y terminada. El código extraído, que nunca se había ejecutado en un dispositivo, no genera coste
  adicional para los Epics 6 y 7.

## Spec Change Log

## Review Triage Log

| # | Capa | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|---|
| E1 | edge | `MotionAdapter.query` no comprueba `start <= end` | low | Ningún llamador actual invierte el rango; el de AD-8 (1.x) lo construye desde la sesión. El arreglo añade una guarda | rechazado |
| E2 · B7 | edge · blind | `requestPermission` convierte cualquier error en `.denied` | medium | `failedWithError ? .denied : .granted` ignora `capabilityError(from:)`; un `.unavailable` activaría la pantalla bloqueante de Motion denegado (AD-11) | patch |
| E3 | edge | Diagnóstico: si el stream termina solo, la UI se queda en "Detener conteo" | low | Tras el `for await` solo se refresca `motionStatus`; `countingSince` sigue puesto. Arreglo de una línea | patch |
| E4 · B3 · V-o1 | edge · blind · verif | Permiso parcial de Salud descarta el workout entero | medium | `status` solo mira `workoutType`; si el usuario deniega pasos o distancia, `addSamples` falla y se descarta todo. El original terminaba el workout igual | patch |
| E5 · B4 | edge · blind | Sin `discardWorkout()` si fallan `beginCollection` o `finishWorkout` | maybe-false | Sin `beginCollection` no hay nada recogido; tras un `finishWorkout` fallido el builder local se libera. Lo zanjaría comprobar si HealthKit persiste algo antes de `finish`. Si fuera cierto, low | rechazado |
| E6 | edge | Se escribe muestra de 0 pasos pero no de 0 m | low | Caso improbable (workout sin pasos); el arreglo añade rama | rechazado |
| E7 | edge | `errorRequiredAuthorizationDenied`/`errorUserCanceled` salen como `.failed` | low | `RequiredAuthorization` es de tipos clínicos, que no se piden; el arreglo añade ramas | rechazado |
| E8 · B12 | edge · blind | Live Activity no soportada sale como `.denied` | false | `TARGETED_DEVICE_FAMILY: 1` e iOS 26: todo iPhone objetivo soporta Live Activities | rechazado |
| E9 · B11 | edge · blind | Dos `start` solapados o `start`/`end` intercalados dejan una actividad huérfana | low | Solo alcanzable con doble toque en diagnóstico o fin de sesión en milisegundos; serializar exige actor o flag entre `await`s | rechazado |
| E10 | edge | `currentID` queda obsoleto si `request` lanza | false | `currentActivity()` busca el id en `Activity.activities`; la actividad ya terminada no está y devuelve `nil` | rechazado |
| E11 | edge | El doc-comment dice que se encuentra la actividad de un lanzamiento anterior; `end()` no lo hace | low | `currentID` no se persiste: el comentario es falso. Corrección directa del comentario | patch |
| E12 | edge | `LiveActivityState` con NaN o negativos se formatea tal cual | low | El productor es el dominio (validado en frontera); el arreglo añade guardas | rechazado |
| E13 | edge | Diagnóstico: `liveActivityRunning` obsoleto si el sistema retira la actividad | low | Solo diagnóstico; exige refrescar desde el puerto | rechazado |
| E14 | edge | Diagnóstico: `healthStatus` no se refresca si `requestAuthorization` lanza | low | Corrección de una línea | patch |
| B1 | blind | `WorkoutRecord.distance` no es opcional | false | La distancia del dominio se deriva de pasos × zancada (Calibration): siempre existe | rechazado |
| B2 | blind | `LiveActivityState.distance` no es opcional | false | Misma derivación que B1 | rechazado |
| B8 | blind | El stream de Motion no dice por qué terminó; el doc promete que `status` lo explica | low | Cierto solo para permisos. Quien consume sabe si canceló él. Cambiar a stream que lanza altera el puerto; se corrige el comentario | patch |
| B9 | blind | El límite de 7 días no se hace cumplir en `query` | false | AD-8 asigna esa regla a la reconciliación (quien llama), y el puerto lo documenta | rechazado |
| B10 | blind | Generaciones del stream y ciclo de Live Activity sin tests | low | Requiere inyectar `CMPedometer` y `Activity`; el camino start/stop/start se ejercita en el iPhone | rechazado |
| B13 | blind | Redondeo: 995 m se muestra "1,00 km" antes del evento de km | low | Formateo declarado provisional por la intención (Epic 7 lo lleva a `Shared` con la regla de `UI/Format`) | rechazado |
| B14 | blind | Locale `es_ES` fijo | low | Provisional por la intención; la parte del test que no fija el texto va en V4 | rechazado |
| B15 | blind | `CHHapticEngine.start()` síncrono en el hilo principal | low | Solo tras background o reinicio; el original hacía lo mismo al arrancar. Arreglo con arranque asíncrono | rechazado |
| B16 | blind | El motor háptico nunca se apaga | medium | Sin `isAutoShutdownEnabled`, el motor queda activo toda la caminata: coste contra el gate de batería (AD-21, 8.4). Una línea; `stoppedHandler` ya marca `needsStart` | patch |
| B17 | blind | `everyEventIsCovered` no prueba nada | low | El `switch` exhaustivo ya lo garantiza. Borrarlo es corrección directa | patch |
| B18 | blind | `DEVELOPMENT_TEAM` fijo en el manifiesto | false | Decisión registrada en la spec aprobada; el arreglo edita la spec | rechazado |
| B19 | blind | `RootView` genérico queda tras borrar el diagnóstico | low | La entrada de `deferred-work.md` no dice que hay que deshacer el genérico. Corrección de texto | patch |
| B20 | blind | El diff no incluye la spec ni `sprint-status.yaml` | false | Exclusión deliberada del flujo de revisión | rechazado |
| V1 | verif | `writeWorkout` no se prueba con su puerta de permiso | gap | Filed: los tests llaman solo al helper estático | patch |
| V2 · B5 | verif · blind | `samples(for:)` sin tests | gap | Filed: unidades, intervalo y rama `distance > 0` sin cubrir | patch |
| V3 · B6 | verif · blind | Validación de `WorkoutRecord` sin tests | gap | Filed: ninguna rama del `init` cubierta | patch |
| V4 | verif | El test de `stepsText` filtra separadores | gap | Filed: 1 234 no agrupa en `es_ES`; el test no fija el texto | patch |
| V5 | verif | Mapeo de errores de `request` de Live Activity sin tests | gap | Filed: el hook existe y no se usa con actividades habilitadas | patch |
| V6 | verif | `soundEnabled` de `fire` sin test | gap | Filed con disposición defer: no hay hook para el sonido | defer |
| V7 | verif | `finishWorkout` sin producir y fallo de `beginCollection` sin tests | gap | Filed: el doble siempre produce | patch |
| V8 | verif | `permission(from:)` sin tests | gap | Filed: función pura sin cubrir | patch |
| V-o2 | verif | 1 234 pasos no agrupan en `es_ES` y los fixtures dicen "1.234" | false | `es_ES` agrupa desde 5 cifras (norma RAE); los fixtures del humo son valores escritos a mano, no salida del adapter | rechazado |

## Verification

**Commands:**
- `xcodegen generate && bash Scripts/check-project-shape.sh` — esperado: forma correcta.
- `xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16e' CODE_SIGNING_ALLOWED=NO test`
  — esperado: `TEST SUCCEEDED`, cero warnings de concurrencia.
- `xcodebuild … -destination 'id=<udid>' build` + `xcrun devicectl device install app` — esperado:
  app instalada en el iPhone 14.

**Manual checks:**
- En el iPhone, Paul: caminar ~30 pasos con la superficie abierta, disparar los cuatro eventos,
  escribir el workout de prueba y localizarlo en Salud → Entrenamientos (borrable después).
