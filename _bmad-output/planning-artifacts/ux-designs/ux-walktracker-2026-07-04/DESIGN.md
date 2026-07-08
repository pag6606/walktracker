---
title: WalkTracker v3.0 PWA
name: WalkTracker
type: design
status: final
created: 2026-07-04
updated: 2026-07-07
sources:
  - input/SPEC_WalkTracker_v3_PWA.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/DESIGN.md
  - _bmad-output/planning-artifacts/ux-designs/ux-walktracker-2026-07-04/EXPERIENCE.md
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
  muted-dark: '#999999'
  muted-light: '#666666'
  border-dark: '#555555'
  border-light: '#8E8E93'
  success: '#30D158'
  estimated: '#FFB347'
  estimated-light: '#CC7A00'
  danger-text: '#1D1D1F'
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
  quote-hero:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 28px
    fontWeight: '700'
    lineHeight: '1.3'
    letterSpacing: '-0.01em'
  quote-hero-mobile:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 22px
    fontWeight: '700'
    lineHeight: '1.3'
  ring-label:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.2'
  ring-value:
    fontFamily: '-apple-system, "Helvetica Neue", sans-serif'
    fontSize: 36px
    fontWeight: '900'
    lineHeight: '1'
    letterSpacing: '-0.02em'
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

WalkTracker is a **sports energy** app for a single user who walks to build capacity and be recognized for progress. The visual language borrows from **Adidas Running** and **Strava**: bold numbers, card-based metric grouping, and a vibrant accent that screams *movement*.

The **Volt** palette (neon yellow-green on dark charcoal, golden amber on light) delivers maximum legibility under direct sunlight while maintaining an energetic, modern feel. The **Card Sport** layout groups metrics in elevated cards with soft shadows, creating a native iOS app aesthetic rather than a web page.

**v3 shift:** the visual hero moves from the "+1 VUELTA" button (v1/v2) to **visible progress** — the large weekly goal ring, achievement badges, and the upward trend in history. The accent color (`#CCFF00`) now celebrates *capacity growth*, not lap registration.

The design is **dark-mode-first** (the default canvas is `#1A1A1A`), with light mode as a fully equal alternative. Both modes use the same structural layout; only color tokens swap.

## Colors

The palette is two-tone energy: a neon accent for progress and primary action, a warm secondary for alerts, and a red danger for destructive actions.

- **Canvas (`#1A1A1A` dark / `#F5F5F7` light)** is the primary background. Dark mode is the default; light mode uses Apple's system gray for familiarity and sun-legibility.
- **Surface (`#2A2A2A` dark / `#FFFFFF` light)** is the card and control background. Cards use a subtle shadow in light mode; tonal separation in dark mode.
- **Accent (`#CCFF00` dark / `#CC9900` light)** is the progress hero color. Used for the goal ring fill, distance metric, achievement badges, and motivational overlay. Means *growth, recognition, movement*.
- **Secondary (`#FF6600`)** is the alert color. Used for the wake lock failure banner and attention-grabbing non-destructive notices.
- **Danger (`#FF453A`)** is the Finalizar button. Apple's system red, consistent with iOS destructive actions.
- **Success (`#30D158`)** is Apple's system green, used for the Reanudar button and goal-completed state.
- **Estimated (`#FFB347`)** is a warm amber for estimated steps ("~") — distinct from accent to signal "this is not measured."
- **Text (`#FFFFFF` dark / `#1D1D1F` light)** is the primary text color.
- **Muted (`#999999` dark / `#666666` light)** is for labels, secondary text, disabled states, and locked achievements. Both modes meet WCAG AA 4.5:1 on their respective surfaces.
- **Border (`#555555` dark / `#8E8E93` light)** is the hairline divider for list items and input fields. Both meet 3:1 minimum for meaningful visual separation.

Avoid: gradients on surfaces (only on the motivational overlay for energy), more than 2 chromatic colors per screen, decorative icons where text suffices.

## Typography

Platform system fonts only — no custom fonts to load (offline-first, NFR-1). The `-apple-system` stack gives SF Pro on iOS, which is the native sports app standard.

| Role | Size | Weight | Use |
|---|---|---|---|
| `metric-hero` | 64px (48px mobile) | 900 | Distance (km) — the biggest metric on Session screen |
| `metric-sub` | 16px | 700 | Steps, time, pace, cadence values |
| `label` | 11px | 400 | Metric labels ("distancia", "pasos", "tiempo", "ritmo") |
| `body` | 15px | 400 | Settings fields, history rows, microcopy |
| `button-primary` | 24px | 900 | "Iniciar caminata" text |
| `button-secondary` | 14px | 600 | Pausar, Finalizar, Exportar |
| `header-title` | 17px | 700 | Screen titles, "Sesión activa" |
| `status-badge` | 12px | 600 | "● EN CURSO" |
| `quote-hero` | 28px (22px mobile) | 700 | Motivational quote text on overlay |
| `ring-value` | 36px | 900 | km value inside goal ring |
| `ring-label` | 14px | 600 | "Meta semanal" label below ring |

