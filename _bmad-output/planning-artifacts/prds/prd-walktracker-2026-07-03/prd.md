---
title: WalkTracker PWA v1.0
created: 2026-07-03
updated: 2026-07-03
status: final
source: input/SPEC_WalkTracker_v1.md
---

# PRD: WalkTracker PWA v1.0
*Contador de vueltas y registro de caminatas sin GPS, en un circuito cerrado pequeño.*

## 0. Document Purpose

Este PRD define los requisitos de **WalkTracker**, una PWA de uso **estrictamente personal**. Está dirigido al propio constructor (Paul) y a los flujos descendentes (Arquitectura, Épicas/Stories, Desarrollo). Se construye **sobre** `input/SPEC_WalkTracker_v1.md` (fuente refinada y aprobada en sesión): no la duplica, la proyecta al formato PRD con FRs globalmente numerados y trazables. El vocabulario se ancla en el Glosario (§3) y se usa de forma consistente. Las decisiones técnicas (ADRs) viven en el SPEC y en `.memlog.md`; aquí solo se enuncian como NFRs cuando afectan al comportamiento.

## 1. Vision

Las apps basadas en GPS (p. ej. Adidas Running) producen errores de distancia del **8–10 %** en circuitos cerrados pequeños (~41 m), por las limitaciones físicas del GPS (precisión 3–5 m, multipath, filtrado Kalman agresivo). WalkTracker elimina esa fuente de error midiendo la distancia por **conteo determinístico de vueltas** sobre un perímetro calibrado.

Es una **PWA instalable en iPhone** (Safari → "Agregar a pantalla de inicio") que registra sesiones de caminata: conteo manual de vueltas con un botón grande operable a ciegas, cronómetro, métricas en vivo (distancia, ritmo), historial local y exportación. **Cero dependencia de GPS, red o backend.** Toda la información permanece en el dispositivo.

El valor central: **precisión derivada de la calibración, no de la señal**, y una UX que permite caminar sin mirar la pantalla.

## 2. Target User

### 2.1 Jobs To Be Done

- **Funcional:** registrar caminatas en un circuito cerrado con distancia y ritmo precisos, sin el drift del GPS.
- **Contextual:** poder cambiar de app (p. ej. a música) durante la sesión sin que el cronómetro se detenga.
- **Emocional:** confiar en que cada vuelta quedó registrada sin tener que mirar la pantalla.
- **De privacidad:** que ningún dato de salud abandone el dispositivo.

### 2.2 Non-Users (v1)

- Cualquier persona que no sea Paul. No hay multi-usuario, cuentas ni sincronización. El modelo **no-backend es un invariante permanente**, no un recorte de v1.

### 2.3 Key User Journeys

- **UJ-1. Paul camina su circuito sin mirar la pantalla.**
  - **Persona + contexto:** Paul, en su circuito de ~41 m, quiere registrar distancia precisa mientras camina y escucha música.
  - **Entry state:** PWA instalada en iPhone, abierta desde el icono de inicio. Sin sesión activa.
  - **Path:** (1) pulsa **Iniciar** → el cronómetro arranca (wall-clock); (2) en cada vuelta pulsa el botón gigante **+1** con el pulgar, sin mirar → suena un **beep** que confirma; (3) cambia a la app de música → el reloj **sigue corriendo** (sin auto-pausa); (4) vuelve a WalkTracker y sigue marcando vueltas; (5) pulsa **Finalizar**.
  - **Climax:** la pantalla muestra distancia total (p. ej. 83 vueltas → 3,37 km), ritmo y duración; la sesión queda persistida en el historial.
  - **Resolution:** sesión cerrada e inmutable en el historial; pronto para una nueva.

- **UJ-2. Paul recalibra el perímetro tras medir de nuevo.**
  - **Path:** en **Ajustes** edita **zancada** y/o **pasos por vuelta** → el perímetro se **recalcula solo** → las próximas sesiones usan el nuevo valor; el historial cerrado **no cambia** (perímetro congelado por sesión).

## 3. Glossary

- **Vuelta (Lap)** — una circunnavegación completa del circuito. Contador entero ≥ 0.
- **Sesión (Session)** — aggregate root: intervalo de caminata con `startedAt`, vueltas, pausas y estado (activa/pausada/finalizada). La sesión finalizada es **inmutable**.
- **Perímetro (lapPerimeterM)** — metros por vuelta. **Siempre derivado** = `strideM × stepsPerLap`; nunca almacenado como fuente de verdad.
- **Zancada (strideM)** — longitud media de paso en metros (> 0). Medida cruda editable.
- **Pasos por vuelta (stepsPerLap)** — número de pasos en una vuelta (> 0). Medida cruda editable.
- **Calibración** — fijar `strideM` y `stepsPerLap` para derivar el perímetro. Valor actual: 0,655 m × 62 = **40,61 m**.
- **Cronómetro wall-clock** — tiempo transcurrido calculado desde `startedAt` con `Date.now()`, restando pausas; no depende de timers que iOS congela en background.
- **Pausa** — detención **explícita** (botón). No existe auto-pausa: cambiar de app no pausa.
- **PWA** — Progressive Web App instalable, offline-first, sin instalación de store.

