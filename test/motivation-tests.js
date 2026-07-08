/**
 * motivation-tests.js — Motivation/Achievement/GoalEngine tests (E2)
 * Run: node test/motivation-tests.js
 */
'use strict';

const quotes = require('../quotes.json');
const { selectQuote, updateRecentIds, getAchievementsCatalog, evaluateAchievements, getWeeklyProgress, checkStreak, checkTimeOfDay } = require('../motivation.js');

let passed = 0, failed = 0;
function assert(c, m) { if (c) { passed++; process.stdout.write('  ✅ ' + m + '\n'); } else { failed++; process.stdout.write('  ❌ ' + m + '\n'); } }

// ═══════════════════════════════════════════════════════
//  MotivationEngine — ACs
// ═══════════════════════════════════════════════════════
console.log('\n📋 MotivationEngine');
{
  // AC-1: selectQuote returns a quote
  const q = selectQuote(quotes);
  assert(q !== null, 'selectQuote returns quote');
  assert(typeof q.id === 'number', 'quote has id');
  assert(typeof q.text === 'string', 'quote has text');

  // AC-2: selectQuote excludes recent IDs
  const recentIds = quotes.slice(0, 20).map(q => q.id);
  const excluded = selectQuote(quotes, recentIds);
  assert(!recentIds.includes(excluded.id), `excluded ID ${excluded.id} not in recent 20`);

  // AC-3: Exclude all → picks any (fallback)
  const allIds = quotes.map(q => q.id);
  const fallback = selectQuote(quotes, allIds);
  assert(fallback !== null, 'fallback works when all excluded');

  // AC-4: Empty quotes → null
  assert(selectQuote([], []) === null, 'empty quotes → null');

  // AC-5: updateRecentIds adds and caps at 20
  let ids = [];
  for (let i = 0; i < 25; i++) ids = updateRecentIds(ids, i);
  assert(ids.length === 20, 'recent IDs capped at 20');
  assert(ids[0] === 5, 'oldest ID removed');
  assert(ids[19] === 24, 'newest ID added');

  // AC-6: quotes.json has 100 quotes
  assert(quotes.length === 100, '100 quotes in bundle');
}

// ═══════════════════════════════════════════════════════
//  AchievementEngine — ACs
// ═══════════════════════════════════════════════════════
console.log('\n📋 AchievementEngine');
{
  // AC-7: getAchievementsCatalog returns 14
  const cat = getAchievementsCatalog();
  assert(cat.length === 14, '14 achievements in catalog');

  // AC-8: first_session earned on first session
  const firstSession = { id: 's1', distanceM: 500, startedAt: '2026-07-07T10:00:00Z' };
  const earned = evaluateAchievements(firstSession, []);
  assert(earned.some(e => e.key === 'first_session'), 'first_session earned');

  // AC-9: first_km earned at ≥1000m
  const kmSession = { id: 's2', distanceM: 1200, startedAt: '2026-07-07T10:00:00Z' };
  const kmEarned = evaluateAchievements(kmSession, []);
  assert(kmEarned.some(e => e.key === 'first_km'), 'first_km earned at 1.2km');

  // AC-10: first_km not earned < 1000m
  const shortSession = { id: 's3', distanceM: 500, startedAt: '2026-07-07T10:00:00Z' };
  const shortEarned = evaluateAchievements(shortSession, []);
  assert(!shortEarned.some(e => e.key === 'first_km'), 'first_km not earned < 1km');

  // AC-11: rain_walker with weather
  const rainSession = { id: 's4', distanceM: 500, startedAt: '2026-07-07T10:00:00Z', weather: { condition: 'Lluvia ligera' } };
  const rainEarned = evaluateAchievements(rainSession, []);
  assert(rainEarned.some(e => e.key === 'rain_walker'), 'rain_walker earned with rain');

  // AC-12: rain_walker not earned without weather
  const noWeather = { id: 's5', distanceM: 500, startedAt: '2026-07-07T10:00:00Z' };
  const noWxEarned = evaluateAchievements(noWeather, []);
  assert(!noWxEarned.some(e => e.key === 'rain_walker'), 'rain_walker not earned without weather');

  // AC-13: speed_walker with fast pace
  const fastSession = { id: 's6', distanceM: 1000, paceSecPerKm: 400, startedAt: '2026-07-07T10:00:00Z' };
  const fastEarned = evaluateAchievements(fastSession, []);
  assert(fastEarned.some(e => e.key === 'speed_walker'), 'speed_walker earned with pace 400s/km');

  // AC-14: No duplicate unlocks
  const alreadyUnlocked = [{ key: 'first_session', unlockedAt: '2026-07-07T09:00:00Z' }];
  const dupeEarned = evaluateAchievements(firstSession, [], alreadyUnlocked);
  assert(!dupeEarned.some(e => e.key === 'first_session'), 'already unlocked not re-earned');
}

