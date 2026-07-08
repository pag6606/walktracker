/**
 * runtime-tests.js — Runtime module tests (E3)
 * Run: node test/runtime-tests.js
 */
'use strict';

const { createWakeLockPort, createBackgroundHandler, checkRecovery } = require('../runtime.js');

let passed = 0, failed = 0;
function assert(c, m) { if (c) { passed++; process.stdout.write('  ✅ ' + m + '\n'); } else { failed++; process.stdout.write('  ❌ ' + m + '\n'); } }

async function main() {

// ═══════════════════════════════════════════════════════
//  WakeLockPort
// ═══════════════════════════════════════════════════════
console.log('\n📋 WakeLockPort');
{
  // AC-1: Acquire success
  let released = false;
  const mockSentinel = {
    release() { released = true; },
    addEventListener(ev, cb) { if (ev === 'release') this._onrelease = cb; },
  };
  const mockWL = {
    request(type) {
      assert(type === 'screen', 'requests screen lock');
      return Promise.resolve(mockSentinel);
    },
  };
  let acquired = false;
  let lostCalled = false;
  const port = createWakeLockPort({ wakeLock: mockWL });
  port.onAcquired(() => { acquired = true; });
  port.onLost(() => { lostCalled = true; });
  const result = await port.acquire();
  assert(result === true, 'acquire returns true');
  assert(acquired === true, 'onAcquired called');

  // AC-2: Release
  port.release();
  assert(released === true, 'release called on sentinel');

  // AC-3: onLost via release event
  // Simulate release event
  if (mockSentinel._onrelease) mockSentinel._onrelease();
  assert(lostCalled === true, 'onLost called after release event');

  // AC-4: No wake lock → onLost inmediato
  let lostNoWL = false;
  const noPort = createWakeLockPort({ wakeLock: null });
  noPort.onLost(() => { lostNoWL = true; });
  const noResult = await noPort.acquire();
  assert(noResult === false, 'returns false without wakeLock');
  assert(lostNoWL === true, 'onLost called when no wakeLock');

  // AC-5: Acquire failure
  const failWL = { request() { return Promise.reject(new Error('denied')); } };
  let failLost = false;
  const failPort = createWakeLockPort({ wakeLock: failWL });
  failPort.onLost(() => { failLost = true; });
  const failResult = await failPort.acquire();
  assert(failResult === false, 'returns false on failure');
  assert(failLost === true, 'onLost called on failure');
}

// ═══════════════════════════════════════════════════════
//  BackgroundHandler
// ═══════════════════════════════════════════════════════
console.log('\n📋 BackgroundHandler');
{
  // AC-6: Visibility change → background
  let bgCalled = false;
  let fgCalled = false;
  const mockDoc = {
    hidden: false,
    visibilityState: 'visible',
    listeners: {},
    addEventListener(ev, cb) { this.listeners[ev] = cb; },
    removeEventListener(ev) { delete this.listeners[ev]; },
  };
  const handler = createBackgroundHandler({ document: mockDoc });
  handler.onBackground(() => { bgCalled = true; });
  handler.onForeground(() => { fgCalled = true; });
  handler.start();

  // Simulate background
  mockDoc.hidden = true;
  mockDoc.visibilityState = 'hidden';
  if (mockDoc.listeners.visibilitychange) mockDoc.listeners.visibilitychange();
  assert(bgCalled === true, 'onBackground called on hide');

  // Simulate foreground
  mockDoc.hidden = false;
  mockDoc.visibilityState = 'visible';
  if (mockDoc.listeners.visibilitychange) mockDoc.listeners.visibilitychange();
  assert(fgCalled === true, 'onForeground called on show');

  // AC-7: Stop removes listener
  bgCalled = false;
  handler.stop();
  mockDoc.hidden = true;
  if (mockDoc.listeners.visibilitychange) mockDoc.listeners.visibilitychange();
  assert(bgCalled === false, 'no callback after stop');

  // AC-8: No document → no-op
  const noHandler = createBackgroundHandler({ document: null });
  noHandler.start(); // should not throw
  assert(true, 'no document does not throw');
}

// ═══════════════════════════════════════════════════════
//  SessionRecovery
// ═══════════════════════════════════════════════════════
console.log('\n📋 SessionRecovery');
{
  // AC-9: No active session
  const emptyStorage = { getActiveSession() { return null; } };
  const noRecovery = checkRecovery(emptyStorage, 1000000);
  assert(noRecovery.hasActiveSession === false, 'no session → no recovery');
  assert(noRecovery.gapS === 0, 'gap = 0');

  // AC-10: Active session with gap
  const storage = {
    getActiveSession() {
      return { startedAtMs: 1000000, lastActiveAtMs: 1000000, stepsMeasured: 500, strideM: 0.655 };
    },
  };
  const recovery = checkRecovery(storage, 1000000 + 300000); // 5 min gap
  assert(recovery.hasActiveSession === true, 'session found');
  assert(Math.abs(recovery.gapS - 300) < 1, `gap ≈ 300s (got ${recovery.gapS})`);
  assert(recovery.snapshot !== null, 'snapshot returned');

  // AC-11: Fallback to startedAtMs if no lastActiveAtMs
  const oldStorage = {
    getActiveSession() {
      return { startedAtMs: 500000, stepsMeasured: 100, strideM: 0.655 };
    },
  };
  const oldRecovery = checkRecovery(oldStorage, 1000000);
  assert(oldRecovery.hasActiveSession === true, 'session found without lastActiveAtMs');
  assert(Math.abs(oldRecovery.gapS - 500) < 1, `gap from startedAtMs (got ${oldRecovery.gapS})`);
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  Runtime: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log('══════════════════════════════════════════\n');

}

main().catch(e => { console.error('FATAL:', e); process.exit(1); });
