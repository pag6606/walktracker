/**
 * migration-tests.js — Migration v1→v3 tests (E0-S5)
 * Run: node test/migration-tests.js
 *
 * D1: Migración inversa stepsMeasured = round(distanceM / strideM).
 */
'use strict';

const { migrateV1Session, runMigration } = require('../migration.js');
const { createStoragePort } = require('../storage.js');

let passed = 0, failed = 0;
function assert(c, m) { if (c) { passed++; process.stdout.write('  ✅ ' + m + '\n'); } else { failed++; process.stdout.write('  ❌ ' + m + '\n'); } }
function assertApprox(a, b, t, m) { const ok = Math.abs(a - b) <= t; if (ok) { passed++; process.stdout.write('  ✅ ' + m + ` (${a} ≈ ${b})\n`); } else { failed++; process.stdout.write('  ❌ ' + m + ` (${a} !≈ ${b}, delta ${Math.abs(a-b)})\n`); } }

async function main() {

// ═══════════════════════════════════════════════════════
//  AC-1: V1 normal → stepsMeasured calculado
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-1: V1 normal → stepsMeasured');
{
  const v1 = {
    id: 'v1-session-1',
    startedAt: '2026-07-03T10:00:00Z',
    endedAt: '2026-07-03T11:02:00Z',
    laps: 83,
    lapPerimeterM: 40.61,
    strideM: 0.655,
    stepsPerLap: 62,
    distanceM: 3370.63,
    durationS: 3720,
    pausesS: 120,
    paceSecPerKm: 1068,
  };
  const v3 = migrateV1Session(v1);
  assert(v3 !== null, 'session migrated');
  assertApprox(v3.stepsMeasured, 5146, 1, `stepsMeasured ≈ 5146 (got ${v3.stepsMeasured})`); // 3370.63 / 0.655 ≈ 5146
  assert(v3.stepsEstimated === 0, 'stepsEstimated = 0');
  assert(v3.source === 'migrated', 'source = migrated');
}

// ═══════════════════════════════════════════════════════
//  AC-2: strideM reconstruido
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-2: strideM reconstructed');
{
  const v1 = { id: 's2', laps: 50, lapPerimeterM: 41.58, stepsPerLap: 63, distanceM: 2079, durationS: 1800 };
  const v3 = migrateV1Session(v1);
  assertApprox(v3.strideM, 0.66, 0.001, `strideM ≈ 0.66 (got ${v3.strideM})`); // 41.58 / 63 = 0.66
}

// ═══════════════════════════════════════════════════════
//  AC-3: source migrated
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-3: Source = migrated');
{
  const v1 = { id: 's3', laps: 10, lapPerimeterM: 40.61, stepsPerLap: 62, distanceM: 406.1, durationS: 600 };
  const v3 = migrateV1Session(v1);
  assert(v3.source === 'migrated', 'source = migrated');
  assert(v3.cadenceSpm === 0, 'cadence = 0 (no real measured segments)');
}

// ═══════════════════════════════════════════════════════
//  AC-4: Campos preservados
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-4: Preserved fields');
{
  const v1 = {
    id: 's4',
    startedAt: '2026-07-04T08:00:00Z',
    endedAt: '2026-07-04T08:45:00Z',
    laps: 62, lapPerimeterM: 40.61, stepsPerLap: 62,
    distanceM: 2517.82, durationS: 2700, pausesS: 60, paceSecPerKm: 1040,
  };
  const v3 = migrateV1Session(v1);
  assert(v3.startedAt === '2026-07-04T08:00:00Z', 'startedAt preserved');
  assert(v3.endedAt === '2026-07-04T08:45:00Z', 'endedAt preserved');
  assertApprox(v3.distanceM, 2517.82, 0.01, 'distanceM preserved');
  assert(v3.durationS === 2700, 'durationS preserved');
  assert(v3.pausesS === 60, 'pausesS preserved');
  assert(v3.paceSecPerKm === 1040, 'paceSecPerKm preserved');
}

// ═══════════════════════════════════════════════════════
//  AC-5: Corrupt — distanceM ≤ 0
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-5: Corrupt distanceM ≤ 0');
{
  const v1 = { id: 'c1', laps: 0, lapPerimeterM: 40.61, stepsPerLap: 62, distanceM: 0, durationS: 0 };
  const v3 = migrateV1Session(v1);
  assert(v3 === null, 'null for distanceM=0');
}

// ═══════════════════════════════════════════════════════
//  AC-6: Corrupt — strideM ≤ 0
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-6: Corrupt strideM ≤ 0');
{
  const v1 = { id: 'c2', laps: 5, lapPerimeterM: 0, stepsPerLap: 0, distanceM: 100, durationS: 300 };
  const v3 = migrateV1Session(v1);
  assert(v3 === null, 'null for strideM=0');
}

// ═══════════════════════════════════════════════════════
//  AC-7: Idempotencia
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-7: Idempotencia');
{
  const storage = createStoragePort();
  storage.setMigrated(); // Ya migrado
  const v1Sessions = [{ id: 's5', laps: 10, lapPerimeterM: 40.61, stepsPerLap: 62, distanceM: 406.1, durationS: 600 }];
  const result = runMigration(storage, v1Sessions);
  assert(result.skipped === true, 'skipped = true (ya migrado)');
  assert(result.migrated === 0, '0 migrated');
  const sessions = await storage.getSessions();
  assert(sessions.length === 0, 'no sessions saved (skipped)');
}

// ═══════════════════════════════════════════════════════
//  AC-8: Múltiples sesiones migradas
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-8: Multiple sessions');
{
  const storage = createStoragePort();
  const v1Sessions = [
    { id: 'm1', laps: 83, lapPerimeterM: 40.61, stepsPerLap: 62, distanceM: 3370.63, durationS: 3720, paceSecPerKm: 1068 },
    { id: 'm2', laps: 50, lapPerimeterM: 41.58, stepsPerLap: 63, distanceM: 2079, durationS: 1800, paceSecPerKm: 865 },
    { id: 'm3', laps: 10, lapPerimeterM: 39.30, stepsPerLap: 60, distanceM: 393, durationS: 480, paceSecPerKm: 1221 },
  ];
  const result = runMigration(storage, v1Sessions);
  assert(result.migrated === 3, '3 migrated');
  assert(result.corrupt === 0, '0 corrupt');
  assert(result.skipped === false, 'not skipped');
  const sessions = await storage.getSessions();
  assert(sessions.length === 3, '3 sessions in storage');
  assert(sessions.every(s => s.source === 'migrated'), 'all have source=migrated');
  assert(sessions.every(s => s.stepsEstimated === 0), 'all have stepsEstimated=0');
}

// ═══════════════════════════════════════════════════════
//  AC-9: Empty v1 sessions → marca migrated sin error
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-9: Empty array');
{
  const storage = createStoragePort();
  const result = runMigration(storage, []);
  assert(result.skipped === false, 'not skipped');
  assert(result.migrated === 0, '0 migrated');
  assert(storage.isMigrated() === true, 'marked as migrated');
}

// ═══════════════════════════════════════════════════════
//  AC-10: Corrupt sessions excluded from migration count
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-10: Mixed valid and corrupt');
{
  const storage = createStoragePort();
  const v1Sessions = [
    { id: 'good', laps: 10, lapPerimeterM: 40.61, stepsPerLap: 62, distanceM: 406.1, durationS: 600 },
    { id: 'bad1', laps: 0, lapPerimeterM: 40.61, stepsPerLap: 62, distanceM: 0, durationS: 0 },
    { id: 'bad2', laps: 5, lapPerimeterM: 0, stepsPerLap: 0, distanceM: 100, durationS: 300 },
  ];
  const result = runMigration(storage, v1Sessions);
  assert(result.migrated === 1, '1 migrated');
  assert(result.corrupt === 2, '2 corrupt');
  const sessions = await storage.getSessions();
  assert(sessions.length === 1, '1 session in storage');
  assert(sessions[0].id === 'good', 'only good session saved');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  Migration: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log('══════════════════════════════════════════\n');

}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
