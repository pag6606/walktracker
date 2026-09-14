---
title: '1.2 — Conteo de pasos en vivo vía coprocesador (MotionPort)'
type: 'feature'
created: '2026-09-13'
status: 'done'
baseline_commit: '4533332e065c4cd5f5fe6f61fc2c4f8149a6b0aa'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-1-iniciar-sesion-cronometro-wall-clock.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la sesión mide el tiempo pero no cuenta pasos, que es el corazón del producto. Además, la
app todavía no pide el permiso de Motion & Fitness ni sabe qué hacer si se deniega.

**Enfoque:** al iniciar, pedir el permiso con una pantalla explicativa previa; con él concedido, abrir la
sesión y consumir las muestras continuas del `MotionPort` de la 8.6, acumulándolas en `stepsMeasured`
del agregado a través de `SessionStore`, y mostrarlas en vivo. Denegado, una pantalla bloqueante con
acceso a Ajustes, y ninguna sesión.

## Boundaries & Constraints

**Always:**
- El conteo sale **solo** del coprocesador por `MotionPort`; `MotionAdapter` es el único que conoce
  `CMPedometer` y ninguna vista importa CoreMotion (AD-10). Solo el DTO `Sendable` cruza al main actor
  (AD-7, AD-12).
- `stepsMeasured` es entero ≥ 0 y **nunca baja**: una muestra acumulada menor que la anterior no resta.
- Mutación del agregado solo por `SessionStore`, con una operación de dominio que porta `addSteps`
  (`domain.js:316`): suma un entero ≥ 0 y rechaza lo demás con error tipado.
- Muestras **acumuladas desde el inicio**: los pasos dados en background entran en la primera muestra al
  volver, sin estimación; `stepsEstimated` sigue en 0 (CAP-3).
- Permiso: pre-pantalla explicativa antes de pedirlo (AD-11). Solo con `granted` se crea la sesión y
  arranca el conteo.
- Motion denegado o restringido: pantalla completa bloqueante con explicación y botón a Ajustes; es la
  única degradación bloqueante (AD-11).
- Escenarios de la 1.2 del inventario portados a mano; `verify-domain.sh` en verde con el gate de citas.

**Never:**
- Distancia, ritmo o cadencia (1.3); pausar o finalizar (1.4); consulta por rango al volver (1.5).
- Detección propia de pasos con acelerómetro: el `StepDetector` de la PWA está retirado.
- Pedir el permiso en frío, sin pre-pantalla.

**Decisiones de Paul (2026-09-13):**
- **Pantalla de sesión:** el tiempo sigue grande en el centro y los pasos van debajo como segunda
  métrica. En la 1.3 la distancia pasa al centro y tiempo y pasos bajan a la rejilla del mockup.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Primera vez | permiso sin decidir, "Iniciar caminata" | pre-pantalla → diálogo del sistema → concedido → sesión y conteo | — |
| Ya concedido | "Iniciar caminata" | sesión directa, sin pre-pantalla | — |
| Denegado o restringido | al iniciar, o al responder al diálogo | pantalla bloqueante con acceso a Ajustes; sin sesión | — |
| Muestra acumulada | 0 → 120 → 350 | `stepsMeasured` 0 → 120 → 350 | — |
| Muestra menor | 350 → 340 | `stepsMeasured` sigue en 350 | — |
| Volver de background | 350 antes, primera muestra 900 | `stepsMeasured` = 900; `stepsEstimated` = 0 | — |
| Stream terminado por el sistema | el adapter cierra sin cancelar | la sesión sigue; conserva los pasos | registrado |
| Cuenta inválida | `addSteps` con negativo | no muta | `invalidValue(field: "steps")` |

</frozen-after-approval>

## Code Map

- `Domain/Ports/MotionPort.swift` · `WalkTracker/Adapters/Motion/MotionAdapter.swift` (8.6) — no se tocan.
  `updates(from:)`: muestras acumuladas desde `start`, buffer `.bufferingNewest(1)`; cancelar la
  iteración detiene el podómetro; si el sistema falla, el stream termina solo (ya lo registra).
  `requestPermission()`: `.granted`, `.denied`, `.unavailable`, o `.notDetermined` ante un fallo
  transitorio (`permission(afterRequest:)`, `:64`). `status` puede ser `.unavailable` (simulador).
- `Domain/Session/Session.swift` (1.1) — `stepsMeasured` `private(set)`; añadir la operación junto a
  `start(at:strideM:)`. Referencia `domain.js:316` `addSteps`: `assertMutable`, entero ≥ 0, 0 no cambia.
  La distancia que recalcula el JS **no** se porta (1.3, AD-22). `DomainError` ya tiene
  `invalidValue(field:)` e `invalidTransition(from:to:)`.
