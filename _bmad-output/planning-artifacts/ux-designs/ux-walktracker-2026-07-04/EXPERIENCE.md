---
title: WalkTracker v2.0 — Experience Specification
type: experience
status: final
created: 2026-07-04
updated: 2026-07-04
sources:
  - _bmad-output/planning-artifacts/ux-designs/UX-BRIEF-walktracker-v2.md
  - _bmad-output/planning-artifacts/prds/prd-walktracker-2026-07-03/prd.md
  - input/SPEC_WalkTracker_v1.md
---

# EXPERIENCE.md — WalkTracker v2.0

## Foundation

Single-surface mobile (iPhone 14, 390×844 pt as reference). iOS Safari PWA with Capacitor native wrapper (v2.0). No UI framework — inherits platform conventions for navigation, gestures, and dynamic type. `DESIGN.md` is the visual identity reference; this spine is the experience.

Dark mode is the default surface; light mode is a fully equal alternative toggled via `prefers-color-scheme` or manual override.

## Information Architecture

| Surface | Reached from | Purpose |
|---|---|---|
| **Home** | App open (cold) | Start session, access Settings (⚙) and History (📋) |
| **Session** | Tap "Iniciar" on Home | Active walk: lap counting, live metrics, pause/finish |
| **Summary** | Tap "Finalizar" on Session | Session results + "Nueva sesión" |
| **Settings** | Tap ⚙ on Home | Calibration (stride, steps/lap), auto-mode toggle |
| **History** | Tap 📋 on Home | Session list with accumulated totals |

Navigation: top-right icons (⚙, 📋) on Home. No tab bar, no drawer. Modal stacks one level deep (Settings and History are full-screen replacements, not modals).

→ Composition reference: `mockups/key-screens-all.html` (5 pantallas, dark+light), `mockups/chosen-direction-volt-card.html` (dirección elegida). Spine wins on conflict.

## Voice and Tone

Microcopy. Brand voice is **energetic, direct, sports-focused**. `DESIGN.md` covers the visual aesthetic; this section covers the words.

| Do | Don't |
|---|---|
| "Sesión activa" | "You are currently in a walking session" |
| "● EN CURSO" | "Recording..." |
| "42 vueltas" | "You have completed 42 laps" |
| "toca para marcar" | "Please tap the button below to register a lap" |
| "✓ Escrito en Salud" | "Data successfully synced to Apple Health" |
| Short, complete phrases. Sports energy. | Exclamation marks, gamification, streaks |

## Component Patterns

Behavioral. Visual specs live in `DESIGN.md.Components`.

| Component | Use | Behavioral rules |
|---|---|---|
| **Metric Card** | Session screen | Shows lap count (hero) + 3 sub-metrics. Updates every second during active session. Frozen during pause. |
| **Lap Button (+1)** | Session screen | ≥40% viewport. Tap increments lap, plays beep, pulses. Disabled during pause. Always visible during active session. |
| **Control Buttons** | Session screen | Pausar ↔ Reanudar (toggle). Finalizar (always available). 44px minimum height. |
| **Toggle Switch** | Settings | "Modo automático" on/off. Persists to `wt:config`. Visual feedback immediate. |
| **Settings Field** | Settings | Editable: stride (number, >0), steps/lap (integer, >0). Readonly: perimeter (derived). Validation on save, not on input. |
| **History Row** | History list | Date + distance + duration + pace. Descending order (newest first). No edit, no delete (v1.0). |
| **Status Badge** | Session header, Summary | "● EN CURSO" (accent) during active session. "✓ Escrito en Salud" (success) after HealthKit write. |

## State Patterns

| State | Surface | Treatment |
|---|---|---|
| **Cold open** | Home | Shows "Iniciar" button, calibration info, ⚙ and 📋 icons. No loading state — instant. |
| **Active session** | Session | Metrics update every second. +1 button enabled. Pausar/Finalizar visible. Status badge "● EN CURSO". |
| **Paused session** | Session | Metrics frozen. +1 button disabled (opacity 0.4). Pausar → Reanudar (green). Finalizar still available. |
| **Session finished** | Summary | Shows final stats (laps, distance, duration, pace). "Nueva sesión" button. No back button — forward only. |
| **Empty history** | History | "Aún no hay sesiones registradas" centered, `muted` color. No action button. |
| **Auto-mode active** | Session | Step counter visible: "Paso X/62" with progress bar. +1 button still available as override. |
| **Permission denied** | Session (auto-mode) | Falls back to manual mode silently. No error banner. Step counter hidden. |
| **HealthKit write** | Summary | "✓ Escrito en Salud" badge appears below stats. If write fails, badge absent — no error shown (non-blocking). |
| **Recovery from purge** | Session | Auto-resumes with saved laps and wall-clock time. No prompt. Status badge shows "● EN CURSO". |

