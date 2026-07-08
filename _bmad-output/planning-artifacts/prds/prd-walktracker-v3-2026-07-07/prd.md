---
title: WalkTracker PWA v3.0 — Product Requirements Document
name: WalkTracker
type: prd
status: final
created: 2026-07-07
updated: 2026-07-07
sources:
  - input/SPEC_WalkTracker_v3_PWA.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/EXPERIENCE.md
  - _bmad-output/planning-artifacts/architecture/architecture-walktracker-v3-2026-07-07/ARCHITECTURE-SPINE-v3.md
  - _bmad-output/planning-artifacts/prds/prd-walktracker-2026-07-03/prd.md
companions:
  - _bmad-output/planning-artifacts/architecture/architecture-walktracker-v3-2026-07-07/ARCHITECTURE-SPINE-v3.md
---

# PRD — WalkTracker PWA v3.0

**Registro de caminatas con conteo de pasos por acelerómetro, clima, metas y motivación — bajo las restricciones del modelo PWA/iOS**

## 1. Contexto y problema

WalkTracker v1.1 es una PWA instalable en iPhone que registra sesiones de caminata mediante conteo manual de vueltas en un circuito cerrado (perímetro ~41 m). Funciona, pero requiere atención constante del usuario (contar vueltas, tocar +1).

La v2.0 define el producto objetivo (conteo automático, clima, metas, logros, motivación) sobre iOS nativo, que exige Mac + Xcode + cuenta Apple Developer + provisioning — barrera de entrada alta.

La **v3.0** es la variante PWA del mismo producto: entrega **cuánto de v2 es posible como PWA** (HTML/JS servido desde GitHub Pages, instalable vía "Agregar a pantalla de inicio"), aceptando las restricciones de la plataforma web en iOS como condiciones de frontera del diseño, no como sorpresas de implementación.

**Problema central:** el usuario quiere ver su progreso de capacidad reconocido sin la fricción del conteo manual ni la barrera de entrada de una app nativa.

## 2. Objetivo

PWA instalable en iPhone que registre sesiones de caminata con **conteo de pasos por acelerómetro** (sin conteo manual de vueltas), muestre **clima al inicio** (geolocalización one-shot + API abierta), persista localmente, gestione **meta semanal de km** y **reconocimientos**, y muestre una de **100 frases motivacionales** al iniciar cada sesión.

**Posicionamiento:** compañero de motivación para superar el sobrepeso, no un instrumento de metrología. Producto puente que valida metas, logros, frases y UX motivacional con costo de entrada cero mientras se concreta la cuenta de developer para v2 nativa.

## 3. Alcance

### In-scope (v3.0)
- Detección de pasos por acelerómetro (`DeviceMotionEvent`, foreground, pantalla activa)
- Cronómetro wall-clock con pausa explícita, sin auto-pausa
- Distancia por zancada configurable (default 0,655 m)
- Clima one-shot al inicio de sesión (Open-Meteo, sin key)
- Meta semanal de km configurable (default 10) con anillo de progreso y celebración
- Catálogo de 14 logros, evaluado al cierre de sesión
- Banco de 100 frases motivacionales, sin repetición en últimas 20
- Historial con totales semana/mes y tendencia (canvas/SVG propio, sin librerías)
- Export CSV/JSON como respaldo (Web Share API)
- Wake lock durante sesión, con re-adquisición tras background
- Feedback sonoro (Web Audio): inicio, km, meta, logro
- Recalibración de zancada in-app
- Eliminación de sesiones individuales
- Aviso de respaldo si >30 días sin export
- Migración de sesiones v1.1 existentes (cálculo inverso de pasos, marcadas `source: "migrated"`)

### Out-of-scope (v3.0)
- Backend, autenticación, multi-usuario, sincronización cloud (invariante permanente)
- GPS de ruta
- HealthKit automático (export manual + Shortcuts como alternativa)
- Conteo en background real (imposible en PWA/iOS — JS congelado)
- Conteo manual de vueltas (superado; no regresa de v1)
- Web Push (Could, diferido a v3.1)

