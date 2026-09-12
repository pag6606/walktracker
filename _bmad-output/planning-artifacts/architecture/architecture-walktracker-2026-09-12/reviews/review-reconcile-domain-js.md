# Review de reconciliación — ARCHITECTURE-SPINE vs. el código JS real

- **Revisor:** agente de reconciliación (foco: código de dominio existente)
- **Fecha:** 2026-09-12
- **Artefacto revisado:** `_bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-09-12/ARCHITECTURE-SPINE.md`
- **Código de referencia:** `/Users/paul/Dev/walktracker/domain.js`, `motivation.js`, `storage.js`
- **Tests leídos y ejecutados:** `test/domain-tests.js`, `test/session-v3-tests.js`, `test/motivation-tests.js`, `test/gapestimator-tests.js` (y `test/stepdetector-tests.js` para contraste)

---

## Veredicto

**AD-6 es inviable tal como está escrito.** Tres razones independientes, cada una suficiente:

1. **El número es falso.** No son 168 aserciones: son **182 sitios estáticos** y **281 aserciones ejecutadas**.
2. **El formato es falso.** Solo **65 de 182** son funciones puras `entrada → salida`. **111** solo existen como *secuencia de comandos sobre un agregado mutable*; una tabla de vectores no las representa.
3. **La premisa es falsa.** "`domain.js` y el dominio Swift ejecutan **el mismo fichero**" contradice al propio SPEC: `domain-model.md §9` y `achievements.md` **ordenan** que 7 aserciones diverjan (UTC→local, regex→WMO), y `domain-model.md §4` **contradice** un valor dorado ya existente (cadencia con pausas). Un vector que falla bloquea el merge ⇒ AD-6 tal cual **bloquea el merge por diseño**.

AD-6 se salva con una corrección acotada (§7). No hay que tirarlo.

---

## 0. Recuento real de aserciones

Ejecutado hoy, los cuatro ficheros pasan al 100 %:

| Fichero | Sitios estáticos | Aserciones ejecutadas |
|---|---:|---:|
| `test/domain-tests.js` | 51 | 51 |
| `test/session-v3-tests.js` | 83 | 182 |
| `test/motivation-tests.js` | 32 | 32 |
| `test/gapestimator-tests.js` | 16 | 16 |
| **Total** | **182** | **281** |

De dónde sale el 168 del spine: `assert(` (134) + `assertThrows(` (34) = **168**. **Se olvidaron los 14 `assertApprox(`** (todos en `session-v3-tests.js`), que son precisamente las aserciones numéricas con tolerancia — las más relevantes para un vector dorado. Y se colapsó el bucle de `session-v3-tests.js:335-338`, que es 1 sitio y 100 aserciones en tiempo de ejecución.

> **[MEDIA]** Corregir el número en AD-6. Un contrato que empieza contando mal su propio alcance no es un suelo.

También: `test/stepdetector-tests.js` aporta **39 aserciones más** y AD-6 no lo menciona ni para excluirlo. La exclusión es *correcta* (`domain-model.md §1` retira `StepDetector`), pero el spine no lo dice en ningún sitio — ver §5.

---

## 1. Aserciones puramente funcionales (extraíbles a datos) — **65 de 182 (36 %)**

Funciones puras, argumentos JSON-representables, sin estado ni reloj:

| Bloque | Líneas | N.º | Función bajo prueba |
|---|---|---:|---|
| `domain-tests` AC-5 | 101 | 1 | `elapsedS` |
| `domain-tests` AC-6 | 110-112 | 2 | `distance`, `pace` |
| `domain-tests` AC-7 | 121-123 | 3 | `recalibrate` |
| `domain-tests` AC-8 | 131-133 | 3 | `recalibrate` (RangeError) |
| `domain-tests` AC-9 | 141-143 | 3 | `recalibrate` (TypeError) |
| `domain-tests` EXTRA Edge | 201-205 | 3 | `pace`, `distance` |
| `session-v3` AC-20 | 351-358 | 8 | `v3distance` |
| `motivation` selectQuote vacío + `updateRecentIds` | 35, 40-42 | 4 | puras |
| `motivation` AchievementEngine | 55-90 | 8 | `evaluateAchievements` |
| `motivation` GoalEngine | 100-132 | 9 | `getWeeklyProgress` |
| `motivation` Streak & Time | 147-161 | 5 | `checkStreak`, `checkTimeOfDay` |
| `gapestimator` (todo) | 21-101 | 16 | `estimateSteps`, `calculateCadence` |
| **Total** | | **65** | |

**`gapestimator-tests.js` es el único fichero 100 % extraíble** — 16/16. (Con una nota: `L29` y `L72` son la **misma aserción duplicada**, `estimateSteps(80,0)===0`; el vector real son 15.)