## 4. Features

### 4.1 Sesión y conteo de vueltas
**Description:** El núcleo del producto. Una sesión se inicia, pausa (solo explícitamente) y finaliza; el usuario marca vueltas con un botón gigante y puede deshacer. Las métricas (vueltas, distancia, tiempo, ritmo) se calculan en vivo. Realiza UJ-1.

**Functional Requirements:**

#### FR-1: Control de sesión con cronómetro
El usuario puede **iniciar, pausar y finalizar** una sesión. El cronómetro es wall-clock (`elapsedS = (now − startedAt) − totalPausesS`); la pausa es **solo explícita** (botón), no hay auto-pausa al cambiar de app. Realiza UJ-1.

**Consequences (testable):**
- Al iniciar, `startedAt` se fija y el cronómetro avanza con `Date.now()`.
- Pausar congela el cronómetro en el instante de la pausa; reanudar lo continúa sin contar el intervalo pausado.
- Cambiar de app y volver NO altera el tiempo: al volver a primer plano el elapsed refleja el wall-clock real.
- Finalizar produce una sesión inmutable.

#### FR-2: Botón de vuelta gigante operable a ciegas
El usuario puede incrementar el contador de vueltas con un botón de **≥ 40 % del viewport**, operable con el pulgar sin precisión visual. Realiza UJ-1.

**Consequences:**
- El botón "+1" ocupa ≥ 40 % del área visible y cumple target táctil ≥ 44 pt.
- Cada pulso incrementa el contador en exactamente 1.

#### FR-3: Deshacer vuelta
El usuario puede **deshacer** (−1) el último incremento por error.

**Consequences:**
- El contador nunca baja de 0 (invariante de dominio).
- Deshacer está disponible solo en sesión activa (no en sesión finalizada).

#### FR-4: Métricas en vivo
El sistema muestra en vivo: **vueltas, distancia (m/km), tiempo y ritmo (min/km)**. Realiza UJ-1.

**Consequences:**
- `distanceM = laps × lapPerimeterM`; `paceSecPerKm = (durationS − pausesS) / (distanceM/1000)`.
- Las métricas se actualizan en cada vuelta y al menos cada segundo durante la sesión.

### 4.2 Calibración y recalibración
**Description:** El perímetro se **deriva** de dos medidas crudas (zancada × pasos/vuelta), lo que hace que recalibrar consista en editar esas medidas. El perímetro vigente al cerrar una sesión queda **congelado** en ella; el historial nunca se reescribe al recalibrar. Realiza UJ-2.

**Functional Requirements:**

#### FR-5: Perímetro derivado (calibración)
El perímetro por vuelta es **siempre derivado** de `strideM × stepsPerLap` (default: 0,655 m × 62 = 40,61 m).

**Consequences:**
- No existe un campo `lapPerimeterM` editable directamente: se muestra como **derivado/readonly**.
- Validación en frontera: `strideM > 0` y `stepsPerLap > 0` (números finitos); se rechazan valores inválidos antes de materializar.

#### FR-6: Recalibración in-app
El usuario puede editar **zancada** y/o **pasos por vuelta** en Ajustes; el perímetro se recalcula y aplica a sesiones **futuras**. Realiza UJ-2.

**Consequences:**
- Las sesiones cerradas conservan su perímetro congelado (no se alteran al recalibrar).
- Tras recalibrar, la siguiente sesión usa el nuevo perímetro derivado.

### 4.3 Persistencia e historial
**Description:** Las sesiones finalizadas se persisten localmente y se consultan en un historial con totales.

**Functional Requirements:**

#### FR-7: Persistencia de sesiones
El sistema persiste cada sesión finalizada (fecha, vueltas, distancia, duración, ritmo, perímetro congelado) en el dispositivo.

**Consequences:**
- El historial sobrevive al reinicio del dispositivo.
- Volumen esperado < 100 KB/año.

#### FR-8: Historial con totales
El usuario ve una lista descendente de sesiones y los **totales acumulados** (p. ej. del mes).

**Consequences:**
- Cada ítem muestra fecha, distancia, duración y ritmo.
- Los totales se calculan sobre las sesiones almacenadas.

### 4.4 Feedback a ciegas
**Description:** Cada vuelta marcada emite un **beep** (Web Audio API) que confirma el registro sin mirar la pantalla. Es lo que hace confiable la operación a ciegas del FR-2, dado que `navigator.vibrate()` **no existe en iOS Safari**.

**Functional Requirements:**

#### FR-9: Feedback sonoro al marcar vuelta
Al marcar una vuelta suena un **beep confirmatorio** vía Web Audio API.

**Consequences:**
- El beep se reproduce en cada "+1" mientras la sesión está activa.
- El AudioContext se desbloquea con el gesto de usuario al pulsar "Iniciar" (requisito de iOS).

## 5. Non-Goals (Explicit)

