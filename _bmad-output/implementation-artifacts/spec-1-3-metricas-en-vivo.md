---
title: '1.3 — Métricas en vivo: distancia, tiempo, ritmo y cadencia'
type: 'feature'
created: '2026-09-13'
baseline_commit: '0de87e3f6538003708195874c194a24a8e2e3545'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-1-2-conteo-pasos-coprocesador.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problema:** la sesión muestra tiempo y pasos, pero no distancia, ritmo ni cadencia. Son las métricas
de CAP-4, y el dominio aún no las calcula [fuente: capabilities.md#CAP-4].

**Enfoque:** portar a `Domain/Metrics` el cálculo de distancia, ritmo y cadencia, con sus vectores y
escenarios. El agregado toma la distancia del sistema cuando llega en la muestra. `SessionStore`
recalcula las métricas con cada muestra del coprocesador y la sesión las muestra con la distancia en
el centro.

## Boundaries & Constraints

**Always:**
- **Distancia:** si el sistema la da, se usa esa; si no, `(stepsMeasured + stepsEstimated) × strideM`.
  La UI no distingue la fuente [fuente: capabilities.md#CAP-4]. La distancia del sistema es acumulada:
  una muestra menor no resta (como los pasos en la 1.2).
- **Ritmo:** `paceSecPerKm` es `Int?` y solo existe con `distanceM ≥ 100` [fuente: capabilities.md#CAP-4].
  Si no, es `nil` y la UI muestra "—" [fuente: ARCHITECTURE-SPINE.md#AD-22].
- **Cadencia:** solo sobre `stepsMeasured`, nunca sobre estimados [fuente: domain-model.md#48].
- **AD-22:** la vista solo pinta lo que produce `Domain/`. La conversión a km, `m:ss` y spm vive en
  `UI/Format/`.
- **AD-21:** las métricas derivadas se recalculan con cada muestra del coprocesador, no con el tick de
  1 Hz; el tiempo sigue a 1 Hz [fuente: ARCHITECTURE-SPINE.md#AD-21].
- **Estilos:** tamaños con estilos de texto del sistema o `@ScaledMetric`, con Dynamic Type sin
  recortes. VoiceOver lee cada magnitud completa ("3,24 kilómetros").
- **Verificación:** `v3distance`, `pace` y `calculateCadence` registradas en el arnés de vectores, y
  `verify-domain.sh` en verde con el gate de citas.

**Never:**
- Pausar o finalizar (1.4), pasos estimados (1.5), persistencia (1.6).
- Calorías u otras magnitudes sin fuente.
- Leer `currentCadence` o `currentPace` de CoreMotion: la cadencia y el ritmo son del dominio.

**Decisiones de Paul (2026-09-13):**
- **Pantalla de sesión** (spec 1.2): la distancia pasa al centro, y tiempo y pasos bajan a la rejilla.
- **Rejilla 2×2 siempre:** pasos · tiempo arriba, ritmo · cadencia abajo, con cualquier tamaño de texto.
  Se aparta del mockup nativo (3 celdas sin cadencia) y de las 4 columnas de `DESIGN.md:212-215`.
- **La spec se mantiene completa** pese a superar el tamaño recomendado.

## I/O & Edge-Case Matrix

| Escenario | Entrada / Estado | Comportamiento esperado | Error |
|---|---|---|---|
| Sesión recién abierta | 0 pasos | 0 m · ritmo `nil` ("—") · cadencia 0 | — |
| Sin distancia del sistema | 4980 pasos, zancada 0,655 | 3261,90 m | — |
| Con distancia del sistema | muestra de 4980 pasos y 3400 m | 3400 m | — |
| Distancia del sistema menor | 3400 → 3390 | sigue en 3400 | — |
| Por debajo de 100 m | 10 pasos a los 60 s | ritmo `nil` → "—" | — |
| Métricas a los 62 min | 4980 pasos sin distancia del sistema, 3720 s | ritmo 1140 s/km · cadencia 80,3 spm | — |
| Distancia del sistema inválida | negativa, NaN o infinita | no muta | `invalidValue(field: "distanceM")`, registrado |

</frozen-after-approval>

## Code Map

- `domain.js:299` `v3distance` (2 decimales), `:105` `pace` (`Math.round(movingS / km)`; Infinity → `nil`
  según el vector) y `:525` `calculateCadence` (1 decimal; 0 si algún argumento es ≤ 0). El umbral de
  100 m lo aplica quien llama (`:355`). La cadencia usa el tiempo neto transcurrido; al finalizar,
  `durS` ya es neto (`:353`).
- `WalkTrackerTests/Vectors/{v3distance,pace,calculateCadence}.json`: 8, 3 y 7 vectores. Los `throws`
  llevan `field` (`stepsMeasured`, `stepsEstimated`, `strideM`, `activeSeconds`). `pace` recibe
  `durationS` y `pausesS`.
- `WalkTrackerTests/Vectors/VectorHarness.swift:186-188` `swiftDomain` y `:228-260` `SwiftDomainPorts`:
  patrón de `elapsedS`. `DomainVectorTests.swift:161,173` tiene tests propios del registro.
- `Domain/Session/Session.swift`: `addMeasuredSteps` (`:66`) y `elapsedS(at:)` (`:78`); el comentario de
  `:10-11` anuncia las métricas. `Domain/Engines/` está vacío; el spine ubica CAP-4 en `Domain/Metrics`.
- `Domain/Ports/PedometerSample.swift`: `distance: Double?` en metros, ya copiada por `MotionAdapter:157`.
  El adapter no se toca.
- `WalkTracker/Application/SessionStore.swift:193-203` `record(_:)` hoy ignora `sample.distance`.
  Conservar `hasSession` guardado y el cálculo del incremento contra el mayor acumulado.
- `WalkTracker/UI/Session/SessionView.swift`: tiempo en `TimelineView` con `@ScaledMetric` 88 y pasos
  debajo. `UI/Format/ElapsedTimeFormat.swift` (`clock`, `spoken`) es el patrón de formato.
- `WalkTrackerTests/Support/MotionStub.swift:92` `emit(steps:)` siempre emite `distance: nil`.
  `SessionStoreTests.swift:128-148` tiene `store(_:)`, `waitUntil` y `steps`.
- `WalkTrackerTests/Scenarios/StepCountingScenarios.swift`: patrón `@Suite("Escenarios 1.x …")` y
  `@Test("session-v3-tests.js:NN · …")`. `Scripts/verify-domain.sh:68-74` lista las suites con
  `-only-testing`.
- `WalkTrackerTests/Vectors/inventory.json`: 15 sitios de la 1.3 en `test/session-v3-tests.js`.
- `Localizable.xcstrings`: `sourceLanguage` `es`; cada clave con `comment`.

## Tasks & Acceptance

**Execution:**
- [x] `Domain/Metrics/MetricsCalculator.swift` — `distanceM(stepsMeasured:stepsEstimated:strideM:)`,
      `paceSecPerKm(movingS:distanceM:) -> Int?` y `cadenceSpm(stepsMeasured:activeSeconds:)`, con
      `throws(DomainError)` y los redondeos de la v3. Añadir `minPaceDistanceM = 100` y `SessionMetrics`
      (`distanceM`, `paceSecPerKm?`, `cadenceSpm`).
- [x] `Domain/Session/Session.swift` — `systemDistanceM: Double?`, `recordSystemDistance(_:)` (solo
      `active`, nunca baja; inválida → `invalidValue(field: "distanceM")`) y `metrics(at:) -> SessionMetrics`.
- [x] `WalkTracker/Application/SessionStore.swift` — `private(set) var metrics: SessionMetrics?`: se fija
      al abrir la sesión y se recalcula en `record(_:)` con `clock.now` tras aplicar pasos y distancia.
      Un error de la distancia se registra y no para el conteo.
- [x] `WalkTracker/UI/Format/` — formatos de distancia (km con 2 decimales en es), ritmo (`m:ss`) y
      cadencia (spm entero), cada uno con su forma hablada. Tests en `WalkTrackerTests`.
- [x] `WalkTracker/UI/Session/SessionView.swift` — distancia grande en el centro y rejilla 2×2 (pasos ·
      tiempo / ritmo · cadencia); tiempo a 1 Hz dentro de la rejilla.
- [x] `VectorHarness.swift` + `DomainVectorTests.swift` — registrar las tres funciones (con
      `pace` recibe `durationS − pausesS`) y un test propio por cada una.
- [x] `WalkTrackerTests/Scenarios/MetricsScenarios.swift` — portar `:68`, `:71`, `:72`, `:102`, `:119`,
      `:147`, `:169`, `:170`, `:285` y `:350` con `metrics(at:)`. En `inventory.json`, `:114` pasa a la
      1.5 y `:156`, `:181`, `:183` y `:186` a la 1.4. Añadir la suite a `verify-domain.sh`.
- [x] `MotionStub.swift` + `SessionStoreTests.swift` — `emit(steps:distance:)` y la matriz entera en
      el store.
- [x] `Localizable.xcstrings` — textos nuevos con `comment`. Después, `xcodegen generate`.

**Acceptance Criteria:**
- Given el iPhone 14 con una sesión abierta, when camino, then la distancia sube en el centro, y pasos,
  tiempo y cadencia suben en la rejilla.
- Given menos de 100 m recorridos, when miro el ritmo, then veo "—"; al pasar de 100 m aparece `m:ss`.
- Given VoiceOver activo, when recorro la sesión, then oigo cada métrica completa con su unidad.

## Implementation Notes

- `MetricsCalculator` (`Domain/Metrics/`): `paceSecPerKm` lanza `invalidValue` con `movingS` o
  `distanceM` si no son finitos (la v3 lanza `TypeError` con tiempos no finitos) y devuelve `nil` sin
  movimiento o si el ritmo no cabe en `Int`. Los redondeos son `(x × 10ⁿ).rounded(.toNearestOrAwayFromZero) / 10ⁿ`,
  equivalentes a `toFixed` dentro de la tolerancia de los vectores.
- `Session.metrics(at:)` no lanza: el agregado garantiza entradas válidas y un fallo del calculador es
  una violación de invariantes (`preconditionFailure`). Con distancia del sistema: `systemDistanceM +
  distanceM(0, stepsEstimated, strideM)`. Una distancia del sistema de 0 m cuenta como dada.
  `recordSystemDistance` fuera de `active` lanza `invalidTransition` (sin test hasta la 1.4, como en la 1.2).
- `SessionStore.record(_:)` ya no sale antes si la muestra no trae pasos nuevos: aplica pasos y distancia
  por separado (un error de uno no impide el otro) y recalcula `metrics` en `clock.now` con **cada**
  muestra. Sin muestra, las métricas no cambian aunque avance el reloj (test propio).
- Formatos en `UI/Format/MetricsFormat.swift` (`DistanceFormat`, `PaceFormat`, `CadenceFormat`). La
  distancia **trunca** al centésimo de km, como el cronómetro al segundo: "0,10" aparece a la vez que el
  ritmo. VoiceOver: "3,24 kilómetros" (`Measurement`), "18 minutos y 14 segundos por kilómetro", "80 pasos
  por minuto" (plural `one`) y, sin ritmo, "Sin ritmo hasta los 100 metros" en vez de leer "—".
- `SessionView`: distancia con `@ScaledMetric` 88 y "km"; `Grid` 2×2 con el tiempo en su propio
  `TimelineView`; el contenido va en un `ScrollView` con altura mínima de pantalla para que Dynamic Type
  grande desplace en lugar de recortar, y los números usan `minimumScaleFactor`. Unidades visibles "/km"
  (solo con ritmo) y "spm". La etiqueta de VoiceOver de los pasos sigue siendo "N pasos" (1.2).
- Harness: `v3distance`, `pace` (`durationS − pausesS`) y `calculateCadence` registradas; tests propios
  por función, uno que prueba que `pace` resta las pausas y otro que rompe con pasos no enteros.
- `MetricsScenarios` porta los 10 sitios; `inventory.json`: `:114` → 1.5 y `:156`, `:181`, `:183`, `:186`
  → 1.4. `waitUntil` de `SessionStoreTests.swift` pasa a función del fichero para compartirla.
- Verificado: `bash Scripts/verify-domain.sh` verde (19 vectores Swift pasan; `v3distance`, `pace` y
  `calculateCadence` fuera de pendientes) y `xcodebuild … iPhone 16e CODE_SIGNING_ALLOWED=NO test` →
  `TEST SUCCEEDED`, 153 tests, sin warnings propios. **Pendiente:** los checks manuales en el iPhone 14
  (el simulador no tiene coprocesador, así que la pantalla de sesión no se ha visto con datos reales ni
  con el tamaño de texto de accesibilidad más grande).
- Revisión (pasada 1): 4 parches (test exacto del redondeo de `distanceM`, truncado de
  `DistanceFormat.spoken`, renombre de `calculatorRejectsNonFinite` y una línea reenvuelta) y 1 diferido
  (alternancia de `distance` en CoreMotion). Tras los parches: `verify-domain.sh` verde y 154 tests,
  `TEST SUCCEEDED`, sin warnings propios.

## Spec Change Log

## Review Triage Log

Pasada 1 (blind-hunter · edge-case-hunter · verification-gap):

| # | Hallazgo | Veredicto | Evidencia | Ruta |
|---|---|---|---|---|
| 1 | BH · La distancia visible puede bajar si primero sale de los pasos y después llega la del sistema (menor) | maybe-false | Solo pasa si CoreMotion alterna `distance` nil y con valor en una misma sesión; en un dispositivo con distancia disponible la da en cada muestra, desde la primera. Lo zanja registrar las muestras de una caminata real en el iPhone 14 | defer (con 2) |
| 2 | EC · Con distancia del sistema ya registrada, muestras posteriores con `distance` nil congelan distancia y ritmo mientras los pasos suben | maybe-false | Misma causa y misma evidencia pendiente que la 1 | defer (con 1) |
| 3 | BH · La rama de la distancia del sistema no redondea a 2 decimales y la de los pasos sí | low | Real, pero la UI trunca al centésimo y el umbral de 100 m no cambia en la práctica; unificarlo exige exponer el redondeo del calculador | rechazado |
| 4 | BH · `paceSecPerKm` devuelve `nil` con negativos en vez de lanzar | false | Igual que la v3: `domain.js:111,113` devuelve Infinity (ausente) con distancia o tiempo ≤ 0, sin lanzar | rechazado |
| 5 | BH · Las métricas usan `clock.now` y no `sample.end` | low | El retraso del handler al main actor es de milisegundos; efecto despreciable en ritmo y cadencia | rechazado |
| 6 | BH · "Sin ritmo hasta los 100 metros" repite el umbral en vez de leer `minPaceDistanceM` | low | Regla de producto de CAP-4; cambiarla exige renegociar la spec, que tocaría también el texto | rechazado |
| 7 | BH · Con ritmo > 60 min/km la pantalla dice "75:30" y VoiceOver "1 hora, 15 minutos…" | low | Ambas lecturas son correctas; caso raro (más de 100 m y casi parado durante mucho tiempo) | rechazado |
| 8 | BH · El parámetro `locale:` de los textos hablados solo formatea los valores | low | Solo hay localización `es`; sin efecto hoy | rechazado |
| 9 | BH · Ritmo y cadencia se congelan sin aviso con el teléfono quieto | false | Comportamiento decidido en Design Notes por AD-21 | rechazado |
| 10 | BH · La celda de pasos usa "N pasos" como etiqueta y valor vacío; la distancia no tiene rótulo visible | low | VoiceOver lee "N pasos", correcto y como en la 1.2; cosmético | rechazado |
| 11 | BH · Faltan tests: `distance` nil tras una del sistema, el registro en el log, negativos fuera de vectores | low | Los negativos ya los cubren los vectores `throws`; lo demás es la causa de la 1 o no es verificable sin inyectar el logger | rechazado |
| 12 | BH · El test `paceRejectsNonFinite` también cubre cadencia y distancia | low | Nombre engañoso en la salida de tests; renombrarlo es directo | patch |
| 13 | BH · Spec `in-review` y sprint `in-progress`; checks manuales pendientes | false | Es el orden del flujo: el sprint se sincroniza al presentar, y los checks del iPhone son del cierre, como en la 1.2 | rechazado |
| 14 | BH · Nada prevé persistir `systemDistanceM` | low | Sin efecto en la 1.3 (no hay persistencia); la 1.6 persiste la sesión entera | rechazado |
| 15 | BH · Línea de comentario de 122 columnas en `SessionStore.swift:11` | low | El resto del fichero envuelve a ~100; reenvolver es directo | patch |
| 16 | EC · Zancada finita enorme desborda la distancia a infinito y `metrics(at:)` llega a `preconditionFailure` | false | `validateStride` y `formulas.json` acotan la zancada; el producto con un `Int` de pasos no se acerca a 1,8·10³⁰⁸ | rechazado |
| 17 | EC · `activeSeconds` subnormal desborda la cadencia | false | `elapsedS` sale de restar `Date`s (resolución ~10⁻⁷ s): nunca es subnormal | rechazado |
| 18 | EC · `pace` lanza con distancia infinita y crashea | false | Duplicado de la 16: la distancia no puede ser infinita | rechazado |
| 19 | EC · Ritmo 0 con ≥ 100 m muestra "— /km" | false | Exige 100 m en menos de 0,05 s desde el inicio | rechazado |
| 20 | EC · VoiceOver dice "hasta los 100 metros" con ≥ 100 m y tiempo 0 | false | Exige 100 m recorridos con tiempo transcurrido 0 | rechazado |
| 21 | EC · `String(format: "%d")` con `Int` de 64 bits trunca minutos enormes | false | En arm64 `%d` lee los 32 bits bajos; ningún ritmo real se acerca a 2³¹ minutos | rechazado |
| 22 | EC · Doble redondeo de la cadencia (84,46 → 84,5 → 85) | low | Solo en la franja x,45–x,4999 y por 1 spm; el dominio conserva el decimal por los vectores | rechazado |
| 23 | EC · El arnés acepta pasos > 2⁵³ que la v3 rechaza | false | Ningún vector lleva esos valores; no hay ejecución que diverja | rechazado |
| 24 | VG · Ningún test afirma el redondeo a 2 decimales de `distanceM` | low | Verificado por la capa: `return steps * strideM` deja todo en verde | patch |
| 25 | VG · Ningún test afirma el truncado de `DistanceFormat.spoken` | low | Verificado por la capa: quitar el truncado deja `distanceSpoken` en verde | patch |
| 26 | EC · La primera distancia del sistema (0 o menor) queda por debajo de la de los pasos ya mostrada | maybe-false | Misma causa y evidencia pendiente que la 1 | defer (con 1) |

## Design Notes

- **Distancia del sistema con estimados:** `systemDistanceM + stepsEstimated × strideM`. En la 1.3
  `stepsEstimated` es siempre 0, pero la fórmula ya queda fijada para la 1.5.
- **Sitios que dependen de otras historias:** un sitio que afirma una métrica sobre una sesión activa
  sin pausa ni estimados se porta aquí con `metrics(at:)`, aunque el JS pase por `finishV3`. Los
  valores coinciden porque `durS` no tiene pausas. Los que necesitan pausa o estimados se reasignan.
- **Cadencia:** el denominador es el tiempo neto transcurrido, como la v3 y su regresión `:183`. Hasta
  la 1.5, los minutos con sensor activo coinciden con ese tiempo.
- **Umbral de 100 m:** es una regla de producto de CAP-4, no una calibración provisional, así que va en
  el dominio y no en `formulas.json`.
- **Métricas congeladas:** con el teléfono quieto el coprocesador no emite, así que ritmo y cadencia se
  quedan en su último valor hasta la siguiente muestra (AD-21).
- **Cadencia en pantalla:** entera ("80 spm"); el dominio conserva el decimal para los vectores.

## Verification

**Commands:**
- `bash Scripts/verify-domain.sh` — esperado: verde, con `v3distance`, `pace` y `calculateCadence` fuera
  de los pendientes de Swift y las citas de 1.1–1.3 completas.
- `xcodegen generate && xcodebuild … iPhone 16e CODE_SIGNING_ALLOWED=NO test` — esperado:
  `TEST SUCCEEDED`, sin warnings propios.

**Manual checks (iPhone 14):**
- Caminar: la distancia y la rejilla suben solas y el ritmo pasa de "—" a `m:ss` tras 100 m.
- VoiceOver lee distancia, pasos, tiempo, ritmo y cadencia con su unidad.
- Con el tamaño de texto de accesibilidad más grande, ninguna métrica se recorta.
