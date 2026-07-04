---
title: WalkTracker v2.0
name: WalkTracker
type: design
status: final
created: 2026-07-04
updated: 2026-07-04
sources:
  - _bmad-output/planning-artifacts/ux-designs/UX-BRIEF-walktracker-v2.md
  - _bmad-output/planning-artifacts/prds/prd-walktracker-2026-07-03/prd.md
  - input/SPEC_WalkTracker_v1.md
colors:
  canvas-dark: '#1A1A1A'
  canvas-light: '#F5F5F7'
  surface-dark: '#2A2A2A'
  surface-light: '#FFFFFF'
  accent-dark: '#CCFF00'
  accent-light: '#CC9900'
  secondary: '#FF6600'
  danger: '#FF453A'
  text-dark: '#FFFFFF'
  text-light: '#1D1D1F'
  muted-dark: '#777777'
  muted-light: '#86868B'
  border-dark: '#3A3A3A'
  border-light: '#D2D2D7'
  success: '#30D158'
typography:
  metric-hero:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 64px
    fontWeight: '900'
    lineHeight: '1'
    letterSpacing: '-0.03em'
  metric-hero-mobile:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 48px
    fontWeight: '900'
    lineHeight: '1'
    letterSpacing: '-0.03em'
  metric-sub:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 16px
    fontWeight: '700'
    lineHeight: '1.2'
  label:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 11px
    fontWeight: '400'
    lineHeight: '1.3'
    color: '{colors.muted-dark}'
  body:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 15px
    fontWeight: '400'
    lineHeight: '1.4'
  button-primary:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 24px
    fontWeight: '900'
    lineHeight: '1.2'
  button-secondary:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.3'
  header-title:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 17px
    fontWeight: '700'
    lineHeight: '1.2'
  status-badge:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 12px
    fontWeight: '600'
    lineHeight: '1.3'
rounded:
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  full: 9999px
spacing:
  '1': 4px
  '2': 8px
  '3': 12px
  '4': 16px
  '5': 24px
  '6': 32px
  margin: 16px
---

## Brand & Style

WalkTracker is a **sports energy** app for a single user who walks a small circuit and wants precise, deterministic lap counting — not GPS approximation. The visual language borrows from **Adidas Running** and **Strava**: bold numbers, card-based metric grouping, and a vibrant accent that screams *movement*.

The **Volt** palette (neon yellow-green on dark charcoal, golden amber on light) delivers maximum legibility under direct sunlight while maintaining an energetic, modern feel. The **Card Sport** layout groups metrics in elevated cards with soft shadows, creating a native iOS app aesthetic rather than a web page.

The design is **dark-mode-first** (the default canvas is `#1A1A1A`), with light mode as a fully equal alternative. Both modes use the same structural layout; only color tokens swap.

## Colors

The palette is two-tone energy: a neon accent for the primary action and metrics, a warm secondary for distance, and a red danger for destructive actions.

- **Canvas (`#1A1A1A` dark / `#F5F5F7` light)** is the primary background. Dark mode is the default; light mode uses Apple's system gray for familiarity and sun-legibility.
- **Surface (`#2A2A2A` dark / `#FFFFFF` light)** is the card and control background. Cards use a subtle shadow in light mode; tonal separation in dark mode.
- **Accent (`#CCFF00` dark / `#CC9900` light)** is the only chromatic hero color. Used for the lap count number, the +1 button, and the "EN CURSO" status. Means *live, active, moving*.
- **Secondary (`#FF6600`)** is the distance metric color. Warm orange that pairs with the accent without competing.
- **Danger (`#FF453A`)** is the Finalizar button. Apple's system red, consistent with iOS destructive actions.
- **Success (`#30D158`)** is Apple's system green, used for the Reanudar button and HealthKit confirmation.
- **Text (`#FFFFFF` dark / `#1D1D1F` light)** is the primary text color.
- **Muted (`#777777` dark / `#86868B` light)** is for labels, secondary text, and disabled states.
- **Border (`#3A3A3A` dark / `#D2D2D7` light)** is the hairline divider for list items and input fields.

Avoid: gradients on surfaces (only on the +1 button in dark mode for energy), more than 2 chromatic colors per screen, decorative icons where text suffices.

## Typography

Platform system fonts only — no custom fonts to load (offline-first, NFR-1). The `-apple-system` stack gives SF Pro on iOS, which is the native sports app standard.

| Role | Size | Weight | Use |
|---|---|---|---|
| `metric-hero` | 64px (48px mobile) | 900 | Lap count number — the biggest thing on screen |
| `metric-sub` | 16px | 700 | Distance, time, pace values |
| `label` | 11px | 400 | Metric labels ("distancia", "tiempo", "ritmo") |
| `body` | 15px | 400 | Settings fields, history rows, microcopy |
| `button-primary` | 24px | 900 | "+1 VUELTA" text |
| `button-secondary` | 14px | 600 | Pausar, Finalizar, Guardar |
| `header-title` | 17px | 700 | Screen titles, "Sesión activa" |
| `status-badge` | 12px | 600 | "● EN CURSO", HealthKit status |

