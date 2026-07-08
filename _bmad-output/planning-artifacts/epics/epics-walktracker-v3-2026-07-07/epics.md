---
title: WalkTracker PWA v3.0 — Epics & Stories
name: WalkTracker
type: epics
status: final
created: 2026-07-07
updated: 2026-07-07
sources:
  - _bmad-output/planning-artifacts/prds/prd-walktracker-v3-2026-07-07/prd.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/EXPERIENCE.md
  - _bmad-output/planning-artifacts/architecture/architecture-walktracker-v3-2026-07-07/ARCHITECTURE-SPINE-v3.md
companions:
  - _bmad-output/planning-artifacts/prds/prd-walktracker-v3-2026-07-07/prd.md
---

# Epics & Stories — WalkTracker PWA v3.0

## Sprint overview

| Metric | Value |
|---|---|
| Epics | 6 |
| Stories | 23 |
| Must stories | 20 |
| Should stories | 3 |
| Estimated effort | ~4-6 semanas (1 dev, part-time) |
| Blocker | E0 (debe completarse antes de E1-E5) |

## Epic E0 — Conteo automático de pasos

**Prioridad:** 🔴 Bloqueante | **Stories:** 5 | **FRs:** RF-02, RF-03, RF-05, RF-08, RF-14, RNF-02, RNF-04

Rediseño del aggregate Session (`stepsMeasured`/`stepsEstimated`/`strideM`), `StepDetector` puro, `GapEstimator`, migración localStorage→IndexedDB, migración datos v1.1.

### E0-S1 — StepDetector puro (dominio)
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** —

**Como** Paul, **quiero** que la app detecte mis pasos automáticamente mientras camino con el teléfono en la mano, **para** no tener que contar vueltas manualmente.

**Criterios de aceptación:**
- [ ] `StepDetector` es dominio puro (sin DOM, sin APIs de navegador)
- [ ] Recibe muestras de magnitud de aceleración vía `MotionPort.sample(magnitude)`
- [ ] Aplica filtro paso-bajo (α=0.2) y detección de picos con umbral adaptativo
- [ ] Ventana refractaria de 300 ms (cadencia máx ~200 spm)
- [ ] Frecuencia fija 60 Hz (AD-12)
- [ ] Emite eventos `onStep()` con contador incremental
- [ ] Testeable con trazas grabadas (input → output determinista)
- [ ] ≥20 tests unitarios, 0 fallos

**Notas técnicas:** AD-12. El detector es testeable con trazas de acelerómetro grabadas en archivos JSON. El umbral adaptativo se calibra con los primeros 10s de muestra (OQ-1).

### E0-S2 — Session aggregate rediseñado
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S1

**Como** Paul, **quiero** que la app registre mis sesiones con pasos medidos y estimados desglosados, **para** saber qué datos son reales y cuáles son estimaciones.

**Criterios de aceptación:**
- [ ] `Session` aggregate expone `stepsMeasured` (entero ≥0), `stepsEstimated` (entero ≥0), `strideM` (>0)
- [ ] Distancia = `(stepsMeasured + stepsEstimated) × strideM`, derivada
- [ ] `stepsEstimated` se almacena desglosado, default 0
- [ ] Sesión finalizada es inmutable; congela `strideM`
- [ ] No hay concepto `laps` ni `lapPerimeterM` en v3
- [ ] `createSession(nowMs, strideM)` crea sesión con stepsMeasured=0, stepsEstimated=0
- [ ] `addSteps(session, count)` incrementa stepsMeasured
- [ ] `pause(session, nowMs)` y `resume(session, nowMs)` funcionan (heredado AD-6)
- [ ] `finish(session, nowMs)` calcula durationS, distanceM, paceSecPerKm, cadenceSpm
- [ ] `restoreSession(snapshot)` restaura desde snapshot (heredado AD-8)
- [ ] ≥15 tests unitarios, 0 fallos

**Notas técnicas:** AD-4, AD-5, AD-6, AD-8. Rompe compatibilidad con sesiones v1.1 (migración en E0-S5).

### E0-S3 — GapEstimator (extrapolación por cadencia)
**Prioridad:** Must | **Estimación:** S (1-2 días) | **Dependencias:** E0-S1, E0-S2

