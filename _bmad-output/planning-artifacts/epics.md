---
stepsCompleted: ['step-01-validate-prerequisites']
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-walktracker-2026-07-03/prd.md
  - _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md
  - input/SPEC_WalkTracker_v1.md
---

# WalkTracker - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for WalkTracker, decomposing the requirements from the PRD, Architecture spine, and SPEC into implementable stories.

## Requirements Inventory

### Functional Requirements

- **FR-1**: Control de sesión con cronómetro — El usuario puede iniciar, pausar y finalizar una sesión. Cronómetro wall-clock (`elapsedS = (now − startedAt) − totalPausesS`); pausa solo explícita (botón), sin auto-pausa al cambiar de app.
- **FR-2**: Botón de vuelta gigante operable a ciegas — Botón "+1" de ≥ 40 % del viewport, operable con el pulgar sin precisión visual. Target táctil ≥ 44 pt.
- **FR-3**: Deshacer vuelta — El usuario puede deshacer (−1) el último incremento. Contador nunca baja de 0. Solo en sesión activa.
- **FR-4**: Métricas en vivo — Muestra vueltas, distancia (m/km), tiempo y ritmo (min/km). `distanceM = laps × lapPerimeterM`; `paceSecPerKm = (durationS − pausesS) / (distanceM/1000)`.
- **FR-5**: Perímetro derivado (calibración) — `lapPerimeterM = strideM × stepsPerLap` (default: 0,655 × 62 = 40,61 m). Sin campo editable directo; validación en frontera (>0, finitos).
- **FR-6**: Recalibración in-app — Editar zancada y/o pasos por vuelta en Ajustes; perímetro recalculado para sesiones futuras. Historial cerrado no cambia.
- **FR-7**: Persistencia de sesiones — Persistir sesiones finalizadas (fecha, vueltas, distancia, duración, ritmo, perímetro congelado) en localStorage. Sobrevive reinicio.
- **FR-8**: Historial con totales — Lista descendente de sesiones con totales acumulados (p. ej. del mes). Cada ítem: fecha, distancia, duración, ritmo.
- **FR-9**: Feedback sonoro al marcar vuelta — Beep confirmatorio vía Web Audio API en cada "+1". AudioContext desbloqueado al pulsar "Iniciar" (gesto de usuario iOS).

### NonFunctional Requirements

- **NFR-1**: Offline-first — 100 % sin red. Service Worker con cache de app shell.
- **NFR-2**: Persistencia — localStorage para config y sesiones (< 100 KB/año). Migración a IndexedDB detrás de StoragePort si escala.
- **NFR-3**: Resiliencia — Autosave cada vuelta + 10 s. Recuperación silenciosa: al reabrir, reanuda desde `startedAt` (tiempo cerrado cuenta).
- **NFR-4**: UX móvil — viewport iPhone 14 (390×844 pt), targets ≥ 44 pt, modo claro/oscuro (`prefers-color-scheme`).
- **NFR-5**: Cero dependencias de build — HTML+CSS+JS vanilla. Sin framework/bundler/CDN. Excepción: `sw.js` separado.
- **NFR-6**: Privacidad — Todos los datos en el dispositivo. Sin analítica ni telemetría.
- **NFR-7**: Despliegue GitHub Pages — HTTPS estático. Rutas relativas (`./`) por subpath de proyecto.

### Additional Requirements

