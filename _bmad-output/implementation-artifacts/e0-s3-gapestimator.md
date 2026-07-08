---
baseline_commit: NO_VCS
epic: E0
story_key: e0-s3-gapestimator
status: review
---

# E0-S3 — GapEstimator (extrapolación por cadencia)

**Epic:** E0 — Conteo automático de pasos
**Prioridad:** Must | **Estimación:** S (1-2 días) | **Dependencias:** E0-S1, E0-S2

## Story

**Como** Paul, **quiero** que al volver de background la app extrapole mis pasos por cadencia y los marque como estimados, **para** ser honesto con mis datos sin inventar.

## Acceptance Criteria

- [x] `estimateSteps(cadenceSpm, gapS)` retorna pasos estimados
- [x] `calculateCadence(stepsMeasured, activeSeconds)` retorna cadencia
- [x] Fórmula: `stepsEstimated = cadenceSpm × (gapS/60)`
- [x] Si cadence ≤ 0 o gapS ≤ 0 → retorna 0
- [x] ≥8 tests unitarios, 0 fallos

## Dev Notes

AD-13: GapEstimator pure domain. `estimateSteps` y `calculateCadence`.

## File List

- `domain.js` — MODIFIED: estimateSteps(), calculateCadence()
- `test/gapestimator-tests.js` — NEW: 16 tests

## Status

**Current:** review | **Last updated:** 2026-07-07