Descontando las que además son **portables** a Swift (§2), quedan **≈44 filas escalares** que son de verdad "el mismo fichero para los dos runtimes". **24 % de 182**, no el 100 % que AD-6 implica.

---

## 2. Aserciones NO extraíbles como vector — **117 de 182 (64 %)**

### 2.1 Secuencia de comandos sobre un agregado mutable — **111**

`domain-tests`: AC-1 (3), AC-2 (3), AC-3 (2), AC-4 (5), EXTRA Pause/resume (8), EXTRA Finish con pausas (4), restoreSession (11) = **36**.
`session-v3`: todo excepto AC-20 = **75**.

Ejemplo canónico, `domain-tests.js:44-51`:

```js
const s0 = Domain.createSession(0, 0.655, 62);
let s = s0;
for (let i = 0; i < 83; i++) s = Domain.lap(s);
assert(Math.abs(s.distanceM - 3370.63) < 0.01, ...);
```

No hay "entrada → salida esperada": hay un **estado inicial + 83 comandos + una proyección del estado final**. Lo mismo en `session-v3-tests.js:99` (bucle de 4 980 `addSteps`), `:335-338` (100 comandos con aserción intermedia en cada uno) y todos los bloques pause/resume/finish.

> **[ALTA]** Estas 111 aserciones **no caben en el formato que AD-6 describe**. O el spine define un segundo tipo de vector (script de comandos + reloj inyectado) o el 61 % del contrato se queda fuera y "los vectores son el suelo" pasa a significar "el suelo cubre un tercio de la habitación".

### 2.2 Dependen de `Math.random()` — **5**

`motivation.js:36` y `:40` usan `Math.random()`. Las aserciones de `motivation-tests.js:20, 21, 22, 27, 32` son **predicados de propiedad**, no valores esperados: "devuelve algo no nulo", "el id es un número", "el elegido no está entre los 20 recientes". No existe salida esperada que congelar.

Corrección obvia y barata: inyectar un `RandomPort` / semilla al `MotivationEngine` (el spine ya tiene `ClockPort` como precedente en AD-10). Con semilla fija, `selectQuote` sí produce vectores. **Sin eso, `MotivationEngine` (CAP-6) queda sin ningún vector** — y AD-6 ni siquiera lo lista entre sus `Binds` (lista CAP-1, 3, 4, 7, 8; CAP-6 no aparece), así que al menos ahí es coherente consigo mismo.

### 2.3 Dependen del reloj real — **11 (bloque completo) / 1 directa**

`domain-tests.js:213` siembra el bloque `restoreSession` con `Date.now()`. Peor: **el propio dominio llama al reloj**:

- `domain.js:249` — `pausedAtMs: isPaused ? Date.now() : null`
- `domain.js:392` — `pausedAtMs: isPaused ? snapshot.pausedAtMs || Date.now() : null`

> **[ALTA]** Esto **viola AD-10** del propio spine: *"El reloj también es un puerto: el dominio nunca llama a `Date()`"*. `restoreSession`/`restoreV3Session` no son funciones puras hoy. La aserción `domain-tests.js:238` (`recoveredPaused.pausedAtMs !== null`) solo puede comprobar "no es nulo" porque el valor es irreproducible. Hay que cambiar la firma (`restore(snapshot, nowMs)`) **antes** de extraer vectores, y eso invalida el bloque tal cual está escrito.

### 2.4 Introspección de runtime JS — vacías en Swift — **9**

| Aserción | Líneas | Por qué muere |
|---|---|---|
| `Object.isFrozen(...)` | `session-v3` 196, 324, 326 | Un `struct` Swift es value type: la aserción es o tautológica o insensata |
| `s.laps === undefined` etc. | `session-v3` 76, 77, 78 | Ausencia de campo: en Swift es un hecho de compilación, no un test |
| `typeof s === 'object'` | `session-v3` 51 | Tautológico |
| `typeof q.id === 'number'`, `typeof q.text === 'string'` | `motivation` 21, 22 | Tautológico |

### 2.5 Argumentos que Swift no puede ni expresar — **2 (+1 dudosa)**

- `domain-tests.js:141` — `recalibrate({ strideM: 'x', ... })` → `TypeError`
- `session-v3-tests.js:56` — `createV3Session(NOW, 'x')` → `TypeError`

Pasar un `String` donde va un `Double` **no compila** en Swift. Estos vectores no tienen ejecución posible del otro lado. (`domain-tests.js:143`, `stepsPerLap: undefined`, sí se puede modelar como `Double?` nil, pero es otro mecanismo, no el mismo contrato.)

### 2.6 `Infinity` como valor esperado — **2**

`domain-tests.js:201` y `:205` esperan `pace(...) === Infinity`. Dos problemas:

