---
title: WalkTracker v3.0 PWA — Experience Specification
type: experience
status: final
created: 2026-07-04
updated: 2026-07-07
sources:
  - input/SPEC_WalkTracker_v3_PWA.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/EXPERIENCE.md
---

# EXPERIENCE.md — WalkTracker v3.0 PWA

## Foundation

Single-surface mobile (iPhone 14, 390×844 pt as reference). iOS Safari PWA — no Capacitor wrapper. HTML/JS/CSS vanilla, single-file app shell + `sw.js` + `manifest.webmanifest`. `DESIGN.md` is the visual identity reference; this spine is the experience.

Dark mode is the default surface; light mode is a fully equal alternative toggled via `prefers-color-scheme` or manual override.

**v3 core shift:** the app counts steps automatically via accelerometer (`DeviceMotionEvent`), not laps. Distance = steps × stride. The emotional center is **visible progress** — the weekly goal ring, achievement recognition, and the upward trend in history.

## Information Architecture

| Surface | Reached from | Purpose |
|---|---|---|
| **Home** | App open (cold) | Weekly goal ring (hero), weather preview, "Iniciar caminata", access to Settings (⚙), History (📋), Achievements (🏆) |
| **Session** | Tap "Iniciar caminata" on Home | Active walk: step counting, live metrics (distance/steps/time/pace/cadence), weather snapshot, pause/finish, recovery indicator (if applicable) |
| **Motivational Overlay** | Auto-triggered at session start | 3-4s full-screen quote, skippable by tap |
| **Summary** | Tap "Finalizar" on Session | Session results + achievements unlocked + goal progress update |
| **Settings** | Tap ⚙ on Home | Stride, weekly goal, sound toggle, export (with last backup date), delete data |
| **History** | Tap 📋 on Home | Session list with accumulated totals + trend chart (4-week bars) |
| **Achievements** | Tap 🏆 on Home | Grid of 14 achievement badges (locked/unlocked/in-progress) |
| **Motion Denied** | Auto-triggered if motion permission denied | Full-screen explanation + settings link |

Navigation: top-right icons (⚙, 📋, 🏆) on Home. No tab bar, no drawer. Screen replacements (not modals) for Settings, History, Achievements. Motivational overlay is a transient full-screen layer.

## Voice and Tone

Microcopy. Brand voice is **energetic, direct, sports-focused**. `DESIGN.md` covers the visual aesthetic; this section covers the words.

| Do | Don't |
|---|---|
| "Sesión activa" | "You are currently in a walking session" |
| "● EN CURSO" | "Recording..." |
| "3.2 km" | "You have walked 3.2 kilometers" |
| "toca para iniciar" | "Please tap the button below to start" |
| "Meta cumplida 🎉" | "Congratulations! You have achieved your weekly goal!" |
| "14 pasos estimados (~)" | "We estimated your steps during the gap" |
| Short, complete phrases. Sports energy. Celebrate progress. | Exclamation marks everywhere, gamification overload, streaks |
| "Mantén la pantalla encendida" | "Wake lock acquisition failed" |
| "Sensor de movimiento requerido" | "DeviceMotionEvent permission denied" |

## Component Patterns

Behavioral. Visual specs live in `DESIGN.md.Components`.

