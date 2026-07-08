/**
 * session-v3-tests.js — V3 Session Aggregate tests (E0-S2)
 * Run: node test/session-v3-tests.js
 *
 * Covers all Acceptance Criteria from Story E0-S2.
 * AD-4, AD-5, AD-6, AD-8: Session con stepsMeasured/stepsEstimated/strideM.
 */
'use strict';

const { Domain } = require('../domain.js');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) { passed++; process.stdout.write('  ✅ ' + msg + '\n'); }
  else { failed++; process.stdout.write('  ❌ ' + msg + '\n'); }
}

function assertThrows(fn, expectedType, msg) {
  try {
    fn();
    failed++;
    process.stdout.write('  ❌ ' + msg + ' (no lanzó error)\n');
  } catch (e) {
    if (e.constructor.name === expectedType || e instanceof expectedType) {
      passed++;
      process.stdout.write('  ✅ ' + msg + '\n');
    } else {
      failed++;
      process.stdout.write('  ❌ ' + msg + ` (lanzó ${e.constructor.name}: ${e.message})\n`);
    }
  }
}

function assertApprox(a, b, tolerance, msg) {
  const ok = Math.abs(a - b) <= tolerance;
  if (ok) { passed++; process.stdout.write('  ✅ ' + msg + ` (${a} ≈ ${b})\n`); }
  else { failed++; process.stdout.write('  ❌ ' + msg + ` (${a} !≈ ${b})\n`); }
}

const NOW = 1000000;
const STRIDE = 0.655;

// ═══════════════════════════════════════════════════════
//  AC-1: createV3Session strideM > 0 validation
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-1: createV3Session validation');
{
  const s = Domain.createV3Session(NOW, STRIDE);
  assert(typeof s === 'object', 'returns object');
  assert(s.strideM === STRIDE, `strideM = ${STRIDE}`);
  assertThrows(() => Domain.createV3Session(NOW, 0), RangeError, 'strideM=0 → RangeError');
  assertThrows(() => Domain.createV3Session(NOW, -1), RangeError, 'strideM=-1 → RangeError');
  assertThrows(() => Domain.createV3Session(NOW, NaN), TypeError, 'strideM=NaN → TypeError');
  assertThrows(() => Domain.createV3Session(NOW, 'x'), TypeError, 'strideM=string → TypeError');
}

// ═══════════════════════════════════════════════════════
//  AC-2: createV3Session initial values
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-2: createV3Session initial state');
{
  const s = Domain.createV3Session(NOW, STRIDE);
  assert(s.stepsMeasured === 0, 'stepsMeasured = 0');
  assert(s.stepsEstimated === 0, 'stepsEstimated = 0');
  assert(s.strideM === STRIDE, `strideM = ${STRIDE}`);
  assert(s.distanceM === 0, 'distanceM = 0');
  assert(s.status === 'active', 'status = active');
  assert(s.startedAt === NOW, 'startedAt set');
  assert(s.paceSecPerKm === null, 'paceSecPerKm = null');
  assert(s.cadenceSpm === 0, 'cadenceSpm = 0');
  assert(s.pausesS === 0, 'pausesS = 0');
  assert(s.endedAt === null, 'endedAt = null');
  // Verify no v1 fields
  assert(s.laps === undefined, 'no laps field (v3)');
  assert(s.lapPerimeterM === undefined, 'no lapPerimeterM field (v3)');
  assert(s.stepsPerLap === undefined, 'no stepsPerLap field (v3)');
}

// ═══════════════════════════════════════════════════════
//  AC-3: addSteps increments
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-3: addSteps increments');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 100);
  assert(s.stepsMeasured === 100, 'stepsMeasured = 100 after 1 add');
  s = Domain.addSteps(s, 50);
  assert(s.stepsMeasured === 150, 'stepsMeasured = 150 after 2 adds');
}