- **GPS** — no se usa para medir distancia.
- **Backend, autenticación, multi-usuario, sincronización cloud** — invariante permanente (producto personal).
- **HealthKit directo** — imposible desde PWA; el flujo a Salud queda vía export manual (v1.1) o Shortcuts (v2).
- **Estimación de pasos (podómetro)** — eliminada: con perímetro derivado de zancada, `estimatedSteps` resulta trivial/circular y no aporta información.
- **Auto-pausa** — expresamente NO: el reloj corre salvo pausa explícita.

## 6. MVP Scope

### 6.1 In Scope (v1.0)
- FR-1 a FR-9 (sesión/conteo, calibración/recalibración, persistencia/historial, beep).
- NFR-1 a NFR-7 (offline-first, localStorage, resiliencia, UX móvil, cero deps, privacidad, GitHub Pages).

### 6.2 Out of Scope for MVP (v1.1+)
*Los IDs `RF-XX` corresponden al SPEC fuente (`input/SPEC_WalkTracker_v1.md`); al promocionarse a una versión, se renumeran como FR del PRD.*
- **RF-09** Hito audible/visual cada km — *v1.1*.
- **RF-10** Export CSV/JSON (schema concreto vs *Health Importer* a definir) — *v1.1*.
- **RF-11** Eliminar sesiones individuales — *v1.1*.
- **RF-12** Wake Lock (pantalla activa) — *v1.1*.
- **RF-13** Segundo perfil de circuito (multi-ubicación) — *Could / futuro*.

## 7. Success Metrics

*Stakes hobby/personal — métricas ligeras.*

**Primary**
- **SM-1**: Adopción personal — Paul usa WalkTracker **semanalmente** y no la abandona tras el primer mes. Valida FR-1, FR-2, FR-4.

**Secondary**
- **SM-2**: Precisión — distancia registrada dentro de un margen aceptable frente a la **distancia real medida con cinta** en el circuito. Valida FR-5. `[ASSUMPTION: el target cuantitativo (margen %) no está definido — ver OQ-1]`

**Counter-metrics (do not optimize)**
- **SM-C1**: No optimizar la "precisión de pasos estimados" a costa de la precisión basada en vueltas medidas — el conteo de vueltas es la fuente de verdad, no la zancada. Contrarresta SM-2.

## 8. Open Questions

1. **OQ-1 (precisión):** ¿qué margen máximo de error (%) frente a la distancia medida con cinta define el "éxito" de SM-2? (Sin resolver; el benchmark GPS es 8–10 %.)
2. **OQ-2 (export):** esquema CSV exacto exigido por *Health Importer* (diferido a v1.1).
3. **OQ-3 (calibración futura):** ¿se ofrecerá una sesión de medición interactiva (caminar N vueltas contando pasos) además de la edición manual de Ajustes?

## 9. Assumptions Index

- `[ASSUMPTION: SM-2 target cuantitativo no definido — ver OQ-1]` (§7).
- `[ASSUMPTION: el perímetro real 40,61 m proviene de medición de Paul (62 pasos × 0,655 m); no de levantamiento topográfico con cinta]` (§3, FR-5).
- `[ASSUMPTION: el AudioContext de Web Audio se desbloquea al pulsar "Iniciar" y permanece activo en foreground]` (FR-9).

---

## Cross-Cutting NFRs

- **NFR-1 Offline-first:** funcionamiento 100 % sin red. Service Worker con cache de app shell.
- **NFR-2 Persistencia:** `localStorage` para configuración y sesiones (volumen < 100 KB/año). Migración a IndexedDB detrás de `StoragePort` si escala.
- **NFR-3 Resiliencia:** autosave del estado de sesión activa cada vuelta y cada 10 s. **Recuperación silenciosa**: al reabrir, si existe sesión activa, se reanuda sola recomputando el tiempo desde `startedAt` — el tiempo con la app cerrada cuenta. Cierre/purge de iOS → vueltas y tiempo correctos al volver.
- **NFR-4 UX móvil:** viewport iPhone 14 (390×844 pt), targets táctiles ≥ 44 pt, modo claro/oscuro según `prefers-color-scheme`.
- **NFR-5 Cero dependencias de build:** un solo archivo HTML autocontenido (HTML+CSS+JS vanilla). Sin framework, sin bundler, sin CDN. **Excepción:** el Service Worker es un archivo local adicional `sw.js` (necesario para offline + PWA instalable).
- **NFR-6 Privacidad:** todos los datos permanecen en el dispositivo.
- **NFR-7 Despliegue (GitHub Pages):** hosting estático sobre HTTPS. Atención al **subpath** de proyecto: `start_url`, `scope` y registro del SW con rutas **relativas** (`./`).

## Constraints and Guardrails

- **Privacidad:** on-device por diseño (NFR-6). Sin analítica ni telemetría.
- **Licencias:** cero dependencias de runtime → sin riesgo copyleft (GPL/AGPL).

## Platform

- **Forma:** PWA (web), instalable en iOS vía Safari. Sin app nativa en v1.
- **Hosting:** GitHub Pages (estático, HTTPS). Estructura mínima: `index.html`, `sw.js`, `manifest.webmanifest`, `.nojekyll`. Deploy desde `main` vía PR (GitFlow).
