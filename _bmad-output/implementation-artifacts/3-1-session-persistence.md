# Story 3.1: Persistencia de sesiones finalizadas

Status: review

## Story

As Paul,
I want my completed sessions to be saved locally in wt:sessions,
So that my history survives device restarts.

## Acceptance Criteria

1. **Given** I finalize a session (10 laps, 406.1 m, etc), **When** finalized, **Then** session appended to `wt:sessions` array
2. **Given** wt:sessions has 3 previous sessions, **When** I finalize a new session, **Then** wt:sessions has 4 entries (append-only)
3. **Given** device restart, **When** app opens, **Then** previous sessions are available

## Tasks / Subtasks

- [x] Task 1: Save session to wt:sessions on finalize
  - [x] UUID via Date.now().toString(36) + random
  - [x] Append to existing array in localStorage
  - [x] Shape: {id, startedAt, endedAt, laps, lapPerimeterM, distanceM, durationS, paceSecPerKm, pausesS}
- [x] Task 2: Load sessions on demand — loadSessions() → parse or []