// ═══════════════════════════════════════════════════════
//  GoalEngine — ACs
// ═══════════════════════════════════════════════════════
console.log('\n📋 GoalEngine');
{
  // AC-15: Weekly progress empty
  const empty = getWeeklyProgress([], 10, new Date('2026-07-08'));
  assert(empty.completedKm === 0, '0 km with no sessions');
  assert(empty.goalKm === 10, 'goal = 10 km');
  assert(empty.isComplete === false, 'not complete');

  // AC-16: Single session in current week
  const sessions = [
    { startedAt: '2026-07-06T10:00:00Z', distanceM: 5000 }, // Monday of reference week
  ];
  const progress = getWeeklyProgress(sessions, 10, new Date('2026-07-08T12:00:00Z')); // Wednesday
  assert(progress.completedKm === 5, '5 km completed');
  assert(progress.percentage === 50, '50%');

  // AC-17: Multiple sessions sum
  const multiSessions = [
    { startedAt: '2026-07-06T10:00:00Z', distanceM: 3000 },
    { startedAt: '2026-07-07T10:00:00Z', distanceM: 4000 },
    { startedAt: '2026-07-08T10:00:00Z', distanceM: 5000 },
  ];
  const multi = getWeeklyProgress(multiSessions, 10, new Date('2026-07-08T12:00:00Z'));
  assert(multi.completedKm === 12, '12 km completed');
  assert(multi.isComplete === true, 'goal complete');

  // AC-18: Week boundary
  const mondaySession = { startedAt: '2026-07-06T00:00:00Z', distanceM: 1000 }; // Monday
  const tuesdaySession = { startedAt: '2026-07-07T00:00:00Z', distanceM: 2000 }; // Tuesday
  const boundary = getWeeklyProgress([mondaySession, tuesdaySession], 10, new Date('2026-07-08T12:00:00Z'));
  assert(boundary.completedKm === 3, '3 km across 2 days');

  // AC-19: Previous week session excluded
  const sundayPrevWeek = { startedAt: '2026-06-28T10:00:00Z', distanceM: 10000 }; // Sunday of prev week
  const thisWeek = { startedAt: '2026-07-06T10:00:00Z', distanceM: 2000 };
  const weekBound = getWeeklyProgress([sundayPrevWeek, thisWeek], 10, new Date('2026-07-08T12:00:00Z'));
  assert(weekBound.completedKm === 2, 'only this week counts (2 km)');
}

// ═══════════════════════════════════════════════════════
//  Streak + Time helpers
// ═══════════════════════════════════════════════════════
console.log('\n📋 Streak & Time');
{
  // AC-20: 7-day streak
  const dates = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date('2026-07-08');
    d.setDate(d.getDate() - i);
    dates.push({ startedAt: d.toISOString(), distanceM: 1000 });
  }
  assert(checkStreak(dates, 7), '7-day streak detected');

  // AC-21: Not enough days
  const few = [{ startedAt: '2026-07-08T10:00:00Z', distanceM: 1000 }];
  assert(!checkStreak(few, 3), 'not a streak with 1 session');

  // AC-22: checkTimeOfDay
  const morning = { startedAt: '2026-07-08T06:30:00Z' };
  assert(checkTimeOfDay(morning, 5, 7), 'morning walk detected');

  const night = { startedAt: '2026-07-08T22:00:00Z' };
  assert(checkTimeOfDay(night, 21, 23), 'night walk detected');

  const noon = { startedAt: '2026-07-08T14:00:00Z' };
  assert(!checkTimeOfDay(noon, 5, 7), 'afternoon not early bird');
}

// ═══════════════════════════════════════════════════════
//  Summary
// ═══════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`  Motivation: ${passed + failed} tests  |  ✅ ${passed} passed  |  ❌ ${failed} failed`);
console.log('══════════════════════════════════════════\n');
