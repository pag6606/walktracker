# Domain Model — WalkTracker iOS

Companion de `SPEC.md`. Modelo de dominio preservado desde la PWA v3 (validado en producción) con las adaptaciones que la plataforma nativa habilita. El dominio es puro: sin imports de UI, HealthKit, CoreMotion ni SwiftData (constraint Arquitectura hexagonal).

## 1. Lenguaje ubicuo (sin cambios desde v3)

`Session` (aggregate root) · `Chronometer` · `MetricsCalculator` · `CalibrationProfile` · `GoalEngine` · `AchievementEngine` · `MotivationEngine` · `GapEstimator` (solo degradación, ver §6).

Retirado en nativo: `StepDetector` (pipeline propio de acelerómetro a 60 Hz, α=0.2, ventana refractaria 300 ms). La detección de pasos la hace el coprocesador del sistema (CAP-2); no hay pipeline propio que preservar.

## 2. Aggregate Session

Estados: `active` → `paused` → `active` → `finished`. Finalizada = **inmutable** (cualquier mutación lanza error de dominio).

| Campo | Regla |
|---|---|
| `id` | UUID al persistir |
| `startedAt` / `endedAt` | ISO-8601; `endedAt` solo al finalizar |
| `stepsMeasured` | entero ≥ 0; en nativo proviene del coprocesador (sistema) |
| `stepsEstimated` | entero ≥ 0, default 0; **siempre desglosado**, mostrado "~", descartable |
| `strideM` | > 0; **congelado al cierre** (recalibrar nunca reescribe historial) |
| `distanceM` | derivada, cacheada al cierre; ver §4 |
| `durationS` / `pausesS` | enteros en segundos |
| `paceSecPerKm` | entero s/km o `null` si `distanceM < 100` |
| `cadenceSpm` | float 1 decimal; solo sobre tramos medidos |
| `weather` | snapshot `{tempC, feelsLikeC, condition, humidityPct, uvIndex, windKmh, capturedAt}` o `null` |
| `quoteId` | id de `quotes.json` mostrada al inicio |
| `source` | `"ios"` \| `"v3"` \| `"migrated"` — ver §7 |

Invariantes de mutación (idénticos a v3): `stepsEstimated` y `stepsMeasured` nunca bajan de 0; pausar/reanudar solo desde el estado que corresponde; finalizar desde pausada acumula la pausa abierta antes de cerrar.

## 3. Chronometer (wall-clock)

```
elapsedS = (now − startedAt) − totalPausesS
```

`now` vía ClockPort; ningún timer es fuente de verdad (los timers solo refrescan UI). Pausa solo explícita. Al reabrir la app con sesión activa, elapsed se recomputa desde `startedAt` — el tiempo cerrado cuenta (recuperación silenciosa, indicador 3 s).

## 4. Cálculos de dominio

| Cálculo | Fórmula | Condición |
|---|---|---|
| Distancia (fallback) | `distanceM = (stepsMeasured + stepsEstimated) × strideM` | Cuando el sistema no provee distancia |
| Distancia (preferida) | distancia reportada por el sistema para la sesión | CAP-4; la fuente es decisión interna, sin distinción en UI |
| Tiempo | `elapsedS = (now − startedAt) − totalPausesS` | Siempre |
| Ritmo | `paceSecPerKm = elapsedMovS / (distanceM/1000)` | Solo si `distanceM ≥ 100`, si no `null` |
| Cadencia | `cadenceSpm = stepsMeasured / minutosConSensorActivo` | **Solo sobre tramos medidos** — nunca sobre estimados (evita realimentar la estimación) |
| Gap (degradación) | `stepsEstimated += cadenceSpm × (gapS/60)` | Solo si el sistema no puede reconstruir el gap, sesión activa, muestra previa ≥ 120 s, los pasos medidos no han crecido desde el inicio del gap (si crecieron, el stream ya los trajo) y `gapS ≤ maxEstimableGapS`; si no, gap = 0. La `cadenceSpm` es la del **inicio del gap** (pasos medidos y tiempo de sesión en ese instante), nunca la de ahora (R1, 2026-09-17) |

Validación en la frontera: `strideM` y `weeklyGoalKm` se validan (> 0, finitos) antes de materializar aggregates; el dominio permanece siempre-válido. Errores de dominio específicos (violación de invariante vs input inválido), no genéricos.

## 5. Engines

### GoalEngine
Progreso semanal sobre **semana ISO**: lunes 00:00 UTC de la semana corriente hasta +7 días.
```
completedKm = Σ distanceM/1000  (sesiones con startedAt dentro de la semana)
percentage  = min(100, completedKm / weeklyGoalKm × 100)
isComplete  = completedKm ≥ weeklyGoalKm   (default weeklyGoalKm = 10)
```

