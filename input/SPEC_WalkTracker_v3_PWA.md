# SPEC — WalkTracker PWA v3.0
**Registro de caminatas con conteo de pasos por acelerómetro, clima, metas y motivación — bajo las restricciones del modelo PWA/iOS**
Fecha: 2026-07-07 · Autor: Paul Alarcón · Estado: Draft para aprobación
Relación: hereda producto de v2.0 (nativa iOS) y plataforma de v1.0 (PWA). **No reemplaza a v2**: es la variante PWA del mismo producto, con capacidades degradadas de forma explícita y documentada.

---

## 1. Contexto y motivación

La v2.0 define el producto objetivo (conteo automático, clima, metas, logros, motivación) sobre iOS nativo, que exige Mac + Xcode + cuenta Apple Developer + provisioning. La v3.0 explora **cuánto de ese producto es entregable como PWA** (HTML/JS servido desde GitHub Pages, instalable vía "Agregar a pantalla de inicio"), aceptando las restricciones de la plataforma web en iOS como **condiciones de frontera del diseño**, no como sorpresas de implementación.

## 2. Matriz de restricciones (PWA/iOS) — gobierna todo el spec

| # | Capacidad en v2 nativa | Disponibilidad en PWA/iOS | Estrategia v3 |
|---|------------------------|---------------------------|---------------|
| R1 | CMPedometer (pasos/distancia del coprocesador, 24/7) | ❌ Inexistente | Detección de pasos por acelerómetro (`DeviceMotionEvent`) procesada en JS, **solo en foreground con pantalla activa** (ADR-13) |
| R2 | Reconstrucción en background por query (música) | ❌ Imposible: JS congelado en background, sin acceso a histórico de sensores | Wall-clock preserva el **tiempo**; los **pasos** del intervalo en background se pierden → extrapolación por cadencia, marcada como estimada (ADR-14) |
| R3 | WeatherKit | ❌ | Geolocation API (one-shot) + API de clima abierta sin key (Open-Meteo). Requiere red; degrada a "sin clima" (ADR-15) |
| R4 | HealthKit (workout sync) | ❌ Sin acceso desde Safari/PWA | Export CSV/JSON + Atajo de Shortcuts (ruta v1 §10); Health queda fuera del flujo automático |
| R5 | CoreHaptics | ❌ `navigator.vibrate` no existe en iOS Safari | Feedback **sonoro** (Web Audio API) como canal primario de confirmación |
| R6 | SwiftData (storage garantizado) | ⚠️ localStorage/IndexedDB **evictable** por iOS en PWAs sin uso | `navigator.storage.persist()` + export como respaldo periódico sugerido in-app (ADR-16) |
| R7 | Live Activity / Dynamic Island | ❌ | Sin equivalente; wake lock mantiene la pantalla como "live view" |
| R8 | Distancia estimada por el sistema | ❌ | Distancia = pasos detectados × zancada configurada → **vuelve la calibración de zancada** (única medición manual que regresa; el conteo de vueltas de v1 NO regresa) |
| R9 | Ejecución garantizada de timers | ⚠️ Timers congelados en background | Cronómetro wall-clock (ADR-05, heredado y vigente) |
| R10 | Web Push (recordatorio de meta) | ✅ Disponible en iOS 16.4+ para PWA instalada | Opcional (Could): recordatorio semanal de meta |

**Consecuencia de producto (decisión consciente):** en v3, la sesión de calidad exige **teléfono con pantalla encendida** (wake lock) durante la caminata — p. ej. en la mano o en soporte. El caso "teléfono en el bolsillo con música sonando" degrada a tiempo exacto + pasos estimados. Este es el costo estructural de la plataforma y el argumento central a favor de v2 nativa a largo plazo.

## 3. Objetivo