- `JSON.stringify(Infinity)` → `null`. **Verificado.** El valor no sobrevive al fichero neutral de lenguaje.
- `domain-model.md §2` define `paceSecPerKm` como *"entero s/km o `null` si `distanceM < 100`"*. En v3 `null` **ya significa otra cosa**. Y el JS es incoherente consigo mismo: `pace()` (`domain.js:111`) devuelve `Infinity`, `finishV3` (`domain.js:351`) devuelve `null`.

> **[MEDIA]** Antes de los vectores: eliminar `Infinity` de la superficie del dominio (`pace` → `null`), o definir un centinela explícito en el esquema de vectores.

### 2.7 Excepciones sin taxonomía neutral — **34 `assertThrows`, 9 de ellas inútiles**

`assertThrows(fn, Error, msg)` en `domain-tests.js:87, 88, 89, 172` y `session-v3-tests.js:191, 192, 193, 288, 289`. El helper hace `e.constructor.name === expectedType || e instanceof expectedType`; **cualquier** error es `instanceof Error`. Esas **9 aserciones no comprueban nada**: pasarían con un `TypeError` de "undefined is not a function".

Además, el JS distingue solo 3 clases (`Error`, `TypeError`, `RangeError`) con mensajes en español embebidos. AD-4 dice *"errores tipados"* pero **ningún AD define el mapa**. Sin un código neutral (`invalidInput` / `outOfRange` / `invariantViolation`) los 34 vectores de excepción no son comparables entre runtimes.

### 2.8 Aserciones sin valor esperado (predicados débiles) — **6**

`domain-tests.js:86, 192, 238`; `session-v3-tests.js:147, 156, 208`.

La más grave, `domain-tests.js:187-192`:

```js
// elapsed = (finishAt - startMs - 120000ms) / 1000 = 580s
// pace = 580 / (406.1/1000) = 580 / 0.4061 ≈ 1428 s/km
assert(f.durationS > 0, `durationS > 0 (got ${f.durationS}s)`);
```

El valor esperado **está en el comentario y no se asserta**. Igual en `session-v3-tests.js:145-147` (`≈ 1140 s/km` en comentario, `assert(f.paceSecPerKm > 0)` en código). No es casualidad — ver §3.1.

### 2.9 No es dominio — **1**

`motivation-tests.js:45` — `quotes.length === 100`. Es una aserción sobre el fichero de datos (`quotes.json`), no sobre comportamiento. Encaja mejor como validación de esquema de arranque (AD-5), no como vector.

### Resumen cuantitativo

| Categoría | N.º | % de 182 |
|---|---:|---:|
| Puras, tabulables como fila escalar | 65 | 36 % |
| Secuencia de comandos (necesitan otro formato) | 111 | 61 % |
| Aleatoriedad (`Math.random`) | 5 | 3 % |
| Reloj real dentro del dominio | 1 directa / 11 de bloque | — |
| Introspección JS (vacías en Swift) | 9 | 5 % |
| Argumentos inexpresables en Swift | 2 | 1 % |
| `Infinity` como salida | 2 | 1 % |
| Predicados sin valor esperado | 6 | 3 % |
| Sobre el fichero de datos, no el dominio | 1 | 0,5 % |

*(las categorías se solapan; la primera fila y la segunda sí particionan las 182)*

### El bloque que nadie ha contado: **52 aserciones sobre un agregado que no existirá en Swift**

`domain-model.md §2` define `Session` **solo con pasos**: no hay `laps`, ni `lapPerimeterM`, ni `stepsPerLap`. `§8` define `config` como `{ strideM, weeklyGoalKm, soundEnabled, recentQuoteIds, lastExportAt }` — **sin `stepsPerLap`**.

Por tanto, **no habrá contraparte Swift** para `createSession`, `lap`, `undo`, `finish`, `restoreSession`, `distance(laps, perimeterM)`, `recalibrate({strideM, stepsPerLap})` ni `averageStepsPerLap`.

- `domain-tests.js`: **47 de 51** aserciones son de la agregada v1 (todas menos `AC-5` y los 3 `pace` de `AC-6`/`EXTRA Edge`).
- `session-v3-tests.js` AC-11 "V1 no regression" (`225-232`): **5** más.

> **[ALTA]** **52 de 182 aserciones (29 %) no tienen nada contra qué ejecutarse en Swift.** AD-6 promete que ambos runtimes ejecutan el mismo fichero; para casi un tercio del contrato, el runtime Swift no existe. Peor, la tabla `Capability → Architecture Map` mapea **CAP-13 (recalibración) a AD-6** — y las 9 aserciones de calibración (`AC-7`, `AC-8`, `AC-9`) son **todas** del perímetro v1 basado en `stepsPerLap`. CAP-13 se queda con **cero vectores portables**.

### Las divergencias que el propio SPEC ordena — **7 aserciones garantizadas en rojo**

`domain-model.md §9` y `achievements.md` ("Nota de zona horaria", "Nota de mapeo lluvia") **mandan** cambiar el comportamiento en iOS:

