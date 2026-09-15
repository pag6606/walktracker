---
title: '2.1 — Clima snapshot al inicio de sesión (Open-Meteo)'
type: 'feature'
created: '2026-09-15'
baseline_commit: 'f65647a74c83cbb62adf4c8808c83915154d216c'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-2-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-6-recuperacion-foreground.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** una caminata no guarda nada del clima en que se hizo. Los logros de clima del Epic 3 (`rain_walker`, `hot_walker`,
`cold_walker`) necesitan `session.weather`, y CAP-5 pide capturarlo al iniciar sin que la falta de red
bloquee [fuente: epics.md Story 2.1; capabilities.md#CAP-5].

**Enfoque:** al iniciar la sesión, pedir en segundo plano una ubicación aproximada, redondeada a 2 decimales
por el `LocationPort`, y el clima actual a Open-Meteo por el `WeatherPort`, con un tope de 3 s. El store
congela ese snapshot en la sesión (`weather`) o la deja sin clima. Es la primera llamada de red del producto,
así que su entrega revisa también la privacidad y el cumplimiento de exportación.

## Boundaries & Constraints

**Always:**
- **Snapshot:** `{tempC, feelsLikeC, wmoCode, condition, humidityPct, uvIndex, windKmh, capturedAt}`.
  - `condition` es la categoría interna que sale del código WMO: `rain` para 51–67, 80–82 y 95–99. No se
    calcula con un regex sobre texto.
  - `wmoCode` se conserva, porque `evaluateAchievements.json` ya modela el clima como `{wmoCode, tempC}`.
  - `capturedAt` llega por `ClockPort`.

  [fuente: epics.md Story 2.1; AD-6 divergencia `wmoCategory`]
- **Sin bloqueo:** la sesión abre y cuenta pasos igual que hoy. El clima se pide en paralelo y, si llega dentro del tope,
  lo escribe `SessionStore` (AD-7). Sin red, con permiso denegado o restringido, sin ubicación o con timeout,
  `weather = nil`, sin error visible [fuente: CAP-5; AD-11].
- **Tope y privacidad:**
  - Timeout de 3 s en Open-Meteo, y también en la lectura de ubicación.
  - Coordenadas redondeadas a 2 decimales **dentro del `LocationPort`**, antes de entregarlas.
  - Solo HTTPS del sistema (`URLSession`) contra `api.open-meteo.com`, sin dependencias.

  [fuente: AR-12 (v3 AD-14/AD-17); AD-10; SPEC Privacidad]
- **Congelado:** el snapshot se captura una vez por sesión y no se actualiza después [fuente: SPEC.md#FR-5].
- **Permiso denegado:** no se vuelve a pedir en cada sesión. El adapter posee el estado (AD-11).
- **Persistencia:** `weather` entra en `ActiveSessionSnapshot` y en su JSON (versión de esquema subida), de modo
  que se conserva al restaurar tras un force-quit.
- **Puertos nuevos:** `LocationPort` y `WeatherPort`, dentro del conjunto cerrado de AD-10.
  - Adapters en `Adapters/Location/` y `Adapters/Weather/`, con stubs en tests.
  - CoreLocation solo en `Adapters/Location/`; `check-project-shape.sh` lo hace cumplir.
- `verify-domain.sh` y la suite completa en verde.

**Decisiones de Paul (2026-09-15):**
- **Permiso de ubicación, tras abrir la sesión:**
  - Con `LocationPort.status = notDetermined`, la sesión abre igual y encima aparece una pre-pantalla breve: "¿Añadir el clima a tus caminatas?", con "Permitir" y "Ahora no".
  - "Permitir" lanza el diálogo del sistema; si se concede, la captura empieza en ese momento con su tope de 3 s.
  - "Ahora no" no vuelve a preguntar al iniciar mientras la app siga abierta. Recordarlo entre lanzamientos queda para cuando exista `settings.json` (2.2 o 2.3), registrado en `deferred-work.md`.
  - La pre-pantalla no bloquea el conteo ni los controles de la sesión.
- **Tarjeta de clima en la sesión:**
  - Es estática y va bajo las métricas: SF Symbol, temperatura, condición en español desde el código WMO, y humedad, UV y viento.
  - Sin clima muestra "Sin clima", sin error.
  - Lleva la atribución "Datos: Open-Meteo" (CC-BY 4.0, AD-24).
  - Mientras la captura está en curso no muestra ceros.
- **Manifiesto de privacidad:** declara "Ubicación aproximada" (`NSPrivacyCollectedDataTypeCoarseLocation`) como dato recogido, no vinculado a la identidad, sin rastreo y con propósito "Funcionalidad de la app".
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

**Never:**
- Retrasar la apertura de la sesión esperando al clima, ni mostrar un error de red o de ubicación.
- Refrescar el clima durante la sesión, ni pedir ubicación continua o precisa.
- WeatherKit, SDKs de terceros o cualquier otra llamada de red.
- Frase motivacional (2.2), ajustes y `settings.json` (2.3), logros (Epic 3), historial y export (Epic 5).

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Con red y permiso | ubicación 40.41683, -3.70379; Open-Meteo responde WMO 61, 18 °C | sesión abierta al instante; `weather` = {18, …, wmoCode 61, condition rain, capturedAt}; la petición usa 40.42, -3.70 | — |
| Sin lluvia | WMO 3 | `condition` ≠ rain (categoría "otra"), `wmoCode` 3 | — |
| Sin red / HTTP ≠ 200 / JSON inválido | el adapter falla | sesión sin clima (`weather` nil) | — |
| Timeout | Open-Meteo no responde en 3 s | sesión sin clima; una respuesta tardía se ignora | — |
| Permiso denegado | `LocationPort.status` = denied | no se pide ubicación ni clima; sesión sin clima; no se muestra ningún diálogo | — |
| Clima tras finalizar | la sesión termina antes de que llegue el clima | no se escribe `weather` en una sesión finalizada | — |
| Recuperación | force-quit con `weather` capturado y relanzar | la sesión restaurada conserva `weather` | — |
| Pre-pantalla · Permitir | primera caminata, permiso notDetermined; "Permitir" y concedido | sesión ya abierta y contando; la captura empieza al conceder; `weather` si llega en 3 s | — |
| Pre-pantalla · Ahora no | "Ahora no" y otra caminata en la misma ejecución | sin clima; la pre-pantalla no vuelve a salir | — |
| Tarjeta | con `weather` / sin `weather` / captura en curso | datos del clima con atribución / "Sin clima" / estado de espera sin ceros | — |
| Snapshot antiguo | `activeSession.json` de esquema 1 sin `weather` | se lee como `weather` nil, sin apartarlo | — |

</frozen-after-approval>

## Code Map

- `Domain/Session/Session.swift`: el agregado con `startedAt`, pasos, zancada, pausas y `recovered`; no tiene
  `weather`. `Session.restore(...)` (1.6) valida el snapshot en la frontera.
- `Domain/Achievements/AchievementMetric.swift:34` define `WeatherCategory` (solo `rain`), que ya consume el catálogo de logros.
- `WalkTrackerTests/Vectors/evaluateAchievements.json` modela `weather` como `{wmoCode, tempC}` (casos de lluvia con WMO 51, 61, 67, 95 y 99).
- `climate.js:22-37` tiene la tabla WMO → español, que sirve de referencia para mostrar `condition`.
  `:50-76` es la ubicación de la v3 (una sola lectura, 3 s, `maximumAge` 5 min, redondeo a 2 decimales) y `:91-133` la
  URL de Open-Meteo: `current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,uv_index`, con `timezone=auto`.
- `Domain/Ports/`: patrón de puerto con DTO `Sendable` (`MotionPort` con `status`/`requestPermission`, `PermissionStatus`).
  `LocationPort` y `WeatherPort` son nuevos, y `CapabilityError` ya existe.
- `WalkTracker/Application/SessionStore+StartFlow.swift`: `start()` y `openSession()`, donde se abre la sesión y el
  conteo. `SessionStore+Recovery.swift` guarda (`persist()`) y restaura. `SessionStore.swift` contiene
  `resetSessionState()` y la entrada de fases.
- **Campos compartidos del store** (lección L3):
  - `session`, `metrics`, `hasSession`, `isReconciling` (comandos bloqueados);
  - `lastSavedAt`, `resetSessionState()` y `restoreOnLaunch()` (1.6).

  Un campo nuevo, como la tarea del clima, entra en `resetSessionState()` y se cancela al finalizar.
- `Domain/Ports/ActiveSessionSnapshot.swift` y `WalkTracker/Adapters/Persistence/ActiveSessionFileAdapter.swift`:
  el snapshot no tiene `weather`; el esquema es 1, `decode` rechaza versiones desconocidas y lo apartado no se borra.
- `WalkTracker/App/CompositionRoot.swift` construye puertos y store; `WalkTracker/App/Info.plist:42` ya tiene
  `NSLocationWhenInUseUsageDescription`, y `:52` `ITSAppUsesNonExemptEncryption = NO`, con una nota "a revisar por la
  historia del clima".
- `WalkTracker/Resources/PrivacyInfo.xcprivacy`: cero datos, con una nota "SUPOSICIÓN, a revisar por la historia del clima".
- `Scripts/check-project-shape.sh`: la sección 10 ya prohíbe CoreLocation en `UI/`, y la 7 limita CoreMotion a su
  adapter, que es el patrón a copiar para CoreLocation. `Scripts/release-testflight.sh` y un diferido de la 8.3 comprueban el
  manifiesto y el flag de cifrado dentro del `.app`.
- `WalkTracker/UI/Session/SessionView.swift`: `DistanceHero`, la rejilla de `MetricCell`, el banner de estimados y
  los controles. `WalkTracker/UI/Permission/MotionPermissionView.swift` es el patrón de la pre-pantalla.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Weather/WeatherSnapshot.swift` (nuevo): tipo de valor validado en la frontera (números finitos,
      humedad y UV en rango), `WeatherCondition` desde el código WMO (`rain` / otra) y test de la tabla WMO.
- [x] `Domain/Session/Session.swift`: `weather: WeatherSnapshot?`, con `attachWeather(_:)` solo activa o pausada
      y una sola vez; restaurarlo con `restore`.
- [x] `Domain/Ports/LocationPort.swift` + `WeatherPort.swift` (nuevos), y
      `WalkTracker/Adapters/Location/LocationAdapter.swift` + `Adapters/Weather/OpenMeteoAdapter.swift` (nuevos): una
      lectura aproximada con 3 s y redondeo a 2 decimales en el adapter de ubicación; `URLSession` con 3 s y
      decodificación del JSON de Open-Meteo.
- [x] `WalkTracker/Application/SessionStore+Weather.swift` (nuevo): captura en paralelo al abrir la sesión, tope de
      3 s en total, escritura por el store, cancelación en `resetSessionState()` y al finalizar, guardado del
      snapshot al llegar.
- [x] `Domain/Ports/ActiveSessionSnapshot.swift` + `ActiveSessionFileAdapter.swift`: `weather` en el snapshot,
      esquema 2 que sigue leyendo el 1.
- [x] `SessionStore` + `WalkTracker/UI/Permission/LocationPermissionView.swift` (nuevo) + `WalkTracker/UI/Session/WeatherCard.swift` (nuevo) + `SessionView.swift`: pre-pantalla de ubicación sobre la sesión y tarjeta de clima según las Decisiones de Paul.
- [x] `WalkTracker/App/CompositionRoot.swift`: cablear los adapters.
- [x] `WalkTracker/Resources/PrivacyInfo.xcprivacy` + `WalkTracker/App/Info.plist` + `README.md`: declarar ubicación
      aproximada según las Decisiones de Paul, quitar las notas de suposición, y confirmar el cifrado exento, ya que solo se usa HTTPS del sistema.
- [x] `Scripts/check-project-shape.sh` + tests: CoreLocation solo en `Adapters/Location/`.
- [x] `Scripts/release-testflight.sh` + tests: comprobar tras archivar que `PrivacyInfo.xcprivacy` está en el `.app` y que
      el flag de cifrado es `false` (cierra el diferido de la 8.3).
- [x] `WalkTrackerTests/`: `WeatherSnapshot`, adapters (URL, redondeo, decodificación, timeout con `URLProtocol`
      de test) y la matriz en el store con stubs.
- [x] `Localizable.xcstrings`: textos con `comment`; después, `xcodegen generate`.

**Acceptance Criteria:**
- Given el iPhone 14 con red y permiso de ubicación, when inicio una caminata, then la sesión arranca al instante y el
  clima aparece (o queda guardado) en unos segundos.
- Given el modo avión, when inicio una caminata, then arranca igual y sin clima, sin ningún error.
- Given el permiso denegado, when inicio varias caminatas, then nunca se me vuelve a pedir la ubicación.

## Implementation Notes

- **Dominio:** `WeatherSnapshot` tiene un `init` que lanza (`throws(DomainError)`). Valida `tempC`/`feelsLikeC` finitos, `wmoCode` en 0–99, `humidityPct` en 0–100, y `uvIndex`/`windKmh` ≥ 0 y finitos. `WeatherCondition(wmoCode:)` da `rain`/`other`. `Session.weather` y `attachWeather(_:)`, que lanza `invalidTransition(from: status, to: "attachWeather")` con la sesión finalizada y `invalidTransition(from: status, to: "replaceWeather")` si ya tiene clima. `restore(..., weather:)` tiene `nil` por defecto.
- **Puertos:**
  - `LocationPort` (`status`, `requestPermission()`, `approximateLocation() throws(CapabilityError) -> Coordinates`).
  - `WeatherPort` (`currentWeather(at:) throws(CapabilityError) -> WeatherReading`). El DTO no lleva fecha: el store crea el snapshot con `clock.now`.
- **`LocationAdapter`:**
  - `CLLocationManager` en un `Core` `@MainActor`, con `kCLLocationAccuracyReduced` y `requestLocation()`.
  - Acepta la ubicación en caché si tiene ≤ 5 min y precisión ≥ 0. Tope de 3 s. Redondea con `rounded(latitude:longitude:)` (mitad lejos de cero, sin `-0`).
  - El permiso se copia a un `Mutex` para leer `status` desde cualquier hilo.
  - **Añadido:** `NSLocationDefaultAccuracyReduced = YES` en `Info.plist`, para que el diálogo ofrezca la ubicación aproximada, coherente con el manifiesto.
- **`OpenMeteoAdapter`:**
  - `URLSession` efímera y URL de la v3, con coordenadas `%.2f`.
  - Carrera petición/temporizador en un `TaskGroup`. Aquí sí vale, porque `URLSession` se cancela.
  - `URLError.timedOut` cuenta como `timeout`. HTTP ≠ 200 da `failed("http N")` y un JSON inválido o con `null`, `failed("decode")`.
- **Store (`SessionStore+Weather.swift`):**
  - `openSession()` llama a `beginWeatherForNewSession()`: con permiso, captura; sin decidir, `locationPrompt = .offering`, salvo tras "Ahora no" en la ejecución; denegado, restringido o sin ubicación, no hace nada.
  - Un tope por paso (`weatherStepTimeoutS`, 3 s): la ubicación con el suyo y el clima con el suyo, cada uno en una carrera con `FirstResult` que la cancelación resuelve. Entre los dos pasos, `guard !Task.isCancelled`. La revisión corrigió un primer tope único de 3 s para los dos, que contradecía la frontera.
  - "Ahora no" vale también en `.requesting`: si el sistema nunca responde, quita la pre-pantalla, y la respuesta tardía no reabre nada ni captura.
  - Al llegar: valida, adjunta si la sesión es la misma (`startedAt`), sigue abierta y no tiene clima, reasigna `metrics` y llama a `persist()`.
  - `cancelWeatherCapture()` corre en `confirmFinish()` y en `resetSessionState()`, y quita también la pre-pantalla.
  - `declinedLocationPromptThisLaunch` no se resetea. Una sesión restaurada sin clima no captura ni pregunta.
  - Estado nuevo: `isCapturingWeather`, `locationPrompt`, `weatherCapture`, `declinedLocationPromptThisLaunch`, y las dependencias `location`, `weather` y `weatherStepTimeoutS`.
- **Persistencia:** esquema 2 con `weather {tempC, feelsLikeC, wmoCode, humidityPct, uvIndex, windKmh, capturedAtMs}`. `condition` no se guarda: sale de `wmoCode`. Se leen las versiones 1 (sin clima) y 2. Un clima con la forma rota da `malformed`. Con la forma bien y los rangos rotos, se lee sin clima y la caminata no se aparta (AD-11).
- **UI:**
  - `WeatherCard` va bajo las métricas: símbolo, temperatura, condición en español (WMO 77 es "Granos de nieve", no granizo como en la v3), humedad/UV/viento y "Datos: Open-Meteo" como `Link` a open-meteo.com (objetivo de 44 pt, elemento de VoiceOver aparte). Mientras captura muestra "Buscando el clima…"; sin clima, "Sin clima".
  - `LocationPermissionView` va como `safeAreaInset(edge: .top)` sobre la sesión, sin tapar los controles.
  - 37 textos nuevos con `comment` en el catálogo; el comentario de "Ahora no" cubre sus dos usos.
- **Gates y release:**
  - `check-project-shape.sh`: la sección 7 pasa a ser `framework_only_in` (CoreMotion → `Motion/`, CoreLocation → `Location/`). La sección 6 añade `beginWeatherForNewSession`, `cancelWeatherCapture`, `weatherCapture`, `stepCounting`, `location` y `weather`. La sección 11 nueva solo admite `URLSession`, `URLRequest` e `import Network` en `WalkTracker/Adapters/Weather/`.
  - `release-testflight.sh` comprueba tras archivar el manifiesto dentro del `.app` (existe, es un plist válido y declara `NSPrivacyCollectedDataTypeCoarseLocation`), `NSLocationWhenInUseUsageDescription` en el `Info.plist` archivado y `ITSAppUsesNonExemptEncryption == false`. Queda cerrado el diferido de la 8.3.
  - `verify-domain.sh` incluye `WeatherSnapshotTests`.
- **Privacidad:** `PrivacyInfo.xcprivacy` declara `CoarseLocation`, no vinculada, sin rastreo y con propósito `AppFunctionality`. Las notas de suposición salen del manifiesto, del `Info.plist` y del README. Declarar lo mismo en «Privacidad de la app» de App Store Connect es un paso de "En cada release" en el README.
- **Tests:**
  - `WeatherSnapshotTests` (tabla WMO 0–99, frontera, agregado).
  - `LocationAdapterTests` y `OpenMeteoAdapterTests` (URL, decodificación, HTTP, sin red, timeout con `URLProtocol` de test, en serie).
  - `SessionStoreWeatherTests` (matriz entera).
  - `WeatherFormatTests`, `ActiveSessionFileAdapterTests` (esquema 2/1), `CompositionRootTests` (cableado).
  - Stubs nuevos `LocationStub` y `WeatherStub`. El fixture del store usa por defecto la ubicación denegada.
- **Verificado (2026-09-15, antes de la revisión):**
  - `bash Scripts/check-project-shape-tests.sh`: 68/68.
  - `bash Scripts/release-testflight-tests.sh`: 36/36.
  - `bash Scripts/verify-domain.sh`: verde, 168 tests en 12 suites.
  - `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO`: `TEST SUCCEEDED`, 420 tests en 39 suites, sin warnings propios.
  - **Pendiente:** los checks manuales en el iPhone 14 (red y permiso, modo avión, permiso denegado).

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH · Ubicación y clima comparten 3 s, pero la frontera congelada dice 3 s para Open-Meteo **y** 3 s para la ubicación; una primera lectura aproximada en frío suele pasar de 3 s | medium | Real: `readingWithinBudget` usa un único `weatherBudgetS = 3`. Las Design Notes (no congeladas) decían tope único "desde la apertura" y contradicen la frontera. Parche: alinear con la frontera, 3 s por paso | patch |
| 2 | EC/BH · Si el sistema no llama al delegado, la pre-pantalla queda en `.requesting` con los botones deshabilitados y no se puede quitar | medium | Real: `Core.requestPermission` solo vuelve con un callback distinto de `notDetermined`, y `.disabled(isRequesting)` cubre "Ahora no" | patch |
| 3 | EC/BH · Un clima que llega durante la reconciliación no se guarda en disco | false | `persist()` no guarda mientras reconcilia, pero `appDidBecomeActive()` y `restoreOnLaunch()` llaman a `persist()` al terminar, y `confirmFinish()` borra el snapshot. Lo que sí es real es el comentario desfasado de `reconcile` | patch (comentario + test) |
| 4 | EC · Ubicación cacheada con `horizontalAccuracy` negativa | low | Real; guarda directa | patch |
| 5 | EC · La tarea cancelada llama al clima después de obtener la ubicación | low | Depende de que `URLSession` respete la cancelación; guarda directa | patch (con 1) |
| 6 | BH · El código WMO 77 aparece como "Granizada", pero son granos de nieve | low | Real; la tabla de la v3 arrastraba el error | patch |
| 7 | BH · La atribución de Open-Meteo no enlaza | low | CC-BY 4.0 y los términos de Open-Meteo piden enlace; un `Link` es directo | patch |
| 8 | BH · `attachWeather` pone un valor que no es de estado en `from:` | low | Real; directo | patch |
| 9 | VG · `WeatherFormat.spoken` sin test | low | Pre-verificado; es la convención de los otros `*Format.spoken` | patch |
| 10 | VG/BH · `lateWeatherDoesNotReachNextSession` no puede fallar | medium | Pre-verificado: quitar el `cancel()` o el guard de `startedAt` deja todo en verde | patch |
| 11 | BH · El gate no casa `store.weatherCapture`/`stepCounting` por el `\b` | low | Real; directo | patch |
| 12 | BH · Ningún gate impone que el clima sea la única llamada de red | medium | El manifiesto, el flag de cifrado y el README dependen de esa regla | patch |
| 13 | BH · `release-testflight.sh` no comprueba el contenido del manifiesto ni la clave de permiso en el Info.plist archivado | low | Un manifiesto vacío pasaría; sin la clave, el permiso no se pide y la pre-pantalla se atasca (hallazgo 2) | patch |
| 14 | BH · La declaración en App Store Connect y los checks manuales no están en los pasos de release | low | Real; va en el README | patch |
| 15 | VG/BH · El camino real de `LocationAdapter` (cache, timeout, permisos) no tiene tests | medium | Pre-verificado; necesita una costura sobre `CLLocationManager` | defer |
| 16 | BH · Dos enums de lluvia sin sincronizar, y el test no lee los vectores | low | Se une cuando el Epic 3 evalúe `rain_walker` (3.2) | defer |
| 17 | BH · El esquema 2 siempre: un build anterior apartaría una caminata en curso | low | Solo bajando de build a mitad de caminata; escribir v1 sin clima añade una rama | rechazado |
| 18 | BH · El adapter nunca devuelve `.unavailable` (servicios de ubicación desactivados) | low | `locationServicesEnabled()` puede bloquear el hilo principal; con servicios desactivados la lectura falla y la sesión sigue sin clima igual | rechazado |
| 19 | EC · "Permitir" pulsado minutos después da clima de ese momento | low | Consecuencia aceptada de la decisión de Paul: la captura empieza al conceder | rechazado |
| 20 | EC · La tarjeta dice "Sin clima" mientras la pre-pantalla ofrece añadirlo | low | La pre-pantalla, encima, lo explica; un estado intermedio añade un texto sin cambiar el resultado | rechazado |
| 21 | EC · El gate de CoreLocation no revisa `Shared/` ni la extensión | low | Fuera del alcance de la spec (`WalkTracker/`), como en el A-6 | rechazado |
| 22 | BH · `timeoutIgnoresLateResponse` duerme 50 ms y el `sharedBudget` es incompleto | low | Se cubre con los parches 1 y 10 | rechazado |
| 23 | BH · Un clima fuera de rango en el snapshot se descarta sin log | low | Solo con un fichero editado a mano; el adapter no tiene logger | rechazado |
| 24 | BH · Docs y spec (`withTaskGroup` en `OpenMeteoAdapter`, estado del sprint) y ficheros fuera del diff | false | El `withTaskGroup` del adapter está justificado en las notas; el sprint se sincroniza al presentar; el catálogo y el contexto se excluyeron del diff a propósito | rechazado |

## Design Notes

- **Tope único:** la ubicación y el clima comparten un presupuesto de 3 s desde la apertura. Así la sesión nunca
  espera y el snapshot corresponde al instante de inicio.
- **Carrera sin `withTaskGroup`:** la misma lección que en la 1.5, porque una tarea colgada no puede bloquear la salida. Se
  puede reutilizar `FirstResult`.
- **Esquema 2 del snapshot:** `weather` es opcional. El decodificador acepta las versiones 1 y 2 y escribe la 2.

## Verification

**Commands:**
- `bash Scripts/check-project-shape-tests.sh` y `bash Scripts/release-testflight-tests.sh`: esperado verde.
- `bash Scripts/verify-domain.sh` y `xcodegen generate && xcodebuild test … iPhone 16e CODE_SIGNING_ALLOWED=NO`:
  esperado verde, sin warnings propios.

**Manual checks (iPhone 14):**
- Caminata con red y permiso: el clima correcto para la zona, y la sesión arranca sin espera.
- Modo avión: la sesión arranca sin clima y sin errores. Permiso denegado en Ajustes: no hay diálogo al iniciar.