- **AD-1** [ADOPTED]: Hexagonal-lite; dependencias apuntan al dominio. Domain puro (sin DOM/infra). Puertos definidos en dominio; adapters en borde.
- **AD-2** [ADOPTED]: Vanilla JS single-file (`index.html`) + `sw.js` separado.
- **AD-3** [ADOPTED]: localStorage detrás de `StoragePort`. Claves: `wt:config`, `wt:sessions`, `wt:activeSession`.
- **AD-4** [ADOPTED]: Session = aggregate root. Invariantes: laps≥0, finalizada inmutable, distancia derivada, perímetro congelado al cierre.
- **AD-5** [ADOPTED]: Perímetro derivado (`strideM × stepsPerLap`), nunca almacenado como verdad.
- **AD-6** [ADOPTED]: Cronómetro wall-clock (`Date.now()`), no ticks. Pausa solo explícita.
- **AD-7**: Validación en la frontera — inputs crudos validados (>0, finitos) antes de materializar aggregate.
- **AD-8** [ADOPTED]: Recuperación silenciosa desde `wt:activeSession`.
- **AD-9**: Web Audio adapter; `AudioContext` desbloqueado en gesto "Iniciar".
- **AD-10** [ADOPTED]: SW cache app-shell (cache-first).
- **AD-11** [ADOPTED]: GitHub Pages, rutas relativas, `.nojekyll`.
- **Storage shapes**: `wt:config` → `{strideM, stepsPerLap}`; `wt:activeSession` → `{startedAtMs, laps, totalPausesMs, paused, strideM, stepsPerLap}`; `wt:sessions` → array de sesiones finalizadas.
- **Port contracts**: `StoragePort`, `ClockPort`, `ExportPort`, `AudioPort`.

### UX Design Requirements

*(No UX design document exists. UX requirements are captured within FRs and NFRs above.)*

### FR Coverage Map

FR-1: Epic 1 — Control de sesión con cronómetro wall-clock
FR-2: Epic 1 — Botón de vuelta gigante operable a ciegas
FR-3: Epic 1 — Deshacer vuelta
FR-4: Epic 1 — Métricas en vivo
FR-5: Epic 2 — Perímetro derivado (calibración)
FR-6: Epic 2 — Recalibración in-app
FR-7: Epic 3 — Historial y persistencia
FR-8: Epic 3 — Historial con totales
FR-9: Epic 1 — Feedback sonoro al marcar vuelta

## Epic List

### Epic 1: Sesión y conteo de vueltas
Paul puede iniciar una caminata, contar vueltas con un botón gigante operable a ciegas, ver métricas en vivo (distancia, tiempo, ritmo) y recibir confirmación sonora de cada vuelta. Es la experiencia central del producto: sin esto, nada más importa.
**FRs covered:** FR-1, FR-2, FR-3, FR-4, FR-9
**NFRs transversales:** NFR-1 (offline), NFR-3 (resiliencia), NFR-4 (UX móvil), NFR-5 (cero deps), NFR-6 (privacidad)
**ADs:** AD-1 (hexagonal-lite), AD-2 (vanilla single-file), AD-4 (Session aggregate), AD-6 (wall-clock), AD-8 (recovery silenciosa), AD-9 (Web Audio beep)
**Nota:** Funciona con calibración por defecto (40,61 m hardcodeado en `wt:config`). No requiere Epic 2 para funcionar.

### Epic 2: Calibración y recalibración
Paul puede configurar el perímetro a partir de medidas crudas (zancada + pasos/vuelta) y recalibrarlo más tarde sin alterar el historial de sesiones cerradas.
**FRs covered:** FR-5, FR-6
**NFRs transversales:** NFR-2 (localStorage), NFR-5 (cero deps)
**ADs:** AD-3 (StoragePort), AD-5 (perímetro derivado), AD-7 (validación en frontera)
**Nota:** Epic 1 funciona sin este epic (usa defaults). Epic 2 mejora la precisión pero no es bloqueante.

### Epic 3: Historial y persistencia
Las sesiones finalizadas se guardan localmente y Paul puede consultarlas en una lista con totales acumulados. El historial sobrevive al reinicio del dispositivo.
**FRs covered:** FR-7, FR-8
**NFRs transversales:** NFR-2 (localStorage), NFR-3 (autosave), NFR-6 (privacidad)
**ADs:** AD-3 (StoragePort), AD-4 (sesión inmutable), AD-8 (snapshot recovery)
**Nota:** Epic 1+2 funcionan sin este epic (las sesiones no se guardan pero la experiencia de caminata es completa).

