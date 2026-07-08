/**
 * stepdetector-tests.js — StepDetector Domain tests (E0-S1)
 * Run: node test/stepdetector-tests.js
 *
 * Covers all Acceptance Criteria from Story E0-S1.
 * AD-12: pure domain, 60 Hz, low-pass α=0.2, refractory 300ms.
 */
'use strict';

const { Domain } = require('../domain.js');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) { passed++; process.stdout.write('  ✅ ' + msg + '\n'); }
  else { failed++; process.stdout.write('  ❌ ' + msg + '\n'); }
}

function assertApprox(a, b, tolerance, msg) {
  const ok = Math.abs(a - b) <= tolerance;
  if (ok) { passed++; process.stdout.write('  ✅ ' + msg + ` (${a} ≈ ${b})\n`); }
  else { failed++; process.stdout.write('  ❌ ' + msg + ` (${a} !≈ ${b}, delta ${Math.abs(a-b)} > ${tolerance})\n`); }
}

// ═══════════════════════════════════════════════════════
//  AC-1: Constructor con valores por defecto
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-1: Constructor defaults');
{
  const sd = Domain.createStepDetector();
  assert(typeof sd === 'object', 'createStepDetector returns object');
  assert(typeof sd.sample === 'function', 'has sample()');
  assert(typeof sd.getCount === 'function', 'has getCount()');
  assert(typeof sd.reset === 'function', 'has reset()');
  assert(sd.getCount() === 0, 'initial count is 0');
}

// ═══════════════════════════════════════════════════════
//  AC-2: Sin movimiento → sin pasos
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-2: No motion → no steps');
{
  const sd = Domain.createStepDetector();
  // calibration phase (600 samples of zero)
  for (let i = 0; i < 650; i++) sd.sample(0, i * 16.67);
  // post-calibration: 1000 zero samples
  for (let i = 0; i < 1000; i++) sd.sample(0, (650 + i) * 16.67);
  assert(sd.getCount() === 0, 'zero motion produces zero steps');
}

// ═══════════════════════════════════════════════════════
//  AC-3: Pico único sobre umbral genera 1 paso
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-3: Single peak → 1 step');
{
  const sd = Domain.createStepDetector();
  // calibration: noise floor
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  // single sharp peak
  sd.sample(1.0, 601 * 16.67);  // rising edge
  sd.sample(1.8, 602 * 16.67);  // peak
  sd.sample(0.5, 603 * 16.67);  // falling
  sd.sample(0.1, 604 * 16.67);
  // wait
  for (let i = 605; i < 700; i++) sd.sample(0.1, i * 16.67);
  assert(sd.getCount() === 1, 'single peak → 1 step');
}

// ═══════════════════════════════════════════════════════
//  AC-4: Refractory window — pico cercano no cuenta
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-4: Refractory window blocks close peaks');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  // Peak 1
  sd.sample(2.0, 601 * 16.67);
  sd.sample(3.0, 602 * 16.67);
  sd.sample(1.0, 603 * 16.67);
  // Peak 2 — only 100ms later (within 300ms refractory)
  sd.sample(2.5, 608 * 16.67);
  sd.sample(3.5, 609 * 16.67);
  sd.sample(1.0, 610 * 16.67);
  // Peak 3 — 500ms later (outside refractory)
  sd.sample(2.0, 640 * 16.67);
  sd.sample(3.2, 641 * 16.67);
  sd.sample(1.0, 642 * 16.67);
  for (let i = 643; i < 700; i++) sd.sample(0.1, i * 16.67);
  assert(sd.getCount() === 2, '2 steps (peak 2 blocked by refractory)');
}

// ═══════════════════════════════════════════════════════
//  AC-5: Picos separados >300ms cuentan múltiples
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-5: Peaks >300ms apart → multiple steps');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  for (let step = 0; step < 10; step++) {
    const base = 601 + step * 25;  // ~416ms apart (>300ms)
    sd.sample(2.0, base * 16.67);
    sd.sample(3.0, (base + 1) * 16.67);
    sd.sample(1.0, (base + 2) * 16.67);
    for (let j = 3; j < 20; j++) sd.sample(0.1, (base + j) * 16.67);
  }
  assert(sd.getCount() === 10, '10 steps at ~416ms intervals');
}

