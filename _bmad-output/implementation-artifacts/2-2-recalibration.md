# Story 2.2: Recalibración (aplicar a sesiones futuras, historial intacto)

Status: review

## Story

As Paul,
I want to change my calibration values and have the perimeter recalculated for future sessions without affecting closed sessions,
So that I can improve accuracy over time.

## Acceptance Criteria

1. **Given** a closed session with `lapPerimeterM: 40.61` (from 83 laps = 3370.63 m), **When** I recalibrate to `strideM: 0.70, stepsPerLap: 63` (new perimeter: 44.10 m), **Then** the closed session still shows `lapPerimeterM: 40.61` and `distanceM: 3370.63`
2. **Given** I recalibrate to new values, **When** I start a new session, **Then** the new session uses the new derived perimeter (44.10 m) and 1 lap = 44.10 m distance
3. **Given** I recalibrate multiple times, **When** I check the history, **Then** each closed session shows the perimeter that was active when it was closed

## Tasks / Subtasks

- [x] Task 1: Config persistence (already in AppConfig from 2.1) — wt:config saved
- [x] Task 2: Session start reads AppConfig.load() — btnStart handler
- [x] Task 3: Closed sessions immutable with frozen perimeter — Domain.createSession (AD-4)
- [x] Task 4: Verify recalibration flow
  - [x] Session 1 (old cal 40.61) → 83 laps = 3370.63 ✅
  - [x] User recalibrates → save to wt:config
  - [x] Session 2 (new cal 44.10) → 1 lap = 44.10 ✅
  - [x] Session 1 still has 40.61 and 3370.63 (historial intacto) ✅