PWA instalable en iPhone que registre sesiones de caminata con **conteo de pasos por acelerómetro** (sin conteo manual de vueltas), muestre **clima al inicio** (geolocalización one-shot + API abierta), persista localmente, gestione **meta semanal de km** y **reconocimientos**, y muestre una de **100 frases motivacionales** al iniciar cada sesión. Mismo posicionamiento de producto que v2: compañero de motivación para superar el sobrepeso, no un instrumento de metrología.

## 4. Alcance

**In-scope (v3.0):** detección de pasos por acelerómetro, cronómetro wall-clock con pausa explícita, distancia por zancada configurada, clima one-shot, metas semanales, catálogo de logros (§9 de v2, reutilizado), banco de 100 frases (Apéndice A de v2, reutilizado), historial con totales y tendencia, export CSV/JSON, wake lock, feedback sonoro.

**Out-of-scope (v3.0):** backend/auth/cloud (invariante permanente), GPS de ruta, HealthKit automático (R4), conteo en background real (R2 — imposible, no diferido), conteo manual de vueltas (superado; no regresa de v1).

## 5. Requisitos funcionales

| ID | Requisito | Prioridad |
|----|-----------|-----------|
| RF-01 | Iniciar/pausar/finalizar sesión; cronómetro wall-clock, pausa explícita, sin auto-pausa (ADR-05) | Must |
| RF-02 | **Detección de pasos por acelerómetro** (`DeviceMotionEvent` + detección de picos con umbral y ventana anti-rebote), con solicitud de permiso (`DeviceMotionEvent.requestPermission()`, iOS 13+) | Must |
| RF-03 | Distancia = pasos × zancada configurada (default 0,655 m — dato validado en campo en v1) | Must |
| RF-04 | Métricas en vivo: pasos, distancia, tiempo, ritmo, cadencia | Must |
| RF-05 | **Manejo de background**: al volver a foreground (`visibilitychange`), el tiempo se recalcula por wall-clock; el gap de pasos se **extrapola por cadencia media de la sesión** y se marca como estimado (ADR-14), con opción de descartar la estimación | Must |
| RF-06 | Clima al iniciar: Geolocation one-shot → Open-Meteo (temp, sensación, condición, humedad, UV, viento) congelado como snapshot; sin red → sesión inicia sin clima | Must |
| RF-07 | Frase motivacional aleatoria al iniciar (banco de 100, sin repetición en las últimas 20) | Must |
| RF-08 | Persistencia local de sesiones: fecha, pasos (reales + estimados desglosados), distancia, duración, ritmo, clima, frase | Must |
| RF-09 | Historial con totales semana/mes y tendencia simple (canvas/SVG propio, sin librerías — RNF-05) | Must |
| RF-10 | Meta semanal de km configurable (default 10) con anillo de progreso y celebración al cumplir | Must |
| RF-11 | Catálogo de logros de v2 §9.2 completo (14 logros), evaluado al cierre de sesión, con celebración visual+sonora | Must |
| RF-12 | **Feedback sonoro** (Web Audio): inicio de sesión, cada km, meta cumplida, logro desbloqueado. Volumen respetuoso con música en reproducción (ducking no disponible: sonidos cortos) | Must |
| RF-13 | Wake Lock (`navigator.wakeLock`) activado automáticamente durante la sesión, con re-adquisición al volver de background | Must |
| RF-14 | Recalibración de zancada in-app; sesiones cerradas conservan su zancada congelada (ADR-03 heredado) | Must |
| RF-15 | Export CSV/JSON vía share sheet (Web Share API) — también actúa como **respaldo** ante evicción de storage (R6) | Must |
| RF-16 | Eliminar sesiones individuales | Should |
| RF-17 | Aviso in-app de respaldo sugerido si han pasado >30 días sin export (mitigación R6) | Should |
| RF-18 | Web Push: recordatorio semanal de meta (PWA instalada, iOS 16.4+) | Could |

## 6. Requisitos no funcionales

