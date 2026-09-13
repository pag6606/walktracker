---
title: '8.7 — Sustrato de verificación del dominio'
type: 'feature'
created: '2026-09-12'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '169cad6c1e8d731864553b1d39fd6ec9f226de1b'
context:
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md'
  - '{project-root}/_bmad-output/implementation-artifacts/epic-8-context.md'
  - '{project-root}/_bmad-output/specs/spec-walktracker-ios/achievements.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** no hay forma de demostrar que el dominio Swift que portarán los Epics 1 y 3 se comporta
como `domain.js`, validado en producción. La suite JS mezcla cálculos puros, secuencias sobre el
agregado y pruebas de la agregada v1 que desaparece; y `GoalEngine` y 8 de los 14 logros no tienen
cobertura que detecte un cambio de semántica como el del incidente de Dart.

**Enfoque:** repartir la suite JS en vectores, escenarios y excluidos, con un inventario comprobable;
extraer los vectores a datos neutrales y escribir los nuevos de logros y meta; crear
`Scripts/verify-domain.sh`, que ejecute `domain.js` contra ellos hoy y el dominio Swift a medida que
cada historia lo porte; y publicar `Resources/achievements.json` validado al arrancar (AD-5).

## Boundaries & Constraints

**Always:**
- Cada sitio de aserción de `test/{domain,session-v3,motivation,gapestimator}-tests.js` aparece
  **exactamente una vez** en el inventario, con categoría y, si es excluido, motivo (AD-6).
- Los vectores son datos neutrales que consumen ambos runtimes; ningún runtime tiene su propia copia.
- Solo dos familias de divergencia declaradas: **hora local** (horas de logro, rachas, semana de la
  meta) y **categoría por código WMO** (lluvia, incluidos chubascos 80–82). El vector lleva el valor
  correcto para Swift; `domain.js` queda registrado como fallándolo a propósito.
- Un vector divergente que `domain.js` pase **rompe** el script: la divergencia ya no existe y hay
  que retirarla de la tabla.
- `achievements.json` sigue el esquema de AD-5 y la app **falla ruidosamente** al arrancar si no
  valida: 14 entradas, claves únicas, todas las de `achievements.md`, `metric` del enum cerrado.
- Sin dependencias nuevas: node sin paquetes para el lado JS, Swift Testing para el lado Swift.

**Never:**
- Portar escenarios ni motores de dominio a Swift (diferido al Epic 1 en `deferred-work.md`), ni
  escribir `AchievementEngine` o `GoalEngine` en Swift.
- Tocar `domain.js`, `climate.js` o `test/`. En `motivation.js`, solo el arreglo de `isComplete`
  decidido abajo.
- Poner el runner JS bajo `test/`: vitest recoge `test/**/*.js`.

**Decisiones de Paul (2026-09-12):**
- **La 8.7 se divide.** Entra el arnés de AD-6 con el catálogo de AD-5; los ~111 escenarios se portan
  en el Epic 1, cuando exista el agregado.
- **Se amplía el esquema de AD-5** (y se enmienda el spine): `comparison` es `gte · lte · eq · gt ·
  lt · between`; `threshold` es número, `[min, max]` para `between`, o cadena para
  `weatherCategory` (`"rain"`). Así caben los 14 logros sin convenciones fuera de los datos.
- **`early_bird` y `night_walker` conservan la conducta de `domain.js`:** hora local entera de 5 a 7
  inclusive (05:00–07:59) y de 21 a 23 inclusive (21:00–23:59). No es una divergencia nueva.
- **Se corrige `getWeeklyProgress` en `motivation.js`:** `isComplete` compara los km sin redondear
  (9,995 km no cumplen una meta de 10). Sigue habiendo solo dos familias de divergencia.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Vector no divergente | JS devuelve el valor esperado | pasa | — |