**Como** Paul, **quiero** que al volver de background la app extrapole mis pasos por cadencia y los marque como estimados, **para** ser honesto con mis datos sin inventar.

**Criterios de aceptación:**
- [ ] `GapEstimator.estimate(cadenceSpm, gapS, minSampleS)` retorna pasos estimados
- [ ] Solo si sesión activa (no pausada) y muestra previa ≥120s
- [ ] Fórmula: `stepsEstimated = cadenceSpm × (gapS/60)`
- [ ] Cadencia se calcula solo sobre tramos medidos (`stepsMeasured / minutosConSensorActivo`)
- [ ] Si sesión pausada o sin muestra suficiente → retorna 0
- [ ] ≥8 tests unitarios, 0 fallos

**Notas técnicas:** AD-13. La cadencia nunca se realimenta con estimados.

### E0-S4 — IndexedDBAdapter + StoragePort actualizado
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S2

**Como** Paul, **quiero** que mis sesiones se guarden en IndexedDB para que el historial crezca sin problemas, **para** no perder datos por límites de localStorage.

**Criterios de aceptación:**
- [ ] `StoragePort` abstrae IndexedDB (sesiones, logros) + localStorage (config, snapshot)
- [ ] IndexedDB store `sessions`: CRUD completo (getSessions, saveSession, deleteSession)
- [ ] IndexedDB store `achievements`: CRUD completo (getAchievements, saveAchievement)
- [ ] localStorage `wt:config`: getConfig, saveConfig
- [ ] localStorage `wt:activeSession`: getActiveSession, saveActiveSession
- [ ] `navigator.storage.persist()` solicitado al instalar
- [ ] `wt:migrated` flag en localStorage para idempotencia
- [ ] ≥12 tests (mock de IndexedDB), 0 fallos

**Notas técnicas:** AD-3. IndexedDB es async; el adapter debe manejar promises. localStorage es sync.

### E0-S5 — Migración datos v1.1 → v3 (D1)
**Prioridad:** Must | **Estimación:** S (1 día) | **Dependencias:** E0-S2, E0-S4

**Como** Paul, **quiero** que mis sesiones v1.1 se migren al nuevo formato sin perder datos, **para** mantener mi historial continuo.

**Criterios de aceptación:**
- [ ] Al detectar `localStorage["wt:sessions"]` con campo `laps`, se ejecuta migración una sola vez
- [ ] `stepsMeasured = round(distanceM / strideM)` (estimación inversa)
- [ ] `stepsEstimated = 0`
- [ ] `strideM = lapPerimeterM / stepsPerLap` (reconstruido)
- [ ] `source: "migrated"` en cada sesión migrada
- [ ] `distanceM`, `durationS`, `paceSecPerKm`, `pausesS`, `startedAt`, `endedAt` se conservan
- [ ] Flag `wt:migrated = "v3"` se setea tras migración exitosa
- [ ] Si `wt:migrated === "v3"`, no se re-migra (idempotencia)
- [ ] Sesiones con datos inválidos (distanceM ≤ 0, strideM ≤ 0) se marcan `source: "corrupt"` y se excluyen
- [ ] ≥8 tests unitarios, 0 fallos

**Notas técnicas:** Decisión D1. Sesiones migradas cuentan para Goal/Logros pero no para cadencia.

---

## Epic E1 — Clima

**Prioridad:** 🟡 Independiente (tras E0) | **Stories:** 2 | **FRs:** RF-06

GeoPort + GeolocationAdapter, WeatherPort + OpenMeteoAdapter. UI movida a E4-S8 (Weather Card en Session screen).

### E1-S1 — GeoPort + GeolocationAdapter
**Prioridad:** Must | **Estimación:** S (1 día) | **Dependencias:** E0-S4

**Como** Paul, **quiero** que la app obtenga mi ubicación una sola vez al iniciar sesión, **para** mostrar el clima actual.

**Criterios de aceptación:**
- [ ] `GeoPort.oneShot()` retorna `{lat, lon}` o `null`
- [ ] Usa `navigator.geolocation.getCurrentPosition` con `enableHighAccuracy: false`, `timeout: 3000`, `maximumAge: 300000`
- [ ] Coordenadas redondeadas a 2 decimales antes de retornar (privacidad RNF-06)
- [ ] Si permiso denegado → retorna `null` (no lanza error)
- [ ] Si timeout → retorna `null`
- [ ] ≥6 tests (mock de geolocation), 0 fallos

