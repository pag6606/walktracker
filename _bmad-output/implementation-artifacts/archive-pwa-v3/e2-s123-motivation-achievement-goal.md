---
baseline_commit: NO_VCS
epic: E2
story_key: e2-s123-motivation-achievement-goal
status: review
---

# E2-S1+S2+S3 — Motores de motivación, logros y meta semanal

**Epic:** E2 — Motivación: frases + logros + meta
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** E0-S4

## Story

**Como** Paul, **quiero** ver frases motivacionales, desbloquear logros al cumplir hitos, y seguir mi meta semanal, **para** sentir que mi progreso es reconocido.

## Acceptance Criteria

- [x] `quotes.json` contiene 100 frases (asset local)
- [x] `selectQuote(quotes, recentQuoteIds)` sin repetición en últimas 20
- [x] Catálogo de 14 logros definido y evaluable
- [x] `getWeeklyProgress()` calcula km de la semana ISO
- [x] ≥32 tests, 0 fallos

## File List

- `quotes.json` — NEW: 100 frases
- `motivation.js` — NEW: 3 engines
- `test/motivation-tests.js` — NEW: 32 tests

## Status

**Current:** review | **Last updated:** 2026-07-07