| Vector no divergente roto | JS devuelve otro valor | `verify-domain.sh` sale ≠ 0 nombrando fichero y caso | — |
| Divergencia declarada | vector de hora local en UTC-5 | JS lo falla y se informa como divergencia esperada; sale 0 | — |
| Divergencia obsoleta | un vector marcado divergente pasa en JS | sale ≠ 0: "la divergencia ya no existe" | — |
| Función aún sin portar a Swift | vector sin implementación Swift registrada | se lista como pendiente; no rompe | — |
| Función portada que falla | implementación Swift registrada devuelve otro valor | sale ≠ 0 | — |
| Inventario incompleto | un sitio de aserción falta o está dos veces | sale ≠ 0 nombrando `fichero:línea` | — |
| Catálogo inválido | 13 entradas, clave repetida o `metric` desconocida | la app no arranca; mensaje con la causa | nunca degrada |

</frozen-after-approval>

## Code Map

- **Inventario reconciliado (hoy, tras `489ad2e`): 186 sitios / 285 ejecutadas** = 56 vectores,
  64 escenarios (163 ejecutadas; `session-v3-tests.js:345` corre 100 veces), 66 excluidos: 52 v1 de
  vueltas, 9 introspección de runtime JS, 1 argumento no tipable (`session-v3:56`), 3 `Math.random`
  (`motivation:20,27,32`), 1 `quotes.json` (`motivation:45`). Los ~65/~111/~52 de AD-6 contaban dos
  veces los 52. `recalibrate` (`domain:121-143`) es todo v1: CAP-13 queda sin vectores portables.
- **Funciones de vector:** `elapsedS` domain.js:69 · `pace` :105 (devuelve `Infinity`; el vector
  lleva `null`, AD-4) · `v3distance` :299 · `estimateSteps` :508 · `calculateCadence` :525 ·
  `selectQuote`/`updateRecentIds` motivation.js:28,48 · `evaluateAchievements` :86 · `checkStreak`
  :154 · `checkTimeOfDay` :178 (`getUTCHours`) · `getWeeklyProgress` :195 (lunes 00:00 UTC).
- **Carga:** los tres módulos son CommonJS (`require('../domain.js')`, `module.exports`); node 24.
- **Lluvia en JS:** `evaluateAchievements` aplica la regex al texto de `climate.js` (`wmoToSpanish`);
  el runner JS deriva ese texto del código WMO del vector con la propia función de la referencia.
- **Catálogo JS:** `motivation.js:58-73` (`desc`, no `description`). No existe ningún fichero de
  catálogo. `quotes.json` en la raíz: 100 `{id, text}`.
- **Tests fuera de AD-6:** `stepdetector` (retirado), `index`, `index-simple`, `runtime`,
  `migration`, `storage`, `climate`.
- `project.yml` — `WalkTrackerTests` ya compila `WalkTrackerTests/`; XcodeGen empaqueta sus `.json`
  como recursos. `WalkTracker/Resources/` solo tiene `Assets.xcassets`.
- `Domain/Ports/ClockPort.swift` — `now` y `calendar` para la zona horaria de los vectores.

## Tasks & Acceptance

**Execution:**
- [x] `WalkTrackerTests/Vectors/inventory.json` — cada sitio de aserción (`fichero:línea`) con
      categoría, motivo de exclusión y, para escenarios, la historia del Epic 1 que lo portará.
- [x] `WalkTrackerTests/Vectors/*.json` — vectores extraídos por función, más los nuevos: los 14
      logros (desbloquea / no desbloquea) y `GoalEngine` (semana ISO, límites de lunes y domingo).
      Cada vector de hora lleva `timeZone`; los límites se escriben en UTC (ambos coinciden) y en
      `America/Guayaquil` (divergencia declarada). Divergentes marcados con `divergence`.
- [x] `Scripts/vectors/run-js.js` — runner node: carga la referencia, ejecuta cada vector, normaliza
      `Infinity` a `null`, aplica las reglas de divergencia de la matriz.
