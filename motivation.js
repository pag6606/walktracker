/**
 * motivation.js — WalkTracker Motivation Engine (AD-18, AD-11)
 *
 * MotivationEngine: selecciona frases aleatorias sin repetición reciente.
 * AchievementEngine: evalúa logros al cierre de sesión.
 * GoalEngine: calcula progreso semanal de meta.
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.Motivation = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ═══════════════════════════════════════════════════════
  //  MotivationEngine — AD-18
  //  ═══════════════════════════════════════════════════════

  /**
   * Selecciona una frase aleatoria excluyendo las últimas N.
   * @param {Array} quotes - array de objetos { id, text }
   * @param {number[]} recentQuoteIds - IDs de frases recientes a excluir (últimas 20)
   * @returns {{ id: number, text: string } | null}
   */
  function selectQuote(quotes, recentQuoteIds = []) {
    if (!Array.isArray(quotes) || quotes.length === 0) return null;

    const excludeSet = new Set(recentQuoteIds.slice(-20));
    const available = quotes.filter(q => !excludeSet.has(q.id));

    if (available.length === 0) {
      // Si todas están excluidas, ignorar el filtro y elegir cualquiera
      const idx = Math.floor(Math.random() * quotes.length);
      return quotes[idx];
    }

    const idx = Math.floor(Math.random() * available.length);
    return available[idx];
  }

  /**
   * Actualiza el array de IDs recientes con la nueva selección.
   * Mantiene máximo 20 IDs.
   */
  function updateRecentIds(recentQuoteIds, selectedId) {
    const updated = [...(recentQuoteIds || []), selectedId];
    return updated.slice(-20);
  }

  // ═══════════════════════════════════════════════════════
  //  AchievementEngine — 14 logros
  //  ═══════════════════════════════════════════════════════

  // Catálogo de 14 logros (v2 §9.2)
  const ACHIEVEMENTS = Object.freeze([
    { key: 'first_km',        name: 'Tu primer kilómetro',       desc: 'Completa 1 km en una sesión',           icon: '🏅' },
    { key: 'first_5km',       name: 'Cinco kilómetros',          desc: 'Completa 5 km en una sesión',           icon: '🥉' },
    { key: 'first_10km',      name: 'Diez kilómetros',           desc: 'Completa 10 km en una sesión',          icon: '🥈' },
    { key: 'first_session',   name: 'Primera caminata',          desc: 'Completa tu primera sesión',           icon: '🚶' },
    { key: 'weekly_goal',     name: 'Meta semanal cumplida',     desc: 'Cumple tu meta de la semana',           icon: '🏆' },
    { key: 'rain_walker',     name: 'Caminata bajo la lluvia',   desc: 'Camina con clima lluvioso',             icon: '🌧️' },
    { key: '7_days_streak',   name: '7 días consecutivos',       desc: 'Camina 7 días seguidos',                icon: '🔥' },
    { key: 'marathon_42km',   name: 'Maratonista',               desc: 'Acumula 42 km en total',                icon: '🏃' },
    { key: 'speed_walker',    name: 'Caminante rápido',          desc: 'Ritmo menor a 8:00 /km',                icon: '⚡' },
    { key: 'early_bird',      name: 'Madrugador',                desc: 'Camina antes de las 7:00',              icon: '🌅' },
    { key: 'night_walker',    name: 'Caminante nocturno',        desc: 'Camina después de las 21:00',           icon: '🌙' },
    { key: 'hot_walker',      name: 'Caminante del sol',         desc: 'Camina con temperatura >30°C',          icon: '☀️' },
    { key: 'cold_walker',     name: 'Caminante del frío',        desc: 'Camina con temperatura <5°C',           icon: '❄️' },
    { key: 'consistency_30',  name: 'Constancia',                 desc: 'Acumula 30 sesiones en total',          icon: '💪' },
  ]);

  function getAchievementsCatalog() {
    return ACHIEVEMENTS.map(a => ({ ...a }));
  }

  /**
   * Evalúa qué logros se desbloquean con una sesión.
   * @param {object} session - sesión finalizada v3 (con stepsMeasured, distanceM, weather, etc.)
   * @param {Array} allSessions - todas las sesiones (para acumulados, streaks)
   * @param {Array} currentAchievements - logros actuales [{ key, unlockedAt, progress }]
   * @returns {Array} logros desbloqueados en esta sesión [{ key, name, icon }]
   */
  function evaluateAchievements(session, allSessions, currentAchievements = []) {
    const unlocked = new Set(currentAchievements.filter(a => a.unlockedAt).map(a => a.key));
    const allSessionsWithCurrent = [...(allSessions || []), session];
    const newlyUnlocked = [];
    const totalKm = allSessionsWithCurrent.reduce((sum, s) => sum + (s.distanceM || 0), 0);
    const totalSessions = allSessionsWithCurrent.length;
    const totalKmThisSession = session.distanceM || 0;

    for (const ach of ACHIEVEMENTS) {
      if (unlocked.has(ach.key)) continue;
      let earned = false;

      switch (ach.key) {
        case 'first_session':
          earned = true; // primera sesión siempre
          break;
        case 'first_km':
          earned = totalKmThisSession >= 1000;
          break;
        case 'first_5km':
          earned = totalKmThisSession >= 5000;
          break;
        case 'first_10km':
          earned = totalKmThisSession >= 10000;
          break;
        case 'weekly_goal':
          // Se evalúa externamente (GoalEngine)
          earned = false;
          break;
        case 'rain_walker':
          earned = session.weather && /lluv|llovi|torment/i.test(session.weather.condition || '');
          break;
        case '7_days_streak':
          earned = checkStreak(allSessionsWithCurrent, 7);
          break;
        case 'marathon_42km':
          earned = totalKm >= 42000;
          break;
        case 'speed_walker':
          earned = session.paceSecPerKm !== null && session.paceSecPerKm > 0 && session.paceSecPerKm < 480;
          break;
        case 'early_bird':
          earned = checkTimeOfDay(session, 5, 7);
          break;
        case 'night_walker':
          earned = checkTimeOfDay(session, 21, 23);
          break;
        case 'hot_walker':
          earned = session.weather && session.weather.tempC > 30;
          break;
        case 'cold_walker':
          earned = session.weather && session.weather.tempC < 5;
          break;
        case 'consistency_30':
          earned = totalSessions >= 30;
          break;
        default:
          break;
      }

      if (earned) {
        newlyUnlocked.push({ key: ach.key, name: ach.name, icon: ach.icon });
      }
    }

    return newlyUnlocked;
  }

  function checkStreak(sessions, days) {
    if (sessions.length < days) return false;
    const dates = [...new Set(sessions.map(s => {
      const d = new Date(s.startedAt);
      return `${d.getUTCFullYear()}-${d.getUTCMonth()+1}-${d.getUTCDate()}`;
    }))].sort().reverse();
    if (dates.length < days) return false;
    let streak = 1;
    for (let i = 1; i < dates.length; i++) {
      const prev = new Date(dates[i-1]);
      const curr = new Date(dates[i]);
      const diff = (prev - curr) / (1000 * 60 * 60 * 24);
      if (Math.round(diff) === 1) streak++;
      else streak = 1;
      if (streak >= days) return true;
    }
    return streak >= days;
  }

  function checkTimeOfDay(session, hourStart, hourEnd) {
    if (!session.startedAt) return false;
    const h = new Date(session.startedAt).getUTCHours();
    return h >= hourStart && h <= hourEnd;
  }

  // ═══════════════════════════════════════════════════════
  //  GoalEngine — meta semanal
  //  ═══════════════════════════════════════════════════════

  /**
   * Calcula el progreso semanal hacia la meta.
   * @param {Array} sessions - todas las sesiones
   * @param {number} weeklyGoalKm - meta en km
   * @param {string|Date} [now] - fecha de referencia (default: ahora)
   * @returns {{ completedKm: number, goalKm: number, percentage: number, isComplete: boolean }}
   */
  function getWeeklyProgress(sessions, weeklyGoalKm = 10, now = new Date()) {
    const nowDate = new Date(now);

    // Calcular inicio de la semana ISO (lunes) en UTC
    const dayOfWeek = nowDate.getUTCDay();
    const mondayOffset = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const monday = new Date(Date.UTC(
      nowDate.getUTCFullYear(),
      nowDate.getUTCMonth(),
      nowDate.getUTCDate() - mondayOffset,
      0, 0, 0, 0
    ));

    const weekStart = monday.getTime();
    const weekEnd = weekStart + 7 * 24 * 60 * 60 * 1000;

    const weekKm = (sessions || []).reduce((sum, s) => {
      const t = new Date(s.startedAt).getTime();
      if (t >= weekStart && t < weekEnd) {
        return sum + ((s.distanceM || 0) / 1000);
      }
      return sum;
    }, 0);

    const completedKm = +(weekKm.toFixed(2));
    const percentage = weeklyGoalKm > 0 ? Math.min(100, +(completedKm / weeklyGoalKm * 100).toFixed(1)) : 0;

    return {
      completedKm,
      goalKm: weeklyGoalKm,
      percentage,
      isComplete: completedKm >= weeklyGoalKm,
    };
  }

  return {
    selectQuote,
    updateRecentIds,
    getAchievementsCatalog,
    evaluateAchievements,
    getWeeklyProgress,
    checkStreak,
    checkTimeOfDay,
  };
}));