| Aserción | Líneas | Comportamiento JS | Comportamiento iOS ordenado |
|---|---|---|---|
| `rain_walker` ×2 | `motivation` 75, 80 | regex `/lluv\|llovi\|torment/i` sobre string localizado (`motivation.js:116`) | mapeo de enum WeatherKit / código WMO 51-67, 80-82, 95-99 |
| `checkTimeOfDay` ×3 | `motivation` 155, 158, 161 | `getUTCHours()` (`motivation.js:175`) | hora **local** del dispositivo |
| `checkStreak` ×2 | `motivation` 147, 151 | fechas en UTC (`motivation.js:156-158`) | fechas en hora **local** |

> **[CRÍTICA]** AD-6 dice literalmente: *"`domain.js` y el dominio Swift ejecutan **el mismo fichero**. Un vector que falla bloquea el merge."* Estas 7 aserciones **están diseñadas para divergir**. Aplicando AD-6 al pie de la letra, el merge de CAP-8 está bloqueado el día uno. AD-6 y `domain-model.md §9` son mutuamente inconsistentes y el spine no lo reconoce.

---

## 3. Lógica de dominio SIN cobertura — los vectores no la protegerían

### 3.1 El bug de la doble resta de pausas — **y un vector dorado que lo congelaría**

`domain.js:349-353`:

```js
const durS = Math.round(elapsedS(session.startedAt, totalPausesMs, nowMs));   // YA neto de pausas
const p = dist >= 100 ? pace(durS, Math.round(totalPausesMs / 1000), dist) : null;
const activeMin = (durS - Math.round(totalPausesMs / 1000)) / 60;             // resta pausas OTRA VEZ
```

`elapsedS` (`domain.js:77`) ya devuelve `(now − started − pausas)/1000`. `pace` (`domain.js:112`) vuelve a hacer `movingS = durationS − pausesS`. Y `activeMin` vuelve a restarlas. **Las pausas se descuentan dos veces**, tanto en el ritmo como en la cadencia. Lo mismo en v1: `domain.js:216`.

Ejecutado (sesión de 3 900 s de reloj, 180 s de pausa, 4 980 pasos, zancada 0,655):

| Métrica | `domain.js` devuelve | `domain-model.md §4` exige |
|---|---:|---:|
| `cadenceSpm` | **84,4** | `4980 / (3720/60)` = **80,3** |
| `paceSecPerKm` | **1 085** | `3720 / (3261,9/1000)` = **1 140** |

`session-v3-tests.js:179` **asserta 84,4** y lo racionaliza en el comentario de la línea 172 (*"59 min = 3720s - 180s"*), que da por hecho que `durS` es reloj bruto cuando ya es neto.

> **[CRÍTICA]** Este es exactamente el fallo que AD-6 dice prevenir, ocurriendo **en la dirección contraria**: no es que Swift cambie el comportamiento sin que nadie lo note; es que **el vector dorado propagaría un bug de la PWA a Swift y bloquearía la implementación correcta según el SPEC**. Hay que adjudicar quién manda —`domain.js` o `domain-model.md §4`— **antes** de extraer nada. Y el ritmo con pausas **no está cubierto por ninguna aserción**: `domain-tests.js:192` solo comprueba `durationS > 0` y `session-v3-tests.js:147, 156` solo `> 0` y `!== null`, con los valores correctos abandonados en comentarios (§2.8). El test suite **esquiva sistemáticamente** el único cálculo donde hay un bug.

### 3.2 Ocho de los catorce logros no tienen ni una sola aserción

`grep` sobre todo `test/`: **`first_5km`, `first_10km`, `marathon_42km`, `consistency_30`, `hot_walker`, `cold_walker`, `early_bird`, `night_walker`** no aparecen en ningún test. (`early_bird`/`night_walker` se prueban indirectamente vía `checkTimeOfDay` con umbrales pasados a mano en el test — no se prueba que `evaluateAchievements` use `5,7` y `21,23`.)

> **[CRÍTICA]** AD-5 dice que previene *"el incidente real de 2026-09-11 — el catálogo se retecleó a mano en Dart y salieron 7 logros con la semántica cambiada"*. **Los vectores de AD-6 no habrían detectado ese incidente**: 8 de los 14 logros —incluido `first_5km`, el que se rompió— **no tienen aserción de la que extraer vector**. AD-5 y AD-6 se apoyan mutuamente sobre un hueco.

### 3.3 `weekly_goal` no se evalúa en ningún sitio

`motivation.js:111-113`:

```js
case 'weekly_goal':
  // Se evalúa externamente (GoalEngine)
  earned = false;
  break;
```

`getWeeklyProgress` devuelve `isComplete` pero **nada en el JS desbloquea `weekly_goal`**. `grep weekly_goal test/` solo lo encuentra en `storage-tests.js`. El spine lo mapea a CAP-7/CAP-8 bajo AD-5 y AD-6, pero **no nombra el componente que lo dispara**. Hueco heredado que pasa a Swift intacto.