### MotivationEngine
- Selección aleatoria sobre `quotes.json` (100 frases, companion adoptado) excluyendo `recentQuoteIds` (últimas 20).
- Si todas están excluidas, se ignora el filtro y se elige de todo el banco (regla heredada).
- `recentQuoteIds` se actualiza con cada selección, máximo 20 ids, persiste en config.

### AchievementEngine
Catálogo y reglas completas en `achievements.md`. Evalúa al cierre de sesión sobre: la sesión, todas las sesiones (acumulados, streaks) y los logros ya desbloqueados (no re-dispara). `weekly_goal` se evalúa externamente vía GoalEngine al cumplirse la meta.

## 6. GapEstimator (solo degradación)

En la PWA era la estrategia principal para background. En nativo, CAP-3 reconstruye por consulta al sistema y el GapEstimator solo opera cuando el sistema **no responde** (`nil`, error o timeout): cualquier respuesta no nula cuenta como dato y corta la estimación (R1, 2026-09-17). Sus reglas heredadas se preservan: cadencia solo sobre tramos medidos, muestra previa ≥ 120 s, sesión no pausada, resultado siempre desglosado en `stepsEstimated`, marcado "~" y descartable. R1 añade dos reglas más, ya recogidas en §4: la cadencia se toma en el **inicio del gap** (pasos medidos y tiempo de sesión de ese instante, nunca los de ahora) y no se estima nada por encima de `maxEstimableGapS`. Cuando no estima, el desenlace dice qué defensa actuó (`notActive`, `streamAdvanced`, `noPriorSample`, `gapAboveCap`, `noCadence`).

## 7. Provenance (`source`) — e importación PWA (archivada)

Con arranque limpio (OQ-3, decisión Paul 2026-07-28), todas las sesiones de la v1 iOS llevan `source: "ios"`. El campo se conserva en el esquema por compatibilidad futura.

| `source` | Origen | Cuenta en Goal/Achievement | Alimenta cadencia |
|---|---|---|---|
| `"ios"` | Sesión de la app iOS (CAP-2) | Sí | Sí |
| `"v3"` | Importada de la PWA — *no aplica en v1 (CAP-16 retirada)* | Sí | No (histórica; su `cadenceSpm` ya viene calculada) |
| `"migrated"` | v1.1 → migrada en la PWA → importada — *no aplica en v1* | Sí (distancia correcta) | No |

Reglas de importación PWA → iOS (**archivadas** — referencia para la eventual reactivación de CAP-16):
- Entrada: JSON de export de la PWA con registros `{id, startedAt, endedAt, stepsMeasured, stepsEstimated, strideM, distanceM, durationS, pausesS, paceSecPerKm, cadenceSpm, weather, quoteId, source}`.
- Se preservan todas las métricas y el `source`; no se recalcula nada.
- Idempotente por `id`: re-importar el mismo archivo no duplica.
- Validación pre-import: registros con `distanceM ≤ 0` o `strideM ≤ 0` se marcan `source: "corrupt"` y se excluyen (regla heredada de la decisión D1).
- Herencia D1 documentada: las sesiones `"migrated"` llevan `stepsMeasured` de estimación inversa (`round(distanceM / strideM)`); esa distinción motiva la columna "Alimenta cadencia".

## 8. Storage shapes (contrato de datos)

```
config → { strideM: 0.655, weeklyGoalKm: 10.0, soundEnabled: true,
           recentQuoteIds: number[≤20], lastExportAt: ISO8601|null }

activeSession (snapshot recuperación) → { startedAtMs, stepsMeasured, stepsEstimated,
           totalPausesMs, paused, pausedAtMs, strideM, weather|null, quoteId }

sessions (store) → { id, startedAt, endedAt, stepsMeasured, stepsEstimated, strideM,
           distanceM, durationS, pausesS, paceSecPerKm|null, cadenceSpm,
           weather|null, quoteId, source }

achievements (store) → { key, unlockedAt: ISO8601|null, progress: 0.0..1.0 }
```

Convenciones (heredadas): timestamps ISO-8601; duraciones en segundos enteros; distancia float metros (2 dp); pasos enteros; cadencia float spm (1 dp). Autosave del snapshot cada 10 s y al ir a background; recuperación silenciosa al reabrir.

## 9. Nota de implementación heredada (corregir en iOS)

- `early_bird` / `night_walker` y el cálculo de racha evalúan horas/fechas en **UTC** en la PWA (detalle de implementación). En iOS deben evaluarse en **hora local del dispositivo** — la intención del logro ("camina antes de las 7:00") es local. Se registra aquí para que la portación lo corrija deliberadamente, no por arrastre.
- `rain_walker` en la PWA aplica regex sobre el string localizado de condición. En iOS la regla debe mapear la condición del proveedor (enum WeatherKit / código WMO) a una categoría interna (`rain`), sin depender de strings localizados.