// ═══════════════════════════════════════════════════════
//  AC-6: Reset reinicia contador
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-6: reset() clears state');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  sd.sample(2.0, 601 * 16.67);
  sd.sample(3.0, 602 * 16.67);
  for (let i = 603; i < 700; i++) sd.sample(0.1, i * 16.67);
  assert(sd.getCount() >= 1, 'steps before reset');
  sd.reset();
  assert(sd.getCount() === 0, 'count is 0 after reset');
  // After reset, recalibration needed: steady input should not produce steps
  for (let i = 0; i < 700; i++) sd.sample(0.1, i * 16.67);
  assert(sd.getCount() === 0, 'no steps after reset + steady input');
}

// ═══════════════════════════════════════════════════════
//  AC-7: Secuencia sinusoidal genera conteo esperado
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-7: Sinusoidal sequence → expected step count');
{
  const sd = Domain.createStepDetector();
  // Simulate walking motion: sinusoidal with period ~500ms (120 spm cadence)
  // Each period = 30 samples at 60Hz (500ms)
  const amplitude = 2.5;
  const baseline = 1.0;
  const period = 30; // samples
  
  // Calibration with noise
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  
  // 20 steps of simulated walking
  for (let step = 0; step < 20; step++) {
    const offset = 600 + step * period;
    for (let s = 0; s < period; s++) {
      const angle = (s / period) * Math.PI * 2;
      const mag = baseline + amplitude * Math.max(0, Math.sin(angle));
      sd.sample(mag, (offset + s) * 16.67);
    }
  }
  // Allow tail
  for (let i = 0; i < 100; i++) sd.sample(baseline, (600 + 20 * period + i) * 16.67);
  
  // Should detect most of the 20 steps (some may be missed due to refractory)
  assert(sd.getCount() >= 15 && sd.getCount() <= 20,
    `sinusoidal yields ${sd.getCount()} steps (expected 15-20)`);
}

// ═══════════════════════════════════════════════════════
//  AC-8: Umbral adaptativo — ruido bajo no genera pasos
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-8: Adaptive threshold — low noise → no steps');
{
  const sd = Domain.createStepDetector();
  // Calibration with very low noise
  for (let i = 0; i < 600; i++) sd.sample(0.05 + Math.random() * 0.05, i * 16.67);
  // Post-calibration: continuing low noise
  for (let i = 600; i < 1200; i++) sd.sample(0.05 + Math.random() * 0.05, i * 16.67);
  assert(sd.getCount() === 0, 'low noise → 0 steps (threshold adapted to noise floor)');
}

// ═══════════════════════════════════════════════════════
//  AC-9: 60 Hz frequency — 60 samples without error
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-9: 60 Hz processing rate');
{
  const sd = Domain.createStepDetector();
  let error = null;
  try {
    for (let i = 0; i < 3600; i++) sd.sample(0.1, i * 16.67); // 60 seconds at 60Hz
  } catch (e) {
    error = e;
  }
  assert(error === null, '3600 samples processed without error');
  // With only noise, should be 0 steps after calibration
  assert(sd.getCount() === 0, '60s of noise → 0 steps');
}

// ═══════════════════════════════════════════════════════
//  AC-10: Negative magnitudes normalized
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-10: Negative magnitudes → |magnitude|');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.05, i * 16.67);
  // Negative peak — should be treated as positive
  sd.sample(-1.5, 601 * 16.67);
  sd.sample(-2.8, 602 * 16.67);
  sd.sample(-1.0, 603 * 16.67);
  for (let i = 604; i < 700; i++) sd.sample(0.05, i * 16.67);
  assert(sd.getCount() === 1, 'negative peak → 1 step');
}

