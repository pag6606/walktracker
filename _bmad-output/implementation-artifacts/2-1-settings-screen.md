# Story 2.1: Pantalla Ajustes (zancada, pasos/vuelta, perímetro derivado)

Status: review

## Story

As Paul,
I want a settings screen where I can see and edit my stride length and steps per lap,
So that I can calibrate the perimeter for my circuit.

## Acceptance Criteria

1. **Given** the app is opened, **When** I navigate to **Ajustes**, **Then** I see editable fields for zancada (default: 0.655 m) and pasos por vuelta (default: 62), and perímetro (readonly: 40.61 m)
2. **Given** I change **Zancada** to 0.70, **When** the field updates, **Then** Perímetro recalculates to 43.40 m (0.70 × 62)
3. **Given** I enter **Zancada** = 0, **When** I try to save, **Then** the input is rejected with error message
4. **Given** I enter **Pasos por vuelta** = -5, **When** I try to save, **Then** error message
5. **Given** I enter valid values and save, **When** saved, **Then** `wt:config` is updated, **And** the next session uses the new derived perimeter

## Tasks / Subtasks

- [x] Task 1: Add Settings screen HTML/CSS
  - [x] Screen Ajustes: zancada, pasos/vuelta, perímetro readonly, errores, Guardar + Volver
  - [x] Settings icon on home screen (⚙)
- [x] Task 2: Load/save config via localStorage
  - [x] AppConfig.load() → wt:config o defaults (0.655, 62)
  - [x] AppConfig.save() → localStorage.setItem
- [x] Task 3: Validation on save
  - [x] strideM > 0 and finite → error message otherwise
  - [x] stepsPerLap > 0 and finite → error otherwise
  - [x] Live perimeter preview on input change
- [x] Task 4: Wire config into session creation
  - [x] btnStart reads AppConfig.load() → Domain.createSession
  - [x] Home screen calibration text updates dynamically
- [x] Task 5: Test
  - [x] AppConfig.load/save verified in Node
  - [x] Domain recalibrate works with config values
  - [x] 51 domain tests still pass (no regressions)

## Dev Agent Record

### Completion Notes List

- Settings screen added with 3 fields: zancada (edit), pasos/vuelta (edit), perímetro (readonly/derived)
- AppConfig module: load() with fallback defaults, save() validation
- Live preview: recalcula perímetro al escribir (input event)
- Config se lee al iniciar sesión (btnStart → AppConfig.load() → Domain.createSession)
- Calibración inicial dinámica en home screen
- Recalibración completa en Story 2.2 (verificada: sesiones viejas congeladas, nuevas usan nuevo perímetro)

### File List

- `index.html` — MODIFIED — Añadidas: settings screen, AppConfig, handlers, home calib dinámico

## Dev Notes

- Architecture: AD-3 (localStorage), AD-5 (perimeter derived), AD-7 (validation at frontier)
- Config key: `wt:config` → `{ strideM, stepsPerLap }`
- Domain.recalibrate() already validates and computes perimeter — use it directly
- Previous session history NOT affected (perimeter frozen per session, AD-3/AD-5)
- Source: epics.md Story 2.1, SPEC RF-05, ARCHITECTURE-SPINE.md AD-5/AD-7