- **RNF-01 Offline-first:** todo offline excepto clima (degrada limpio). Service Worker con cache de app shell.
- **RNF-02 Persistencia:** IndexedDB para sesiones (histórico crece con pasos estimados desglosados), localStorage para config. `navigator.storage.persist()` solicitado al instalar. El export periódico es el respaldo real (ADR-16).
- **RNF-03 Resiliencia:** autosave de sesión activa cada 10 s y en cada `visibilitychange`; recuperación silenciosa por wall-clock al reabrir (herencia v1 RNF-03).
- **RNF-04 Procesamiento de sensores:** pipeline de detección de pasos a ≤60 Hz con filtro paso-bajo + detección de picos; presupuesto de CPU compatible con 60 min de sesión sin degradar batería de forma notoria.
- **RNF-05 Cero build:** un `index.html` autocontenido + `sw.js` + `manifest.webmanifest` (herencia v1 RNF-05/07). Sin frameworks, sin CDN en runtime. Rutas relativas para subpath de GitHub Pages.
- **RNF-06 Privacidad:** datos en dispositivo; única llamada de red: API de clima (sin key, sin cuenta, coordenadas redondeadas a 2 decimales antes de enviar).
- **RNF-07 UX:** viewport iPhone, targets ≥44 pt, claro/oscuro por `prefers-color-scheme`, dirección visual de v2 §10 adaptada (celebrar, nunca culpar; números grandes; momento motivacional de 3–4 s saltable).

## 7. Arquitectura

Hexagonal-lite en un archivo (herencia v1 §6), con el dominio compartiendo conceptos con v2 (mismo lenguaje ubicuo: Session, GoalEngine, AchievementEngine, MotivationEngine):

```
┌──────────────────────────────────────────────┐
│  UI Layer (DOM handlers, render, screens)    │
├──────────────────────────────────────────────┤
│  Domain (puro, testeable)                    │
│  · Session (aggregate root)                  │
│  · Chronometer (wall-clock + pausas)         │
│  · StepDetector (picos sobre |a|, estado     │
│    puro: recibe muestras, emite pasos)       │
│  · GapEstimator (extrapolación por cadencia) │
│  · GoalEngine · AchievementEngine            │
│  · MotivationEngine                          │
├──────────────────────────────────────────────┤
│  Ports/Adapters                              │
│  · MotionPort    → DeviceMotionAdapter       │
│  · GeoPort       → GeolocationAdapter        │
│  · WeatherPort   → OpenMeteoAdapter          │
│  · StoragePort   → IndexedDBAdapter          │
│  · AudioPort     → WebAudioAdapter           │
│  · WakeLockPort  → WakeLockAdapter           │
│  · ExportPort    → CsvAdapter/JsonAdapter    │
│  · ClockPort     → SystemClockAdapter        │
└──────────────────────────────────────────────┘
```

**Decisiones (mini-ADRs v3):**