**Notas técnicas:** AD-17. Permiso opcional; degradación limpia.

### E1-S2 — WeatherPort + OpenMeteoAdapter
**Prioridad:** Must | **Estimación:** S (1 día) | **Dependencias:** E1-S1

**Como** Paul, **quiero** que la app consulte el clima actual sin necesidad de API key, **para** ver la temperatura y condiciones al iniciar mi caminata.

**Criterios de aceptación:**
- [ ] `WeatherPort.fetch({lat, lon})` retorna snapshot de clima o `null`
- [ ] Llama a Open-Meteo API (sin key, CORS abierto)
- [ ] Timeout 3s; si falla → retorna `null` (degradación limpia)
- [ ] Snapshot incluye: `tempC`, `feelsLikeC`, `condition`, `humidityPct`, `uvIndex`, `windKmh`, `capturedAt`
- [ ] `condition` mapea código WMO a texto en español (p. ej. 0→"Despejado", 3→"Nublado", 61→"Lluvia ligera")
- [ ] ≥8 tests (mock de fetch), 0 fallos

**Notas técnicas:** AD-14. Sin API key = sin secretos en cliente público.

---

## Epic E2 — Motivación: frases + logros + meta

**Prioridad:** 🟡 Independiente (tras E0) | **Stories:** 3 | **FRs:** RF-07, RF-10, RF-11, RF-12

### E2-S1 — MotivationEngine + quotes.json + overlay UI
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S4

**Como** Paul, **quiero** ver una frase motivacional diferente al iniciar cada sesión, **para** sentirme motivado antes de caminar.

**Criterios de aceptación:**
- [ ] `quotes.json` contiene 100 frases, servido como asset local (cacheado por SW)
- [ ] `MotivationEngine.select(recentQuoteIds)` retorna frase aleatoria excluyendo últimas 20
- [ ] `config.recentQuoteIds` se actualiza tras cada selección (rotación al llenarse)
- [ ] Overlay motivacional: full-screen `accent` background, frase grande en `canvas-dark`
- [ ] Auto-dismiss 3-4s; tap para saltar inmediatamente
- [ ] "Toca para continuar" legible en bottom-center
- [ ] `prefers-reduced-motion`: skip fade-in, show immediately
- [ ] ≥10 tests unitarios (engine) + verificación visual (overlay), 0 fallos

**Notas técnicas:** AD-18. El overlay se muestra al iniciar sesión, antes de que el usuario empiece a caminar. Métricas cuentan detrás del overlay.

### E2-S2 — AchievementEngine + 14 logros + pantalla Logros
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S4

**Como** Paul, **quiero** desbloquear logros al cumplir hitos de caminata, **para** sentir que mi progreso es reconocido.

**Criterios de aceptación:**
- [ ] Catálogo de 14 logros definido (mismo que v2 §9.2): `first_km`, `first_5km`, `first_10km`, `first_session`, `weekly_goal`, `rain_walker`, `7_days_streak`, `marathon_42km`, `speed_walker`, `early_bird`, `night_walker`, `hot_walker`, `cold_walker`, `consistency_30`
- [ ] `AchievementEngine.evaluate(session, history, achievements)` retorna logros desbloqueados en esta sesión
- [ ] Cada logro tiene: `key`, `name`, `description`, `icon` (emoji), `condition` (función booleana)
- [ ] Logro desbloqueado → celebración toast (RF-12) + persistencia en IndexedDB
- [ ] Pantalla Logros: grid 2 columnas, locked/unlocked/in-progress con progress bar
- [ ] Locked: muted + 🔒; Unlocked: accent + nombre; In-progress: progress bar
- [ ] ≥14 tests unitarios (uno por logro) + verificación visual (pantalla), 0 fallos

**Notas técnicas:** Los logros se evalúan al cierre de sesión (`finish`). Algunos dependen de historial (streak, acumulado).

### E2-S3 — GoalEngine + anillo de progreso + celebración
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S4

**Como** Paul, **quiero** ver mi progreso semanal hacia mi meta de km, **para** saber cuánto me falta y celebrar cuando la cumpla.