Dynamic type: all text scales with iOS Dynamic Type. `metric-hero` and `quote-hero` must remain legible at largest setting — no truncation.

## Layout & Spacing

Scale: 4 / 8 / 12 / 16 / 24 / 32 px. iPhone 14 reference (390×844 pt).

- **Margins**: 16px horizontal on all screens.
- **Card padding**: 20px internal.
- **Goal ring**: 300px diameter, centered, occupies upper half of Home screen.
- **Touch targets**: ≥44pt minimum (NFR-4).
- **Safe areas**: `env(safe-area-inset-bottom)` respected on all bottom-aligned controls.
- **Vertical rhythm**: Header → Ring/Card → Button → Controls, with consistent gaps (`spacing.3` = 12px between major blocks).

Single-column always. No multi-column layouts. Modal stacks one level deep maximum.

## Elevation & Depth

Cards are distinguished from canvas by tone (dark) or shadow (light):

- **Dark mode**: `surface-dark` (`#2A2A2A`) on `canvas-dark` (`#1A1A1A`) — no shadow, tonal separation only.
- **Light mode**: `surface-light` (`#FFFFFF`) on `canvas-light` (`#F5F5F7`) with `box-shadow: 0 2px 8px rgba(0,0,0,0.06)`.
- **Motivational overlay**: full-screen `accent` background, no elevation — it IS the surface.
- **No floating elements**: everything sits on the card or canvas plane.

## Shapes

| Token | Radius | Use |
|---|---|---|
| `rounded/sm` | 8px | Input fields, small buttons, estimated banner |
| `rounded/md` | 12px | Control buttons (Pausar, Finalizar), list rows, achievement cards |
| `rounded/lg` | 16px | Cards, settings fields, weather card |
| `rounded/xl` | 20px | "Iniciar caminata" button |
| `rounded/full` | 9999px | Status badges, toggle knobs, goal ring, achievement icons |

Nothing fully rounded except the toggle knob, status badge, goal ring, and achievement icons. The "Iniciar caminata" button is `rounded/xl` — soft but not a pill.

## Components

→ Composition reference: `mockups/key-screens-v3.html` (9 pantallas: Home, Session, Session+WakeLock, Summary, Settings, History, Achievements, Motivational Overlay, Motion Denied). Spine wins on conflict.

### Goal Ring
- 300px diameter circle, `surface` background track (8px stroke)
- Progress arc: `accent` color, stroke-width 12px, rounded caps
- Center: `ring-value` in `accent` (km completed), `ring-label` below in `muted`
- When complete: ring fills to 100%, `success` color replaces `accent`, celebration toast triggers
- Below ring: "Meta semanal" label in `ring-label`, progress text "X / 10 km"
- Light mode: shadow on ring container; dark mode: tonal

### Metric Card (Session)
- `surface` background, `rounded/lg` padding, `spacing.5` internal
- Hero metric (distance in km) at top: `metric-hero` in `accent` color
- Sub-metrics row below: 4 columns (pasos, tiempo, ritmo, cadencia), `metric-sub` values in `secondary` or `text`, `label` below each
- Steps with "~" prefix use `estimated` color for the estimated portion
- Light mode: shadow; dark mode: tonal

### Weather Card
- `surface` background, `rounded/lg`, padding `spacing.4`
- Temperature: `metric-sub` large (24px), condition icon (emoji) + text in `body`
- Optional row below: humidity, UV, wind in `label` size, separated by `·`
- If no network: "Sin clima" in `muted`, `label` size, centered
- Compact — does not compete with metrics

