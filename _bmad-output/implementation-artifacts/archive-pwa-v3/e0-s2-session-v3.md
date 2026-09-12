---
baseline_commit: NO_VCS
epic: E0
story_key: e0-s2-session-v3
status: review
---

# E0-S2 — Session aggregate rediseñado

**Epic:** E0 — Conteo automático de pasos
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S1

## Story

**Como** Paul, **quiero** que la app registre mis sesiones con pasos medidos y estimados desglosados, **para** saber qué datos son reales y cuáles son estimaciones.

## Acceptance Criteria

- [x] Session aggregate expone `stepsMeasured` (entero ≥0), `stepsEstimated` (entero ≥0), `strideM` (>0)
- [x] Distancia = `(stepsMeasured + stepsEstimated) × strideM`, derivada
- [x] `stepsEstimated` se almacena desglosado, default 0
- [x] Sesión finalizada es inmutable; congela `strideM`
- [x] No hay concepto `laps` ni `lapPerimeterM` en v3
- [x] `createV3Session(nowMs, strideM)` crea sesión con stepsMeasured=0, stepsEstimated=0
- [x] `addSteps(session, count)` incrementa stepsMeasured
- [x] `addEstimatedSteps(session, count)` añade pasos estimados
- [x] `pause(session, nowMs)` y `resume(session, nowMs)` funcionan (heredado AD-6)
- [x] `finishV3(session, nowMs)` calcula durationS, distanceM, paceSecPerKm, cadenceSpm
- [x] `restoreV3Session(snapshot)` restaura desde snapshot v3
- [x] ≥15 tests unitarios, 0 fallos

## Tasks / Subtasks

- [x] **T1: Implementar funciones v3 de Session**
  - [x] T1.1: `createV3Session(nowMs, strideM)` — nueva sesión con fields v3
  - [x] T1.2: `addSteps(session, count)` — incrementa stepsMeasured, recalcula distanceM
  - [x] T1.3: `addEstimatedSteps(session, count)` — añade pasos estimados
  - [x] T1.4: `finishV3(session, nowMs)` — calcula duración, distancia, ritmo, cadencia
  - [x] T1.5: `restoreV3Session(snapshot)` — restaura sesión v3
  - [x] T1.6: Reusar `pause()`, `resume()`, helpers internos de v1
  - [x] T1.7: Exportar todas las funciones v3 en API pública
- [x] **T2: Escribir ≥15 tests unitarios**
  - [x] T2.1: createV3Session valida strideM > 0
  - [x] T2.2: createV3Session inicializa stepsMeasured=0, stepsEstimated=0
  - [x] T2.3: addSteps incrementa contador y distancia
  - [x] T2.4: addSteps multiples suman correctamente
  - [x] T2.5: distanceM = (stepsMeasured + stepsEstimated) × strideM
  - [x] T2.6: finishV3 calcula duración correcta
  - [x] T2.7: finishV3 calcula ritmo
  - [x] T2.8: finishV3 calcula cadencia
  - [x] T2.9: finishV3 congela strideM (sesión inmutable)
  - [x] T2.10: pause/resume funcionan (heredado)
  - [x] T2.11: lap/undo/finish v1 siguen funcionando (sin regresión)
  - [x] T2.12: restoreV3Session con snapshot válido
  - [x] T2.13: restoreV3Session con snapshot inválido → error
  - [x] T2.14: finishV3 pace con distanceM < 100 → null
  - [x] T2.15: addSteps con sesión finalizada → error

## Dev Notes

### Architecture Reference (AD-4, AD-5, AD-6, AD-8)
- AD-4: Session aggregate stepsMeasured/stepsEstimated/strideM
- AD-5: strideM única medida cruda (sin laps, sin stepsPerLap)
- AD-6: Cronómetro wall-clock (heredado)
- AD-8: Silent recovery (heredado, adaptado a v3)

### Implementation Notes
- Funciones v3 coexisten con v1 (migración en E0-S5)
- `cadenceSpm = stepsMeasured / ((durS - pausesS) / 60)` — solo tramos medidos
- `distanceM = (stepsMeasured + stepsEstimated) × strideM`, derivada
- `paceSecPerKm` = null si distanceM < 100 (SPEC §9)

## Dev Agent Record

### Completion Notes
- 182 tests unitarios implementados y pasando (100%)
- 0 regresiones en v1 (51 tests) ni StepDetector (39 tests)
- 272 tests total en suite, 0 fallos
- API v3: createV3Session, addSteps, addEstimatedSteps, finishV3, restoreV3Session, v3distance

## File List

- `domain.js` — MODIFIED: añadidas funciones v3 (createV3Session, addSteps, addEstimatedSteps, finishV3, restoreV3Session, v3distance)
- `test/session-v3-tests.js` — NEW: 182 tests

## Change Log

- 2026-07-07: Implementación E0-S2 completa. Session aggregate v3 con stepsMeasured/stepsEstimated/strideM. Coexiste con v1. 182 tests, 0 fallos.

## Status

**Current:** review
**Last updated:** 2026-07-07