**Criterios de aceptación:**
- [ ] `GoalEngine.getWeeklyProgress(sessions, weeklyGoalKm, currentWeekISO)` retorna `{completedKm, goalKm, percentage, isComplete}`
- [ ] Semana ISO (lunes a domingo)
- [ ] Meta configurable en Settings (default 10 km)
- [ ] Anillo de progreso en Home: 300px, fill proporcional con `accent`
- [ ] Al cumplir (percentage ≥ 100%): ring switches to `success`, celebration toast "Meta semanal cumplida 🎉"
- [ ] Goal progress text: "X / 10 km" debajo del anillo
- [ ] ≥8 tests unitarios + verificación visual (anillo), 0 fallos

**Notas técnicas:** El goal se calcula sumando `distanceM` de sesiones de la semana ISO actual. Sesiones migradas cuentan (distancia correcta).

---

## Epic E3 — Caminata sin interrupciones

**Prioridad:** 🟡 Depende E0 | **Stories:** 2 | **FRs:** RF-05, RF-13, RNF-03

### E3-S1 — WakeLockPort + WakeLockAdapter + banner UI
**Prioridad:** Must | **Estimación:** S (1-2 días) | **Dependencias:** E0-S4

**Como** Paul, **quiero** que la pantalla se mantenga encendida durante mi caminata, **para** que el acelerómetro siga contando mis pasos.

**Criterios de aceptación:**
- [ ] `WakeLockPort.acquire()` solicita `navigator.wakeLock.request('screen')`
- [ ] `WakeLockPort.release()` libera el wake lock
- [ ] `onLost(callback)` se dispara si el wake lock se libera (p. ej. tab en background)
- [ ] `onAcquired(callback)` se dispara al adquirir exitosamente
- [ ] Si `navigator.wakeLock` no existe → callback `onLost` inmediato
- [ ] Banner wake lock: sticky top, `secondary` background, "Mantén la pantalla encendida para contar pasos"
- [ ] Banner dismissible con ×; reaparece si wake lock falla de nuevo
- [ ] ≥6 tests (mock de wakeLock) + verificación visual (banner), 0 fallos

**Notas técnicas:** AD-16. iOS Safari 16.4+ requerido (A-1).

### E3-S2 — Background→foreground handling (estimated steps banner + re-adquisición)
**Prioridad:** Must | **Estimación:** S (1-2 días) | **Dependencias:** E0-S3, E3-S1

**Como** Paul, **quiero** que al volver de background la app me muestre los pasos estimados y me permita descartarlos, **para** ser honesto con mis datos.

**Criterios de aceptación:**
- [ ] Al `visibilitychange` → foreground: tiempo recalculado por wall-clock (AD-6)
- [ ] Si sesión activa (no pausada) y gap > 0: GapEstimator calcula pasos estimados
- [ ] Banner estimated steps: "~ N pasos estimados" con botón "Descartar"
- [ ] Botón "Descartar" → stepsEstimated = 0 para este gap, banner desaparece
- [ ] Auto-dismiss banner tras 30s si no se descarta
- [ ] Wake lock se re-adquiere automáticamente (E3-S1)
- [ ] Recovery indicator: "Sesión recuperada" 3s si hay snapshot de autosave
- [ ] ≥8 tests unitarios + verificación visual (banners), 0 fallos

**Notas técnicas:** AD-13, AD-8. El gap se calcula como `now - lastVisibilityHidden`.

---

## Epic E4 — Pantallas v3 (Home, Session, Summary, History, Settings, Logros, Motion Denied)

**Prioridad:** 🟡 Depende E0-E3 | **Stories:** 8 | **FRs:** RF-01, RF-04, RF-05, RF-06, RF-09, RF-10, RF-11, RF-13, RF-16, RF-17, UI §11 completo

8 pantallas nuevas/adaptadas. Mockups Sally ya listos (`key-screens-v3.html`).

### E4-S1 — Home screen (Goal Ring + clima preview + Iniciar) [RF-10, RF-06, RF-17]
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S4, E2-S3, E1-S2

**Como** Paul, **quiero** ver mi progreso semanal y el clima al abrir la app, **para** saber dónde estoy y decidir si caminar.