| Component | Use | Behavioral rules |
|---|---|---|
| **Goal Ring** | Home screen | Shows weekly km progress. Updates on session finish. Fills with `accent` proportionally. At 100%: switches to `success`, triggers celebration toast. |
| **Metric Card** | Session screen | Shows distance (hero) + 4 sub-metrics (steps, time, pace, cadence). Updates every second during active session. Frozen during pause. Steps show "~" prefix if estimated portion exists. |
| **Weather Card** | Session screen (below metrics) | Shows snapshot from session start. Temp large + condition. Degrades to "Sin clima" if no network. Static during session. |
| **Session Controls** | Session screen | Pausar ↔ Reanudar (toggle). Finalizar (always available). 44px minimum height. |
| **Estimated Steps Banner** | Session screen (below step counter) | Appears when returning from background with estimated gap. Shows "~ N pasos estimados" + "Descartar" button. Disappears on discard or after 30s. |
| **Wake Lock Banner** | Session screen (top sticky) | Appears if wake lock fails. "Mantén la pantalla encendida para contar pasos". Dismissible. Reappears if wake lock fails again. |
| **Recovery Indicator** | Session screen (top, transient) | "Sesión recuperada" banner, `muted` text, auto-dismiss 3s. Only after purge/crash recovery. |
| **Motivational Overlay** | Session start (transient) | Full-screen `accent` background with quote. Auto-dismiss 3-4s. Tap to skip immediately. No close button. `role="dialog" aria-modal="true" aria-label="Frase motivacional"`. Keyboard Escape to dismiss. |
| **Achievement Badge** | Achievements screen | 2-column grid. Locked: muted + 🔒 (`aria-label="Logro bloqueado: [nombre]"`). Unlocked: accent + name. In-progress: progress bar at bottom. |
| **Celebration Toast** | Any screen (non-blocking) | Top of screen, `accent` background. Auto-dismiss 2-3s. Queued if multiple. Sound plays simultaneously. `role="status" aria-live="polite"`. |
| **History Row** | History list | Date + distance + duration + pace. Descending order (newest first). "~" marker on estimated sessions. Delete icon (🗑️) right-aligned, 44×44px hit area → confirmation dialog. |
| **Settings Field** | Settings | Editable: stride (number, >0), weekly goal (number, >0). Readonly: last export date. Validation on save. Export button triggers Web Share. Delete data: "Borrar todos los datos" requires confirmation dialog. |
| **Motion Denied Screen** | Auto (permission denied) | Full-screen, centered. Explanation + "Abrir Configuración" button. No session can start without motion permission. |
| **Status Badge** | Session header | "● EN CURSO" (accent) during active session. |
| **Toggle Switch** | Settings | "Sonido" on/off. Persists to `wt:config`. Visual feedback immediate. |
| **Summary Screen** | After session finish | Final distance (hero), stats grid (steps measured/estimated, duration, pace), achievements unlocked, goal progress, "Nueva sesión" button. No back button — forward only. |

## State Patterns

| State | Surface | Treatment |
|---|---|---|
| **Cold open** | Home | Shows goal ring (current week progress), weather preview, "Iniciar caminata", ⚙📋🏆 icons. No loading state — instant. |
| **Active session** | Session | Metrics update every second. Steps counted by accelerometer. Pausar/Finalizar visible. Status badge "● EN CURSO". Weather snapshot visible. |
| **Paused session** | Session | Metrics frozen. Pausar → Reanudar (green). Finalizar still available. |
| **Background → foreground** | Session | Time recalculated by wall-clock. If gap > 0 and session was active: estimated steps banner appears ("~ N pasos estimados") with "Descartar" button. Wake lock re-acquired. |
| **Session finished** | Summary | Shows final stats (distance, steps measured, steps estimated, duration, pace). Achievements unlocked listed. Goal progress update. "Nueva sesión" button. |
| **Motivational overlay** | Session (transient) | Full-screen accent with quote. Auto-dismiss 3-4s. Tap to skip. Metrics start counting behind it. |
| **Goal completed** | Any | Celebration toast: "Meta semanal cumplida 🎉". Non-blocking. Ring switches to `success`. |
| **Achievement unlocked** | Any (during session or summary) | Celebration toast: "Logro desbloqueado: [nombre]". Non-blocking. Badge updates in Achievements screen. |
| **Wake lock failed** | Session | Top sticky banner in `secondary`. "Mantén la pantalla encendida para contar pasos". Dismissible. |
| **No network** | Home/Session | Weather shows "Sin clima". Everything else works offline. |
| **Motion permission denied** | Motion Denied screen | Full-screen explanation. No session can start. "Abrir Configuración" button. |
| **Empty history** | History | "Aún no hay sesiones registradas" centered, `muted` color. No trend chart shown. |
| **Empty achievements** | Achievements | All 14 badges shown as locked. No empty state. |
| **Backup overdue** | Settings + Home | Banner in Settings: "Último respaldo: hace X días. Exporta tu historial." Badge on ⚙ icon in Home. |
| **Recovery from purge** | Session | Auto-resumes with saved session and wall-clock time. "Sesión recuperada" indicator appears for 3s (top banner, `muted`). Estimated steps banner appears for the gap. |