Dynamic type: all text scales with iOS Dynamic Type. `metric-hero` must remain legible at largest setting — no truncation.

## Layout & Spacing

Scale: 4 / 8 / 12 / 16 / 24 / 32 px. iPhone 14 reference (390×844 pt).

- **Margins**: 16px horizontal on all screens.
- **Card padding**: 20px internal.
- **Button +1 height**: ≥40% viewport height (FR-02, NFR-4).
- **Touch targets**: ≥44pt minimum (NFR-4).
- **Safe areas**: `env(safe-area-inset-bottom)` respected on all bottom-aligned controls.
- **Vertical rhythm**: Header → Card → Button → Controls, with consistent gaps (`spacing.3` = 12px between major blocks).

Single-column always. No multi-column layouts. Modal stacks one level deep maximum.

## Elevation & Depth

Cards are distinguished from canvas by tone (dark) or shadow (light):

- **Dark mode**: `surface-dark` (`#2A2A2A`) on `canvas-dark` (`#1A1A1A`) — no shadow, tonal separation only.
- **Light mode**: `surface-light` (`#FFFFFF`) on `canvas-light` (`#F5F5F7`) with `box-shadow: 0 2px 8px rgba(0,0,0,0.06)`.
- **Buttons**: no elevation except the +1 button in light mode (`box-shadow: 0 4px 16px rgba(204,153,0,0.3)`).
- **No floating elements**: everything sits on the card or canvas plane.

## Shapes

| Token | Radius | Use |
|---|---|---|
| `rounded/sm` | 8px | Input fields, small buttons |
| `rounded/md` | 12px | Control buttons (Pausar, Finalizar), list rows |
| `rounded/lg` | 16px | Cards, settings fields |
| `rounded/xl` | 20px | +1 VUELTA button |
| `rounded/full` | 9999px | Status badges, toggle knobs |

Nothing fully rounded except the toggle knob and status badge. The +1 button is `rounded/xl` — soft but not a pill.

## Components

→ Composition reference: `mockups/key-screens-all.html` (5 pantallas, dark+light), `mockups/chosen-direction-volt-card.html` (dirección elegida). Spine wins on conflict.

### Metric Card
- `surface` background, `rounded/lg` padding, `spacing.5` internal
- Hero metric (lap count) at top: `metric-hero` in `accent` color
- Sub-metrics row below: 3 columns, `metric-sub` values in `secondary` or `text`, `label` below each
- Light mode: shadow; dark mode: tonal

### Lap Button (+1)
- `accent` background, `rounded/xl`, ≥40% viewport height
- `button-primary` text in `canvas-dark` (dark mode) or `text-dark` (light mode)
- Subtitle in `muted` below main text
- Pulse animation on tap (0.15s scale 1.02)
- Touch target: fills available width, min-height 40vh

### Control Buttons
- Two buttons side-by-side: Pausar (left), Finalizar (right)
- Pausar: `surface` background, `muted` text, `rounded/md`
- Finalizar: `danger` background, `text-dark` text, `rounded/md`
- Reanudar: `success` background, `text-dark` text (replaces Pausar when paused)
- Height: 44px minimum

### Toggle Switch
- 48×28px pill, `border` background when off, `success` when on
- White knob (24px circle) slides left/right
- Used for "Modo automático" in Settings

### History Row
- `surface` background, `rounded/md`, padding `spacing.4`
- Date in `label` (top), metrics row below: distance, duration, pace in `metric-sub`
- Hairline divider (`border`) between rows
- No icon, no avatar — text-only

### Settings Field
- Label in `body` (top), input field below
- Input: `surface` background, `rounded/sm`, `spacing.4` padding, `border` focus ring
- Readonly fields: transparent background, `accent` text, no border
- Error message in `danger` below field, `label` size

### Status Badge
- `rounded/full`, `status-badge` text
- "● EN CURSO" in `accent` color
- "✓ Escrito en Salud" in `success` color (HealthKit confirmation)

## Do's and Don'ts

| Do | Don't |
|---|---|
| Use `accent` only for live/active metrics and primary action | Use `accent` for chrome, decoration, or secondary text |
| Card-based metric grouping (all metrics in one card) | Scatter metrics across the screen |
| System fonts only (no custom font loading) | Import Google Fonts or custom typefaces |
| Dark mode as default, light as equal alternative | Light-only or dark-only |
| ≥40% viewport for +1 button | Shrink the button to fit other content |
| Text-only state indicators ("✓ Escrito en Salud") | Icon-only states without text labels |
| Hairline dividers at lowest legible contrast | Thick borders or gradient fills |
| Honor safe areas and 44pt touch targets | Overlap the home indicator or notch |