- [x] `WalkTrackerTests/Vectors/DomainVectorTests.swift` — decodifica todos los vectores, ejecuta los
      de funciones Swift registradas (hoy ninguna) y lista las pendientes.
- [x] `Scripts/verify-domain.sh` — inventario completo, runner JS, `xcodebuild test
      -only-testing:WalkTrackerTests/…`; sale ≠ 0 ante cualquier fila de fallo de la matriz.
- [x] `WalkTracker/Resources/achievements.json` — los 14 logros con el esquema ampliado de AD-5.
- [x] `ARCHITECTURE-SPINE.md` §AD-5 — enmienda del esquema: las tres comparaciones nuevas y los tipos
      de `threshold`, con fecha y decisión de Paul.
- [x] `motivation.js` — `isComplete: weekKm >= weeklyGoalKm`; un vector de 9,995 km lo cubre.
- [x] `Domain/Achievements/` — `AchievementCatalog` `Codable` con `validate()` y errores tipados;
      `AchievementMetric` como enum cerrado de AD-5.
- [x] `WalkTracker/App/CompositionRoot.swift` — carga y valida el catálogo al arrancar; si no valida,
      termina la app con la causa.
- [x] `WalkTrackerTests/Domain/AchievementCatalogTests.swift` — el catálogo real valida; los tres
      casos inválidos de la matriz lanzan su error.
- [x] `README.md` — cómo ejecutar `verify-domain.sh` y que su verde es DoD de toda historia de dominio.

**Acceptance Criteria:**
- Given el inventario, when `verify-domain.sh` lo contrasta con los cuatro ficheros de test, then los
  186 sitios están cada uno exactamente una vez.
- Given los vectores, when corre `verify-domain.sh`, then sale 0 y los únicos fallos JS informados
  son de las dos familias declaradas.
- Given los 14 logros, then cada uno tiene al menos un vector que desbloquea y otro que no.
- Given la app, when arranca con el catálogo real, then valida; con uno inválido, no arranca.

## Implementation Notes

- **Inventario y vectores.** 186 sitios / 285 ejecutadas = 56 vectores, 64 escenarios (Epic 1:
  1.1:14 · 1.2:8 · 1.3:11 · 1.4:18 · 1.5:3 · 1.6:10), 66 excluidos con motivo. 109 vectores en 12
  ficheros; en `domain.js` pasan 91 y 18 son divergencias declaradas (localTime 15, wmoCategory 3).
  Cada entrada del inventario guarda el texto de la aserción: una línea movida o editada rompe.
- **Divergencias precisas.** Un divergente de logros solo puede diferir en logros de su familia; uno
  de otra función lleva `expectedJs` con el valor exacto de `domain.js`. Swift ignora el campo.
- **Arreglo de la referencia (decisión de Paul).** `getWeeklyProgress` suma la semana en **metros** y
  `isComplete` compara `weekM >= goalKm × 1000`. La primera versión comparaba km sumados en coma
  flotante y la revisión lo cazó: 2 394 de 20 000 repartos exactos de 10 000 m no cumplían. Registrado
  en `DEROGACIONES.md §6`.
- **Catálogo.** Esquema ampliado de AD-5 (spine enmendado). La app termina al arrancar si no valida;
  un test fija `metric`/`threshold`/`comparison` de los 14 logros para que un catálogo reteclado no
  pase. Consecuencia conocida: con un catálogo inválido la app —que aloja los tests— no arranca y
  cae toda la suite Swift, no solo el test del catálogo.
- **Lado Swift.** Registro `VectorHarness.swiftDomain` vacío: las 12 funciones quedan pendientes. Un
  test registra una implementación errónea contra los ficheros reales y exige que falle.
- **Verificación final:** `verify-domain.sh` verde (camino rojo 17/17); suite completa en iPhone 16e →
  51 tests en 11 suites, cero warnings propios; `check-project-shape.sh` correcto.