### 3.4 `checkStreak` está roto en frontera de mes — sin cobertura

`motivation.js:156-159` construye claves `${year}-${month+1}-${day}` **sin cero a la izquierda** y las ordena **lexicográficamente**. Verificado:

```
7 días consecutivos 2026-09-25 … 2026-10-01  →  checkStreak(..., 7) === false
```

`"2026-10-1"` ordena antes que `"2026-9-25"`. El logro `7_days_streak` **es inalcanzable** en cualquier racha que cruce del día 9 al 10 del mes, o de septiembre a octubre. `motivation-tests.js:147` solo prueba una racha dentro de julio (pasa). Además `new Date("2026-7-8")` es parsing no-ISO, dependiente de implementación.

Adicionalmente `motivation.js:155` usa `sessions.length < days` (nº de **sesiones**) donde `achievements.md #7` exige *"≥ 1 sesión por día durante 7 días consecutivos"* (nº de **días**): dos sesiones el mismo día cuentan como dos hacia el umbral.

> **[ALTA]** Un vector extraído del comportamiento actual **congelaría el bug**. Y ninguna aserción existente lo expone.

### 3.5 Otra lógica sin ninguna aserción

| Elemento | Ubicación | Estado |
|---|---|---|
| `averageStepsPerLap` | `domain.js:52-59` | 0 tests, 0 usos en test/, ausente del spine |
| `FeedbackPort.fire` / `registerFeedbackAdapter` | `domain.js:558-577` | 0 tests en cualquier fichero |
| `getWeeklyProgress` con `weeklyGoalKm = 0` | `motivation.js:215` (rama `: 0`) | rama no cubierta |
| `selectQuote` con `quotes` no-array | `motivation.js:29` | no cubierto |
| `restoreV3Session` con `paused: true` | `domain.js:390-392` | no cubierto (solo el caso `active`, `session-v3:252`) |
| `pace` con pausas, valor concreto | `domain.js:112` | **deliberadamente no asertado** (§3.1) |
| `progress: 0.0..1.0` de los logros | `domain-model.md §8` | **el JS no lo calcula nunca**; `evaluateAchievements` devuelve solo `{key,name,icon}` |

---

## 4. Constantes embebidas que AD-5 exige mover a `formulas.json`

AD-5: *"las constantes de las fórmulas (umbrales, ventanas, mínimos) se cargan de JSON versionado del bundle"*. Lista concreta de lo que hoy está cableado en código:

### `domain.js`

| Línea | Constante | Qué es |
|---|---|---|
| 22 | `DEFAULT_STRIDE = 0.655` | zancada por defecto |
| 23 | `DEFAULT_STEPS_PER_LAP = 62` | v1 — probablemente derogado con la agregada v1 |
| 45 | `.toFixed(4)` | precisión del perímetro |
| 98, 308 | `.toFixed(2)` | precisión de distancia (2 dp — coincide con `domain-model.md §8`) |
| 114 | `Math.round` | redondeo del ritmo a entero |
| 216, 224, 253, 349, 362, 396 | `/ 1000` + `Math.round` | conversión ms→s |
| **351** | **`dist >= 100`** | **mínimo de distancia para calcular ritmo** — el umbral más semántico de todos |
| 353, 528 | `.toFixed(1)` | precisión de cadencia (1 dp) |
| 511 | `gapS / 60` + `Math.round` | conversión de la extrapolación del gap |
| 416 | `alpha = 0.2` | StepDetector — **retirado** por `domain-model.md §1` |
| 417 | `refractoryMs = 300` | StepDetector — retirado |
| 418 | `calibrationSamples = 600` | StepDetector — retirado |
| 453 | `rms * 3`, mínimo `0.15` | StepDetector — retirado |
| 468 | `0.999` / `0.001` | StepDetector — retirado |
| 469 | `0.15` | StepDetector — retirado |

**Ausente del JS y exigido por `domain-model.md §4`:** el mínimo de **muestra previa ≥ 120 s** para que el GapEstimator opere. `estimateSteps` (`domain.js:503-512`) no lo implementa. Es una constante nueva que debe nacer directamente en `formulas.json` — y para la que **no existe ningún vector**.

### `motivation.js`

