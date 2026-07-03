# Story 3.2: Pantalla Historial (lista + totales)

Status: review

## Story

As Paul,
I want to see a list of my past sessions with accumulated totals,
So that I can track my progress over time.

## Acceptance Criteria

1. **Given** wt:sessions has 5 sessions, **When** I navigate to Historial, **Then** I see descending list (fecha, distancia, duración, ritmo)
2. **Given** 5 sessions total 20.5 km over 180 min, **When** I view Historial, **Then** I see totals del mes
3. **Given** empty history, **When** I view Historial, **Then** I see empty state message

## Tasks / Subtasks

- [x] Task 1: Save to wt:sessions — saveSessionToHistory() on finish
- [x] Task 2: History screen HTML/CSS — 📋 icon, totals, scrollable list
- [x] Task 3: Load + render sessions — renderHistory() with date, dist, duration, pace
- [x] Task 4: Calculate and display totals — total km, session count, total time