- **ADR-13:** **Detección de pasos por acelerómetro en foreground como única fuente de pasos reales.** Pipeline: magnitud de aceleración → filtro paso-bajo → detección de picos con umbral adaptativo y ventana refractaria (~300 ms, cadencia máx ~200 spm). El `StepDetector` es dominio puro (recibe muestras, emite eventos) → testeable con trazas grabadas. *Trade-off:* precisión inferior al coprocesador (±5–10% típico según posición del teléfono) y **requiere pantalla activa**; aceptado porque el producto mide tendencia y motivación, no metrología (coherente con ADR-08 de v2).
- **ADR-14:** **Extrapolación por cadencia para gaps de background, siempre marcada.** `pasosEstimados = cadenciaMediaSesión × minutosDeGap` (solo si la sesión no estaba pausada y hay ≥2 min de muestra previa). Los pasos estimados se almacenan **desglosados** (`stepsMeasured` + `stepsEstimated`), se muestran con distintivo ("~") y el usuario puede descartarlos al volver. *Razón:* honestidad del dato sobre conveniencia; nunca mezclar medición con estimación de forma opaca. *Trade-off:* complejidad de UI; aceptado — es la diferencia entre una app confiable y una que "inventa".
- **ADR-15:** **Open-Meteo como proveedor de clima.** *Razón:* sin API key, sin cuenta, sin costo, CORS abierto — coherente con cero backend y cero secretos en un cliente estático público (una key en JS de GitHub Pages sería pública de facto). *Trade-off:* sin SLA; mitigado con timeout de 3 s y degradación a "sin clima".
- **ADR-16:** **Export como mecanismo de respaldo de primera clase.** iOS puede purgar storage de PWAs (R6); `storage.persist()` ayuda pero no garantiza. El export CSV/JSON pasa de "nice to have" (v1 RF-10 Should) a **Must**, con recordatorio a los 30 días (RF-17). *Trade-off:* responsabilidad de respaldo en el usuario; explícito y comunicado in-app.
- **ADR-05 (heredado, vigente):** cronómetro wall-clock, pausa explícita únicamente.
- **ADR-03 (heredado, adaptado):** sesiones cerradas inmutables; congelan la **zancada** vigente al cierre.
- **ADR-11 (heredado):** frases en bundle JSON, selección sin repetición reciente (últimas 20).

## 8. Modelo de datos

```json
// localStorage["wt:config"]
{ "strideM": 0.655, "weeklyGoalKm": 10.0, "soundEnabled": true,
  "recentQuoteIds": [], "lastExportAt": "ISO8601|null" }

// IndexedDB store "sessions" — inmutables al cierre
{
  "id": "uuid",
  "startedAt": "ISO8601", "endedAt": "ISO8601",
  "stepsMeasured": 4980,          // acelerómetro (ADR-13)
  "stepsEstimated": 320,          // gaps de background (ADR-14); 0 si no hubo o se descartó
  "strideM": 0.655,               // congelada al cierre (ADR-03)
  "distanceM": 3471.5,            // (measured+estimated) × strideM, cacheada
  "durationS": 3720, "pausesS": 180,
  "paceSecPerKm": 1020, "cadenceSpm": 84.2,
  "weather": { "tempC": 14.2, "feelsLikeC": 12.8, "condition": "Parcialmente nublado",
               "humidityPct": 71, "uvIndex": 6, "windKmh": 9.4, "capturedAt": "ISO8601" },
  "quoteId": 47
}

// IndexedDB store "achievements"
{ "key": "first_km", "unlockedAt": "ISO8601|null", "progress": 0.0 }

// localStorage["wt:activeSession"] — snapshot para recuperación (RNF-03)
```

## 9. Cálculos (dominio)

- `distanceM = (stepsMeasured + stepsEstimated) × strideM`.
- `elapsedS = (now − startedAt) − totalPausesS` (wall-clock).
- `paceSecPerKm = elapsedS / (distanceM/1000)` — solo si `distanceM ≥ 100`.
- `cadenceSpm = stepsMeasured / (minutosConSensorActivo)` — la cadencia se calcula **solo sobre tramos medidos** (nunca sobre estimados, evita realimentar la estimación).
- Gap de background (ADR-14): `stepsEstimated += cadenceSpm × (gapS/60)` si sesión activa (no pausada) y `muestraPrevia ≥ 120 s`; en caso contrario, gap = 0 pasos y se informa.
- Meta, hitos de km y logros: idénticos a v2 §8–§9 (mismo dominio).

## 10. Metas, logros y motivación

Se reutilizan íntegros de v2: meta semanal (§9.1), catálogo de 14 logros (§9.2 — `rain_walker` sigue funcionando con el snapshot de Open-Meteo) y el banco de 100 frases (Apéndice A de v2, empaquetado como `quotes.json` en el bundle). Única adaptación: las celebraciones usan sonido + animación (sin háptica, R5).

## 11. UI — Pantallas