### Invariantes permanentes (heredados de v1)
- **No-backend / localStorage / IndexedDB es invariante de arquitectura**, no un trade-off de v3.
- **Cero build, cero CDN en runtime** — vanilla JS, archivos locales.
- **Producto estrictamente personal** — un solo usuario (Paul).

## 4. User persona

**Paul** — usuario único, camina en circuito cerrado y abierto, quiere ver su progreso reconocido. Usa iPhone. Valora la precisión sobre la aproximación GPS. Quiere motivación, no métricas frías.

## 5. Requisitos funcionales

| ID | Requisito | Prioridad | Fuente |
|---|---|---|---|
| RF-01 | Iniciar/pausar/finalizar sesión; cronómetro wall-clock, pausa explícita, sin auto-pausa | Must | SPEC RF-01 |
| RF-02 | Detección de pasos por acelerómetro (`DeviceMotionEvent` + detección de picos con umbral y ventana anti-rebote), con solicitud de permiso (`DeviceMotionEvent.requestPermission()`, iOS 13+) | Must | SPEC RF-02 |
| RF-03 | Distancia = pasos × zancada configurada (default 0,655 m) | Must | SPEC RF-03 |
| RF-04 | Métricas en vivo: pasos, distancia, tiempo, ritmo, cadencia | Must | SPEC RF-04 |
| RF-05 | Manejo de background: al volver a foreground, tiempo recalculado por wall-clock; gap de pasos extrapolado por cadencia media de sesión, marcado como estimado ("~"), descartable | Must | SPEC RF-05 |
| RF-06 | Clima al iniciar: Geolocation one-shot → Open-Meteo (temp, sensación, condición, humedad, UV, viento) congelado como snapshot; sin red → sesión inicia sin clima | Must | SPEC RF-06 |
| RF-07 | Frase motivacional aleatoria al iniciar (banco de 100, sin repetición en últimas 20) | Must | SPEC RF-07 |
| RF-08 | Persistencia local de sesiones: fecha, pasos (reales + estimados desglosados), distancia, duración, ritmo, clima, frase | Must | SPEC RF-08 |
| RF-09 | Historial con totales semana/mes y tendencia simple (canvas/SVG propio, sin librerías) | Must | SPEC RF-09 |
| RF-10 | Meta semanal de km configurable (default 10) con anillo de progreso y celebración al cumplir | Must | SPEC RF-10 |
| RF-11 | Catálogo de logros (14 logros), evaluado al cierre de sesión, con celebración visual+sonora | Must | SPEC RF-11 |
| RF-12 | Feedback sonoro (Web Audio): inicio de sesión, cada km, meta cumplida, logro desbloqueado. Volumen respetuoso con música en reproducción | Must | SPEC RF-12 |
| RF-13 | Wake Lock activado automáticamente durante sesión, con re-adquisición al volver de background | Must | SPEC RF-13 |
| RF-14 | Recalibración de zancada in-app; sesiones cerradas conservan su zancada congelada | Must | SPEC RF-14 |
| RF-15 | Export CSV/JSON vía Web Share API — también actúa como respaldo ante evicción de storage | Must | SPEC RF-15 |
| RF-16 | Eliminar sesiones individuales | Should | SPEC RF-16 |
| RF-17 | Aviso in-app de respaldo sugerido si >30 días sin export | Should | SPEC RF-17 |
| RF-18 | Web Push: recordatorio semanal de meta (PWA instalada, iOS 16.4+) | Could | SPEC RF-18 |

### Notas de validación cruzada