## Interaction Primitives

- **Tap to act.** Every interactive element responds to a single tap. No long-press, no swipe gestures in v1.0.
- **+1 button** is the primary interaction — largest, most accessible, operable with thumb without looking.
- **Pulse animation** on lap registration (0.15s scale 1.02) provides visual confirmation alongside the beep.
- **Beep** (Web Audio API, 440Hz, 80ms) is the primary feedback for lap registration. Cannot be disabled in v1.0.
- **Banned everywhere:** carousels, hero animations on open, badge counts, streaks, push notifications, pull-to-refresh, swipe-to-delete (v1.0).

## Accessibility Floor

Behavioral. Visual contrast lives in `DESIGN.md`.

- **VoiceOver:** every interactive element labeled with role + state. Lap button announces "Botón, más una vuelta". Metrics announce as "42 vueltas, 1.71 kilómetros, 18 minutos 24 segundos".
- **Dynamic Type:** all text scales with iOS Dynamic Type. `metric-hero` must remain legible at largest setting — no truncation, no overlap.
- **Reduce Motion:** skip the pulse animation on lap registration; show the updated count immediately.
- **Tap targets:** ≥44pt (iOS HIG). The +1 button is ≥40% viewport, far exceeding this.
- **Color contrast:** all text/background combinations meet WCAG AA (4.5:1 for normal text, 3:1 for large text). `accent-dark` (#CCFF00) on `canvas-dark` (#1A1A1A) = 15.4:1. `accent-light` (#CC9900) on `canvas-light` (#F5F5F7) = 4.6:1.
- **Focus traversal:** follows reading order on every surface (top → bottom).

## Key Flows

### Flow 1 — Paul walks his circuit (manual mode)

1. Paul opens WalkTracker from his home screen.
2. Home shows "Iniciar" button, calibration info (62 pasos × 0,655 m = 40,61 m/vuelta), ⚙ and 📋 icons.
3. He taps **Iniciar**.
4. **Session screen** appears: lap count "0", metrics "0.00 m", "00:00", "--:-- /km", status "● EN CURSO".
5. He starts walking. After one lap (~41m, ~30s), he taps **+1 VUELTA** with his thumb without looking.
6. **Beep** sounds, lap counter pulses to "1", distance updates to "40.61 m", time continues.
7. He switches to his music app (backgrounds WalkTracker). The cronómetro keeps running (wall-clock).
8. He returns to WalkTracker after 5 minutes. Metrics show the correct elapsed time.
9. He repeats steps 5-8 for 83 laps.
10. **Climax:** He taps **Finalizar**. Summary screen appears: "83 vueltas", "3.37 km", "62:00", "10:44 /km". He taps **Nueva sesión** to start again.

Failure: Safari purges WalkTracker while in background → on reopen, session auto-resumes with correct laps and wall-clock time. No data lost.

### Flow 2 — Paul recalibrates his circuit

1. Paul opens WalkTracker, taps ⚙ (Settings).
2. Settings screen shows: Zancada (0.655 m), Pasos por vuelta (62), Perímetro (40.61 m, readonly), toggle "Modo automático" (off).
3. He changes Pasos por vuelta to 60.
4. Perímetro recalculates live to "39.30 m".
5. He taps **Guardar**.
6. Returns to Home. Calibration info now shows "60 pasos × 0,655 m = 39.30 m/vuelta".
7. **Climax:** He starts a new session — the first lap registers as 39.30 m. Previous sessions in History still show their original perimeter (frozen at close).

### Flow 3 — Paul walks with auto-mode (pedometer)

1. Paul opens Settings, toggles **Modo automático** ON. Saves.
2. He taps **Iniciar** on Home.
3. iOS requests motion permission. Paul grants it.
4. Session screen appears with step counter: "Paso 0 / 60" and a progress bar.
5. He walks. Each step increments the counter. The progress bar fills.
6. At step 60: **beep** sounds, lap counter increments, step counter resets to "Paso 0 / 60", progress bar resets.
7. He can still tap **+1 VUELTA** manually to override if the pedometer misses a step.
8. **Climax:** After 83 auto-laps, he taps Finalizar. Summary shows the same stats as manual mode, plus "✓ Escrito en Salud" if HealthKit write succeeded.

Failure: motion permission denied → falls back to manual mode silently. Step counter hidden. +1 button works normally.
