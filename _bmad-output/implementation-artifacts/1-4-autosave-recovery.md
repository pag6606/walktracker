# Story 1.4: Autosave + Recuperación silenciosa (wt:activeSession)

Status: review

## Story

As Paul,
I want my active session to be saved automatically and recovered silently if Safari closes,
So that I never lose my progress during a walk.

## Acceptance Criteria

1. **Given** an active session with 5 laps, **When** a lap is marked, **Then** `wt:activeSession` is saved with `{startedAtMs, laps, totalPausesMs, paused, strideM, stepsPerLap}`
2. **Given** an active session running for 15s without a lap, **When** 10s have passed since the last autosave, **Then** `wt:activeSession` is saved with the current state
3. **Given** `wt:activeSession` exists from a previous session (Safari purged), **When** the app opens, **Then** the session resumes silently (no prompt) with correct laps and time
4. **Given** `wt:activeSession` exists with `paused: true`, **When** the app opens, **Then** the session resumes in paused state with frozen elapsed
5. **Given** I press **Finalizar**, **When** the session is finalized, **Then** `wt:activeSession` is cleared

## Tasks / Subtasks

- [x] Task 1: Add restoreSession to Domain
  - [x] `restoreSession(snapshot)` — reconstructs session from snapshot shape
  - [x] Applies perimeter derivation, laps, distance, pause state
  - [x] Tested with 9 assertions in domain-tests.js
- [x] Task 2: Add autosave logic to UI Controller
  - [x] saveSnapshot(), clearSnapshot(), loadSnapshot() functions
  - [x] localStorage key: wt:activeSession
  - [x] Save after lap, pause, resume
  - [x] Save every 10s in tick interval
- [x] Task 3: Add silent recovery on page load
  - [x] autoRecover() IIFE after UI init
  - [x] recoverFromSnapshot() exposed from UI
  - [x] Session restored with correct laps, time, state
- [x] Task 4: Clear snapshot on finish / new session
  - [x] On Finalizar: clearSnapshot()
  - [x] On "Nueva sesión": clearSnapshot()
- [x] Task 5: Test
  - [x] Domain restoreSession: 11 tests (active, paused, invalid)
  - [x] Inline JS: all 6 symbols verified present
  - [x] Domain inline code parsed and working

## Dev Notes

- Architecture: AD-3 (localStorage via StoragePort), AD-4 (session immutable), AD-8 (silent recovery)
- Snapshot shape per ARCHITECTURE-SPINE.md: `{ startedAtMs, laps, totalPausesMs, paused, strideM, stepsPerLap }`
- Timer recovery: elapsed recomputed from startedAtMs (wall-clock). Time with app closed COUNTS.
- Paused recovery: if snapshot.paused=true, session restored in PAUSED state. pausedAtMs = Date.now() at recovery time (so the current pause interval counts from now).
- localStorage.clear() NOT called — solo se elimina `wt:activeSession`. `wt:config` y `wt:sessions` no se tocan.
- Source: epics.md Story 1.4, SPEC NFR-3, ARCHITECTURE-SPINE.md AD-8, storage shapes