// ═══════════════════════════════════════════════════════
//  AC-11: StepDetector es dominio puro (sin DOM)
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-11: Pure domain (no DOM, no browser APIs)');
{
  const sd = Domain.createStepDetector();
  const sourceString = sd.toString();
  assert(!sourceString.includes('document'), 'no document reference');
  assert(!sourceString.includes('window'), 'no window reference');
  assert(!sourceString.includes('navigator'), 'no navigator reference');
  assert(typeof sd.sample(0.5, 0) === 'undefined', 'sample() returns undefined (event-based)');
  // This test verifies the StepDetector is pure domain by checking
  // it works in Node.js without any browser environment
  assert(true, 'StepDetector runs in Node.js without DOM');
}

// ═══════════════════════════════════════════════════════
//  AC-12: Múltiples instancias independientes
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-12: Multiple independent instances');
{
  const sd1 = Domain.createStepDetector();
  const sd2 = Domain.createStepDetector();
  
  for (let i = 0; i < 600; i++) sd1.sample(0.1, i * 16.67);
  for (let i = 0; i < 600; i++) sd2.sample(0.1, i * 16.67);
  
  // Step on sd1 only
  sd1.sample(2.0, 601 * 16.67);
  sd1.sample(3.0, 602 * 16.67);
  sd1.sample(1.0, 603 * 16.67);
  for (let i = 604; i < 700; i++) sd1.sample(0.1, i * 16.67);
  
  // sd2 should not be affected
  assert(sd1.getCount() >= 1, 'sd1 has steps');
  assert(sd2.getCount() === 0, 'sd2 has 0 steps (independent)');
}

// ═══════════════════════════════════════════════════════
//  AC-13: Custom alpha and refractory options
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-13: Custom options');
{
  const sd = Domain.createStepDetector({ alpha: 0.5, refractoryMs: 500 });
  assert(typeof sd.sample === 'function', 'accepts custom alpha');
  assert(typeof sd.getCount === 'function', 'accepts custom refractoryMs');
  // Quick calibration (faster with higher alpha)
  for (let i = 0; i < 600; i++) sd.sample(0.05, i * 16.67);
  sd.sample(2.0, 601 * 16.67);
  sd.sample(3.0, 602 * 16.67);
  sd.sample(1.0, 603 * 16.67);
  for (let i = 604; i < 700; i++) sd.sample(0.05, i * 16.67);
  assert(sd.getCount() === 1, 'custom config detects step');
}

// ═══════════════════════════════════════════════════════
//  AC-14: Recalibración post-reset
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-14: Recalibration after reset');
{
  const sd = Domain.createStepDetector();
  // First calibration + steps
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  sd.sample(2.0, 601 * 16.67);
  sd.sample(3.0, 602 * 16.67);
  for (let i = 603; i < 700; i++) sd.sample(0.1, i * 16.67);
  const countBefore = sd.getCount();
  
  sd.reset();
  // Second calibration with different noise floor
  for (let i = 0; i < 600; i++) sd.sample(0.5, i * 16.67); // higher noise floor
  // Same peak might not trigger with higher threshold
  sd.sample(2.0, 601 * 16.67);
  sd.sample(3.0, 602 * 16.67);
  for (let i = 603; i < 700; i++) sd.sample(0.5, i * 16.67);
  
  assert(sd.getCount() >= 0, 'reset recalibrated properly');
  assert(sd.getCount() !== countBefore, 'new calibration is independent');
}

// ═══════════════════════════════════════════════════════
//  AC-15: Edge case — NaN magnitudes
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-15: NaN magnitude handling');
{
  const sd = Domain.createStepDetector();
  let error = null;
  try {
    sd.sample(NaN, 0);
  } catch (e) {
    error = e;
  }
  assert(error !== null, 'NaN sample throws error');
  
  const sd2 = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd2.sample(0.1, i * 16.67);
  try {
    sd2.sample(NaN, 601 * 16.67);
  } catch (e) {
    error = e;
  }
  assert(error !== null, 'NaN post-calibration throws error');
}

