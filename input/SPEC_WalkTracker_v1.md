# SPEC — WalkTracker PWA v1.0
**Contador de vueltas y registro de caminatas sin GPS**
Fecha: 2026-07-03 · Autor: Paul Alarcón · Estado: Draft para aprobación

---

## 1. Contexto y problema

El registro de caminatas en circuitos cerrados pequeños (perímetro ~41 m, medido: 62 pasos × 0,655 m) mediante apps basadas en GPS (Adidas Running) produce errores de distancia del 8–10% por limitaciones físicas del GPS (precisión 3–5 m, filtrado Kalman agresivo en nubes de puntos densas, multipath). Se requiere un mecanismo de medición determinístico basado en conteo de vueltas con perímetro calibrado.

## 2. Objetivo

PWA instalable en iPhone (Safari → "Agregar a pantalla de inicio") que permita registrar sesiones de caminata mediante conteo manual de vueltas, con cálculo de distancia, ritmo y persistencia local del historial. Cero dependencia de GPS, red o backend.

## 3. Alcance

**In-scope (v1):** contador de vueltas, cronómetro de sesión, cálculo de métricas en vivo, calibración configurable, historial de sesiones, exportación de datos.
**Out-of-scope (permanente — producto estrictamente personal):** backend, autenticación, multi-usuario, sincronización cloud, GPS. (HealthKit imposible desde PWA; ver §10.) El modelo **no-backend / localStorage es un invariante de arquitectura**, no un trade-off de v1.

## 4. Requisitos funcionales

| ID | Requisito | Prioridad |
|----|-----------|-----------|
| RF-01 | Iniciar/pausar/finalizar sesión con cronómetro (pausa **explícita** solo vía botón; sin auto-pausa, ADR-05) | Must |
| RF-02 | Botón de vuelta (+1) de área grande (≥40% viewport), operable sin mirar | Must |
| RF-03 | Botón deshacer (−1) para correcciones | Must |
| RF-04 | Métricas en vivo: vueltas, distancia (m/km), tiempo, ritmo (min/km) | Must |
| RF-05 | Calibración: perímetro por vuelta **derivado** de `strideM × stepsPerLap` (default: 0,655 m × 62 = 40,61 m) | Must |
| RF-06 | Persistencia de sesiones finalizadas (fecha, vueltas, distancia, duración, ritmo) | Must |
| RF-07 | Historial con lista de sesiones y totales acumulados | Must |
| RF-08 | **Feedback sonoro al marcar vuelta** (beep vía Web Audio API) — **Must en v1.0**, fiabiliza el "sin mirar" del RF-02. Háptico descartado: `navigator.vibrate` no disponible en iOS Safari | Must |
| RF-09 | Hito audible/visual cada km completado | Should |
| RF-10 | Exportar historial a CSV/JSON (para importación manual a Salud vía apps de terceros). **Schema CSV concreto vs *Health Importer* → diferido a v1.1** | Should |
| RF-11 | Eliminar sesiones individuales del historial | Should |
| RF-12 | Wake Lock (pantalla activa durante sesión) vía `navigator.wakeLock` | Should |
| RF-13 | Segundo perfil de circuito (multi-ubicación) | Could |
| RF-14 | Recalibración in-app: editar zancada y/o pasos por vuelta; perímetro recalculado y aplicado a sesiones **futuras** (las cerradas quedan congeladas, ADR-03) | Must |

## 5. Requisitos no funcionales

- **RNF-01 Offline-first:** funcionamiento 100% sin red. Service Worker con cache de app shell.
- **RNF-02 Persistencia:** `localStorage` para configuración; `localStorage` o IndexedDB para sesiones (volumen esperado <100 KB/año → localStorage suficiente en v1).
- **RNF-03 Resiliencia:** autosave del estado de sesión activa cada vuelta y cada 10 s. Recuperación **silenciosa**: al reabrir, si existe `wt:activeSession`, la sesión se reanuda sola recomputando el tiempo desde `startedAt` (wall-clock, ADR-05) — el tiempo con la app cerrada **cuenta** (no hay auto-pausa). Cierre accidental de Safari/purge de iOS → vueltas y tiempo correctos al volver.
- **RNF-04 UX móvil:** viewport iPhone 14 (390×844 pt), targets táctiles ≥44 pt, modo claro/oscuro según `prefers-color-scheme`.
- **RNF-05 Cero dependencias de build:** un solo archivo HTML autocontenido (HTML+CSS+JS vanilla). Sin framework, sin bundler, sin CDN en runtime (offline). **Excepción:** el Service Worker es un archivo local adicional `sw.js` (imprescindible para offline + PWA instalable; sin CDN, mismo origen).
- **RNF-06 Privacidad:** todos los datos permanecen en el dispositivo.
- **RNF-07 Despliegue (GitHub Pages):** hosting estático sobre HTTPS (requisito PWA). Atención al **subpath** de páginas de proyecto (`usuario.github.io/repo/`): `manifest.start_url`, `scope` y registro del SW deben usar rutas **relativas** (`./`) para no romper al cambiar de ruta/base. Sin rutas absolutas (`/sw.js` → `./sw.js`).