- **Sin cubrir en la spec de AD-6:** el spine sigue diciendo 281 aserciones y ~65/~111/~52, y lista
  `recalibrate` como vector (es todo v1: CAP-13 sin vectores portables). Solo se enmendó §AD-5.

## Spec Change Log

## Review Triage Log

| # | Capa | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|---|
| E1 · C2 | edge | `isComplete` sobre km sumados en coma flotante: 10 000 m exactos en varias sesiones no cumplen | high | Verificado: 2 394 de 20 000 repartos aleatorios de exactamente 10 000 m dan `isComplete: false` (p. ej. 8806+603+456+1+68+66). Regresión del arreglo de esta historia | patch |
| B2 · C4 | blind · edge | El vector `nueve-995-km-no-cumplen-10` fija `completedKm: 10`, que solo sale por acumulación en coma flotante | medium | `5 + 4.995 = 9.995000000000001` → `"10.00"`; `(9.995).toFixed(2)` es `"9.99"`. Un port Swift que sume metros falla el vector | patch |
| B4 · E3 · C1 | blind · edge | Un vector divergente fuera de `evaluateAchievements` acepta cualquier diferencia | medium | `run-js.js` solo comprueba la diferencia ajena en logros; un `weeklyProgress` con `goalKm` erróneo marcado `localTime` sale 0 (reproducido por el revisor) | patch |
| E19 | edge | La semántica del catálogo (`metric`/`threshold`/`comparison`) no está fijada por ningún gate | medium | Solo se comparan nombre, icono y descripción; `first_10km` con umbral 1000 pasa todo. Es el incidente de AD-5 | patch |
| V1 | verif | El bucle de `DomainVectorTests` nunca ve un `.failed`: nada prueba que una función portada que falla rompa | gap | Filed: los tests del arnés llaman a `verdict`, no al bucle | patch |
| V2 · B8 | verif · blind | Faltan casos del catálogo: `schemaVersion`, `unknownComparison`, `"snow"`, `[7, 5]`, categoría en métrica no climática | gap | Filed | patch |
| V4 · B11 | verif · blind | El camino rojo no cubre: `code` cambiado, excluido sin motivo, `executions` erróneo, logro sin cobertura, deriva de `achievements.json` | gap | Filed; la deriva del catálogo necesita un `--root` temporal | patch |
| V3 | verif | Ningún test prueba que el arranque termina con un catálogo inválido | gap | Filed con disposición defer: requiere costura inyectable para `fatalError` | defer |
| B6 · Vo1 | blind · verif | `AchievementCatalogError.unexpectedKeys` es inalcanzable | low | Tras 14 entradas, sin duplicados y sin claves que falten, no puede sobrar ninguna. Borrar el caso es corrección directa | patch |
| E7 | edge | Un JSON de vectores o inventario mal formado revienta sin nombrar el fichero | low | `readJSON` no envuelve el error; editar vectores a mano lo hará frecuente. Envolver es una línea | patch |
| E15 | edge | `VectorBundle.files()` decodifica cualquier `.json` del bundle de tests | low | Un fixture futuro de `Scenarios/` rompería todos los tests de vectores. Filtrar por `knownFunctions` es directo | patch |
| B3 | blind | El arreglo de `isComplete` en `motivation.js` no queda registrado junto a los de la referencia | low | `DEROGACIONES.md §6` lista los arreglos del 2026-09-12; este falta. Corrección de texto | patch |
| B12 | blind | `deferred-work.md` dice "~111 escenarios" y `source_spec: none` | low | El inventario cuenta 64 sitios / 163 ejecutadas, repartidos 1.1:14 · 1.2:8 · 1.3:11 · 1.4:18 · 1.5:3 · 1.6:10. Corrección de texto | patch |
| B13 | blind | `verify-domain.sh` deja un temporal vacío | low | `mktemp -t …` crea un fichero y el log va a otro con `.log`. Corrección directa | patch |
| B15 | blind | README con totales fijos y la instrucción de ejecutar el camino rojo a mano, que ya corre en el script | low | Corrección de texto | patch |
| B1 | blind | `weekly_goal` no se prueba como desbloqueo por el camino de `GoalEngine` | false | `achievements.md` define `weekly_goal` como "evaluado por GoalEngine al cumplirse la meta": `isComplete` es la regla; la no-redisparada es de AD-17 y sin API en JS | rechazado |
| B5 | blind | Vectores de hora local solo en `America/Guayaquil`, sin horario de verano ni zona al este | low | Mejora de cobertura para los ports; ningún consumidor actual. Se añaden al portar Goal/Achievement | rechazado |
| B7 · E17 · E18 | blind · edge | La validación del catálogo no comprueba semántica por métrica (horas 0–23, `weeklyGoalMet eq 1`) | low | Con E19 los valores del catálogo real quedan fijados; validar catálogos sintéticos añade ramas | rechazado |
| B9 | blind | Swift y JS validan el formato de vectores de forma distinta | false | Un vector que JS acepta y Swift no decodifica deja `verify-domain.sh` en rojo en el paso 3 | rechazado |
| B10 · E10 | blind · edge | Campos del inventario sin comprobar (`excludedByReason`, texto de motivos, `baseline`, regex de historia) | low | Documentales; no cambian el reparto que sí se comprueba | rechazado |
| B14 | blind | `divergentMustPassInSwift` equivale a `registeredWrongFails` | low | El arnés ignora `divergence` por diseño; el test es redundante, no dañino | rechazado |
| B16 · E4 · E5 · E6 | blind · edge | Robustez de `run-js.js`: `TIME_FUNCTIONS` duplicado, `covers` con `throws` o `expected: null` revienta, versión de node | low | Un TypeError sigue saliendo ≠ 0; las guardas añaden ramas para errores de autoría raros | rechazado |
| E2 | edge | `completedKm` 10 y 100 % con `isComplete: false` | low | Presentación de la referencia congelada; la de Swift la define `UI/Format` | rechazado |
| E8 | edge | `--root`/`--vectors` sin valor da TypeError críptico | low | Uso interno del camino rojo | rechazado |
| E9 | edge | `scanSites` no ignora comentarios de bloque ni cadenas | low | Los cuatro ficheros están congelados y el recuento de ejecuciones contrasta el total | rechazado |
| E11 | edge | `execFileSync` sin timeout | low | Las cuatro suites terminan en milisegundos | rechazado |
| E12 | edge | `mktemp -d -t` falla con GNU mktemp | false | Proyecto solo macOS (Xcode); BSD `mktemp` acepta `-t` | rechazado |
| E13 | edge | Solo se exige el resumen de `DomainVectorTests` en el log | low | Las otras dos suites existen; el riesgo es un renombrado futuro | rechazado |
| E14 | edge | Un fichero de vectores ausente del bundle no se detecta en Swift | low | `verify-domain.sh` regenera el proyecto; el lado JS detecta el borrado por inventario y cobertura | rechazado |
| E16 · C3 | edge | Un catálogo inyectado en `CompositionRoot` no se valida | low | Solo los tests inyectan; producción pasa `nil` | rechazado |
| Vo2 | verif | Los `isFinite` de `hasCoherentThreshold` son inalcanzables desde `decode` | false | `validate()` es pública y se aplica a catálogos construidos en código | rechazado |

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — esperado: sale 0; resumen con vectores JS pasados, divergencias
  esperadas, y funciones Swift pendientes.
- `xcodegen generate && xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 16e'
  CODE_SIGNING_ALLOWED=NO test` — esperado: `TEST SUCCEEDED`.
- Sondas rojas: alterar un valor esperado, marcar divergente un vector que pasa, borrar una línea del
  inventario, quitar un logro del catálogo — cada una debe romper su comprobación.
