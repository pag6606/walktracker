---
baseline_commit: NO_VCS
epic: E0
story_key: e0-s1-stepdetector-puro
status: review
---

# E0-S1 — StepDetector puro (dominio)

**Epic:** E0 — Conteo automático de pasos
**Prioridad:** Must | **Estimación:** M (2-3 días) | **Dependencias:** —

## Story

**Como** Paul, **quiero** que la app detecte mis pasos automáticamente mientras camino con el teléfono en la mano, **para** no tener que contar vueltas manualmente.

## Acceptance Criteria

- [x] `StepDetector` es dominio puro (sin DOM, sin APIs de navegador)
- [x] Recibe muestras de magnitud de aceleración vía `MotionPort.sample(magnitude)`
- [x] Aplica filtro paso-bajo (α=0.2) y detección de picos con umbral adaptativo
- [x] Ventana refractaria de 300 ms (cadencia máx ~200 spm)
- [x] Frecuencia fija 60 Hz (AD-12)
- [x] Emite eventos `onStep()` con contador incremental
- [x] Testeable con trazas grabadas (input → output determinista)
- [x] ≥20 tests unitarios, 0 fallos

## Tasks / Subtasks

- [x] **T1: Implementar StepDetector (dominio puro)**
  - [x] T1.1: Crear módulo `Domain.StepDetector` en `domain.js`
  - [x] T1.2: Implementar `constructor()` con configuración (alpha=0.2, refractoryMs=300)
  - [x] T1.3: Implementar `sample(magnitude)` — método público que recibe magnitud de aceleración
  - [x] T1.4: Implementar filtro paso-bajo (α=0.2): `filtered = α × magnitude + (1-α) × prevFiltered`
  - [x] T1.5: Implementar cálculo de umbral adaptativo sobre ventana deslizante (primeros 10s)
  - [x] T1.6: Implementar detección de picos: `filtered − prevFiltered > threshold` + ventana refractaria
  - [x] T1.7: Implementar contador incremental de pasos
  - [x] T1.8: Implementar `reset()` para reiniciar contador y estado interno
- [x] **T2: Escribir ≥20 tests unitarios**
  - [x] T2.1: Test: constructor con valores por defecto
  - [x] T2.2: Test: sample(0) repetido no genera pasos (sin movimiento)
  - [x] T2.3: Test: pico único sobre umbral genera 1 paso
  - [x] T2.4: Test: pico dentro de ventana refractaria no genera paso (anti-rebote)
  - [x] T2.5: Test: picos separados >300ms generan pasos múltiples
  - [x] T2.6: Test: reset() reinicia contador a 0
  - [x] T2.7: Test: secuencia sinusoidal de 100 muestras genera conteo esperado
  - [x] T2.8: Test: umbral adaptativo se calibra con primeros 10s de ruido
  - [x] T2.9: Test: frecuencia 60 Hz — 60 samples/segundo procesadas sin error
  - [x] T2.10: Test: magnitudes negativas se toman como |magnitud|
  - [x] T2.11: Test: secuencia sinusoidal (validación pipeline completa)
  - [x] T2.12: Test: múltiples instancias independientes
  - [x] T2.13: Test: opciones custom (alpha y refractoryMs)
  - [x] T2.14: Test: recalibración post-reset
  - [x] T2.15: Test: NaN magnitudes lanzan TypeError
  - [x] T2.16: Test: cadencia máxima ~200 spm (refractory 300ms)
  - [x] T2.17: Test: timestamps out-of-order no crean pasos extra
  - [x] T2.18: Test: pendiente gradual no genera paso (solo picos)
  - [x] T2.19: Test: getOptions() retorna configuración
  - [x] T2.20: Test: delta threshold detection

## Dev Notes

### Architecture Reference (AD-12)
- **StepDetector** es dominio puro — sin DOM, sin browser APIs, testeable en Node.js
- Frecuencia fija 60 Hz — determinista, testeable con trazas grabadas
- Pipeline: magnitud → filtro paso-bajo (α=0.2) → pico sobre umbral adaptativo → ventana refractaria 300ms
- `MotionPort` (puerto del dominio) define la interfaz; `sample()` es el entry point
- Contador incremental: cada pico que pasa filtros incrementa en 1

### Implementation Notes
- La calibración del umbral adaptativo usa RMS del noise floor durante los primeros 600 samples (~10s a 60Hz)
- Threshold = max(RMS × 3, 0.15) — se adapta al nivel de ruido del sensor
- El filtro paso-bajo con α=0.2 elimina vibraciones de alta frecuencia
- La ventana refractaria de 300ms limita la cadencia máxima a ~200 spm (AD-12)
- El umbral se adapta lentamente post-calibración (factor 0.999/0.001)
- Magnitudes negativas se toman como |magnitud| (acelerómetro produce ± valores)
- NaN magnitudes lanzan TypeError (validación en frontera, AD-7)

## Dev Agent Record

### Implementation Plan
1. Añadir `createStepDetector()` a `domain.js` en el módulo `Domain`
2. Export a través del objeto de retorno de `Domain`
3. Tests en `test/stepdetector-tests.js` siguiendo el patrón inline assert de los tests v1

### Completion Notes
- 39 tests unitarios implementados y pasando (100%)
- 0 regresiones en los 51 tests v1 existentes
- 90 tests total en suite, 0 fallos
- Cobertura: 20 acceptance criteria cubiertos
- Pipeline: mag → |mag| → low-pass α=0.2 → delta → threshold adaptativo → refractory 300ms → step

## File List

- `domain.js` — MODIFIED: añadido `createStepDetector()` + helpers internos
- `test/stepdetector-tests.js` — NEW: 39 tests unitarios

## Change Log

- 2026-07-07: Implementación E0-S1 completa. StepDetector dominio puro con filtro paso-bajo, umbral adaptativo RMS, ventana refractaria. 39 tests, 0 fallos. Sin regresiones.

## Status

**Current:** review
**Last updated:** 2026-07-07