| Línea | Constante | Qué es |
|---|---|---|
| **58-73** | **el catálogo entero de 14 logros** | `Object.freeze([...])` con `key`, `name`, `desc`, `icon` en código. Es exactamente el objetivo de AD-5, y además mezcla i18n español con datos |
| 31, 51 | `.slice(-20)` ×2 | ventana de frases recientes — **la constante está duplicada en dos sitios** |
| 103 | `>= 1000` | `first_km` |
| 106 | `>= 5000` | `first_5km` |
| 109 | `>= 10000` | `first_10km` |
| 116 | `/lluv\|llovi\|torment/i` | `rain_walker` — regex sobre string **localizado**; `achievements.md` exige sustituirlo por códigos WMO 51-67, 80-82, 95-99 |
| 119 | `7` | días de racha |
| 122 | `>= 42000` | `marathon_42km` |
| 125 | `< 480` | `speed_walker`, s/km |
| 128 | `5, 7` | ventana `early_bird` |
| 131 | `21, 23` | ventana `night_walker` |
| 134 | `> 30` | `hot_walker`, °C |
| 137 | `< 5` | `cold_walker`, °C |
| 140 | `>= 30` | `consistency_30`, nº de sesiones |
| 190 | `weeklyGoalKm = 10` | meta semanal por defecto |
| 214 | `.toFixed(2)` | precisión de km |
| 215 | `Math.min(100, …)`, `.toFixed(1)` | tope y precisión del porcentaje |

### `storage.js` — duplicación de los mismos valores

| Línea | Constante |
|---|---|
| 31 | `{ strideM: 0.655, weeklyGoalKm: 10.0, soundEnabled: true, … }` (MemoryAdapter) |
| 75 | **el mismo objeto, reescrito** (LocalStorage adapter) |

`0.655` vive hoy en **tres** sitios (`domain.js:22`, `storage.js:31`, `storage.js:75`) y `10` de meta semanal en **tres** (`motivation.js:190`, `storage.js:31`, `storage.js:75`). Exactamente el patrón que AD-5 quiere eliminar.

> **[MEDIA]** El spine nombra `formulas.json` en el árbol estructural pero **nunca enumera su contenido ni fija su esquema**. Con 30+ constantes candidatas repartidas por tres ficheros, "las constantes de las fórmulas" no es una instrucción ejecutable. AD-5 necesita el inventario, o el fichero nacerá con las tres que alguien recuerde.

---

## 5. Engines y cálculos que el spine omite

| # | Elemento en JS | Situación en el spine | Severidad |
|---|---|---|---|
| 1 | **`StepDetector`** (`domain.js:415-491`, 39 aserciones en `test/stepdetector-tests.js`) | `domain-model.md §1` lo **retira** explícitamente. El **spine no lo menciona en absoluto**: ni en `Domain/Engines/`, ni en `Deferred`, ni en AD-6 (que excluye su fichero de tests sin decir por qué). `DEROGACIONES.md` está declarado en `companions:` del frontmatter y **no existe en disco** | **ALTA** |
| 2 | **`averageStepsPerLap`** (`domain.js:52-59`) | Ausente del spine y de `domain-model.md §1`. Sin tests. Si CAP-13 mide pasos-por-vuelta en iOS, no tiene destino | MEDIA |
| 3 | **Rehidratación desde snapshot** (`restoreSession` `domain.js:234`, `restoreV3Session` `domain.js:373`) | El spine cubre reconciliación (AD-8) y persistencia (AD-9), pero **nadie posee el paso snapshot → agregado**, que además re-deriva la distancia y valida. `domain-model.md §8` define la forma del snapshot; el `Structural Seed` no tiene ningún `SessionSnapshot` | **ALTA** |
| 4 | **Catálogo de eventos de `FeedbackPort`** (`domain.js:558-563`: `session_start`, `km`, `goal`, `achievement`) | El spine tiene `FeedbackPort` en `Ports/` (AD-10) pero **nunca los cuatro tipos de evento**, y AD-5 no los enruta a datos. Sin tests | MEDIA |
| 5 | **`progress: 0.0..1.0`** de los logros | Está en `domain-model.md §8` y `achievements.md`, pero **ningún motor lo calcula** (ni en JS ni asignado en el spine). `AchievementsStore` es el candidato implícito, sin decirlo | MEDIA |
| 6 | **Disparo de `weekly_goal`** | Hueco en el JS (§3.3) que el spine no cierra: mapea el logro a CAP-7 y CAP-8 pero no nombra quién lo desbloquea ni cuándo | MEDIA |
| 7 | **Distancia preferida del sistema** (`domain-model.md §4`) | El spine mapea CAP-4 → `Domain/Metrics` **gobernado por AD-6**. Pero `domain.js` solo tiene el *fallback* `(medidos+estimados)×zancada`. **No hay vector posible** para la fuente preferida: AD-6 promete cobertura de CAP-4 que no puede entregar | **ALTA** |
| 8 | **Regla "alimenta cadencia" por `source`** (`domain-model.md §7`) | Sin equivalente en JS, sin vectores, y el spine no la asigna a ninguna capa | BAJA (CAP-16 retirada) |
| 9 | **Regla del gap "muestra previa ≥ 120 s"** (`domain-model.md §4`) | No existe en `estimateSteps`. AD-6 dice que los vectores vinculan CAP-3, pero la regla nueva de CAP-3 no tiene vector de origen | MEDIA |
| 10 | **`MotivationEngine` sin `RandomPort`** | AD-10 lista 8 puertos y **no incluye aleatoriedad**, siendo la única dependencia impura del `MotivationEngine`. Sin él, CAP-6 no es testeable ni por vectores ni de otra forma | MEDIA |
| 11 | **`companions:` inexistentes** | El frontmatter declara `REESTIMACION-EPICS.md` y `DEROGACIONES.md`; el directorio contiene solo `ARCHITECTURE-SPINE.md` y `.memlog.md` | BAJA |