- `WalkTracker/Application/SessionStore.swift` (1.1) — hoy `init(clock:strideM:)` y `start()` síncrono.
  Pasa a recibir `motion: any MotionPort`; conservar `elapsedS(notBefore:)` y el guard de doble toque.
- `WalkTracker/App/CompositionRoot.swift:47` — pasar `motion` al `SessionStore`.
- `WalkTracker/UI/Home/HomeView.swift` — `start()` síncrono con alerta "No se pudo iniciar la
  caminata"; pasa a `Task { await … }` y presenta la pre-pantalla y la pantalla bloqueante.
- `WalkTracker/UI/Session/SessionView.swift` — tiempo en `@ScaledMetric` 88; los pasos van debajo.
- `WalkTracker/UI/RootView.swift` y `NativeLayerDiagnosticsView` — no se tocan (su borrado está
  diferido y no es de esta historia).
- `WalkTracker/App/Info.plist:33` — `NSMotionUsageDescription` ya existe.
- `WalkTracker/Resources/Localizable.xcstrings` — `sourceLanguage` `es`, cada clave con `comment`.
- `WalkTrackerTests/Application/SessionStoreTests.swift` — adaptar su `init` al `MotionStub`.
  `WalkTrackerTests/Support/ClockStub.swift` es el patrón del stub (`Mutex`, sin `@unchecked`).
- `WalkTrackerTests/Scenarios/SessionStartScenarios.swift` — patrón de cita: `@Suite("Escenarios 1.2 …")`
  y `@Test("session-v3-tests.js:NN · …")`. `Scripts/vectors/lib.js:118` saca la historia del `@Suite`.
- `WalkTrackerTests/Vectors/inventory.json` — sitios 1.2: `:88`, `:90`, `:100`, `:321`, `:323`, `:345`
  (`executions: 100`) se portan; `:350` pasa a `"story": "1.3"` y `:351` a `"story": "1.4"`.
  `check-inventory.js:141` exige una cita por sitio de cada historia con alguna cita.
- `index.html:249` `screen-motion-denied` (v3): título "Sensor de movimiento requerido", "Abrir
  Configuración" y "Volver al inicio". Es la referencia de la pantalla bloqueante.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Session/Session.swift` — `mutating func addMeasuredSteps(_ count: Int) throws(DomainError)`:
      solo en `active` (si no, `invalidTransition`); negativo → `invalidValue(field: "steps")`; 0 no muta.
- [x] `WalkTracker/Application/SessionStore.swift` — `init(clock:motion:strideM:)`; flujo de permiso
      observable (ver Design Notes); al abrir sesión, tarea que consume `motion.updates(from: startedAt)`
      y aplica `max(0, muestra − mayor acumulado visto)`; intenciones para confirmar la pre-pantalla,
      cerrarla y volver de la pantalla bloqueante. Actualizar `CompositionRoot.swift:47`.
- [x] `WalkTracker/UI/Permission/MotionPermissionView.swift` y `MotionBlockedView.swift` — pre-pantalla
      y pantalla bloqueante; `HomeView.swift` las presenta y lanza `start()` en un `Task`.
- [x] `WalkTracker/UI/Session/SessionView.swift` — pasos en vivo debajo del tiempo; VoiceOver lee
      "N pasos".
- [x] `WalkTrackerTests/Support/MotionStub.swift` + `SessionStoreTests.swift` — la matriz entera y las
      decisiones de Design Notes, sin hardware.
- [x] `WalkTrackerTests/Scenarios/StepCountingScenarios.swift` — los 6 sitios, citados; `inventory.json`
      con `:350` → 1.3 y `:351` → 1.4.
- [x] `WalkTracker/Resources/Localizable.xcstrings` — textos nuevos, con `comment`. `xcodegen generate`.

**Acceptance Criteria:**
- Given el iPhone 14 con el permiso concedido, when camino con la sesión abierta, then los pasos suben en
  pantalla sin tocar nada.
- Given una caminata de 10 min con la pantalla bloqueada y música, when la termino (cierro la app), then
  los pasos difieren ≤ 10 % de los de Apple Salud en ese intervalo.
- Given el permiso denegado en Ajustes, when pulso "Iniciar caminata", then veo la pantalla bloqueante y
  no empieza ninguna sesión.

## Implementation Notes

- `Session.addMeasuredSteps(_:)`: fuera de `active` lanza `invalidTransition(from: status, to: "addMeasuredSteps")`
  (la v3 también rechaza pausada y finalizada en `assertMutable`); negativo o desbordamiento de `Int` →
  `invalidValue(field: "steps")`. La rama `invalidTransition` no tiene test: hasta la 1.4 no hay forma de
  construir una sesión que no esté activa.