## Interaction Primitives

- **Tap to act.** Every interactive element responds to a single tap. No long-press, no swipe gestures in v3.0.
- **"Iniciar caminata" button** is the primary action on Home — large, accessible, below the goal ring.
- **Beep** (Web Audio API) is the primary feedback for: session start, km milestone, goal completed, achievement unlocked. Volume respectful with music playback (short sounds).
- **Goal ring** is the visual anchor of Home — 300px, centered, fills with `accent` as weekly km accumulates.
- **Banned everywhere:** carousels, hero animations on open, badge counts, streaks, pull-to-refresh, swipe-to-delete.
- **New in v3:** motivational overlay (tap to skip), estimated steps banner (dismissable), celebration toast (non-blocking).

## Accessibility Floor

Behavioral. Visual contrast lives in `DESIGN.md`.

- **VoiceOver:** every interactive element labeled with role + state. Distance announces as "3.2 kilómetros". Steps announce as "4,980 pasos" or "4,980 pasos, 320 estimados" if estimated. Navigation icons: `aria-label="Configuración"`, `aria-label="Historial"`, `aria-label="Logros"`. Motivational overlay: `role="dialog" aria-modal="true"`. Celebration toast: `role="status" aria-live="polite"`. Achievement locked: `aria-label="Logro bloqueado: [nombre]"`.
- **Dynamic Type:** all text scales with iOS Dynamic Type. `metric-hero` and `quote-hero` must remain legible at largest setting — no truncation, no overlap. Max-scale cap: `clamp()` limits `metric-hero` to 80px and `quote-hero` to 36px at 200% Dynamic Type.
- **Reduce Motion:** skip motivational overlay fade-in; show quote immediately. Celebration toast appears without animation. Goal ring fill animation: instant transition under `prefers-reduced-motion`.
- **Tap targets:** ≥44pt (iOS HIG). The "Iniciar caminata" button is large, far exceeding this.
- **Color contrast:** all text/background combinations meet WCAG AA (4.5:1 for normal text, 3:1 for large text). `accent-dark` (#CCFF00) on `canvas-dark` (#1A1A1A) = 15.4:1. `estimated` (#FFB347) on `surface-dark` (#2A2A2A) = 7.2:1. `estimated-light` (#CC7A00) on `surface-light` (#FFFFFF) = 4.6:1. `muted-dark` (#999999) on `canvas-dark` = 4.9:1. `muted-light` (#666666) on `canvas-light` = 5.0:1.
- **Focus traversal:** follows reading order on every surface (top → bottom). Focus ring: `accent` 2px outline on all interactive elements (high-contrast, visible in both modes).
- **Keyboard:** Escape dismisses motivational overlay. Tab order follows visual reading order.
- **Estimated steps distinction:** "~" prefix + `estimated` color ensures screen readers and sighted users can distinguish measured from estimated data.

## Key Flows

### Flow 1 — Paul walks and sees his progress grow

1. Paul opens WalkTracker from his home screen.
2. **Home** shows: large goal ring at 6.2/10 km (62% filled, `accent`), weather preview ("14°C, Parcialmente nublado"), "Iniciar caminata" button, ⚙📋🏆 icons.
3. He taps **Iniciar caminata**.
4. **Motivational overlay** appears: full-screen `accent` with quote "Cada paso te acerca a tu mejor versión" in `canvas-dark`. He taps to skip after 1 second.
5. **Session screen** appears: distance "0.00 km" (hero, `accent`), steps "0", time "00:00", pace "--:-- /km", cadence "-- spm". Weather snapshot below metrics. Status "● EN CURSO".
6. He starts walking with phone in hand, screen active. Steps count automatically via accelerometer. Distance updates: "0.05 km", "0.12 km"...
7. He switches to his music app (backgrounds WalkTracker). The cronómetro keeps running (wall-clock).
8. He returns to WalkTracker after 5 minutes. Time shows correct elapsed. Estimated steps banner appears: "~ 420 pasos estimados" with "Descartar" button. He taps "Descartar" — banner disappears.
9. He continues walking. Distance reaches "1.00 km" → **beep** sounds, celebration toast: "1 km completado 🎉" (non-blocking, 2s).
10. **Climax:** After 45 minutes, distance shows "3.2 km", steps "4,980". He taps **Finalizar**.
11. **Summary** appears: "3.2 km", "4,980 pasos", "45:00", "9:22 /km". Below: "Logro desbloqueado: Tu primer kilómetro 🏅". Goal ring update: "6.2 → 9.4 km". He taps **Nueva sesión**.

Failure: Safari purges WalkTracker while in background → on reopen, session auto-resumes with correct distance (wall-clock) and estimated steps banner for the gap. No data lost.

### Flow 2 — Paul fulfills his weekly goal

1. Paul opens WalkTracker. Home shows goal ring at 8.5/10 km (85% filled).
2. He starts a session, walks 1.8 km.
3. At session finish: distance "1.8 km", total week becomes 10.3 km.
4. **Celebration toast** appears: "Meta semanal cumplida 🎉" (non-blocking, 2s). Ring switches to `success` green, fills to 100%.
5. Summary shows: "Logro desbloqueado: Primera meta semanal 🏆".
6. Paul feels the satisfaction of seeing his capacity recognized.

### Flow 3 — Paul checks his progress trend

1. Paul taps 📋 (History) on Home.
2. **History** shows: session list (newest first) with distance, duration, pace. Totals at top: "Esta semana: 10.3 km, 3 sesiones".
3. Below totals: **trend chart** — 4 vertical bars (last 4 weeks), heights proportional to km. Current week bar in `accent`, previous weeks in `muted`.
4. Paul sees the upward trend: 6.2 → 7.8 → 9.1 → 10.3 km. Satisfaction.

### Flow 4 — Paul checks his achievements

1. Paul taps 🏆 (Achievements) on Home.
2. **Achievements** shows: 2-column grid of 14 badges.
3. Unlocked (3): "Tu primer kilómetro" 🏅, "Primera meta semanal" 🏆, "Caminata bajo la lluvia" 🌧️ — accent icons, names in `text`.
4. In-progress (2): "10 km en una sesión" (progress bar at 32%), "7 días consecutivos" (progress bar at 43%).
5. Locked (9): muted icons, names in `muted`, 🔒 overlay.
6. Paul sees what's next and feels motivated.

### Flow 5 — Paul recalibrates his stride

1. Paul opens Settings (⚙).
2. Settings shows: Zancada (0.655 m), Meta semanal (10.0 km), Sonido (ON), Último respaldo (hace 15 días), Exportar, Borrar datos.
3. He changes Zancada to 0.670 m.
4. He taps **Guardar**.
5. Returns to Home. New stride applies to future sessions. Previous sessions in History keep their frozen stride.

### Flow 6 — Motion permission denied

1. Paul opens WalkTracker, taps "Iniciar caminata".
2. iOS requests motion permission. Paul taps "Don't Allow" (accidentally or intentionally).
3. **Motion Denied screen** appears: full-screen, centered. "Sensor de movimiento requerido" + explanation + "Abrir Configuración" button.
4. Paul taps "Abrir Configuración" → Safari opens Settings app (if URL scheme works) or shows instructions.
5. Paul enables motion permission, returns to WalkTracker, starts session successfully.