### Epic 4: Despliegue y PWA instalable
La app se publica en GitHub Pages como PWA instalable (HTTPS, Service Worker offline, manifest, rutas relativas bajo subpath de proyecto).
**FRs covered:** — (infraestructura transversal)
**NFRs covered:** NFR-1 (offline-first), NFR-5 (sw.js separado), NFR-7 (GitHub Pages)
**ADs:** AD-10 (SW cache app-shell), AD-11 (rutas relativas, .nojekyll)
**Nota:** Puede ejecutarse en paralelo con cualquier epic funcional. Habilita la instalación en iPhone y el funcionamiento 100 % offline.

## FR Coverage Map

FR-1: Epic 1 — Control de sesión con cronómetro wall-clock
FR-2: Epic 1 — Botón de vuelta gigante operable a ciegas
FR-3: Epic 1 — Deshacer vuelta
FR-4: Epic 1 — Métricas en vivo
FR-5: Epic 2 — Perímetro derivado (calibración)
FR-6: Epic 2 — Recalibración in-app
FR-7: Epic 3 — Persistencia de sesiones
FR-8: Epic 3 — Historial con totales
FR-9: Epic 1 — Feedback sonoro al marcar vuelta

NFR-1: Epic 1 + Epic 4 — Offline-first (SW cache)
NFR-2: Epic 2 + Epic 3 — Persistencia localStorage
NFR-3: Epic 1 + Epic 3 — Resiliencia (autosave + recovery)
NFR-4: Epic 1 — UX móvil (viewport, targets, dark/light)
NFR-5: Epic 1 + Epic 4 — Cero deps de build + sw.js
NFR-6: Epic 1 + Epic 3 — Privacidad on-device
NFR-7: Epic 4 — Despliegue GitHub Pages

---

## Epic 1: Sesión y conteo de vueltas

Paul puede iniciar una caminata, contar vueltas con un botón gigante operable a ciegas, ver métricas en vivo (distancia, tiempo, ritmo) y recibir confirmación sonora de cada vuelta. Funciona con calibración por defecto (40,61 m).
**FRs covered:** FR-1, FR-2, FR-3, FR-4, FR-9
**NFRs transversales:** NFR-1, NFR-3, NFR-4, NFR-5, NFR-6
**ADs:** AD-1, AD-2, AD-4, AD-6, AD-8, AD-9

### Story 1.1: Domain core (Session, Chronometer, MetricsCalculator, CalibrationProfile)

As a developer,
I want a pure JS domain layer with no DOM or infrastructure dependencies,
So that the core logic is testable without a browser and enforces all invariants.

**Acceptance Criteria:**

**Given** a new Session is created with `startedAt` and default calibration (strideM=0.655, stepsPerLap=62)
**When** `lap()` is called 83 times
**Then** `session.laps === 83`
**And** `session.distanceM === 3370.63` (83 × 40.61)
**And** `session.lapPerimeterM === 40.61` (frozen at session start)

**Given** an active Session with 5 laps
**When** `undo()` is called
**Then** `session.laps === 4`
**And** `session.distanceM === 162.44` (4 × 40.61)

**Given** an active Session with 0 laps
**When** `undo()` is called
**Then** `session.laps === 0` (invariante: nunca baja de 0)

**Given** a finalized Session
**When** any mutation method (`lap()`, `undo()`, `pause()`, `resume()`) is called
**Then** it throws an error (sesión finalizada es inmutable)

**Given** a Chronometer with `startedAt = Date.now() - 3720000` and `totalPausesMs = 120000`
**When** `elapsedS(now)` is called
**Then** it returns `3600` seconds ((3720000 - 120000) / 1000)

**Given** a MetricsCalculator with `laps=83`, `lapPerimeterM=40.61`, `durationS=3720`, `pausesS=120`
**When** `paceSecPerKm()` is called
**Then** it returns `1068` ((3720-120) / (3370.63/1000))

