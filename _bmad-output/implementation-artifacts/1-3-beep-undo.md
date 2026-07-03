# Story 1.3: Feedback sonoro (beep) + deshacer vuelta

Status: review

## Story

As Paul,
I want an audible beep on each lap and the ability to undo a mistaken tap,
So that I can trust the count without looking and correct errors.

## Acceptance Criteria

1. **Given** an active session, **When** I press "+1 VUELTA", **Then** a short beep sounds via Web Audio API and the lap counter increments
2. **Given** the app is opened (no session started yet), **When** the AudioContext is accessed, **Then** it is in "suspended" state (iOS autoplay policy)
3. **Given** I press **Iniciar**, **When** the AudioContext is accessed, **Then** it is resumed (user gesture unlocks audio) and subsequent beeps play without issue
4. **Given** an active session with 5 laps, **When** I press the **Deshacer** button, **Then** the lap counter decrements to 4, distance recalculates to 162.44m
5. **Given** an active session with 0 laps, **When** I press **Deshacer**, **Then** the lap counter stays at 0 (invariante)
6. **Given** a finalized session, **When** I try to access the **Deshacer** button, **Then** it is not available (deshacer solo en sesión activa)

## Tasks / Subtasks

- [x] Task 1: Web Audio beep module
  - [x] AudioContext creado lazy (suspendido inicialmente en iOS)
  - [x] `unlock()` resume contexto en gesto de usuario (Iniciar)
  - [x] `beep()` — oscilador 440Hz, 80ms, sine wave
- [x] Task 2: Wire beep into session flow
  - [x] `onBeep('start')` → Audio.unlock()
  - [x] `onBeep('lap')` → Audio.beep(440, 0.08)
  - [x] `onBeep('finish')` → Audio.beep(660, 0.15)
  - [x] `onBeep('undo')` → Audio.beep(330, 0.05)
- [x] Task 3: Add Undo button to session UI
  - [x] Botón "↩ −1" debajo del botón +1
  - [x] Hidden por defecto, visible en sesión activa
- [x] Task 4: Wire Undo to Domain.undo()
  - [x] On click: Domain.undo() + updateMetrics
  - [x] Hidden cuando pausado o finalizado
- [x] Task 5: Verify syntax
  - [x] Domain, Audio, UI, onBeep parsed OK via Node
  - [x] Domain undo test passed

## Dev Notes

- AudioContext in iOS Safari: starts in "suspended" state. Must be resumed from user gesture (the Iniciar button click). That's already the entry point.
- Web Audio beep: create OscillatorNode (440Hz) + GainNode -> AudioContext.destination. Start+stop in ~80ms.
- Undo button: small circle or rounded pill, labeled "−1" or "↩", positioned below the +1 button or next to the controls.
- The onBeep callback hook is already prepared in Story 1.2's UI Controller (checks `typeof onBeep === 'function'`).
- Source: epics.md Story 1.3, SPEC RF-08/F-9, ARCHITECTURE-SPINE.md AD-9