// ═══════════════════════════════════════════════════════
//  AC-4: addSteps multiples
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-4: addSteps sum');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  for (let i = 0; i < 4980; i++) s = Domain.addSteps(s, 1);
  assert(s.stepsMeasured === 4980, '4980 steps after 4980 addSteps(1)');
  const expectedDist = +(4980 * STRIDE).toFixed(2);
  assertApprox(s.distanceM, expectedDist, 0.01, `distanceM ≈ ${expectedDist} (got ${s.distanceM})`);
}

// ═══════════════════════════════════════════════════════
//  AC-5: distanceM = (stepsMeasured + stepsEstimated) × strideM
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-5: distance derivation');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 4980);
  s = Domain.addEstimatedSteps(s, 320);
  const expected = +((4980 + 320) * STRIDE).toFixed(2);
  assertApprox(s.distanceM, expected, 0.01, `distanceM = ${expected} (got ${s.distanceM})`);
  // Solo medidos
  let s2 = Domain.createV3Session(NOW, STRIDE);
  s2 = Domain.addSteps(s2, 4980);
  const expected2 = +(4980 * STRIDE).toFixed(2);
  assertApprox(s2.distanceM, expected2, 0.01, `without estimated: ${expected2} (got ${s2.distanceM})`);
}

// ═══════════════════════════════════════════════════════
//  AC-6: finishV3 duration
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-6: finishV3 duration');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 4980);
  const ended = NOW + 3720000; // 62 min
  const f = Domain.finishV3(s, ended);
  assert(f.status === 'finished', 'status = finished');
  assert(f.endedAt === ended, 'endedAt set');
  assertApprox(f.durationS, 3720, 1, `durationS ≈ 3720 (got ${f.durationS})`);
}

// ═══════════════════════════════════════════════════════
//  AC-7: finishV3 pace
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-7: finishV3 pace');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 4980);
  const ended = NOW + 3720000; // 62 min (no pauses)
  const f = Domain.finishV3(s, ended);
  // distance = 4980 * 0.655 = 3261.9m = 3.2619 km
  // pace = 3720 / (3261.9/1000) ≈ 1140 s/km
  assert(f.paceSecPerKm > 0, `pace = ${f.paceSecPerKm} s/km`);
  // With pauses
  let s2 = Domain.createV3Session(NOW, STRIDE);
  s2 = Domain.addSteps(s2, 4980);
  s2 = Domain.pause(s2, NOW + 600000);
  s2 = Domain.resume(s2, NOW + 780000); // 3 min pause
  const ended2 = NOW + 3720000 + 180000; // 65 min total, 62 active
  const f2 = Domain.finishV3(s2, ended2);
  assert(f2.pausesS === 180, `pausesS = 180 (got ${f2.pausesS})`);
  assert(f2.paceSecPerKm !== null, 'pace calculated with pauses');
}

// ═══════════════════════════════════════════════════════
//  AC-8: finishV3 cadence
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-8: finishV3 cadence');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 4980);
  const ended = NOW + 3720000; // 62 min
  const f = Domain.finishV3(s, ended);
  // cadence = 4980 / (3720 - 0 / 60) = 4980 / 62 = 80.3 spm
  assert(f.cadenceSpm > 0, `cadence = ${f.cadenceSpm} spm`);
  assertApprox(f.cadenceSpm, 80.3, 0.5, `cadence ≈ 80.3 spm (got ${f.cadenceSpm})`);

  // Con pausas — solo tramo activo (59 min = 3720s - 180s = 3540s = 59 min)
  let s2 = Domain.createV3Session(NOW, STRIDE);
  s2 = Domain.addSteps(s2, 4980);
  s2 = Domain.pause(s2, NOW + 600000);
  s2 = Domain.resume(s2, NOW + 780000);
  const ended2 = NOW + 3900000; // 65 min total, 59 min active (3720s - 180s pauses)
  const f2 = Domain.finishV3(s2, ended2);
  assertApprox(f2.cadenceSpm, 84.4, 0.5, `cadence with pauses ≈ 84.4 spm (got ${f2.cadenceSpm})`);
}

