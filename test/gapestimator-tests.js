/**
 * gapestimator-tests.js — GapEstimator tests (E0-S3)
 * Run: node test/gapestimator-tests.js
 *
 * AD-13: Extrapolación por cadencia, siempre marcado "~".
 */
'use strict';

const { Domain } = require('../domain.js');

let passed = 0, failed = 0;
function assert(c, m) { if (c) { passed++; process.stdout.write('  ✅ ' + m + '\n'); } else { failed++; process.stdout.write('  ❌ ' + m + '\n'); } }
function assertThrows(fn, t, m) { try { fn(); failed++; process.stdout.write('  ❌ ' + m + ' (no error)\n'); } catch(e) { if (e.constructor.name === t || e instanceof t) { passed++; process.stdout.write('  ✅ ' + m + '\n'); } else { failed++; process.stdout.write('  ❌ ' + m + ` (${e.constructor.name}: ${e.message})\n`); } } }

// ═══════════════════════════════════════════════════════
//  AC-1: estimateSteps normal
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-1: estimateSteps normal');
{
  const steps = Domain.estimateSteps(80, 300); // 80 spm × 5 min = 400
  assert(steps === 400, `80 spm × 5 min = 400 (got ${steps})`);
}

// ═══════════════════════════════════════════════════════
//  AC-2: estimateSteps retorna 0 si gapS <= 0
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-2: gapS <= 0 → 0');
{
  assert(Domain.estimateSteps(80, 0) === 0, 'gapS=0 → 0');
  assert(Domain.estimateSteps(80, -1) === 0, 'gapS=-1 → 0');
}

// ═══════════════════════════════════════════════════════
//  AC-3: estimateSteps retorna 0 si cadenceSpm <= 0
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-3: cadenceSpm <= 0 → 0');
{
  assert(Domain.estimateSteps(0, 300) === 0, 'cadence=0 → 0');
  assert(Domain.estimateSteps(-1, 300) === 0, 'cadence=-1 → 0');
}

// ═══════════════════════════════════════════════════════
//  AC-4: calculateCadence normal
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-4: calculateCadence normal');
{
  const cad = Domain.calculateCadence(4980, 3540); // 4980 steps / 59 min
  assert(cad === 84.4, `4980 steps / 59 min = 84.4 spm (got ${cad})`);
}

// ═══════════════════════════════════════════════════════
//  AC-5: calculateCadence con 0 pasos
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-5: calculateCadence 0 steps');
{
  assert(Domain.calculateCadence(0, 3540) === 0, '0 steps → 0');
}

// ═══════════════════════════════════════════════════════
//  AC-6: calculateCadence con 0 segundos activos
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-6: calculateCadence 0 active');
{
  assert(Domain.calculateCadence(4980, 0) === 0, '0 active seconds → 0');
}

// ═══════════════════════════════════════════════════════
//  AC-7: estimateSteps gap de 0s
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-7: estimateSteps 0s gap');
{
  assert(Domain.estimateSteps(80, 0) === 0, '0s gap → 0');
}

// ═══════════════════════════════════════════════════════
//  AC-8: estimateSteps gap grande
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-8: estimateSteps large gap');
{
  const steps = Domain.estimateSteps(80, 3600); // 80 spm × 60 min = 4800
  assert(steps === 4800, `80 spm × 60 min = 4800 (got ${steps})`);
}

// ═══════════════════════════════════════════════════════
//  AC-9: estimateSteps NaN → TypeError
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-9: NaN validation');
{
  assertThrows(() => Domain.estimateSteps(NaN, 300), TypeError, 'NaN cadence → TypeError');
  assertThrows(() => Domain.estimateSteps(80, NaN), TypeError, 'NaN gap → TypeError');
}

// ═══════════════════════════════════════════════════════
//  AC-10: calculateCadence edge cases
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-10: calculateCadence edge cases');
{
  assert(Domain.calculateCadence(100, 60) === 100, '100 steps / 1 min = 100 spm');
  assert(Domain.calculateCadence(100, 120) === 50, '100 steps / 2 min = 50 spm');
  assertThrows(() => Domain.calculateCadence(-1, 60), RangeError, 'negative steps → RangeError');
  assertThrows(() => Domain.calculateCadence(100, -1), RangeError, 'negative seconds → RangeError');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  GapEstimator: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log('══════════════════════════════════════════\n');