**Given** a CalibrationProfile with `strideM=0.655` and `stepsPerLap=62`
**When** `recalibrate({strideM: 0.66, stepsPerLap: 63})` is called
**Then** it returns `{strideM: 0.66, stepsPerLap: 63, lapPerimeterM: 41.58}`

**Given** `recalibrate({strideM: 0, stepsPerLap: 62})`
**When** called
**Then** it throws `RangeError` (strideM must be > 0)

**Given** `recalibrate({strideM: 'x', stepsPerLap: 62})`
**When** called
**Then** it throws `TypeError` (must be finite numbers)

---

### Story 1.2: UI Session screen (botón +1, métricas, controles)

As Paul,
I want a session screen with a giant +1 button, live metrics, and start/pause/finish controls,
So that I can walk and count laps without looking at the screen.

**Acceptance Criteria:**

**Given** the app is opened with no active session
**When** I see the home screen
**Then** I see a prominent **Iniciar** button and no lap counter

**Given** I press **Iniciar**
**When** the session starts
**Then** I see a button "+1 VUELTA" occupying ≥ 40% of the viewport
**And** I see live metrics: vueltas (0), distancia (0.00 m), tiempo (00:00), ritmo (—)
**And** I see **Pausar** and **Finalizar** buttons
**And** the cronómetro advances using wall-clock (`Date.now()`)

**Given** an active session with 0 laps
**When** I press "+1 VUELTA"
**Then** the lap counter increments to 1
**And** distancia updates to 40.61 m
**And** the button is ≥ 44 pt touch target

**Given** an active session with 5 laps
**When** I press "+1 VUELTA" 3 more times
**Then** the lap counter shows 8
**And** distancia shows 324.88 m (8 × 40.61)

**Given** an active session
**When** I press **Pausar**
**Then** the cronómetro freezes (elapsed does not increase)
**And** the button changes to **Reanudar**

**Given** a paused session
**When** I press **Reanudar**
**Then** the cronómetro continues from where it froze
**And** the pause interval is NOT counted in elapsed time

**Given** an active session with 10 laps and 300s elapsed
**When** I press **Finalizar**
**Then** the session is marked as finalized (immutable)
**And** the UI shows the summary: 10 laps, 406.1 m, 300s, pace

**Given** an active session
**When** I switch to another app (e.g., music) and return after 60s
**Then** the cronómetro reflects the full 60s elapsed (wall-clock, no auto-pause)

---

### Story 1.3: Feedback sonoro (beep) + deshacer vuelta

As Paul,
I want an audible beep on each lap and the ability to undo a mistaken tap,
So that I can trust the count without looking and correct errors.

**Acceptance Criteria:**

**Given** an active session
**When** I press "+1 VUELTA"
**Then** a short beep sounds via Web Audio API
**And** the lap counter increments

**Given** the app is opened (no session started yet)
**When** the AudioContext is accessed before any user gesture
**Then** it is in "suspended" state (iOS autoplay policy)

**Given** I press **Iniciar**
**When** the AudioContext is accessed
**Then** it is resumed (user gesture unlocks audio)
**And** subsequent beeps play without issue

**Given** an active session with 5 laps
**When** I press the **Deshacer** button
**Then** the lap counter decrements to 4
**And** distancia recalculates to 162.44 m
**And** a distinct sound (or no sound) confirms the undo

**Given** an active session with 0 laps
**When** I press **Deshacer**
**Then** the lap counter stays at 0 (invariante: no baja de 0)

**Given** a finalized session
**When** I try to access the **Deshacer** button
**Then** it is not available (deshacer solo en sesión activa)

---

### Story 1.4: Autosave + recuperación silenciosa (wt:activeSession)

As Paul,
I want my active session to be saved automatically and recovered silently if Safari closes,
So that I never lose my progress during a walk.

**Acceptance Criteria:**