- **RF-02** validado contra UX: pantalla Motion Denied si permiso denegado (EXPERIENCE.md Flow 6). Validado contra Architecture: AD-12 StepDetector puro, 60 Hz fijo.
- **RF-05** validado contra UX: banner "~ N pasos estimados" con botón "Descartar" (DESIGN.md Estimated Steps Banner). Validado contra Architecture: AD-13 GapEstimator, cadencia solo sobre tramos medidos.
- **RF-06** validado contra UX: Weather Card en Session, "Sin clima" si sin red (DESIGN.md Weather Card). Validado contra Architecture: AD-14 Open-Meteo sin key, timeout 3s.
- **RF-10** validado contra UX: Goal Ring 300px en Home, celebración toast no-bloqueante (DESIGN.md Goal Ring, Celebration Toast).
- **RF-11** validado contra UX: pantalla Logros grid 2 columnas, locked/unlocked (DESIGN.md Achievement Badge).
- **RF-13** validado contra UX: banner wake lock fallido en secondary (DESIGN.md Wake Lock Banner). Validado contra Architecture: AD-16 WakeLock re-adquisición.
- **RF-15** validado contra UX: export en Settings con fecha último respaldo (DESIGN.md Settings Field). Validado contra Architecture: AD-15 Export como respaldo Must.

## 6. Requisitos no funcionales

| ID | Requisito | Fuente |
|---|---|---|
| RNF-01 | **Offline-first:** todo offline excepto clima (degrada limpio). Service Worker con cache de app shell + quotes.json. | SPEC RNF-01 |
| RNF-02 | **Persistencia:** IndexedDB para sesiones (histórico crece), localStorage para config. `navigator.storage.persist()` al instalar. Export periódico como respaldo real. | SPEC RNF-02 |
| RNF-03 | **Resiliencia:** autosave cada 10s y en cada `visibilitychange`; recuperación silenciosa por wall-clock al reabrir. "Sesión recuperada" indicator 3s. | SPEC RNF-03 |
| RNF-04 | **Procesamiento de sensores:** pipeline de detección de pasos a ≤60 Hz con filtro paso-bajo + detección de picos; presupuesto CPU compatible con 60 min sin degradar batería. | SPEC RNF-04 |
| RNF-05 | **Cero build:** `index.html` + `domain.js` + `sw.js` + `manifest.webmanifest` + `quotes.json`. Sin frameworks, sin CDN en runtime. Rutas relativas para subpath GitHub Pages. | SPEC RNF-05 |
| RNF-06 | **Privacidad:** datos en dispositivo; única llamada de red: API de clima (sin key, coordenadas redondeadas a 2 decimales). | SPEC RNF-06 |
| RNF-07 | **UX:** viewport iPhone, targets ≥44 pt, claro/oscuro por `prefers-color-scheme`, dirección visual v3 (celebrar, nunca culpar; números grandes; momento motivacional 3-4s saltable). | SPEC RNF-07 |

## 7. Modelo de datos

### localStorage

```json
// wt:config
{
  "strideM": 0.655,
  "weeklyGoalKm": 10.0,
  "soundEnabled": true,
  "recentQuoteIds": [47, 12, 88, ...],  // últimas 20
  "lastExportAt": "2026-07-01T14:30:00Z"
}

// wt:activeSession (snapshot para recuperación)
{
  "startedAtMs": 1720357800000,
  "stepsMeasured": 2450,
  "stepsEstimated": 0,
  "totalPausesMs": 60000,
  "paused": false,
  "strideM": 0.655,
  "weather": { "tempC": 14.2, "feelsLikeC": 12.8, "condition": "Parcialmente nublado", ... },
  "quoteId": 47
}

// wt:migrated → "v3" (flag idempotencia migración D1)
```

### IndexedDB

```json
// store "sessions"
{
  "id": "uuid",
  "startedAt": "2026-07-07T08:30:00Z",
  "endedAt": "2026-07-07T09:15:00Z",
  "stepsMeasured": 4980,
  "stepsEstimated": 320,
  "strideM": 0.655,
  "distanceM": 3471.5,
  "durationS": 3720,
  "pausesS": 180,
  "paceSecPerKm": 1020,
  "cadenceSpm": 84.2,
  "weather": { "tempC": 14.2, "feelsLikeC": 12.8, "condition": "Parcialmente nublado", "humidityPct": 71, "uvIndex": 6, "windKmh": 9.4, "capturedAt": "2026-07-07T08:30:00Z" },
  "quoteId": 47,
  "source": "v3"  // o "migrated" para sesiones v1.1 migradas
}

// store "achievements"
{ "key": "first_km", "unlockedAt": "2026-07-07T09:15:00Z", "progress": 1.0 }
```