---

## 6. Hallazgos ordenados por severidad

| # | Severidad | Hallazgo |
|---|---|---|
| H1 | **CRÍTICA** | El vector dorado de cadencia (`session-v3-tests.js:179` → **84,4 spm**) **congela el bug de doble resta de pausas** de `domain.js:351-352` y **contradice** `domain-model.md §4` (80,3 spm). El ritmo con pausas está igualmente mal (1 085 vs 1 140) y **ninguna aserción lo comprueba** — los valores correctos están abandonados en comentarios (`domain-tests.js:190-191`, `session-v3-tests.js:145-146`) |
| H2 | **CRÍTICA** | AD-6 (*"el mismo fichero", "un vector que falla bloquea el merge"*) **contradice** `domain-model.md §9` y `achievements.md`, que **ordenan** divergir en `early_bird`, `night_walker`, racha (UTC→local) y `rain_walker` (regex→WMO). **7 aserciones** garantizan merge bloqueado el día uno |
| H3 | **CRÍTICA** | **8 de los 14 logros no tienen ninguna aserción** (`first_5km`, `first_10km`, `marathon_42km`, `consistency_30`, `hot_walker`, `cold_walker`, `early_bird`, `night_walker`). Los vectores de AD-6 **no habrían detectado el incidente Dart de 2026-09-11** que AD-5 dice prevenir — `first_5km`, el que se rompió, es uno de los ocho |
| H4 | **ALTA** | **111 de 182 aserciones (61 %) no son `entrada → salida`**: son secuencias de comandos sobre un agregado mutable. El formato que AD-6 describe no las admite |
| H5 | **ALTA** | **52 de 182 (29 %) prueban la agregada v1 basada en vueltas** (`createSession`/`lap`/`undo`/`recalibrate(stepsPerLap)`), que `domain-model.md §2` y `§8` **eliminan** del modelo iOS. No hay runtime Swift contra el que ejecutarlas. CAP-13, mapeado a AD-6, se queda con **cero vectores portables** |
| H6 | **ALTA** | `domain.js:249` y `:392` llaman a `Date.now()` **dentro del dominio**, violando AD-10 (*"el dominio nunca llama a `Date()`"*). `restoreSession`/`restoreV3Session` no son puras y su bloque de 11 aserciones no es reproducible |
| H7 | **ALTA** | `checkStreak` (`motivation.js:156-159`) ordena claves de fecha **sin cero a la izquierda** lexicográficamente: **verificado que devuelve `false` para una racha real de 7 días 25-sep → 1-oct**. Ninguna aserción lo cubre; el vector congelaría el bug. Además cuenta **sesiones** donde `achievements.md #7` exige **días** |
| H8 | **ALTA** | El spine **nunca menciona `StepDetector`** (retirado por `domain-model.md §1`), ni sus 39 aserciones, ni el `DEROGACIONES.md` que debería registrarlo — y ese fichero no existe. AD-6 excluye `stepdetector-tests.js` en silencio |
| H9 | **ALTA** | AD-6 promete cobertura de CAP-4 por vectores, pero `domain-model.md §4` define la **distancia preferida** como la reportada por el sistema — que `domain.js` no tiene. Nadie posee la rehidratación snapshot→agregado |
| H10 | **MEDIA** | **El recuento de AD-6 es erróneo**: 168 = `assert` (134) + `assertThrows` (34), **olvidando los 14 `assertApprox`** (los numéricos con tolerancia). Real: **182 sitios / 281 ejecutadas** |
| H11 | **MEDIA** | **34 `assertThrows` sin taxonomía neutral de errores**, y **9 de ellos** (`domain-tests` 87, 88, 89, 172; `session-v3` 191, 192, 193, 288, 289) usan `Error` a secas: el helper acepta **cualquier** excepción. No comprueban nada |
| H12 | **MEDIA** | AD-5 nombra `formulas.json` pero **no enumera su contenido**. Hay **30+ constantes** repartidas por tres ficheros; `0.655` está triplicado (`domain.js:22`, `storage.js:31`, `storage.js:75`) y la meta de `10` km también |
| H13 | **MEDIA** | `MotivationEngine` depende de `Math.random()` (`motivation.js:36, 40`): **5 aserciones son predicados de propiedad, no vectores**. AD-10 lista 8 puertos y ninguno cubre la aleatoriedad |
| H14 | **MEDIA** | `Infinity` como salida esperada (`domain-tests.js:201, 205`) **no sobrevive a JSON** (`JSON.stringify(Infinity)` → `null`, verificado) y `null` ya significa otra cosa en v3. `pace()` devuelve `Infinity` y `finishV3` devuelve `null` para el mismo concepto |
| H15 | **MEDIA** | `weekly_goal` (`motivation.js:111-113`) está cableado a `earned = false` y **nada lo desbloquea nunca**. El spine no nombra al responsable |
| H16 | **BAJA** | **9 aserciones son introspección de runtime JS** y quedan vacías en Swift: `Object.isFrozen` ×3, `=== undefined` ×3, `typeof` ×3 |
| H17 | **BAJA** | `domain-tests.js:141` y `session-v3-tests.js:56` pasan un `String` donde va un número: **no compila** en Swift; el vector no tiene ejecución posible |
| H18 | **BAJA** | Sin cobertura alguna: `averageStepsPerLap` (`domain.js:52`), `FeedbackPort.fire`/`registerFeedbackAdapter` (`domain.js:565-577`), `restoreV3Session` con `paused: true`, `getWeeklyProgress` con meta 0, `progress` de logros |
| H19 | **BAJA** | `gapestimator-tests.js:29` y `:72` son **la misma aserción duplicada** (`estimateSteps(80,0)===0`) |
| H20 | **BAJA** | El frontmatter declara `companions: REESTIMACION-EPICS.md, DEROGACIONES.md`; **ninguno existe** en el directorio |