### Session Controls
- Two buttons side-by-side: Pausar (left), Finalizar (right)
- Pausar: `surface` background, `muted` text, `rounded/md`
- Finalizar: `danger` background, `danger-text` (#1D1D1F) text, `rounded/md`
- Reanudar: `success` background, `danger-text` (#1D1D1F) text (replaces Pausar when paused)
- Height: 44px minimum
- "Iniciar caminata": full-width, `accent` background, `canvas-dark` text, `rounded/xl`, `button-primary`

### Estimated Steps Banner
- `surface` background with `estimated` left border (4px), `rounded/sm`
- "~" prefix in `estimated` (dark mode) / `estimated-light` (light mode), `metric-sub` for estimated count
- "Descartar estimación" button in `muted`, `button-secondary` size
- Appears below step counter when returning from background with estimated gap
- Dismissible — disappears on discard or after 30s

### Wake Lock Banner
- `secondary` (`#FF6600`) background, `text-dark` text, full-width, `rounded/sm`
- Sticky at top of Session screen (below status bar)
- "Mantén la pantalla encendida para contar pasos" in `body`
- Dismissible with × icon (right-aligned)
- Reappears if wake lock fails again

### Recovery Indicator
- Inline banner at top of Session screen (below status bar, above metrics)
- `surface` background, `muted` text, `rounded/sm`, padding `spacing.2`
- "Sesión recuperada" in `label` size, centered
- Auto-dismiss after 3 seconds
- Only appears after recovery from purge/crash (not on normal background→foreground)

### Motivational Overlay
- Full-screen `accent` background, no gaps
- Quote text: `quote-hero` in `canvas-dark`, centered vertically and horizontally
- "Toca para continuar" in `canvas-dark` (#1A1A1A) at 50% opacity, `label` size, bottom-center (13.5:1 on accent background)
- Auto-dismiss after 3-4 seconds; tap to skip immediately
- No close button — the entire surface is tappable
- `Reduce Motion`: skip fade-in animation, show immediately

### Achievement Badge
- 2-column grid, each card: `surface` background, `rounded/md`, padding `spacing.4`
- Icon: 64px circle (`rounded/full`), `accent` background when unlocked, `muted` when locked
- Icon content: emoji or simple SVG (medal, trophy, flame, etc.)
- Name: `body` bold, below icon
- Description: `label` in `muted`, below name
- Progress bar (for in-progress): thin bar at bottom, `accent` fill proportional to progress
- Locked: icon `muted` background, name `muted`, description `muted`, lock icon overlay (🔒)
- Unlocked: icon `accent` background, name `text`, description `muted`

### Celebration Toast
- Non-blocking, top of screen (below status bar), `accent` background, `canvas-dark` text
- `rounded/md`, padding `spacing.4`, max-width 90% of screen
- Text: `body` bold, centered
- Auto-dismiss after 2-3 seconds
- Sound plays simultaneously (short, respectful volume)
- Stacks: if multiple celebrations, show sequentially (queue)

### Summary Screen
- Full-screen replacement after session finish
- Header: "Caminata completada" in `header-title`, centered
- Hero: final distance in `metric-hero` `accent`, centered
- Stats grid: 2×2 cards (`surface`, `rounded/md`) — pasos medidos, pasos estimados ("~" si aplica), duración, ritmo
- Achievements unlocked: horizontal scroll of achievement badges (unlocked this session), `accent` icons
- Goal progress: mini ring or text "Meta semanal: X / 10 km" with `accent` progress bar
- "Nueva sesión" button: full-width, `accent` background, `canvas-dark` text, `rounded/xl`, `button-primary`
- No back button — forward only (consistent with v2 EXPERIENCE.md)

### History Row
- `surface` background, `rounded/md`, padding `spacing.4`
- Date in `label` (top), metrics row below: distance, duration, pace in `metric-sub`
- Sessions with estimated steps: "~" prefix on steps in `estimated` / `estimated-light` color
- Hairline divider (`border`) between rows
- Delete action: small trash icon (🗑️) right-aligned, `muted` color, 44×44px hit area. Tap → confirmation dialog ("¿Eliminar esta sesión?") → delete.
- No avatar — text-only with inline action.

### Settings Field
- Label in `body` (top), input field below
- Input: `surface` background, `rounded/sm`, `spacing.4` padding, `accent` 2px focus ring (high-contrast, visible in both modes)
- Readonly fields: transparent background, `accent` text, no border
- Error message in `danger` below field, `label` size
- Export section: "Último respaldo: [fecha]" in `label`, "Exportar" button in `button-secondary`
- Backup warning: if >30 days since export, banner in `secondary` above settings
- Delete data: "Borrar todos los datos" in `danger` text, `button-secondary`, requires confirmation dialog

### Motion Denied Screen
- Full-screen `surface` background, centered content
- Icon: large (80px) motion/sensor emoji (📱) in `muted`
- Title: `header-title` in `text`, "Sensor de movimiento requerido"
- Body: `body` in `muted`, "WalkTracker necesita acceso al sensor de movimiento para contar tus pasos. Actívalo en Configuración de Safari > Movimiento y orientación."
- Button: "Abrir Configuración" in `accent`, `button-primary`, opens `app-settings:` URL
- Secondary link: "Volver al inicio" in `muted`, `button-secondary`

### Status Badge
- `rounded/full`, `status-badge` text
- "● EN CURSO" in `accent` color
- Positioned in session header

### Toggle Switch
- 48×28px visual pill, `border` background when off, `success` when on
- White knob (24px circle) slides left/right
- **Hit area**: transparent padding extends tappable region to 48×44px minimum (WCAG)
- Used for "Sonido" in Settings

## Do's and Don'ts

| Do | Don't |
|---|---|
| Use `accent` for progress, distance, achievements, and primary action | Use `accent` for chrome, decoration, or secondary text |
| Card-based metric grouping (all metrics in one card) | Scatter metrics across the screen |
| System fonts only (no custom font loading) | Import Google Fonts or custom typefaces |
| Dark mode as default, light as equal alternative | Light-only or dark-only |
| Goal ring as the visual anchor of Home | Shrink the ring to fit other content |
| Text-only state indicators | Icon-only states without text labels |
| Hairline dividers at lowest legible contrast | Thick borders or gradient fills |
| Honor safe areas and 44pt touch targets | Overlap the home indicator or notch |
| Estimated steps visually distinct from measured (`estimated` color, "~" prefix) | Blend estimated and measured steps without distinction |
| Celebration toast is non-blocking during session | Block the session flow with full-screen celebrations |
| Motivational overlay is skippable (tap) | Force the user to wait 4 seconds |
