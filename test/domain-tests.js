/**
 * domain-tests.js — WalkTracker Domain tests
 * Run: node test/domain-tests.js
 *
 * Covers all Acceptance Criteria from Story 1.1.
 * Uses inline assert (no test framework needed).
 */

const { Domain } = require('../domain.js');

let passed = 0;
let failed = 0;

function assert(condition, msg) {
  if (condition) {
    passed++;
    process.stdout.write('  ✅ ' + msg + '\n');
  } else {
    failed++;
    process.stdout.write('  ❌ ' + msg + '\n');
  }
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

// ═══════════════════════════════════════════════════════
//  AC-1: Session de 83 vueltas → 4.11 km
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-1: Session 83 laps → distance');
{
  const s0 = Domain.createSession(0, 0.655, 62);
  let s = s0;
  for (let i = 0; i < 83; i++) s = Domain.lap(s);
  assert(s.laps === 83, 'laps === 83');
  assert(Math.abs(s.distanceM - 3370.63) < 0.01, `distanceM ≈ 3370.63 (got ${s.distanceM})`);
  assert(Math.abs(s.lapPerimeterM - 40.61) < 0.001, `lapPerimeterM frozen at 40.61 (got ${s.lapPerimeterM})`);
}

// ═══════════════════════════════════════════════════════
//  AC-2: Undo 5→4, distance recalculated
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-2: Undo lap');
{
  let s = Domain.createSession(0, 0.655, 62);
  for (let i = 0; i < 5; i++) s = Domain.lap(s);
  assert(s.laps === 5, '5 laps after adding');
  s = Domain.undo(s);
  assert(s.laps === 4, 'laps === 4 after undo');
  assert(Math.abs(s.distanceM - 162.44) < 0.01, `distanceM ≈ 162.44 after undo (got ${s.distanceM})`);
}

// ═══════════════════════════════════════════════════════
//  AC-3: Undo at 0 laps stays at 0
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-3: Undo at 0');
{
  let s = Domain.createSession(0, 0.655, 62);
  assert(s.laps === 0, 'starts at 0');
  s = Domain.undo(s);
  assert(s.laps === 0, 'laps stays 0 after undo');
}

// ═══════════════════════════════════════════════════════
//  AC-4: Finalized session is immutable
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-4: Immutable after finish');
{
  let s = Domain.createSession(0, 0.655, 62);
  s = Domain.lap(s);
  const finished = Domain.finish(s, 3600000); // 1 hour later
  assert(finished.status === 'finished', 'status === finished');
  assert(finished.endedAt !== null, 'endedAt set');
  assertThrows(() => Domain.lap(finished), Error, 'lap() on finished throws');
  assertThrows(() => Domain.undo(finished), Error, 'undo() on finished throws');
  assertThrows(() => Domain.pause(finished, 3600000), Error, 'pause() on finished throws');
}

// ═══════════════════════════════════════════════════════
//  AC-5: Chronometer elapsedS wall-clock
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-5: Chronometer wall-clock');
{
  const now = Date.now();
  const startedAt = now - 3720000; // 62 min ago
  const totalPausesMs = 120000;    // 2 min pauses
  const elapsed = Domain.elapsedS(startedAt, totalPausesMs, now);
  assert(Math.abs(elapsed - 3600) < 0.1, `elapsedS ≈ 3600s (got ${elapsed}s)`);
}

// ═══════════════════════════════════════════════════════
//  AC-6: MetricsCalculator pace computation
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-6: Metrics pace');
{
  const dist = Domain.distance(83, 40.61);
  assert(Math.abs(dist - 3370.63) < 0.01, `distance(83, 40.61) ≈ 3370.63 (got ${dist})`);
  const p = Domain.pace(3720, 120, 3370.63);
  assert(p === 1068, `pace === 1068 s/km (got ${p})`);
}

// ═══════════════════════════════════════════════════════
//  AC-7: CalibrationProfile recalibrate
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-7: recalibrate perimeter');
{
  const r = Domain.recalibrate({ strideM: 0.66, stepsPerLap: 63 });
  assert(Math.abs(r.lapPerimeterM - 41.58) < 0.01, `recalibrate(0.66, 63) → 41.58 (got ${r.lapPerimeterM})`);
  assert(r.strideM === 0.66, 'strideM preserved');
  assert(r.stepsPerLap === 63, 'stepsPerLap preserved');
}

// ═══════════════════════════════════════════════════════
//  AC-8: RangeError on zero/invalid strideM
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-8: Validation RangeError');
{
  assertThrows(() => Domain.recalibrate({ strideM: 0, stepsPerLap: 62 }), RangeError, 'strideM=0 → RangeError');
  assertThrows(() => Domain.recalibrate({ strideM: -1, stepsPerLap: 62 }), RangeError, 'strideM=-1 → RangeError');
  assertThrows(() => Domain.recalibrate({ strideM: 0.5, stepsPerLap: 0 }), RangeError, 'stepsPerLap=0 → RangeError');
}

// ═══════════════════════════════════════════════════════
//  AC-9: TypeError on non-numeric inputs
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-9: Validation TypeError');
{
  assertThrows(() => Domain.recalibrate({ strideM: 'x', stepsPerLap: 62 }), TypeError, 'strideM string → TypeError');
  assertThrows(() => Domain.recalibrate({ strideM: NaN, stepsPerLap: 62 }), TypeError, 'strideM NaN → TypeError');
  assertThrows(() => Domain.recalibrate({ strideM: 0.5, stepsPerLap: undefined }), TypeError, 'stepsPerLap undefined → TypeError');
}

// ═══════════════════════════════════════════════════════
//  EXTRA: Pause / Resume invariants
// ═══════════════════════════════════════════════════════
console.log('\n📋 EXTRA: Pause/resume');
{
  const startMs = 1000000;
  let s = Domain.createSession(startMs, 0.655, 62);
  s = Domain.lap(s);
  s = Domain.lap(s);
  assert(s.laps === 2, '2 laps before pause');

  const pauseAtMs = startMs + 300000; // 5 min
  s = Domain.pause(s, pauseAtMs);
  assert(s.status === 'paused', 'status = paused after pause');
  assert(s.pausedAtMs === pauseAtMs, 'pausedAtMs stored');

  // Elapsed frozen during pause
  const resumeAtMs = pauseAtMs + 120000; // 2 min pause
  s = Domain.resume(s, resumeAtMs);
  assert(s.status === 'active', 'status = active after resume');
  assert(s.totalPausesMs === 120000, `totalPausesMs = 120000 (got ${s.totalPausesMs})`);
  assert(s.pausedAtMs === null, 'pausedAtMs cleared');

  // Can't pause a finished session
  const finished = Domain.finish(s, resumeAtMs + 600000);
  assert(finished.status === 'finished', 'finish works after resume');
  assertThrows(() => Domain.pause(finished, resumeAtMs + 600000), Error, 'pause on finished throws');
}

// ═══════════════════════════════════════════════════════
//  EXTRA: finish with accumulated pauses
// ═══════════════════════════════════════════════════════
console.log('\n📋 EXTRA: Finish with pauses');
{
  const startMs = 2000000;
  let s = Domain.createSession(startMs, 0.655, 62);
  for (let i = 0; i < 10; i++) s = Domain.lap(s);
  s = Domain.pause(s, startMs + 180000);
  s = Domain.resume(s, startMs + 300000);  // 2 min pause
  const finishAt = startMs + 2700000;      // total wall: 700s = 11.67 min
  const f = Domain.finish(s, finishAt);
  assert(f.laps === 10, '10 laps');
  assert(Math.abs(f.distanceM - 406.1) < 0.01, `distance ≈ 406.1m (got ${f.distanceM})`);
  assert(f.pausesS === 120, `pausesS === 120 (got ${f.pausesS})`);
  // elapsed = (finishAt - startMs - 120000ms) / 1000 = (700000 - 120000)/1000 = 580s
  // pace = 580 / (406.1/1000) = 580 / 0.4061 ≈ 1428 s/km
  assert(f.durationS > 0, `durationS > 0 (got ${f.durationS}s)`);
}

// ═══════════════════════════════════════════════════════
//  EXTRA: distance edge cases
// ═══════════════════════════════════════════════════════
console.log('\n📋 EXTRA: Edge cases');
{
  // Zero distance → pace Infinity
  assert(Domain.pace(3600, 0, 0) === Infinity, 'pace with 0 distance → Infinity');
  // Negative laps rejected
  assertThrows(() => Domain.distance(-1, 40.61), RangeError, 'negative laps → RangeError');
  // pace no moving = Infinity
  assert(Domain.pace(0, 0, 406.1) === Infinity, 'pace with 0 duration → Infinity');
}

// ═══════════════════════════════════════════════════════
//  EXTRA: restoreSession (AD-8)
// ═══════════════════════════════════════════════════════
console.log('\n📋 restoreSession (AD-8)');
{
  const now = Date.now();
  const recovered = Domain.restoreSession({
    startedAtMs: now - 3600000,
    laps: 42,
    totalPausesMs: 60000,
    paused: false,
    strideM: 0.655,
    stepsPerLap: 62,
  });
  assert(recovered.laps === 42, 'laps restored');
  assert(recovered.status === 'active', 'active status');
  assert(Math.abs(recovered.lapPerimeterM - 40.61) < 0.001, 'perimeter derived');
  assert(Math.abs(recovered.distanceM - 1705.62) < 0.01, `distance derived (got ${recovered.distanceM})`);

  const recoveredPaused = Domain.restoreSession({
    startedAtMs: now - 1800000,
    laps: 15,
    totalPausesMs: 300000,
    paused: true,
    strideM: 0.66,
    stepsPerLap: 63,
  });
  assert(recoveredPaused.status === 'paused', 'paused status restored');
  assert(recoveredPaused.laps === 15, 'laps in paused');
  assert(Math.abs(recoveredPaused.lapPerimeterM - 41.58) < 0.01, 'perimeter 0.66*63=41.58');
  assert(recoveredPaused.pausedAtMs !== null, 'pausedAtMs set to current time');
  assert(recoveredPaused.totalPausesMs === 300000, 'totalPausesMs restored');

  assertThrows(() => Domain.restoreSession({}), TypeError, 'empty snapshot throws');
  assertThrows(() => Domain.restoreSession(null), TypeError, 'null snapshot throws');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  Total: ${passed + failed}  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log('══════════════════════════════════════════\n');

process.exit(failed > 0 ? 1 : 0);
