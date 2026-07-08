/**
 * storage-tests.js — StoragePort tests (E0-S4)
 * Run: node test/storage-tests.js
 */
'use strict';

const { createStoragePort, createMemoryAdapter } = require('../storage.js');

let passed = 0, failed = 0;
function assert(c, m) { if (c) { passed++; process.stdout.write('  ✅ ' + m + '\n'); } else { failed++; process.stdout.write('  ❌ ' + m + '\n'); } }

async function main() {

// ═══════════════════════════════════════════════════════
//  AC-1: Config
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-1: Config roundtrip');
{
  const port = createStoragePort();
  const cfg = port.getConfig();
  assert(cfg.strideM === 0.655, 'default strideM = 0.655');
  assert(cfg.weeklyGoalKm === 10.0, 'default weeklyGoalKm = 10');
  port.saveConfig({ strideM: 0.670, weeklyGoalKm: 15 });
  const updated = port.getConfig();
  assert(updated.strideM === 0.670, 'strideM updated');
  assert(updated.weeklyGoalKm === 15, 'weeklyGoalKm updated');
  assert(updated.soundEnabled === true, 'soundEnabled preserved');
}

// ═══════════════════════════════════════════════════════
//  AC-2: Sessions roundtrip
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-2: Sessions roundtrip');
{
  const port = createStoragePort();
  await port.saveSession({ id: 'abc-123', stepsMeasured: 4980, stepsEstimated: 320, strideM: 0.655, distanceM: 3471.5, durationS: 3720, source: 'v3' });
  const sessions = await port.getSessions();
  assert(sessions.length === 1, '1 session saved');
  assert(sessions[0].id === 'abc-123', 'id preserved');
  assert(sessions[0].stepsMeasured === 4980, 'stepsMeasured preserved');
}

// ═══════════════════════════════════════════════════════
//  AC-3: Delete
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-3: Delete session');
{
  const port = createStoragePort();
  await port.saveSession({ id: 's1', stepsMeasured: 100, strideM: 0.655, source: 'v3' });
  await port.saveSession({ id: 's2', stepsMeasured: 200, strideM: 0.655, source: 'v3' });
  await port.saveSession({ id: 's3', stepsMeasured: 300, strideM: 0.655, source: 'v3' });
  await port.deleteSession('s2');
  const sessions = await port.getSessions();
  assert(sessions.length === 2, '2 sessions after delete');
  assert(sessions[0].id === 's1', 's1 preserved');
  assert(sessions[1].id === 's3', 's3 preserved');
}

// ═══════════════════════════════════════════════════════
//  AC-4: Empty sessions
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-4: Empty sessions');
{
  const port = createStoragePort();
  const sessions = await port.getSessions();
  assert(Array.isArray(sessions), 'returns array');
  assert(sessions.length === 0, 'empty array');
}

// ═══════════════════════════════════════════════════════
//  AC-5: Achievements
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-5: Achievements');
{
  const port = createStoragePort();
  await port.saveAchievement({ key: 'first_km', unlockedAt: '2026-07-07T09:15:00Z', progress: 1.0 });
  await port.saveAchievement({ key: 'weekly_goal', unlockedAt: null, progress: 0.6 });
  const achievements = await port.getAchievements();
  assert(achievements.length === 2, '2 achievements');
  const first = achievements.find(a => a.key === 'first_km');
  assert(first !== undefined, 'first_km found');
  assert(first.progress === 1.0, 'first_km progress = 1.0');
}

// ═══════════════════════════════════════════════════════
//  AC-6: Active session
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-6: Active session');
{
  const port = createStoragePort();
  assert(port.getActiveSession() === null, 'null initially');
  port.saveActiveSession({ startedAtMs: 1000000, stepsMeasured: 500, strideM: 0.655 });
  const restored = port.getActiveSession();
  assert(restored !== null, 'not null after save');
  assert(restored.stepsMeasured === 500, 'stepsMeasured preserved');
  port.saveActiveSession(null);
  assert(port.getActiveSession() === null, 'null after clear');
}

// ═══════════════════════════════════════════════════════
//  AC-7: Multiple sessions
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-7: Multiple sessions');
{
  const port = createStoragePort();
  for (let i = 0; i < 10; i++) {
    await port.saveSession({ id: `s${i}`, stepsMeasured: i * 100, strideM: 0.655, source: 'v3' });
  }
  const sessions = await port.getSessions();
  assert(sessions.length === 10, '10 sessions');
  assert(sessions[9].id === 's9', 'last session preserved');
}

// ═══════════════════════════════════════════════════════
//  AC-8: Custom adapters
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-8: Custom adapters');
{
  const customSession = {
    _data: [],
    getSessions() { return [...this._data]; },
    saveSession(s) { this._data.push({ ...s }); },
    deleteSession(id) { this._data = this._data.filter(x => x.id !== id); },
  };
  const port = createStoragePort({ sessionAdapter: customSession });
  await port.saveSession({ id: 'custom-1', stepsMeasured: 99, strideM: 0.655, source: 'v3' });
  const sessions = await port.getSessions();
  assert(sessions.length === 1, 'custom adapter used');
  assert(sessions[0].stepsMeasured === 99, 'data preserved');
}

// ═══════════════════════════════════════════════════════
//  AC-9: MemoryAdapter standalone
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-9: MemoryAdapter standalone');
{
  const mem = createMemoryAdapter();
  mem.saveConfig({ strideM: 0.700 });
  assert(mem.getConfig().strideM === 0.700, 'config works standalone');
  mem.saveSession({ id: 'm1', stepsMeasured: 100, strideM: 0.655, source: 'v3' });
  mem.saveSession({ id: 'm2', stepsMeasured: 200, strideM: 0.655, source: 'v3' });
  assert(mem.getSessions().length === 2, 'sessions work standalone');
  mem.deleteSession('m1');
  assert(mem.getSessions().length === 1, 'delete works standalone');
  mem.saveAchievement({ key: 'test', progress: 0.5 });
  assert(mem.getAchievements().length === 1, 'achievements work standalone');
}

// ═══════════════════════════════════════════════════════
//  AC-10: Persist
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-10: Persist');
{
  const port = createStoragePort();
  const result = await port.persist();
  assert(result === true, 'persist returns true (MemoryAdapter)');
}

// ═══════════════════════════════════════════════════════
//  AC-11: Config defaults
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-11: Config defaults');
{
  const mem = createMemoryAdapter();
  const cfg = mem.getConfig();
  assert(cfg.strideM === 0.655, 'default strideM');
  assert(cfg.weeklyGoalKm === 10.0, 'default goal');
  assert(cfg.soundEnabled === true, 'default sound');
}

// ═══════════════════════════════════════════════════════
//  AC-12: Session upsert
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-12: Session upsert');
{
  const port = createStoragePort();
  await port.saveSession({ id: 'u1', stepsMeasured: 100, strideM: 0.655, source: 'v3' });
  await port.saveSession({ id: 'u1', stepsMeasured: 200, strideM: 0.700, source: 'v3' });
  const sessions = await port.getSessions();
  assert(sessions.length === 1, '1 session after upsert');
  assert(sessions[0].stepsMeasured === 200, 'stepsMeasured updated');
  assert(sessions[0].strideM === 0.700, 'strideM updated');
}

// ═══════════════════════════════════════════════════════
//  AC-13: Migration flag
// ═══════════════════════════════════════════════════════
console.log('\n📋 AC-13: Migration flag');
{
  const port = createStoragePort();
  assert(port.isMigrated() === false, 'not migrated initially');
  port.setMigrated();
  assert(port.isMigrated() === true, 'migrated after set');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  StoragePort: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log('══════════════════════════════════════════\n');

}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
