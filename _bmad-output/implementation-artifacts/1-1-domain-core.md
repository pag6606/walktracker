# Story 1.1: Domain core (Session, Chronometer, MetricsCalculator, CalibrationProfile)

Status: review

## Story

As a developer,
I want a pure JS domain layer with no DOM or infrastructure dependencies,
so that the core logic is testable without a browser and enforces all invariants.

## Acceptance Criteria

1. **Given** a new Session is created with `startedAt` and default calibration (strideM=0.655, stepsPerLap=62), **When** `lap()` is called 83 times, **Then** `session.laps === 83`, `session.distanceM === 3370.63`, `session.lapPerimeterM === 40.61` (frozen at session start)
2. **Given** an active Session with 5 laps, **When** `undo()` is called, **Then** `session.laps === 4`, `session.distanceM === 162.44` (4 × 40.61)
3. **Given** an active Session with 0 laps, **When** `undo()` is called, **Then** `session.laps === 0` (invariante: nunca baja de 0)
4. **Given** a finalized Session, **When** any mutation method is called, **Then** it throws an error (sesión finalizada es inmutable)
5. **Given** a Chronometer with `startedAt = Date.now() - 3720000` and `totalPausesMs = 120000`, **When** `elapsedS(now)` is called, **Then** it returns 3600 seconds
6. **Given** a MetricsCalculator with `laps=83`, `lapPerimeterM=40.61`, `durationS=3720`, `pausesS=120`, **When** `paceSecPerKm()` is called, **Then** it returns 1068
7. **Given** a CalibrationProfile with `strideM=0.655` and `stepsPerLap=62`, **When** `recalibrate({strideM: 0.66, stepsPerLap: 63})` is called, **Then** it returns `{strideM: 0.66, stepsPerLap: 63, lapPerimeterM: 41.58}`
8. **Given** `recalibrate({strideM: 0, stepsPerLap: 62})`, **When** called, **Then** it throws `RangeError`
9. **Given** `recalibrate({strideM: 'x', stepsPerLap: 62})`, **When** called, **Then** it throws `TypeError`

## Tasks / Subtasks

- [x] Task 1: Create CalibrationProfile (recalibrate function)
  - [x] Pure function `recalibrate({strideM, stepsPerLap})` with validation (>0, finite)
  - [x] Returns `{strideM, stepsPerLap, lapPerimeterM}` derived
  - [x] Edge cases: zero, negative, NaN, non-numeric inputs → throws RangeError/TypeError
- [x] Task 2: Create Chronometer (wall-clock elapsed)
  - [x] Pure function `elapsedS(startedAtMs, totalPausesMs, nowMs)`
  - [x] Support for pause: if `pausedAtMs` is set, elapsed freezes at that moment
- [x] Task 3: Create Session aggregate root
  - [x] Factory `createSession`, mutation via `lap/undo/pause/resume/finish`
  - [x] Lap invariant (≥0), immutable after finish, perimeter frozen at start
- [x] Task 4: Create MetricsCalculator
  - [x] Pure functions: `distance(laps, lapPerimeterM)`, `pace(durationS, pausesS, distanceM)`
  - [x] Edge: zero distance → pace = Infinity
- [x] Task 5: Add inline tests (console.assert) for all functions
  - [x] Tests for all 9 ACs + extras (pause/resume, edge cases)
  - [x] 40 tests total, 0 failures
- [x] Task 6: Export all domain functions as `Domain` namespace (Node + browser)

## Dev Notes

- Relevant architecture: Hexagonal-lite (AD-1), Domain is pure (no DOM/infra). AD-4 (Session aggregate), AD-5 (perimeter derived), AD-6 (wall-clock), AD-7 (validation at frontier)
- All code will eventually be embedded in index.html. For testability, keep as pure functions exported via `window.WT = { Domain: { ... } }`
- Use vanilla JS (ES2020+). No classes if functions suffice; use plain objects for state (immutable pattern: mutations return new objects)
- File: `index.html` (temporary: can be tested in browser console or Node via standalone .mjs file)
- Testing: use inline `console.assert` for initial tests (later can upgrade to vitest if needed). ACs must pass.
- Source: epics.md Story 1.1, SPEC §6-8, ARCHITECTURE-SPINE.md AD-1/4/5/6/7

### Project Structure Notes

- The domain is the first piece of the single-file app. It will go into `index.html` as an inline `<script>` module or as IIFE attached to `window.WT.Domain`
- For now, create as a standalone `test/domain-tests.js` file for Node execution, plus the domain functions ready for embedding

### References

- [Source: input/SPEC_WalkTracker_v1.md#section-6]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md#AD-1]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md#AD-4]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md#AD-5]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md#AD-6]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-walktracker-2026-07-03/ARCHITECTURE-SPINE.md#AD-7]
- [Source: _bmad-output/planning-artifacts/epics.md#Story-11-domain-core-session-chronometer-metricscalculator-calibrationprofile]

## Dev Agent Record

### Agent Model Used

deepseek-v4-flash (OpenCode)

### Debug Log References

- `domain.js` created and tested via Node
- `test/domain-tests.js` with 40 tests, 100% pass rate
- All 9 acceptance criteria satisfied
- AC-1: 83 laps × 40.61 = 3370.63m ✅
- AC-2: Undo from 5→4 laps, distance recalculated ✅
- AC-3: Undo at 0 stays 0 ✅
- AC-4: Finalized session immutable (lap/undo/pause throw) ✅
- AC-5: elapsedS wall-clock gives 3600s for 62 min - 2 min pause ✅
- AC-6: pace(3720, 120, 3370.63) = 1068 s/km ✅
- AC-7: recalibrate(0.66, 63) → 41.58 ✅
- AC-8: strideM=0 → RangeError ✅
- AC-9: strideM='x' → TypeError ✅

### Completion Notes List

- Domain module created as domain.js (pure, no DOM/infra)
- Immutable state pattern: mutations return new frozen objects
- Perimeter frozen at session creation (AD-3/AD-5)
- Chronometer uses wall-clock Date.now() (AD-6)
- Validation at frontier (AD-7): all inputs checked before domain accepts them
- Export: `module.exports` for Node, `window.WT.Domain` for browser
- Ready to be embedded into index.html in Story 1.2

### File List

- `domain.js` — NEW — Domain core module (pure JS)
- `test/domain-tests.js` — NEW — Tests (40 assertions, 0 failures)
