---
title: '1.1 — Iniciar sesión de caminata con cronómetro wall-clock'
type: 'feature'
created: '2026-09-13'
status: 'in-review'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '08a006914810b4c4f7895a78f7519623a5534f07'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/specs/spec-walktracker-ios/domain-model.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la app no tiene ninguna funcionalidad: no se puede empezar una caminata ni medir su
tiempo. Todo el Epic 1 se apoya en un agregado `Session` y en un cronómetro que todavía no existen.

**Enfoque:** portar al dominio Swift la creación de la sesión y el cronómetro wall-clock como
funciones puras, con el reloj entrando por `ClockPort`; un `SessionStore` único escritor que las usa;
y la navegación de AD-14 —pestañas con Inicio y la sesión como modo a pantalla completa— con el
tiempo transcurrido refrescándose a 1 Hz.

## Boundaries & Constraints

**Always:**
- `elapsedS = (now − startedAt) − totalPausesS`, con `now` de `ClockPort`. Ningún timer es fuente de
  verdad: el tick de 1 Hz solo repinta.
- Sesión nueva: `active`, `startedAt` = ahora, `stepsMeasured` = 0, `stepsEstimated` = 0,
  `source` = `"ios"`, sin `endedAt`, pausas 0.
- `strideM` ≤ 0 o no finito se rechaza **antes** de crear el agregado, con
  `DomainError.invalidValue(field: "strideM")`.
- `Domain/` solo Foundation; value types `Sendable`; `SessionStore` es `@MainActor @Observable`, único
  que muta la sesión, y las vistas solo llaman a intenciones (AD-3, AD-7, AD-12).
- Zancada por defecto `0.655` en `Resources/formulas.json`, validado al arrancar como el catálogo
  (falla ruidosamente).
- `Scripts/verify-domain.sh` en verde: se registra la implementación Swift de `elapsedS` y se portan
  a mano los escenarios de la 1.1 del inventario (AD-6).
- `TabView` de cuatro pestañas (Inicio · Historial · Logros · Ajustes); la sesión como
  `fullScreenCover`, del que no se navega fuera (AD-14). Textos en `Localizable.xcstrings`.

**Never:**
- Pasos, distancia, ritmo o cadencia en pantalla (1.2, 1.3); pausar, reanudar o finalizar (1.4);
  persistir la sesión o recuperarla tras un cierre forzoso (1.6, 5.1).
- Contenido inventado en Historial, Logros o Ajustes: sin datos de dominio, no se pinta nada (AD-22).
- Tamaños de fuente fijos, colores en hexadecimal o emoji en el chrome.
- Ninguna salida de la sesión antes de la 1.4, ni siquiera en `DEBUG`.

**Decisiones de Paul (2026-09-13):**
- **Sin salida de la sesión hasta la 1.4:** la sesión queda abierta; como no se persiste, cerrar la app
  desde el selector la descarta y se vuelve a Inicio. Cumple AD-14 y AD-20 sin adelantar la 1.4.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Iniciar | sin sesión, Inicio, "Iniciar caminata" | sesión `active` con los valores iniciales; se presenta la sesión | — |
| Zancada inválida | `strideM` 0, −1, NaN o infinito | no se crea la sesión | `invalidValue(field: "strideM")` |
| Background | 10 min activa, 5 min en otra app, volver | `elapsedS` ≈ 900 s | — |
| Reloj hacia atrás | `now` < `startedAt` | `elapsedS` = 0, nunca negativo | — |
| Doble toque | "Iniciar caminata" con una sesión ya activa | no se crea otra | ignorado |

</frozen-after-approval>

## Code Map

- `domain.js:69` `elapsedS(startedAtMs, totalPausesMs, nowMs, pausedAtMs)` y `:271`
  `createV3Session(nowMs, strideM)` — referencia. Swift trabaja en **segundos**; el vector
  `WalkTrackerTests/Vectors/elapsedS.json` está en ms y lo traduce la implementación registrada.
- `WalkTrackerTests/Vectors/VectorHarness.swift` — `VectorHarness.swiftDomain`: registro vacío donde se
  añade `elapsedS`. `inventory.json`: 14 sitios con `"story": "1.1"`, todos de
  `test/session-v3-tests.js:52-74`. Tres (`distanceM === 0`, `paceSecPerKm === null`,
  `cadenceSpm === 0`, `:68`, `:71`, `:72`) son métricas: se reasignan a `"1.3"` en el inventario.