## 6. Arquitectura

**Estilo:** SPA monolítica en un archivo, con separación lógica interna tipo hexagonal-lite (proporcional al tamaño del problema — no sobre-ingeniería):

```
┌─────────────────────────────────────┐
│  UI Layer (DOM handlers, render)    │
├─────────────────────────────────────┤
│  Domain (core puro, testeable)      │
│  · Session (aggregate root)         │
│  · LapCounter, Chronometer          │
│  · MetricsCalculator                │
│  · CalibrationProfile               │
├─────────────────────────────────────┤
│  Ports/Adapters                     │
│  · StoragePort → LocalStorageAdapter│
│  · ClockPort → SystemClockAdapter   │
│  · ExportPort → CsvAdapter/JsonAd.  │
└─────────────────────────────────────┘
```

**Decisiones (mini-ADRs):**
- **ADR-01:** Vanilla JS sobre React. *Razón:* un archivo, cero build, instalable directo. React aporta nada a esta escala. *Trade-off:* menos estructura de componentes; mitigado con módulos ES inline.
- **ADR-02:** localStorage sobre IndexedDB. *Razón:* volumen trivial, API síncrona simple. *Trade-off:* límite ~5 MB (irrelevante aquí). Migración a IndexedDB detrás de `StoragePort` si escala.
- **ADR-03:** Session como aggregate root. Invariantes: vueltas ≥ 0, sesión finalizada es inmutable, distancia siempre derivada (nunca almacenada como fuente de verdad → se recalcula si cambia calibración retroactivamente **NO**: la sesión congela el perímetro vigente al finalizar).
- **ADR-04:** Perímetro **derivado**, no almacenado. `lapPerimeterM = strideM × stepsPerLap`. La config guarda medidas crudas (zancada, pasos/vuelta) y el perímetro se calcula. *Razón:* la recalibración (RF-14) consiste en editar las medidas crudas y el perímetro se actualiza solo, sin datos duplicados ni inconsistencias. *Trade-off:* requiere validar ambas entradas (>0) en la frontera; las sesiones cerradas conservan el perímetro congelado (consistente con ADR-03).
- **ADR-05:** Cronómetro basado en **wall-clock** (`startedAt` + `Date.now()`), no en acumulación de ticks. *Razón:* iOS Safari congela los timers en background; al volver a primer plano, `Date.now()` refleja el tiempo real transcurrido → cronómetro correcto sin depender de que el timer corra. Pausa **explícita únicamente** (botón): no hay auto-pausa al cambiar de app (p. ej. música) — el reloj sigue corriendo por decisión de producto. *Trade-off:* si el usuario se distrae sin pausar, el tiempo corre; mitigado con feedback claro del estado (activo/pausado) y wake lock (RF-12).

## 7. Modelo de datos

```json
// localStorage["wt:config"] — medidas crudas; lapPerimeterM se DERIVA (ADR-04), no se almacena
{ "strideM": 0.655, "stepsPerLap": 62 }   // → lapPerimeterM = 0,655 × 62 = 40,61 m   [heightCm eliminado en C2: sin consumidor]

// localStorage["wt:sessions"] — array append-only
{
  "id": "uuid",
  "startedAt": "ISO8601",
  "endedAt": "ISO8601",
  "laps": 83,
  "lapPerimeterM": 40.61,       // congelado al cierre (ADR-03); = strideM×stepsPerLap vigente al cerrar
  "distanceM": 3370.63,          // derivado, cacheado (= 83 × 40,61)
  "durationS": 3720,
  "paceSecPerKm": 1068,          // = (3720−120) / (3370,63/1000)  [corregido: antes 905, no restaba pausas]
  "pausesS": 120
}

// localStorage["wt:activeSession"] — snapshot para recuperación (RNF-03)
```