**Criterios de aceptación:**
- [ ] Goal Ring 300px centrado, fill proporcional con `accent`
- [ ] Goal progress text: "X / 10 km" + progress bar
- [ ] Clima preview (temp + condición) debajo del anillo
- [ ] Botón "Iniciar caminata" full-width, `accent` background
- [ ] Iconos top-right: 🏆 (Logros), 📋 (Historial), ⚙ (Ajustes)
- [ ] Badge en ⚙ si backup overdue (RF-17)
- [ ] Visual: DESIGN.md Goal Ring, mockup key-screens-v3.html #1

### E4-S2 — Session screen (sin +1, métricas pasos, clima, controles) [RF-01, RF-04, RF-05, RF-06, RF-13]
**Prioridad:** Must | **Estimación:** L (3-4 días) | **Dependencias:** E0-S2, E0-S3, E1-S2, E2-S1, E3-S1, E3-S2

**Como** Paul, **quiero** ver mis pasos, distancia, tiempo, ritmo y cadencia en vivo mientras camino, **para** monitorear mi progreso en tiempo real.

**Criterios de aceptación:**
- [ ] Métrica hero: distancia en km (grande, `accent`)
- [ ] Sub-métricas: pasos, tiempo, ritmo, cadencia (4 columnas)
- [ ] Pasos con "~" prefix si hay estimados (color `estimated`)
- [ ] Weather Card debajo de métricas
- [ ] Status badge "● EN CURSO"
- [ ] Controles: Pausar ↔ Reanudar (toggle), Finalizar
- [ ] Estimated steps banner (si aplica, E3-S2)
- [ ] Wake lock banner (si aplica, E3-S1)
- [ ] Recovery indicator (si aplica, E3-S2)
- [ ] Visual: DESIGN.md Metric Card, mockup key-screens-v3.html #2, #3

### E4-S3 — Summary screen (stats + logros + meta progress) [RF-10, RF-11]
**Prioridad:** Must | **Estimación:** S (1-2 días) | **Dependencias:** E0-S2, E2-S2, E2-S3

**Como** Paul, **quiero** ver el resumen de mi caminata al finalizar, **para** sentir satisfacción por mi esfuerzo.

**Criterios de aceptación:**
- [ ] Header: "Caminata completada"
- [ ] Hero: distancia final (grande, `accent`)
- [ ] Stats grid 2×2: pasos medidos, pasos estimados, duración, ritmo
- [ ] Logros desbloqueados en esta sesión (horizontal scroll de badges)
- [ ] Goal progress: mini progress bar "X → Y / 10 km"
- [ ] Botón "Nueva sesión" full-width
- [ ] Sin back button — forward only
- [ ] Visual: DESIGN.md Summary Screen, mockup key-screens-v3.html #4

### E4-S4 — History screen (lista + totales + tendencia) [RF-09, RF-16]
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S4

**Como** Paul, **quiero** ver mi historial de caminatas con totales y tendencia, **para** ver cómo mi capacidad crece semana a semana.

**Criterios de aceptación:**
- [ ] Totals row: km totales, sesiones, tiempo (semana actual)
- [ ] Trend chart: 4 barras verticales (últimas 4 semanas), current en `accent`, previas en `muted`
- [ ] Lista de sesiones: fecha, distancia, duración, ritmo (descendente)
- [ ] Sesiones con estimados: "~" prefix en distancia
- [ ] Sesiones migradas: se muestran normalmente (distancia correcta)
- [ ] Empty state: "Aún no hay sesiones registradas"
- [ ] Visual: DESIGN.md History Row, mockup key-screens-v3.html #6

### E4-S5 — Settings screen (zancada, meta, sonido, export, borrar) [RF-14, RF-15, RF-17]
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S4, E2-S3, E5-S1

**Como** Paul, **quiero** ajustar mi zancada, meta semanal y exportar mi historial, **para** mantener mis datos calibrados y respaldados.

**Criterios de aceptación:**
- [ ] Campo Zancada (number, >0, default 0.655)
- [ ] Campo Meta semanal (number, >0, default 10)
- [ ] Toggle Sonido (on/off)
- [ ] Sección Export: "Último respaldo: [fecha]" + botón "Exportar historial"
- [ ] Banner backup warning si >30 días sin export
- [ ] "Borrar todos los datos" en `danger`, requiere confirmación
- [ ] Validación en save (no en input)
- [ ] Visual: DESIGN.md Settings Field, mockup key-screens-v3.html #5