---

## 7. Corrección mínima propuesta para AD-6

No cambia la intención — la hace ejecutable. Reescritura sugerida de la `Rule`:

> **Rule:** el comportamiento del dominio se fija en ficheros de vectores versionados bajo `WalkTrackerTests/GoldenVectors/`, en dos formatos:
>
> - **`calc/*.json`** — filas escalares `{ fn, args, expect | throws }` para funciones puras. Cubre `elapsedS`, `pace`, `v3distance`, `estimateSteps`, `calculateCadence`, `getWeeklyProgress`, `evaluateAchievements`.
> - **`trace/*.json`** — guiones de comandos `{ seed, ops: [...], expect: {…} }` con **reloj y aleatoriedad inyectados**, replicados por ambos runtimes. Cubre el ciclo de vida de `Session` (crear · pasos · pausar · reanudar · finalizar · rehidratar).
>
> Alcance de extracción: **182 sitios de aserción** en `test/{domain,session-v3,motivation,gapestimator}-tests.js` (281 ejecutadas). `test/stepdetector-tests.js` (39) **queda fuera**: `StepDetector` está retirado por `domain-model.md §1`.
>
> **Lista de exclusión explícita, con motivo** (no se extraen; ~68 aserciones): agregada v1 de vueltas (52 — sin contraparte en `domain-model.md §2`); introspección de runtime JS (9); argumentos no tipables en Swift (2); `Math.random` sin semilla (5); aserción sobre `quotes.json` (1) → pasa a validación de esquema de AD-5.
>
> **Divergencias declaradas** (`divergent/*.json`, un fichero por plataforma, **no** bloquean el merge): `early_bird`, `night_walker` y racha en UTC (JS) vs hora local (iOS); `rain_walker` por regex localizada (JS) vs código WMO / enum WeatherKit (iOS). Origen: `domain-model.md §9` y `achievements.md`.
>
> **Taxonomía de errores neutral**, obligatoria en todo vector con `throws`: `invalidInput` · `outOfRange` · `invariantViolation`. Reemplaza los 9 `assertThrows(…, Error, …)` que hoy aceptan cualquier excepción.
>
> **Suelo de cobertura**, como puerta previa a la extracción: los **14** logros con al menos un vector positivo y uno negativo (hoy 6); el ritmo y la cadencia **con pausas** con valor exacto (hoy son predicados `> 0`); la racha cruzando frontera de mes.

Y tres cosas que hay que hacer **antes** de extraer un solo vector:

1. **Adjudicar H1** (doble resta de pausas). O el SPEC cede o `domain.js` se corrige y el test `session-v3-tests.js:179` cambia de 84,4 a 80,3. No hay tercera opción compatible con "un vector que falla bloquea el merge".
2. **Adjudicar H7** (racha rota en frontera de mes). Es un bug puro: se corrige en JS, se añade el vector, y entonces sí se hereda.
3. **Sacar `Date.now()` de `domain.js:249` y `:392`** (firma `restore(snapshot, nowMs)`). Sin eso, AD-10 es falso hoy y 11 aserciones no son reproducibles.

Y un añadido a **AD-5**: publicar el inventario de `formulas.json` (§4 de esta revisión sirve de borrador). Una regla que dice "las constantes van a JSON" sin enumerarlas producirá un fichero con tres constantes y veintisiete cableadas.
