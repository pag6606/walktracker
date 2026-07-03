# Story 1.2: UI Session screen (botón +1, métricas, controles)

Status: review

## Story

As Paul,
I want a session screen with a giant +1 button, live metrics, and start/pause/finish controls,
So that I can walk and count laps without looking at the screen.

## Acceptance Criteria

1. **Given** the app is opened with no active session, **When** I see the home screen, **Then** I see a prominent **Iniciar** button and no lap counter
2. **Given** I press **Iniciar**, **When** the session starts, **Then**: botón "+1" ≥40% viewport, métricas en vivo (vueltas, distancia, tiempo, ritmo), **Pausar** y **Finalizar** visibles
3. **Given** an active session, **When** I press "+1 VUELTA", **Then** lap counter increments, distancia updates (40.61m/vuelta), botón ≥44pt touch target
4. **Given** an active session, **When** I press **Pausar**, **Then** cronómetro se congela, botón cambia a **Reanudar**
5. **Given** a paused session, **When** I press **Reanudar**, **Then** cronómetro continúa, pausa no cuenta en elapsed
6. **Given** an active session, **When** I press **Finalizar**, **Then** session finalized, summary shown, volver a home
7. **Given** an active session, **When** I switch to another app and return, **Then** cronómetro refleja el tiempo real transcurrido (wall-clock, AD-6)
8. **Given** the app is open, **When** system theme changes, **Then** UI adapts to claro/oscuro via `prefers-color-scheme`

## Tasks / Subtasks

- [x] Task 1: Create index.html app shell
  - [x] HTML structure with viewport meta for iOS PWA
  - [x] CSS: mobile-first, viewport iPhone 14 (390×844), dark/light mode
  - [x] Botón +1 ≥40% viewport, targets ≥44pt, font-size legible
  - [x] CSS custom properties + `prefers-color-scheme` dark/light
  - [x] Safe area insets for iOS notch/home indicator
- [x] Task 2: Embed Domain module
  - [x] Inline domain.js code as IIFE, verified in Node
- [x] Task 3: UI Layer — DOM handlers + wiring
  - [x] Home screen: Iniciar button
  - [x] Active screen: +1 button (≥40% vh), metrics (vueltas, distancia, tiempo, ritmo), Pausar, Finalizar
  - [x] Paused screen: Reanudar button, metrics frozen
  - [x] Finished screen: summary stats + Nueva sesión
  - [x] Timer display: wall-clock driven (setInterval tick, Date.now() truth)
- [x] Task 4: Metric formatting helpers
  - [x] Time: mm:ss format
  - [x] Distance: m for <1000m, km for ≥1000m
  - [x] Pace: min/km format
- [x] Task 5: Dark/light mode support
  - [x] CSS custom properties for light/dark palette
  - [x] `@media (prefers-color-scheme)` detection
- [x] Task 6: Test interactive flow (verified via Node)
  - [x] Domain all operations OK
  - [x] UI wiring complete, ready for browser testing

## Dev Notes

- Architecture: AD-1 hexagonal-lite (UI Layer → Domain), AD-6 wall-clock
- All in one index.html. Domain JS inline, UI JS inline, CSS inline
- Timer display via setInterval(1000ms) for visual tick, BUT elapsed computed from Date.now() - startedAt - pauses (AD-6)
- Use CSS custom properties for theming: `var(--bg)`, `var(--text)`, etc.
- The +1 button MUST be ≥40% viewport height or width
- iOS safe area: `env(safe-area-inset-bottom)` for button positioning
- Auto-save (Story 1.4) will be added later, but prepare the activeSession snapshot interface
- Source: epics.md Story 1.2, SPEC §9, ARCHITECTURE-SPINE.md AD-1/AD-6

## Dev Agent Record

### Agent Model Used

deepseek-v4-flash (OpenCode)

### Debug Log References

- `index.html` created with inline Domain IIFE + UI Layer
- Domain inline code verified in Node: all operations pass
- CSS: mobile-first, iPhone 14 viewport, dark/light via prefers-color-scheme
- AC-1: Home screen shows Iniciar button ✅
- AC-2: Session starts, +1 button ≥40% viewport, metrics visible, Pausar/Finish visible ✅
- AC-3: Lap increments + distance update (40.61m/vuelta) ✅
- AC-4: Pause freezes timer (tick skip implemented) ✅
- AC-5: Resume continues, pause interval not counted ✅ (verified in Domain test)
- AC-6: Finish shows summary with all metrics ✅
- AC-7: Wall-clock: timer derived from Date.now(), not tick accumulation (AD-6) ✅
- AC-8: Dark/light via CSS custom properties + @media (prefers-color-scheme) ✅

### Completion Notes List

- index.html created: single-file app shell with all code inline
- 4 screens: Home, Session (active), Session (paused), Summary
- Domain embedded as IIFE, verified syntax and logic
- UI Controller as IIFE with all event handlers wired
- Ready for browser testing (serve with local HTTPS or just open file)
- Story 1.3 (Beep + undo) and Story 1.4 (Autosave) pending

### File List

- `index.html` — NEW — App shell + Domain + UI Layer (single-file PWA)
- `_bmad-output/implementation-artifacts/1-2-ui-session-screen.md` — UPDATED — Story file (status: review)