- `SessionStore` expone `startFlow` (`idle` · `explainingPermission` · `requestingPermission` ·
  `blocked(.permissionDenied | .deviceUnsupported)`), `startFailure` (`invalidSession(DomainError)` ·
  `permissionUnresolved`) e `isCountingSteps`. Intenciones: `start()` (async), `confirmMotionPermission()`,
  `declineMotionPermission()`, `leaveMotionBlocked()`, `motionStatusMayHaveChanged()` y
  `acknowledgeStartFailure()`. `start()` ya no lanza: la zancada inválida sale por `startFailure`, que la
  alerta de Inicio lee con un binding de solo lectura más la intención de reconocerlo.
- `hasSession` pasa a propiedad guardada, fijada solo al abrir la sesión: cada muestra muta `session`, y
  `RootView`/`HomeView` solo necesitan saber si hay una, así que no se redibujan por cada muestra.
- Si el primer `start()` ve la zancada inválida con el permiso concedido, no se abre stream alguno.
- `HomeView` pinta la pre-pantalla y la bloqueante **en el sitio**, a pantalla completa con la barra de
  pestañas y la de navegación ocultas, en vez de como `fullScreenCover`: la sesión ya es el cover de
  `RootView` (que no se toca) y al conceder el permiso tiene que presentarse sin competir con otra
  presentación que se esté cerrando; lo mismo la alerta de "sin decidir". La relectura al volver a
  primer plano va por `scenePhase == .active` solo tras pasar por `.background`: cerrar el diálogo del
  sistema es `inactive → active` y el permiso aún puede leerse `.notDetermined`.
- "Abrir Ajustes" abre `UIApplication.openSettingsURLString` (ajustes de la app). VoiceOver lee los pasos
  como un solo elemento con la clave plural `%lld pasos` (`one`: "%lld paso").
- `MotionStub` usa un stream sin descarte (el adapter usa `.bufferingNewest(1)`) para afirmar sobre cada
  muestra; su petición de permiso puede quedar en vilo para probar el segundo toque. El store expone
  `stepCounting` (la `Task` del consumo) para que los tests esperen el final del stream.
- Mutación comprobada: un store que descarta muestras hace fallar los cinco tests de conteo (sin colgarse).
- `verify-domain.sh` corre además `StepCountingScenarios`. Los sitios `:350` y `:351` pasan a la 1.3 y 1.4.
- Riesgo conocido, fuera de alcance: `NativeLayerDiagnosticsView` (solo `DEBUG`) llama a
  `motion.updates(from:)` del mismo adapter, que admite un único stream; usarla con una sesión abierta
  terminaría el conteo de la sesión (se registraría como fin por el sistema).