## 8. Cálculos (dominio)

- `lapPerimeterM = strideM × stepsPerLap`   (derivation; ADR-04)
- `distanceM = laps × lapPerimeterM`
- `paceSecPerKm = (durationS − pausesS) / (distanceM / 1000)`
- Cronómetro wall-clock (ADR-05): `elapsedS = (now − startedAt) − totalPausesS`
  - `totalPausesS` = suma de intervalos `[pauseStart, resume]`; si la sesión está pausada ahora, el reloj se congela en `pauseStart` (no avanza).
  - Sin auto-pausa: cambiar de app (p. ej. a música) NO pausa; el wall-clock sigue avanzando. Pausa solo con botón.
- Hito de km: `floor(distanceM / 1000)` cambia → trigger RF-09

## 9. UI — Pantallas

1. **Home/Sesión:** métrica principal (vueltas) + botón gigante "+1 VUELTA", métricas secundarias (distancia, tiempo, ritmo), controles iniciar/pausar/finalizar, deshacer.
2. **Historial:** lista descendente (fecha, distancia, duración, ritmo), totales del mes, acción exportar y eliminar.
3. **Ajustes:** zancada y pasos por vuelta (recalibración RF-14; perímetro mostrado como **derivado/readonly**), borrar datos.

## 10. Limitación conocida: integración HealthKit

Safari/PWA **no tiene acceso a HealthKit**. Alternativas documentadas:
- **v1:** exportar CSV (RF-10) → importar con app *Health Importer* (manual).
- **v2 (futuro):** Atajo de Shortcuts que lea el JSON exportado (compartido vía share sheet) y escriba el workout en Salud.
- **v3 (futuro):** app nativa SwiftUI si el flujo lo justifica.

## 11. Criterios de aceptación (v1)

- [ ] Sesión de 83 vueltas registra 3,37 km con perímetro 40,61 m (62 pasos × 0,655 m)
- [ ] App funciona en modo avión, instalada como PWA
- [ ] Instalable y offline desde GitHub Pages (HTTPS); las rutas relativas funcionan bajo subpath de proyecto (`usuario.github.io/repo/`)
- [ ] Cierre forzado de Safari durante sesión activa → al reabrir, sesión recuperada con vueltas y tiempo correctos
- [ ] Historial sobrevive reinicio del dispositivo
- [ ] Botón +1 operable con pulgar sin precisión (test en movimiento)
- [ ] Al marcar vuelta suena un beep confirmatorio (Web Audio) → permite operar sin mirar (RF-02 + RF-08)
- [ ] Export CSV abre correctamente en Numbers/Excel **(v1.1)**

## 12. Roadmap

| Versión | Contenido |
|---------|-----------|
| v1.0 | RF-01..08, RF-14, RNF completos |
| v1.1 | RF-09..12 (hitos km, wake lock, export, eliminar sesiones) |
| v2.0 | Integración Shortcuts→HealthKit, multi-circuito |

## 13. Despliegue

- **Destino:** GitHub Pages (estático, HTTPS). Cumple el requisito HTTPS de PWA y la instalación en iOS (Agregar a pantalla de inicio).
- **Estructura mínima del repo (raíz servida):**
  - `index.html` — app shell + JS vanilla (RNF-05).
  - `sw.js` — Service Worker (cache de app shell, offline). Registrado con `scope: "./"`.
  - `manifest.webmanifest` — `start_url: "./"`, `scope: "./"`, `display: standalone`, iconos con rutas relativas.
  - `.nojekyll` — para que Pages sirva archivos/carpetas con `_` sin procesado Jekyll.
- **Subpath de proyecto:** al servir bajo `usuario.github.io/repo/`, **todo relativo** (`./sw.js`, `./manifest.webmanifest`). Evitar rutas absolutas. Solo introducir `<base>` si la app cambia de ruta.
- **Workflow de publicación:** deploy desde `main` (GitHub Action → Pages, o branch `gh-pages`). Alinea con el GitFlow del proyecto: el merge a `main` vía PR dispara el despliegue. Nunca push directo a `main`.