1. **Home/Sesión:** anillo de meta semanal + "Iniciar caminata"; en sesión: pasos (con "~" si hay estimados), distancia, tiempo, ritmo, clima, controles. Banner persistente si el wake lock falla ("mantén la pantalla encendida para contar pasos").
2. **Momento motivacional:** overlay de 3–4 s con la frase (saltable con tap).
3. **Historial:** lista + totales + tendencia; sesiones con pasos estimados marcadas.
4. **Logros:** grid de medallas (idéntico concepto a v2).
5. **Ajustes:** zancada, meta semanal, sonido, exportar (con fecha del último respaldo), borrar datos.

## 12. Permisos

| Permiso | Uso | Si se deniega |
|---------|-----|---------------|
| Motion (`DeviceMotionEvent.requestPermission`) | Conteo de pasos (núcleo) | La app no puede operar → pantalla explicativa |
| Geolocation (one-shot) | Clima al inicio | Sesión sin clima |
| Notificaciones (RF-18, opcional) | Recordatorio de meta | Sin recordatorios |

## 13. Criterios de aceptación (v3.0)

- [ ] Caminata de 10 min con teléfono en mano y pantalla activa: pasos detectados con error ≤10% vs conteo del iPhone (app Salud como referencia)
- [ ] Sesión iniciada → cambio a app de música 5 min → volver: tiempo exacto (wall-clock); gap de pasos extrapolado, marcado "~" y descartable
- [ ] Cierre forzado de Safari en sesión activa → al reabrir, sesión recuperada (tiempo correcto; pasos del gap tratados como background)
- [ ] Con red: snapshot de clima visible; en modo avión: sesión inicia sin clima y todo lo demás funciona
- [ ] Frase motivacional sin repetición en 20 sesiones consecutivas
- [ ] Cruce de km y desbloqueo de "Tu primer kilómetro" con celebración sonora/visual
- [ ] Anillo de meta semanal correcto sobre semana ISO
- [ ] Wake lock activo en sesión; se re-adquiere tras volver de background
- [ ] Instalada desde GitHub Pages (subpath de proyecto), funciona offline
- [ ] Export CSV abre en Numbers/Excel; import posterior del JSON restaura el historial (prueba de respaldo/restauración)
- [ ] Historial sobrevive reinicio del dispositivo con `storage.persist()` concedido

## 14. Comparativa de cierre — v3 PWA vs v2 nativa

| Dimensión | v3 PWA | v2 nativa |
|-----------|--------|-----------|
| Pasos | Acelerómetro JS, pantalla activa, ±5–10% | Coprocesador, 24/7, precisión del sistema |
| Música en paralelo | Tiempo sí; pasos estimados | Todo exacto (reconstrucción por query) |
| Clima | Open-Meteo (red) | WeatherKit |
| Health | Export manual + Shortcuts | Sync automático (workout) |
| Feedback | Sonido | Háptica + sonido |
| Storage | Evictable (export = respaldo) | Garantizado (SwiftData) |
| Costo de entrada | $0, deploy inmediato (GitHub Pages) | Mac + Xcode + cuenta developer |
| Time-to-first-walk | Días | Semanas |

**Recomendación de arquitectura:** v3 como **producto puente** — valida metas, logros, frases y UX motivacional con costo de entrada cero mientras se concreta la cuenta de developer; el dominio (GoalEngine, AchievementEngine, MotivationEngine, catálogo de logros, frases) está diseñado con el mismo lenguaje ubicuo que v2, de modo que la migración a nativa es un cambio de adaptadores, no de modelo.

## 15. Despliegue

Herencia completa de v1 §13: GitHub Pages, HTTPS, rutas relativas (`./sw.js`, `./manifest.webmanifest`, `start_url: "./"`), `.nojekyll`, deploy por merge a `main` vía PR (GitFlow, sin push directo).

## Apéndice A

El banco de 100 frases motivacionales se reutiliza sin cambios desde SPEC v2.0 — Apéndice A (`quotes.json` en el bundle, ADR-11).