### E4-S6 — Motion Denied screen [RF-02]
**Prioridad:** Must | **Estimación:** S (1 día) | **Dependencias:** E0-S1

**Como** Paul, **quiero** saber por qué la app no puede contar mis pasos si deniego el permiso, **para** poder habilitarlo manualmente.

**Criterios de aceptación:**
- [ ] Full-screen, centrado
- [ ] Icono grande (📱) en `muted`
- [ ] Título: "Sensor de movimiento requerido"
- [ ] Body: explicación en lenguaje simple + instrucciones (Configuración de Safari > Movimiento y orientación)
- [ ] Botón "Abrir Configuración" (intenta `app-settings:` URL)
- [ ] Link "Volver al inicio"
- [ ] Visual: DESIGN.md Motion Denied Screen, mockup key-screens-v3.html #9

### E4-S7 — Achievements screen (grid 2 columnas) [RF-11]
**Prioridad:** Must | **Estimación:** S (1-2 días) | **Dependencias:** E2-S2

**Como** Paul, **quiero** ver todos mis logros y cuáles me faltan, **para** saber qué metas perseguir.

**Criterios de aceptación:**
- [ ] Grid 2 columnas × 7 filas
- [ ] Cada card: icono 64px (circle), nombre, descripción
- [ ] Locked: icono `muted` + 🔒, nombre `muted`
- [ ] Unlocked: icono `accent`, nombre `text`
- [ ] In-progress: progress bar al fondo de la card
- [ ] Visual: DESIGN.md Achievement Badge, mockup key-screens-v3.html #7

### E4-S8 — Weather Card UI (snapshot en Session) [RF-06]
**Prioridad:** Must | **Estimación:** S (1 día) | **Dependencias:** E1-S2, E4-S2

**Como** Paul, **quiero** ver el clima actual en la pantalla de sesión, **para** saber las condiciones de mi caminata.

**Criterios de aceptación:**
- [ ] Weather Card muestra: temperatura grande + condición (emoji + texto)
- [ ] Fila opcional: humedad, UV, viento separados por `·`
- [ ] Si sin red o sin clima: "Sin clima" en `muted`, centrado
- [ ] Snapshot congelado al inicio de sesión (no se actualiza durante sesión)
- [ ] Card compacta — no compite con métricas principales
- [ ] Visual: DESIGN.md Weather Card

**Notas técnicas:** Se invoca al iniciar sesión (antes de mostrar Session screen). Si retorna null, se muestra "Sin clima". Movida de E1-S3 para eliminar dependencia forward.

---

## Epic E5 — Respaldo & despliegue

**Prioridad:** 🟢 Último | **Stories:** 4 | **FRs:** RF-15, RF-16, RF-17

### E5-S1 — Export CSV/JSON via Web Share API
**Prioridad:** Must | **Estimación:** S (1-2 días) | **Dependencias:** E0-S4

**Como** Paul, **quiero** exportar mi historial como CSV o JSON, **para** respaldar mis datos ante evicción de storage.

**Criterios de aceptación:**
- [ ] `ExportPort.toCsv(sessions)` genera CSV con headers: startedAt, endedAt, stepsMeasured, stepsEstimated, strideM, distanceM, durationS, paceSecPerKm, cadenceSpm, weather, quoteId, source
- [ ] `ExportPort.toJson(sessions)` genera JSON válido (importable)
- [ ] `ExportPort.share(data)` usa `navigator.share` (Web Share API)
- [ ] Si Web Share no disponible → fallback a download
- [ ] `config.lastExportAt` se actualiza tras export exitoso
- [ ] ≥6 tests, 0 fallos

**Notas técnicas:** AD-15. El JSON debe ser importable (prueba de respaldo/restauración).

### E5-S2 — Aviso respaldo >30 días
**Prioridad:** Should | **Estimación:** XS (0.5 día) | **Dependencias:** E5-S1, E4-S5

**Como** Paul, **quiero** que la app me recuerde exportar mi historial si han pasado más de 30 días, **para** no perder mis datos.

**Criterios de aceptación:**
- [ ] Si `config.lastExportAt` es null o >30 días: banner en Settings "Último respaldo: hace X días. Exporta tu historial."
- [ ] Badge en icono ⚙ de Home si backup overdue
- [ ] Banner no bloqueante; se puede dismiss
- [ ] ≥4 tests, 0 fallos