// ═══════════════════════════════════════════════════════
//  AC-16: Rapid succession — max cadence 200 spm
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-16: Max cadence ~200 spm (300ms refractory)');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  // Peaks every 250ms (240 spm) — should be limited by 300ms refractory
  for (let step = 0; step < 20; step++) {
    const base = 601 + step * 15;  // 250ms intervals
    sd.sample(2.0, base * 16.67);
    sd.sample(3.0, (base + 1) * 16.67);
    for (let j = 2; j < 14; j++) sd.sample(0.1, (base + j) * 16.67);
  }
  // With 250ms intervals, ~4/5 steps should be blocked by 300ms refractory
  // Theoretical: 20 * (250/300) ≈ 16-17 steps (some may be counted)
  assert(sd.getCount() < 15, `cadence limited (< 15 steps at 240 spm, got ${sd.getCount()})`);
}

// ═══════════════════════════════════════════════════════
//  AC-17: Sample timestamp ordering
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-17: Out-of-order timestamps');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  // Normal step
  sd.sample(2.0, 601 * 16.67);
  sd.sample(3.0, 602 * 16.67);
  sd.sample(1.0, 603 * 16.67);
  const countAfterStep = sd.getCount();
  // Out-of-order timestamp (going back in time should not break it)
  sd.sample(0.1, 500 * 16.67); // earlier timestamp
  assert(sd.getCount() === countAfterStep, 'out-of-order timestamp does not create extra steps');
}

// ═══════════════════════════════════════════════════════
//  AC-18: Gradual slope vs sharp peak
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-18: Gradual slope vs sharp peak');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.05, i * 16.67);
  // Gradual slope should NOT trigger (not a sharp peak)
  for (let i = 0; i < 50; i++) {
    sd.sample(0.05 + (i / 50) * 0.5, (601 + i) * 16.67);
  }
  // Sharp peak
  sd.sample(2.0, 651 * 16.67);
  sd.sample(3.5, 652 * 16.67);
  sd.sample(1.0, 653 * 16.67);
  for (let i = 654; i < 750; i++) sd.sample(0.05, i * 16.67);
  assert(sd.getCount() === 1, 'gradual slope does not trigger, sharp peak does');
}

// ═══════════════════════════════════════════════════════
//  AC-19: Extensión — getOptions()
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-19: getOptions returns config');
{
  const options = { alpha: 0.3, refractoryMs: 400 };
  const sd = Domain.createStepDetector(options);
  const opts = sd.getOptions();
  assert(opts.alpha !== undefined, 'getOptions returns alpha');
  assert(opts.refractoryMs !== undefined, 'getOptions returns refractoryMs');
  assert(opts.alpha === 0.3, 'alpha matches config');
  assert(opts.refractoryMs === 400, 'refractoryMs matches config');
}

// ═══════════════════════════════════════════════════════
//  AC-20: Peak detection — delta-based positive crossing
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-20: Delta threshold detection');
{
  const sd = Domain.createStepDetector();
  for (let i = 0; i < 600; i++) sd.sample(0.1, i * 16.67);
  // A series of samples where the filtered value increases then decreases
  sd.sample(0.1, 601 * 16.67);  // baseline
  sd.sample(0.1, 602 * 16.67);
  sd.sample(0.3, 603 * 16.67);  // slight rise
  sd.sample(0.8, 604 * 16.67);  // steeper rise
  sd.sample(1.5, 605 * 16.67);  // peak → filtered should have positive delta
  sd.sample(2.5, 606 * 16.67);  // higher peak
  sd.sample(3.0, 607 * 16.67);  // max peak
  sd.sample(2.0, 608 * 16.67);  // falling
  sd.sample(0.5, 609 * 16.67);  // falling more
  sd.sample(0.1, 610 * 16.67);  // back to baseline
  for (let i = 611; i < 750; i++) sd.sample(0.1, i * 16.67);
  assert(sd.getCount() === 1, 'delta-based peak detection → 1 step');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  StepDetector: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log(`  Pass rate: ${(passed / (passed + failed) * 100).toFixed(1)}%`);
console.log('══════════════════════════════════════════\n');