// ═══════════════════════════════════════════════════════
//  AC-9: finishV3 — strideM frozen (immutable)
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-9: Immutable after finish');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 100);
  const f = Domain.finishV3(s, NOW + 600000);
  assert(f.status === 'finished', 'status = finished');
  assertThrows(() => Domain.addSteps(f, 1), Error, 'addSteps on finished throws');
  assertThrows(() => Domain.addEstimatedSteps(f, 1), Error, 'addEstimatedSteps on finished throws');
  assertThrows(() => Domain.finishV3(f, NOW + 900000), Error, 'finishV3 on finished throws');
  assert(f.strideM === STRIDE, 'strideM preserved');
  // Verify frozen (Object.freeze)
  assert(Object.isFrozen(f), 'finished session is frozen');
}

// ═══════════════════════════════════════════════════════
//  AC-10: pause/resume en sesión v3
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-10: Pause/resume');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 50);
  s = Domain.pause(s, NOW + 300000);
  assert(s.status === 'paused', 'status = paused after pause');
  assert(s.pausedAtMs !== null, 'pausedAtMs set');
  s = Domain.resume(s, NOW + 420000); // 2 min pause
  assert(s.status === 'active', 'status = active after resume');
  assert(s.totalPausesMs === 120000, `totalPausesMs = 120000 (got ${s.totalPausesMs})`);
  assert(s.pausedAtMs === null, 'pausedAtMs cleared');
  // Steps preserved after pause
  assert(s.stepsMeasured === 50, 'stepsMeasured preserved');
  s = Domain.addSteps(s, 30);
  assert(s.stepsMeasured === 80, 'stepsMeasured = 80 after add after resume');
}

// ═══════════════════════════════════════════════════════
//  AC-11: V1 functions still work (no regression)
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-11: V1 no regression');
{
  const s = Domain.createSession(NOW, 0.655, 62);
  assert(s.laps === 0, 'v1 createSession works');
  assert(s.lapPerimeterM === 40.61, 'v1 perimeter derived');
  let s1 = Domain.lap(s);
  assert(s1.laps === 1, 'v1 lap works');
  s1 = Domain.undo(s1);
  assert(s1.laps === 0, 'v1 undo works');
  const f = Domain.finish(s1, NOW + 60000);
  assert(f.status === 'finished', 'v1 finish works');
}

// ═══════════════════════════════════════════════════════
//  AC-12: restoreV3Session
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-12: restoreV3Session');
{
  const snapshot = {
    startedAtMs: NOW,
    stepsMeasured: 2450,
    stepsEstimated: 320,
    totalPausesMs: 60000,
    paused: false,
    strideM: STRIDE,
  };
  const r = Domain.restoreV3Session(snapshot);
  assert(r.stepsMeasured === 2450, 'stepsMeasured restored');
  assert(r.stepsEstimated === 320, 'stepsEstimated restored');
  assert(r.strideM === STRIDE, 'strideM restored');
  assert(r.status === 'active', 'status = active');
  const expDist = +((2450 + 320) * STRIDE).toFixed(2);
  assertApprox(r.distanceM, expDist, 0.01, `distanceM derived (got ${r.distanceM})`);
}

// ═══════════════════════════════════════════════════════
//  AC-13: restoreV3Session invalid snapshot
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-13: restoreV3Session invalid');
{
  assertThrows(() => Domain.restoreV3Session(null), TypeError, 'null snapshot → TypeError');
  assertThrows(() => Domain.restoreV3Session({}), TypeError, 'empty snapshot → TypeError');
  assertThrows(() => Domain.restoreV3Session({ startedAtMs: 0 }), TypeError, 'missing strideM → TypeError');
  assertThrows(() => Domain.restoreV3Session({ startedAtMs: 0, strideM: 0 }), RangeError, 'strideM=0 → RangeError');
  assertThrows(() => Domain.restoreV3Session({ startedAtMs: 0, strideM: -1 }), RangeError, 'strideM=-1 → RangeError');
}