**Given** an active session with 5 laps
**When** a lap is marked
**Then** `wt:activeSession` is saved with `{startedAtMs, laps: 5, totalPausesMs, paused, strideM, stepsPerLap}`

**Given** an active session running for 15s without a lap
**When** 10s have passed since the last autosave
**Then** `wt:activeSession` is saved with the current state

**Given** `wt:activeSession` exists from a previous session (Safari was purged)
**When** the app opens
**Then** the session resumes silently (no prompt)
**And** the cronómetro recomputes elapsed from `startedAtMs` (time counts, including closure)
**And** the lap counter shows the saved laps

**Given** `wt:activeSession` exists with `paused: true`
**When** the app opens
**Then** the session resumes in paused state
**And** the elapsed time is frozen at the pause moment

**Given** I press **Finalizar** on an active session
**When** the session is finalized
**Then** `wt:activeSession` is cleared (session moved to history in Epic 3)

---

## Epic 2: Calibración y recalibración

Paul puede configurar el perímetro a partir de medidas crudas (zancada + pasos/vuelta) y recalibrarlo más tarde sin alterar el historial de sesiones cerradas.
**FRs covered:** FR-5, FR-6
**NFRs transversales:** NFR-2, NFR-5
**ADs:** AD-3, AD-5, AD-7

### Story 2.1: Pantalla Ajustes (zancada, pasos/vuelta, perímetro derivado)

As Paul,
I want a settings screen where I can see and edit my stride length and steps per lap,
So that I can calibrate the perimeter for my circuit.

**Acceptance Criteria:**

**Given** the app is opened
**When** I navigate to **Ajustes**
**Then** I see **Zancada** (default: 0.655 m) and **Pasos por vuelta** (default: 62) as editable fields
**And** I see **Perímetro** displayed as readonly: "40.61 m (derivado)"

**Given** I change **Zancada** to 0.70
**When** the field updates
**Then** **Perímetro** recalculates to 43.40 m (0.70 × 62)

**Given** I change **Pasos por vuelta** to 60
**When** the field updates
**Then** **Perímetro** recalculates to 39.30 m (0.655 × 60)

**Given** I enter **Zancada** = 0
**When** I try to save
**Then** the input is rejected with an error message (validación en frontera: > 0)

**Given** I enter **Pasos por vuelta** = -5
**When** I try to save
**Then** the input is rejected with an error message (validación en frontera: > 0)

**Given** I enter valid values and save
**When** the settings are saved
**Then** `wt:config` is updated with the new `strideM` and `stepsPerLap`
**And** the next session uses the new derived perimeter

---

### Story 2.2: Recalibración (aplicar a sesiones futuras, historial intacto)

As Paul,
I want to change my calibration values and have the perimeter recalculated for future sessions without affecting closed sessions,
So that I can improve accuracy over time.

**Acceptance Criteria:**

**Given** a closed session with `lapPerimeterM: 40.61` (from 83 laps = 3370.63 m)
**When** I recalibrate to `strideM: 0.70, stepsPerLap: 63` (new perimeter: 44.10 m)
**Then** the closed session still shows `lapPerimeterM: 40.61` and `distanceM: 3370.63` (congelado)

**Given** I recalibrate to new values
**When** I start a new session
**Then** the new session uses the new derived perimeter (44.10 m)
**And** 1 lap = 44.10 m distance

**Given** I recalibrate multiple times
**When** I check the history
**Then** each closed session shows the perimeter that was active when it was closed
**And** no session's distance changes after recalibration

---

## Epic 3: Historial y persistencia

Las sesiones finalizadas se guardan localmente y Paul puede consultarlas en una lista con totales acumulados. El historial sobrevive al reinicio del dispositivo.
**FRs covered:** FR-7, FR-8
**NFRs transversales:** NFR-2, NFR-3, NFR-6
**ADs:** AD-3, AD-4, AD-8

### Story 3.1: Persistencia de sesiones finalizadas

