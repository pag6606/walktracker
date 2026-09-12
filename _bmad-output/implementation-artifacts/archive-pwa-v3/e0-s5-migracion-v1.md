---
baseline_commit: NO_VCS
epic: E0
story_key: e0-s5-migracion-v1
status: review
---

# E0-S5 — Migración datos v1.1 → v3 (D1)

**Epic:** E0 — Conteo automático de pasos
**Prioridad:** Must | **Estimación:** S (1 día) | **Dependencias:** E0-S2, E0-S4

## Story

**Como** Paul, **quiero** que mis sesiones v1.1 se migren al nuevo formato sin perder datos, **para** mantener mi historial continuo.

## Acceptance Criteria

- [x] `migrateV1Session(v1Session)` transforma 1 sesión v1 → v3
- [x] `runMigration(storage, v1Sessions)` orquesta migración completa
- [x] `stepsMeasured = round(distanceM / strideM)` (estimación inversa)
- [x] `strideM = lapPerimeterM / stepsPerLap` (reconstruido)
- [x] `source: "migrated"` en cada sesión validada
- [x] `distanceM`, `durationS`, `paceSecPerKm`, `pausesS`, `startedAt`, `endedAt` preservados
- [x] Flag `isMigrated()` / `setMigrated()` para idempotencia
- [x] Sesiones corruptas (distanceM ≤ 0, strideM ≤ 0) → excluidas
- [x] ≥8 tests, 0 fallos

## Tasks / Subtasks

- [x] **T1: Implementar migración**
  - [x] T1.1: `migrateV1Session(v1Session)` — transforma 1 sesión v1 → v3
  - [x] T1.2: `runMigration(storage, v1Sessions)` — orquestación con idempotencia
  - [x] T1.3: Manejo de sesiones corruptas
- [x] **T2: Tests**
  - [x] T2.1: Sesión v1 normal → stepsMeasured correcto
  - [x] T2.2: strideM reconstruido
  - [x] T2.3: source migrated
  - [x] T2.4: Campos preservados
  - [x] T2.5: Corrupt distanceM ≤ 0
  - [x] T2.6: Corrupt strideM ≤ 0
  - [x] T2.7: Idempotencia
  - [x] T2.8: Múltiples sesiones
  - [x] T2.9: Empty array → migrated flag sin error
  - [x] T2.10: Mixed valid + corrupt

## Dev Notes

### Decisión D1
- `stepsMeasured = round(distanceM / strideM)` — matemáticamente idéntico a `laps × stepsPerLap`
- `strideM = lapPerimeterM / stepsPerLap` — reconstrucción exacta desde campos congelados v1
- Sesiones migradas cuentan para Goal/Logros (distancia correcta)
- Sesiones migradas excluidas de cadencia (cadenceSpm = 0)

## File List

- `migration.js` — NEW: migrateV1Session + runMigration
- `test/migration-tests.js` — NEW: 31 tests

## Change Log

- 2026-07-07: Implementación E0-S5 completa. Migración v1→v3 con idempotencia. 31 tests, 0 fallos.

## Status

**Current:** review
**Last updated:** 2026-07-07