- `Domain/DomainError.swift` (`invalidValue`, `invalidTransition`), `Domain/Ports/ClockPort.swift`.
- `WalkTracker/App/CompositionRoot.swift` — carga y valida `achievements.json` al arrancar: patrón a
  seguir para `formulas.json`. `WalkTrackerApp.swift` y `UI/RootView.swift` (con el enlace `DEBUG` a
  la pantalla de diagnóstico, que se conserva en Inicio).
- `WalkTracker/Application/` — vacío salvo `.gitkeep`. `WalkTrackerTests/Scenarios/` — ídem.
- `mock-01-home.html`, `mock-02-session-active.html` — dirección visual: número grande del tiempo, CTA
  principal. No sus métricas ni sus extras.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Session/` — `SessionStatus`, `Session` y `Session.start(at:strideM:) throws(DomainError)`.
- [x] `Domain/Session/Chronometer.swift` — `elapsedS(startedAt:totalPausesS:now:)`, nunca negativo.
- [x] `WalkTracker/Resources/formulas.json` + carga y validación en `CompositionRoot`.
- [x] `WalkTracker/Application/SessionStore.swift` — `@MainActor @Observable`; intención `start()`;
      `elapsedS` leído del reloj; ignora un segundo `start()`.
- [x] `WalkTracker/UI/` — `TabView` de AD-14; Inicio con "Iniciar caminata"; `SessionView` en
      `fullScreenCover` con el tiempo (`TimelineView` o tick a 1 Hz), sin controles de salida;
      `ContentUnavailableView` en las otras tres pestañas; `Localizable.xcstrings`.
- [x] `WalkTrackerTests/Scenarios/SessionStartScenarios.swift` — los 11 escenarios de la 1.1, citando
      su línea JS; `inventory.json` con los 3 reasignados a la 1.3.
- [x] `VectorHarness.swift` — registrar `elapsedS`; tests de la matriz para `SessionStore` con un
      `ClockStub`.

**Acceptance Criteria:**
- Given la app en el iPhone, when toco "Iniciar caminata", then aparece la sesión y el tiempo avanza
  cada segundo desde 0:00.
- Given `verify-domain.sh`, then sale en verde con `elapsedS` pasando en Swift y las demás funciones
  pendientes.
- Given el inventario, then `check-inventory` sigue en verde tras reasignar los tres sitios.

## Implementation Notes

- `SessionStatus` no tiene `idle`: antes de iniciar no hay agregado y el store lo expresa con
  `session == nil`. `source` es el enum `SessionSource` (`ios` · `v3` · `migrated`).
- `Chronometer.elapsedS` recorta a 0 (reloj hacia atrás), a diferencia de `domain.js`; no se añade
  vector de ese caso porque el runner JS lo fallaría fuera de las dos divergencias admitidas. Queda
  cubierto en `ChronometerTests` y `SessionStoreTests`.
- La implementación registrada de `elapsedS` rechaza un vector con `pausedAtMs` no nulo (pausa
  abierta, 1.4) en vez de ignorarlo.
- `SessionStore` se construye en `CompositionRoot` con `formulas.defaultStrideM`. `start()` lanza
  `DomainError`; Inicio lo traduce a una alerta. El segundo `start()` se ignora mientras haya
  sesión (1.4 decidirá qué pasa con una finalizada).
- `verify-domain.sh` corre además `FormulasTests`, `ChronometerTests` y `SessionStartScenarios`.
- `check-inventory.js` cruza los `@Test` de `Scenarios/` que citan `*-tests.js:NN` con el inventario:
  la historia sale del `@Suite("Escenarios 1.x …")`; por cada historia citada, todo escenario suyo
  debe estar citado y toda cita debe ser escenario suyo. Casos rojos en `red-path-tests.sh`.
- `SessionView` mide en `max(context.date, clock.now)` vía `SessionStore.elapsedS(notBefore:)`.
- `project.yml`: `developmentLanguage: es`, alineado con `CFBundleDevelopmentRegion` y el catálogo.

## Spec Change Log

## Review Triage Log

| # | Capa | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|---|
| V1 | verif | Nada comprueba que los escenarios de la 1.1 del inventario estén portados | gap | Filed: `check-inventory.js` solo valida la regex de `story`; borrar un test de `SessionStartScenarios` o reasignar otro sitio a la 1.3 deja el gate en verde | patch |
| V3 | verif | `ElapsedTimeFormat.spoken` (valor de VoiceOver) sin test | gap | Filed: redondear o quitar horas no rompe nada y VoiceOver diría otro tiempo que la pantalla | patch |
| B6 · E4 | blind · edge | El `TimelineView` puede pintar un segundo repetido y saltarse el siguiente | medium | La vista relee `clock.now` e ignora `context.date`; SwiftUI puede evaluar entradas del timeline algo antes de su instante y el truncado da `k−1`. `max(context.date, clock.now)` es corrección directa | patch |
| B9 | blind | El valor de accesibilidad cambia cada segundo sin `.updatesFrequently` | low | VoiceOver puede reanunciar o no refrescar; convención de accesibilidad del spine. Una línea | patch |
| B10 | blind | Escenarios duplicados (`:52` y `:67`) y `:55` mezclado con ±∞ | low | `initialStride` repite `keepsStride` con `0.655` a mano; la cita `:55` deja de ser trazable al sitio. Corrección directa, y V1 depende de citas precisas | patch |
| B3 (parte) | blind | `ElapsedTimeFormatTests` vive dentro de `SessionStoreTests.swift` | low | Formateador de UI en el fichero del store. Mover el fichero es directo | patch |
| V2 · B11 | verif · blind | Sin test automático de la presentación de la sesión ni del avance del tiempo en pantalla | gap | Filed con disposición defer: no hay target de UI tests; la historia verifica en dispositivo | defer |
| B1 · E6 · E7 | blind · edge | Tiempos o pausas no finitos dan 0 en Swift y `TypeError` en JS; el puerto de vectores los deja pasar | low | Inalcanzable en producción (`Date` de `ClockPort` y del agregado siempre finitos); un vector futuro que lo pruebe fallaría con motivo visible | rechazado |
| B2 · E8 | blind · edge | El puerto de vectores rechaza cualquier `pausedAtMs`, más estricto que `domain.js` | low | Ningún vector actual lo trae y la 1.4 sustituye esa rama; hoy solo produciría un fallo explícito | rechazado |
| B3 (resto) | blind | Los tests de `SessionStore` y del formato no están en `verify-domain.sh` | low | El gate es de dominio (AD-6); la suite completa los ejecuta | rechazado |
| B4 · E5 | blind · edge | `Formulas` inyectado en `CompositionRoot` no se valida | low | Solo los tests inyectan; producción carga del bundle y valida | rechazado |
| B5 | blind | `defaultStrideM` sin rango plausible | low | `domain-model.md` fija "> 0 y finito"; un rango es decisión de la 1.3/2.3 con la calibración | rechazado |
| B7 | blind | La alerta de inicio fallido no dice el motivo ni se registra | low | Improbable: la zancada se valida al arrancar; añadir log y mensaje es trabajo de UX de errores | rechazado |
| B8 · E1 · E2 | blind · edge | `ElapsedTimeFormat` atrapa con segundos mayores que `Int.max`; `%d` ignora el locale | false | `Int.max` segundos son ~2,9·10¹¹ años: inalcanzable con fechas reales; español usa dígitos latinos | rechazado |
| B12 | blind | El `set` vacío del binding del cover podría desincronizarse si el sistema lo cerrara | low | `fullScreenCover` no se cierra por gesto ni por el sistema en uso normal | rechazado |
| E3 | edge | `totalPausesS` negativo haría el tiempo mayor que el reloj | low | Inalcanzable hoy: el agregado mantiene pausas en 0; la 1.4 introduce las pausas con su validación | rechazado |

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — esperado: verde, `elapsedS` sin pendientes.
- `xcodegen generate && xcodebuild … iPhone 16e CODE_SIGNING_ALLOWED=NO test` — esperado:
  `TEST SUCCEEDED`, sin warnings de concurrencia.

**Manual checks:**
- En el iPhone (build local o TestFlight): iniciar, ver el tiempo avanzar, ir a otra app 1 min y
  volver: el tiempo incluye ese minuto.