### Migración v1.1 → v3 (D1)

Sesiones v1.1 existentes en `localStorage["wt:sessions"]` se migran una sola vez (flag `wt:migrated`):
- `stepsMeasured = round(distanceM / strideM)` (estimación inversa)
- `stepsEstimated = 0`
- `strideM = lapPerimeterM / stepsPerLap` (reconstruido)
- `source: "migrated"`
- `distanceM`, `durationS`, `paceSecPerKm`, `pausesS`, `startedAt`, `endedAt` se conservan

**Reglas de uso:**
- Sesiones migradas **sí cuentan** para GoalEngine (distancia semanal) y AchievementEngine (km acumulados).
- Sesiones migradas **no se incluyen** en cálculo de `cadenceSpm` (no hay tramos medidos reales).
- Se muestran en historial con distancia/tiempo/ritmo correctos.

## 8. Cálculos

| Cálculo | Fórmula | Condición |
|---|---|---|
| Distancia | `distanceM = (stepsMeasured + stepsEstimated) × strideM` | Siempre |
| Tiempo transcurrido | `elapsedS = (now − startedAt) − totalPausesS` | Wall-clock (AD-6) |
| Ritmo | `paceSecPerKm = elapsedS / (distanceM/1000)` | Solo si `distanceM ≥ 100` |
| Cadencia | `cadenceSpm = stepsMeasured / minutosConSensorActivo` | Solo sobre tramos medidos |
| Gap background | `stepsEstimated += cadenceSpm × (gapS/60)` | Sesión activa, muestra ≥120s |

## 9. Criterios de aceptación

- [ ] Caminata de 10 min con teléfono en mano y pantalla activa: pasos detectados con error ≤10% vs conteo del iPhone (app Salud como referencia)
- [ ] Sesión iniciada → cambio a app de música 5 min → volver: tiempo exacto (wall-clock); gap de pasos extrapolado, marcado "~" y descartable
- [ ] Cierre forzado de Safari en sesión activa → al reabrir, sesión recuperada (tiempo correcto; pasos del gap tratados como background)
- [ ] Con red: snapshot de clima visible; en modo avión: sesión inicia sin clima y todo lo demás funciona
- [ ] Frase motivacional sin repetición en 20 sesiones consecutivas
- [ ] Cruce de km y desbloqueo de "Tu primer kilómetro" con celebración sonora/visual
- [ ] Anillo de meta semanal correcto sobre semana ISO
- [ ] Wake lock activo en sesión; se re-adquiere tras volver de background
- [ ] Instalada desde GitHub Pages (subpath de proyecto), funciona offline
- [ ] Export CSV abre en Numbers/Excel; import posterior del JSON restaura el historial
- [ ] Historial sobrevive reinicio del dispositivo con `storage.persist()` concedido
- [ ] Sesiones v1.1 migradas se muestran en historial con datos correctos (distancia, tiempo, ritmo)
- [ ] Sesiones migradas no afectan cálculo de cadencia de sesiones v3

## 10. Open Questions

| # | Pregunta | Impacto | Estado |
|---|---|---|---|
| OQ-1 | ¿Umbral adaptativo exacto del StepDetector? (ventana deslizante, α del filtro) | Implementación | → Decisión de Amelia durante E0 |
| OQ-2 | ¿Cache-busting / versionado de `sw.js` al publicar nuevas versiones? | Infra | → Diferido (mismo problema que v1) |
| OQ-3 | ¿Calibración interactiva de zancada (caminar N pasos para medir automáticamente)? | Producto futuro | → Fuera de scope v3.0 |
| OQ-4 | ¿Web Push (RF-18) se promueve a Should en v3.1? | Producto | → Decisión de Paul en v3.1 planning |

## 11. Assumptions