- El simulador no tiene coprocesador: allí "Iniciar caminata" lleva a la bloqueante de "no disponible".
- **Verificación en el iPhone 14 (2026-09-13, Paul): funciona.** Build de desarrollo instalado y lanzado
  con `devicectl`. Pasan los tres criterios de aceptación: pre-pantalla → diálogo → conceder → los pasos
  suben solos; 10 min con la pantalla bloqueada y música dentro del ±10 % de Salud; permiso denegado en
  Ajustes → pantalla bloqueante sin sesión. También a mano: conceder desde "Abrir Ajustes" y volver
  cierra la bloqueante a Inicio sin sesión (hallazgo 19; el test automático sigue diferido), "Ahora no",
  doble toque, barra de pestañas oculta en ambas pantallas (hallazgo 14), VoiceOver "N pasos" y los
  pasos nunca bajan.

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | EC · Al cerrarse el diálogo del sistema (`inactive → active`) se relee `status`, que aún puede ser `.notDetermined` tras denegar, y la bloqueante se cierra | medium | `MotionAdapter.requestPermission` ya contempla que el sistema no haya publicado la decisión; `motionStatusMayHaveChanged` mapea `.notDetermined → .idle`, y `HomeView` reacciona a cualquier `.active`, no solo al volver de background | patch |
| 2 | EC · Releer tras el diálogo y no solo tras volver de background | medium | Misma causa que la 1 | patch (con 1) |
| 3 | EC/BH · `requestPermission()` sin timeout puede dejar Inicio atascado | false | El adapter espera el handler de `queryPedometerData`, que CoreMotion siempre invoca (con datos o error); no hay camino mostrado en que no vuelva | rechazado |
| 4 | EC · Si `addMeasuredSteps` lanza, `highestCumulativeSteps` ya avanzó | false | Inalcanzable en la 1.2: sesión siempre `active`, incremento > 0 y un desbordamiento de `Int` exige 9·10¹⁸ pasos | rechazado |
| 5 | EC/BH · Ninguna vista lee `isCountingSteps`; el conteo se congela sin aviso | false | La matriz congelada fija "la sesión sigue; conserva los pasos · registrado": sin señal visual por intención | rechazado |
| 6 | BH · No se reabre el stream cuando el sistema lo termina | false | Fuera de la intención: la reconstrucción por consulta es la 1.5 | rechazado |
| 7 | EC/BH · Un segundo `countSteps` no cancela la tarea anterior | false | Solo `openSession()` lo llama y el guard `session == nil` impide una segunda sesión en la 1.2 (no hay cierre hasta la 1.4) | rechazado |
| 8 | EC/BH · `hasSession` almacenado puede divergir de `session` | low | Solo diverge cuando `session` vuelva a `nil`, que no existe hasta la 1.4; el arreglo añade un `didSet` | rechazado (a tener en cuenta en la 1.4) |
| 9 | BH · `.restricted` muestra "Abrir Ajustes" | false | La matriz congelada: "Denegado o restringido → pantalla bloqueante con acceso a Ajustes" | rechazado |
| 10 | BH · La alerta de inicio fallido no dice por qué ni que se reintenta | low | Real, pero el fallo transitorio es raro y el arreglo añade una rama de mensaje por causa | rechazado |
| 11 | BH · El timeout de reintentos del permiso deja los botones deshabilitados | false | Duplicado de la 3 | rechazado |
| 12 | BH · Cada muestra redibuja el cuerpo entero de `SessionView`, `TimelineView` incluido | low | Una muestra cada ~2,5 s; coste despreciable; el arreglo extrae una subvista | rechazado |
| 13 | BH · `start()` es `async` sin ningún `await` | low | Cosmético; quitarlo obliga a tocar todos los tests (`await` sin operación async avisa) | rechazado |
| 14 | BH · `.toolbar(…, for: .tabBar)` aplicado al `NavigationStack` y no a su contenido | maybe-false | Se resuelve mirando en el iPhone si la barra de pestañas desaparece en la pre-pantalla y la bloqueante; si falla, sería low (las pantallas funcionan igual) | rechazado |
| 15 | BH · El test 0 → 120 → 350 no afirma que la muestra 0 deje 0 | low | El 0 inicial ya se afirma antes de emitir y el incremento contra 0 es 0 por construcción | rechazado |
| 16 | BH/VG · `motionStatusMayHaveChanged` solo se prueba con `.denied` y `.granted` | low | Mover `.restricted` al caso de `.idle` deja los tests en verde (VG, verificado) | patch |
| 17 | BH · El `ProgressView` del botón "Continuar" no tiene etiqueta de accesibilidad | low | Solo se ve con el diálogo del sistema encima, que es lo que VoiceOver enfoca | rechazado |
| 18 | BH · Las muestras no se cotejan con `session.startedAt` | low | Solo la pantalla de diagnóstico `DEBUG` puede reemplazar el stream, y ya consta como riesgo | rechazado |
| 19 | VG · Nada verifica que `HomeView` llame a `motionStatusMayHaveChanged()` al volver a primer plano | medium | Sin target de UI tests; los checks manuales no cubren conceder en Ajustes y volver (VG, verificado) | defer |

## Design Notes

Decisiones de implementación (casos que la matriz no cubre):
- **Muestra menor:** el delta se mide contra el **mayor** acumulado visto, no contra el último.
  350 → 340 → 360 suma 10 (total 360); medir contra 340 sumaría 20 y contaría pasos de más.
- **`.unavailable`** (sin coprocesador, o el simulador): la misma pantalla bloqueante con un texto de
  "este dispositivo no puede contar pasos" y **sin** "Abrir Ajustes". Ninguna sesión (como la v3, que
  bloquea todo lo que no es `granted`).
- **`.notDetermined` tras pedir** (fallo transitorio): no bloquea. Se vuelve a Inicio con la alerta
  existente "No se pudo iniciar la caminata", y el siguiente toque lo reintenta.
- **Pantalla bloqueante:** "Abrir Ajustes" y "Volver al inicio" (v3). Al volver la app a primer plano
  se relee `motion.status`: si ya no es denegado ni restringido, se cierra a Inicio, sin arrancar sola.
- **Pre-pantalla:** "Continuar" dispara `requestPermission()`; "Ahora no" vuelve a Inicio sin sesión.
- Un segundo toque mientras el flujo de permiso está en curso no hace nada (como el doble toque de la 1.1).

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — esperado: verde, citas de 1.1 y 1.2 completas.
- `xcodegen generate && xcodebuild … iPhone 16e CODE_SIGNING_ALLOWED=NO test` — esperado:
  `TEST SUCCEEDED`, sin warnings.

**Manual checks (iPhone 14, el simulador no tiene coprocesador):**
- Primera vez: pre-pantalla → diálogo → conceder → pasos suben al caminar.
- 10 min con la pantalla bloqueada y música; comparar con Salud → Pasos en ese intervalo (±10 %).
- Denegar en Ajustes → Privacidad → Movimiento y forma física → pantalla bloqueante.
