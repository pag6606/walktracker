---
baseline_commit: NO_VCS
epic: E3
story_key: e3-s12-wakelock-background
status: ready-for-dev
---

# E3-S1+S2 — WakeLock + Background Handling

**Epic:** E3 — Caminata sin interrupciones
**Prioridad:** Must | **Estimación:** S (2 días) | **Dependencias:** E0-S3, E0-S4

## Story

**Como** Paul, **quiero** que la pantalla se mantenga encendida durante mi caminata y que al volver de background los pasos estimados se muestren correctamente, **para** no perder datos.

## Acceptance Criteria

- [ ] `WakeLockPort.acquire()` solicita wake lock
- [ ] `WakeLockPort.release()` libera wake lock
- [ ] `onLost(callback)` y `onAcquired(callback)` eventos
- [ ] Si wake lock no existe → callback onLost inmediato
- [ ] Background→foreground: tiempo recalculado wall-clock
- [ ] Gap estimado calculado via GapEstimator
- [ ] Recovery indicator: "Sesión recuperada" tras purge
- [ ] ≥10 tests (mock de WakeLock + visibility), 0 fallos

## File List
*To be filled on completion*

## Status
**Current:** ready-for-dev | **Last updated:** 2026-07-07