// ═══════════════════════════════════════════════════════
//  AC-14: finishV3 pace Infinity when distance < 100m
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-14: Pace Infinity for short distance');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 10); // 10 * 0.655 = 6.55m (< 100m)
  const f = Domain.finishV3(s, NOW + 60000);
  assert(f.paceSecPerKm === null, `pace = null for short distance (got ${f.paceSecPerKm})`);
}

// ═══════════════════════════════════════════════════════
//  AC-15: addSteps on finished session throws
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-15: addSteps on finished');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 100);
  const f = Domain.finishV3(s, NOW + 600000);
  assertThrows(() => Domain.addSteps(f, 1), Error, 'addSteps on finished → Error');
  assertThrows(() => Domain.addEstimatedSteps(f, 1), Error, 'addEstimatedSteps on finished → Error');
}

// ═══════════════════════════════════════════════════════
//  AC-16: addEstimatedSteps increments correctly
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-16: addEstimatedSteps');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 4980);
  s = Domain.addEstimatedSteps(s, 320);
  assert(s.stepsEstimated === 320, 'stepsEstimated = 320');
  assert(s.stepsMeasured === 4980, 'stepsMeasured unchanged');
  const expDist = +((4980 + 320) * STRIDE).toFixed(2);
  assertApprox(s.distanceM, expDist, 0.01, `distance includes estimated (got ${s.distanceM})`);
}

// ═══════════════════════════════════════════════════════
//  AC-17: addSteps with count=0 returns same session
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-17: addSteps(0) no-op');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  s = Domain.addSteps(s, 0);
  assert(s.stepsMeasured === 0, 'stepsMeasured = 0 after addSteps(0)');
  const s2 = Domain.addSteps(s, 5);
  assert(s2.stepsMeasured === 5, 'addSteps(5) works after addSteps(0)');
}

// ═══════════════════════════════════════════════════════
//  AC-18: Session immutable (frozen) before finish
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-18: Active session is frozen');
{
  const s = Domain.createV3Session(NOW, STRIDE);
  assert(Object.isFrozen(s), 'active session is frozen');
  const s2 = Domain.addSteps(s, 10);
  assert(Object.isFrozen(s2), 'after addSteps, session is frozen');
}

// ═══════════════════════════════════════════════════════
//  AC-19: Multiple addSteps en secuencia
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-19: Sequential addSteps');
{
  let s = Domain.createV3Session(NOW, STRIDE);
  for (let i = 0; i < 100; i++) {
    s = Domain.addSteps(s, 1);
    assert(s.stepsMeasured === i + 1, `step ${i+1}: stepsMeasured = ${i+1}`);
  }
  // Check final state
  const f = Domain.finishV3(s, NOW + 600000);
  const expDist = +(100 * STRIDE).toFixed(2);
  assertApprox(f.distanceM, expDist, 0.01, `final distance = ${expDist}`);
  assert(f.status === 'finished', 'finished');
}

// ═══════════════════════════════════════════════════════
//  AC-20: v3 distance formula edge cases
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-20: v3distance edge cases');
{
  assertApprox(Domain.v3distance(0, 0, 0.655), 0, 0.001, '0 steps = 0 distance');
  assertApprox(Domain.v3distance(1, 0, 0.655), 0.66, 0.01, '1 step * 0.655 = 0.66m');
  assertApprox(Domain.v3distance(0, 1, 0.655), 0.66, 0.01, '1 estimated * 0.655 = 0.66m');
  assertApprox(Domain.v3distance(1000, 0, 0.655), 655, 0.01, '1000 steps = 655m');
  assertApprox(Domain.v3distance(1000, 500, 0.655), 982.5, 0.01, '1000+500 steps = 982.5m');
  assertThrows(() => Domain.v3distance(-1, 0, 0.655), RangeError, 'negative stepsMeasured → error');
  assertThrows(() => Domain.v3distance(0, -1, 0.655), RangeError, 'negative stepsEstimated → error');
  assertThrows(() => Domain.v3distance(0, 0, 0), RangeError, 'strideM=0 → error');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  V3 Session: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log(`  Pass rate: ${(passed / (passed + failed) * 100).toFixed(1)}%`);
console.log('══════════════════════════════════════════\n');
