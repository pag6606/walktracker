/**
 * migration.js — WalkTracker v1.1 → v3 Migration (D1)
 *
 * Transforma sesiones del formato v1 (laps/lapPerimeterM) a v3 (stepsMeasured/strideM).
 * La migración es idempotente: si `storage.isMigrated()` retorna true, no se ejecuta.
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.Migration = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /**
   * Transforma una sesión v1 individual al formato v3.
   * @param {object} v1 - sesión en formato v1 { laps, lapPerimeterM, strideM, stepsPerLap, distanceM, ... }
   * @returns {object|null} sesión en formato v3 con source:"migrated", o null si corrupta
   */
  function migrateV1Session(v1) {
    if (!v1) return null;

    const strideM = v1.lapPerimeterM && v1.stepsPerLap && v1.stepsPerLap > 0
      ? +(v1.lapPerimeterM / v1.stepsPerLap).toFixed(4)
      : v1.strideM || 0;

    // Validate: strideM must be > 0 and distanceM must be > 0
    if (strideM <= 0 || !v1.distanceM || v1.distanceM <= 0) {
      return null;
    }

    // Calculate stepsMeasured inversely from distance
    const stepsMeasured = Math.round(v1.distanceM / strideM);

    return {
      id: v1.id || `v1-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      startedAt: v1.startedAt,
      endedAt: v1.endedAt,
      stepsMeasured: stepsMeasured >= 0 ? stepsMeasured : 0,
      stepsEstimated: 0,
      strideM: strideM,
      distanceM: v1.distanceM,
      durationS: v1.durationS || 0,
      pausesS: v1.pausesS || 0,
      paceSecPerKm: v1.paceSecPerKm || null,
      cadenceSpm: 0,  // No hay tramos medidos reales
      weather: v1.weather || null,
      quoteId: v1.quoteId || null,
      source: 'migrated',
    };
  }

  /**
   * Ejecuta la migración completa si no se ha ejecutado antes.
   * @param {object} storage - StoragePort (con isMigrated, setMigrated, saveSession)
   * @param {Array} v1Sessions - array de sesiones en formato v1
   * @returns {{ migrated: number, corrupt: number, skipped: boolean }}
   */
  function runMigration(storage, v1Sessions) {
    // Idempotencia
    if (storage.isMigrated()) {
      return { migrated: 0, corrupt: 0, skipped: true };
    }

    if (!Array.isArray(v1Sessions) || v1Sessions.length === 0) {
      storage.setMigrated();
      return { migrated: 0, corrupt: 0, skipped: false };
    }

    let migrated = 0;
    let corrupt = 0;

    for (const v1 of v1Sessions) {
      const v3 = migrateV1Session(v1);
      if (v3) {
        storage.saveSession(v3);
        migrated++;
      } else {
        corrupt++;
      }
    }

    storage.setMigrated();
    return { migrated, corrupt, skipped: false };
  }

  return { migrateV1Session, runMigration };
}));