| # | Suposición | Riesgo | Mitigación |
|---|---|---|---|
| A-1 | Paul tiene iOS 16.4+ (requerido para Wake Lock y Web Push) | Si iOS < 16.4, wake lock no funciona | Banner persistente como mitigación (AD-16) |
| A-2 | Open-Meteo estará disponible durante el desarrollo y uso | Sin SLA | Timeout 3s + degradación a "sin clima" (AD-14) |
| A-3 | El dispositivo de Paul tiene sensor de acelerómetro funcional | Si no, app no opera | Pantalla Motion Denied con instrucciones (UX) |
| A-4 | Paul mantendrá la pantalla activa durante caminatas (teléfono en mano o soporte) | Si no, pasos no detectados | Wake lock banner + producto puente hacia v2 nativa |
| A-5 | Las sesiones v1.1 de Paul tienen datos válidos (distanceM > 0, strideM > 0) | Si datos corruptos, migración falla | Validación pre-migración; sesiones inválidas se marcan `source: "corrupt"` y se excluyen |

## 12. Métricas de éxito

| Métrica | Target | Cómo medir |
|---|---|---|
| Precisión de pasos | ≤10% error vs app Salud | Prueba manual de 10 min (criterio de aceptación #1) |
| Tasa de recuperación | 100% de sesiones recuperadas tras cierre forzado | Criterio de aceptación #3 |
| Tasa de export | >50% de usuarios exportan al menos una vez en 30 días | `config.lastExportAt` (RF-17) |
| Satisfacción motivacional | Paul reporta sentirse reconocido al ver progreso | Feedback cualitativo (producto personal) |

## 13. Dependencias y riesgos

| Dependencia | Tipo | Estado |
|---|---|---|
| SPEC v3 PWA | Input | ✅ Draft para aprobación |
| UX Design v3 | Input | ✅ Final |
| Architecture v3 | Input | ✅ Final |
| Migración datos v1.1 | Riesgo | ✅ Decisión D1 aprobada |
| iOS Safari 16.4+ | Plataforma | ⚠️ Asumido (A-1) |
| Open-Meteo API | Externa | ⚠️ Sin SLA (A-2) |

## 14. Roadmap de epics (propuesto)

| Epic | Contenido | FRs | Prioridad | Dependencia |
|---|---|---|---|---|
| **E0** | Conteo automático de pasos: Session (stepsMeasured/Estimated), StepDetector, GapEstimator, IndexedDBAdapter, migración D1 | RF-02, RF-03, RF-05, RF-08, RF-14, RNF-02 | 🔴 Bloqueante | — |
| **E1** | Clima: GeoPort + GeolocationAdapter, WeatherPort + OpenMeteoAdapter (engine only; UI en E4-S8) | RF-06 | 🟡 Independiente | E0 (StoragePort) |
| **E2** | Motivación: MotivationEngine (100 frases), AchievementEngine (14 logros), GoalEngine (meta semanal) | RF-07, RF-10, RF-11, RF-12 | 🟡 Independiente | E0 (StoragePort) |
| **E3** | Caminata sin interrupciones: WakeLock + re-adquisición, extrapolación gaps UI "~" | RF-05, RF-13, RNF-03 | 🟡 Depende E0 | E0 |
| **E4** | UX v3 pantallas: Home (anillo+clima), Session (sin +1), Summary, Logros, Motivación overlay, History (tendencia), Settings, Motion Denied | UI §11 completo | 🟡 Depende E0-E3 | E0, E1, E2, E3 |
| **E5** | Respaldo & despliegue: Export CSV/JSON Must, aviso >30 días, revalidar GitHub Pages | RF-15, RF-16, RF-17 | 🟢 Último | E0, E4 |

## 15. Release criteria

- [ ] Todos los criterios de aceptación (§9) verificados
- [ ] PRD, UX, Architecture, Epics alineados (implementation readiness check)
- [ ] Migración D1 probada con datos reales de Paul (si existen sesiones v1.1)
- [ ] Deploy a GitHub Pages desde `main` vía PR (GitFlow)
- [ ] Paul aprueba el producto en su iPhone (instalable, offline, funcional)