### E5-S3 — Eliminar sesiones individuales (RF-16)
**Prioridad:** Should | **Estimación:** S (1 día) | **Dependencias:** E0-S4, E4-S4

**Como** Paul, **quiero** poder eliminar sesiones individuales de mi historial, **para** limpiar sesiones de prueba o erróneas.

**Criterios de aceptación:**
- [ ] Icono 🗑️ right-aligned en cada History Row (44×44px hit area)
- [ ] Tap → confirmation dialog "¿Eliminar esta sesión?"
- [ ] Confirm → `StoragePort.deleteSession(id)`
- [ ] Cancel → no action
- [ ] Historial se actualiza tras eliminación
- [ ] ≥4 tests, 0 fallos

### E5-S4 — Revalidar GitHub Pages (subpath, SW cache)
**Prioridad:** Must | **Estimación:** S (1 día) | **Dependencias:** E4 (todas las pantallas)

**Como** Paul, **quiero** que la app funcione correctamente instalada desde GitHub Pages, **para** usarla offline en mi iPhone.

**Criterios de aceptación:**
- [ ] `sw.js` registra con `scope: "./"`
- [ ] `manifest.start_url` y `manifest.scope` son `"./"`
- [ ] Todas las rutas son relativas (`./sw.js`, `./manifest.webmanifest`, `./quotes.json`)
- [ ] `.nojekyll` presente en raíz
- [ ] Service Worker cachea: `index.html`, `domain.js`, `sw.js`, `manifest.webmanifest`, `quotes.json`, icons
- [ ] App funciona offline (modo avión) tras primera carga
- [ ] Instalable como PWA ("Agregar a pantalla de inicio")
- [ ] Deploy desde `main` vía PR (GitFlow)

---

## Dependency graph

```
E0 (Bloqueante)
├── E0-S1 StepDetector
├── E0-S2 Session aggregate
├── E0-S3 GapEstimator → E0-S1, E0-S2
├── E0-S4 IndexedDBAdapter → E0-S2
└── E0-S5 Migración D1 → E0-S2, E0-S4

E1 (Independiente tras E0 — engine only)
├── E1-S1 GeoPort → E0-S4
└── E1-S2 WeatherPort → E1-S1

E2 (Independiente tras E0)
├── E2-S1 MotivationEngine + overlay → E0-S4
├── E2-S2 AchievementEngine + Logros → E0-S4
└── E2-S3 GoalEngine + anillo → E0-S4

E3 (Depende E0)
├── E3-S1 WakeLock → E0-S4
└── E3-S2 Background handling → E0-S3, E3-S1

E4 (Depende E0-E3)
├── E4-S6 Motion Denied → E0-S1
├── E4-S1 Home → E0-S4, E2-S3, E1-S2
├── E4-S7 Achievements → E2-S2
├── E4-S4 History → E0-S4
├── E4-S5 Settings → E0-S4, E2-S3, E5-S1
├── E4-S3 Summary → E0-S2, E2-S2, E2-S3
├── E4-S2 Session → E0-S2, E0-S3, E1-S2, E2-S1, E3-S1, E3-S2
└── E4-S8 Weather Card → E1-S2, E4-S2

E5 (Último)
├── E5-S1 Export → E0-S4
├── E5-S3 Eliminar sesiones → E0-S4, E4-S4
├── E5-S2 Aviso respaldo → E5-S1, E4-S5
└── E5-S4 GitHub Pages → E4 (todas)
```

## Sprint execution order

**Fase 1 (E0 — 1-2 semanas):** E0-S1 → E0-S2 → E0-S3 → E0-S4 → E0-S5
**Fase 2 (E1+E2+E3 — 1-2 semanas, paralelo):** E1-S1→S2 | E2-S1→S2→S3 | E3-S1→S2
**Fase 3 (E4 — 1-2 semanas):** E4-S6 → E4-S1 → E4-S7 → E4-S4 → E4-S5 → E4-S3 → E4-S2 → E4-S8
**Fase 4 (E5 — 0.5 semana):** E5-S1 → E5-S3 → E5-S2 → E5-S4

> **Nota:** E4-S2 (Session screen) es la story más compleja (depende de 6 stories previas). Se deja para el final de E4 para que todo el dominio esté listo.
