/**
 * domain.js — WalkTracker Domain (pure, no DOM/infra)
 *
 * AD-1: Hexagonal-lite core — zero dependencies outward.
 * AD-4: Session aggregate root.
 * AD-5: Perimeter derived (strideM × stepsPerLap).
 * AD-6: Wall-clock chronometer.
 * AD-7: Validation at the frontier.
 *
 * Usage in browser:   window.WT.Domain
 * Usage in Node/ESM:  import { Domain } from './domain.js'  (add export line)
 * For single-file PWA: inline this code inside index.html <script>
 */

const Domain = (() => {
  'use strict';

  // ═══════════════════════════════════════════════════════
  //  CalibrationProfile — AD-5, AD-7
  // ═══════════════════════════════════════════════════════

  const DEFAULT_STRIDE = 0.655;
  const DEFAULT_STEPS_PER_LAP = 62;

  /**
   * Recalibra el perímetro a partir de medidas crudas.
   * @param {object} input
   * @param {number} input.strideM      - zancada en metros (> 0)
   * @param {number} input.stepsPerLap  - pasos por vuelta (> 0)
   * @returns {{ strideM, stepsPerLap, lapPerimeterM }}
   * @throws {TypeError}  si algún arg no es número finito
   * @throws {RangeError} si strideM ≤ 0 o stepsPerLap ≤ 0
   */
  function recalibrate({ strideM, stepsPerLap } = {}) {
    if (!Number.isFinite(strideM) || !Number.isFinite(stepsPerLap)) {
      throw new TypeError(
        'recalibrate: strideM y stepsPerLap deben ser números finitos'
      );
    }
    if (strideM <= 0 || stepsPerLap <= 0) {
      throw new RangeError(
        'recalibrate: strideM y stepsPerLap deben ser > 0'
      );
    }
    const lapPerimeterM = +(strideM * stepsPerLap).toFixed(4);
    return { strideM, stepsPerLap, lapPerimeterM };
  }

  /**
   * Helper para promediar pasos por vuelta desde una medición interactiva.
   */
  function averageStepsPerLap(totalSteps, laps) {
    if (!Number.isFinite(totalSteps) || !Number.isFinite(laps) || laps <= 0) {
      throw new RangeError(
        'averageStepsPerLap: totalSteps finito y laps > 0 requeridos'
      );
    }
    return totalSteps / laps;
  }

  // ═══════════════════════════════════════════════════════
  //  Chronometer — AD-6 (wall-clock)
  // ═══════════════════════════════════════════════════════

  /**
   * Calcula segundos transcurridos desde startedAt, restando pausas.
   * @returns {number} segundos (float, puede truncarse a entero)
   */
  function elapsedS(startedAtMs, totalPausesMs, nowMs) {
    if (!Number.isFinite(startedAtMs) || !Number.isFinite(nowMs)) {
      throw new TypeError(
        'elapsedS: startedAtMs y nowMs deben ser números finitos'
      );
    }
    const tp = totalPausesMs || 0;
    return (nowMs - startedAtMs - tp) / 1000;
  }

  // ═══════════════════════════════════════════════════════
  //  MetricsCalculator
  // ═══════════════════════════════════════════════════════

  /**
   * Distancia total a partir de vueltas y perímetro.
   */
  function distance(laps, lapPerimeterM) {
    if (!Number.isSafeInteger(laps) || laps < 0) {
      throw new RangeError(
        'distance: laps debe ser un entero no negativo'
      );
    }
    if (!Number.isFinite(lapPerimeterM) || lapPerimeterM <= 0) {
      throw new RangeError(
        'distance: lapPerimeterM debe ser > 0'
      );
    }
    return +(laps * lapPerimeterM).toFixed(2);
  }

  /**
   * Ritmo en segundos por kilómetro.
   * Retorna Infinity si distanceM <= 0 (aún sin movimiento).
   */
  function pace(durationS, pausesS, distanceM) {
    if (!Number.isFinite(durationS) || !Number.isFinite(pausesS)) {
      throw new TypeError(
        'pace: durationS y pausesS deben ser números finitos'
      );
    }
    if (distanceM <= 0) return Infinity;
    const movingS = durationS - (pausesS || 0);
    if (movingS <= 0) return Infinity;
    return Math.round(movingS / (distanceM / 1000));
  }

  // ═══════════════════════════════════════════════════════
  //  Session Aggregate — AD-4
  // ═══════════════════════════════════════════════════════

  const SESSION_STATUS = Object.freeze({
    ACTIVE: 'active',
    PAUSED: 'paused',
    FINISHED: 'finished',
  });

  /**
   * Crea una nueva sesión activa.
   * Congela el perímetro al inicio (AD-3, AD-5).
   */
  function createSession(nowMs, strideM, stepsPerLap) {
    const cal = recalibrate({ strideM, stepsPerLap });
    return Object.freeze({
      id: null,
      startedAt: nowMs,
      endedAt: null,
      laps: 0,
      lapPerimeterM: cal.lapPerimeterM,
      strideM,
      stepsPerLap,
      status: SESSION_STATUS.ACTIVE,
      totalPausesMs: 0,
      pausedAtMs: null,
      durationS: 0,
      distanceM: 0,
      paceSecPerKm: null,
      pausesS: 0,
    });
  }

  /**
   * Marca una vuelta (+1).
   */
  function lap(session) {
    assertMutable(session, 'lap');
    const newLaps = session.laps + 1;
    const dist = distance(newLaps, session.lapPerimeterM);
    return mutate(session, { laps: newLaps, distanceM: dist });
  }

  /**
   * Deshace la última vuelta (−1).
   * Invariante: nunca baja de 0.
   */
  function undo(session) {
    assertMutable(session, 'undo');
    if (session.laps <= 0) return session;
    const newLaps = session.laps - 1;
    const dist = distance(newLaps, session.lapPerimeterM);
    return mutate(session, { laps: newLaps, distanceM: dist });
  }

  /**
   * Pausa la sesión (reloj se congela).
   */
  function pause(session, nowMs) {
    assertActive(session, 'pause');
    return mutate(session, {
      status: SESSION_STATUS.PAUSED,
      pausedAtMs: nowMs,
    });
  }

  /**
   * Reanuda la sesión (reloj continúa).
   */
  function resume(session, nowMs) {
    if (session.status !== SESSION_STATUS.PAUSED) {
      throw new Error('resume: la sesión no está pausada');
    }
    const pauseDurationMs = nowMs - session.pausedAtMs;
    const newTotalPausesMs = session.totalPausesMs + pauseDurationMs;
    return mutate(session, {
      status: SESSION_STATUS.ACTIVE,
      pausedAtMs: null,
      totalPausesMs: newTotalPausesMs,
    });
  }

  /**
   * Finaliza la sesión. Calcula duración, distancia y ritmo.
   * La sesión finalizada es INMUTABLE (AD-4).
   */
  function finish(session, nowMs) {
    if (session.status === SESSION_STATUS.FINISHED) {
      throw new Error('finish: la sesión ya está finalizada');
    }
    // Si está pausada, acumula la pausa actual antes de finalizar
    const totalPausesMs = session.pausedAtMs
      ? session.totalPausesMs + (nowMs - session.pausedAtMs)
      : session.totalPausesMs;
    const durS = Math.round(
      elapsedS(session.startedAt, totalPausesMs, nowMs)
    );
    const dist = distance(session.laps, session.lapPerimeterM);
    const paceSec = pace(durS, Math.round(totalPausesMs / 1000), dist);
    return Object.freeze({
      ...session,
      status: SESSION_STATUS.FINISHED,
      endedAt: nowMs,
      durationS: durS,
      distanceM: dist,
      paceSecPerKm: paceSec,
      pausesS: Math.round(totalPausesMs / 1000),
      totalPausesMs,
      pausedAtMs: null,
    });
  }

  /**
   * Restaura una sesión desde un snapshot guardado (AD-8).
   * Snapshot shape: { startedAtMs, laps, totalPausesMs, paused, strideM, stepsPerLap }
   */
  function restoreSession(snapshot) {
    if (!snapshot || !snapshot.startedAtMs || snapshot.laps == null)
      throw new TypeError('restoreSession: snapshot inválido');
    const cal = recalibrate({ strideM: snapshot.strideM, stepsPerLap: snapshot.stepsPerLap });
    const isPaused = !!snapshot.paused;
    return Object.freeze({
      id: null,
      startedAt: snapshot.startedAtMs,
      endedAt: null,
      laps: snapshot.laps,
      lapPerimeterM: cal.lapPerimeterM,
      strideM: snapshot.strideM,
      stepsPerLap: snapshot.stepsPerLap,
      status: isPaused ? SESSION_STATUS.PAUSED : SESSION_STATUS.ACTIVE,
      totalPausesMs: snapshot.totalPausesMs || 0,
      pausedAtMs: isPaused ? Date.now() : null,
      durationS: 0,
      distanceM: distance(snapshot.laps, cal.lapPerimeterM),
      paceSecPerKm: null,
      pausesS: Math.round((snapshot.totalPausesMs || 0) / 1000),
    });
  }

  // ═══════════════════════════════════════════════════════
  //  Helpers internos
  // ═══════════════════════════════════════════════════════

  function assertMutable(session, op) {
    if (session.status === SESSION_STATUS.FINISHED) {
      throw new Error(`${op}: la sesión está finalizada (inmutable)`);
    }
    if (session.status === SESSION_STATUS.PAUSED && op !== 'resume') {
      throw new Error(`${op}: la sesión está pausada; reanúdela primero`);
    }
  }

  function assertActive(session, op) {
    if (session.status === SESSION_STATUS.FINISHED) {
      throw new Error(`${op}: la sesión está finalizada`);
    }
  }

  function mutate(session, changes) {
    return Object.freeze({ ...session, ...changes });
  }

  // ═══════════════════════════════════════════════════════
  //  Public API
  // ═══════════════════════════════════════════════════════

  return {
    recalibrate,
    averageStepsPerLap,
    elapsedS,
    distance,
    pace,
    createSession,
    lap,
    undo,
    pause,
    resume,
    finish,
    restoreSession,
    SESSION_STATUS,
    DEFAULT_STRIDE,
    DEFAULT_STEPS_PER_LAP,
  };
})();

// Export for Node.js
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { Domain };
}
// Export for browser
if (typeof window !== 'undefined') {
  window.WT = window.WT || {};
  window.WT.Domain = Domain;
}