As Paul,
I want my completed sessions to be saved locally in `wt:sessions`,
So that my history survives device restarts.

**Acceptance Criteria:**

**Given** I finalize a session (10 laps, 406.1 m, 300s, pace 738 s/km)
**When** the session is finalized
**Then** it is appended to `wt:sessions` array with `{id, startedAt, endedAt, laps, lapPerimeterM, distanceM, durationS, paceSecPerKm, pausesS}`

**Given** `wt:sessions` has 3 previous sessions
**When** I finalize a new session
**Then** `wt:sessions` has 4 entries (append-only)

**Given** the device is restarted
**When** the app opens
**Then** `wt:sessions` is loaded and all previous sessions are available

**Given** `wt:sessions` volume approaches localStorage limits
**When** a new session is saved
**Then** it still saves (expected volume < 100 KB/year, well within ~5 MB limit)

---

### Story 3.2: Pantalla Historial (lista + totales)

As Paul,
I want to see a list of my past sessions with accumulated totals,
So that I can track my progress over time.

**Acceptance Criteria:**

**Given** `wt:sessions` has 5 sessions
**When** I navigate to **Historial**
**Then** I see a descending list (most recent first) with: fecha, distancia, duración, ritmo

**Given** the 5 sessions total 20.5 km over 180 minutes
**When** I view the Historial
**Then** I see **Totales del mes**: 20.5 km, 180 min, average pace

**Given** `wt:sessions` is empty
**When** I navigate to **Historial**
**Then** I see an empty state message ("Aún no hay sesiones registradas")

**Given** I have sessions from different months
**When** I view the Historial
**Then** I see totals for the current month only (or a month selector if implemented)

---

## Epic 4: Despliegue y PWA instalable

La app se publica en GitHub Pages como PWA instalable (HTTPS, Service Worker offline, manifest, rutas relativas bajo subpath de proyecto).
**FRs covered:** — (infraestructura transversal)
**NFRs covered:** NFR-1, NFR-5, NFR-7
**ADs:** AD-10, AD-11

### Story 4.1: Service Worker offline (sw.js)

As Paul,
I want the app to work without an internet connection,
So that I can use it anywhere, even in airplane mode.

**Acceptance Criteria:**

**Given** the app is loaded for the first time with internet
**When** the Service Worker installs
**Then** `index.html`, `manifest.webmanifest`, and icons are cached (app-shell cache-first)

**Given** the Service Worker is active
**When** I enable airplane mode and reload the app
**Then** the app loads from cache and is fully functional

**Given** a new version of `index.html` is deployed
**When** the Service Worker detects the change
**Then** it installs the new version and activates on next load (cache-busting via `CACHE_NAME` version)

**Given** the app is served from `usuario.github.io/repo/`
**When** the Service Worker is registered
**Then** it uses `scope: "./"` and all cached paths are relative

---

### Story 4.2: PWA manifest + iconos + .nojekyll + rutas relativas

As Paul,
I want to install the app on my iPhone from GitHub Pages,
So that I can launch it like a native app from my home screen.

**Acceptance Criteria:**

**Given** the app is served from GitHub Pages
**When** I open it in Safari
**Then** Safari offers "Agregar a pantalla de inicio"

**Given** `manifest.webmanifest` exists
**When** I inspect it
**Then** it has `start_url: "./"`, `scope: "./"`, `display: "standalone"`, and icon references with relative paths

**Given** `.nojekyll` exists in the repo root
**When** GitHub Pages serves the site
**Then** files/folders with `_` prefixes are served without Jekyll processing

**Given** the app is served under a project subpath (`usuario.github.io/repo/`)
**When** I check all resource references (sw.js, manifest, icons, CSS)
**Then** all paths are relative (`./sw.js`, `./manifest.webmanifest`, `./icons/`) — no absolute paths

**Given** the app is installed via "Agregar a pantalla de inicio"
**When** I launch it from the home screen
**Then** it opens in standalone mode (no Safari chrome) and works offline
