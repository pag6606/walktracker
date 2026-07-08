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
  //  V3 Session Aggregate — AD-4 (pasos: measured + estimated)
  //  ═══════════════════════════════════════════════════════

  /**
   * Crea una sesión v3 (conteo de pasos).
   * @param {number} nowMs  - timestamp de inicio
   * @param {number} strideM - zancada en metros (>0)
   * @returns {object} sesión inmutabled
   * @throws {TypeError} si strideM no es finito
   * @throws {RangeError} si strideM ≤ 0
   */
  function createV3Session(nowMs, strideM) {
    if (!Number.isFinite(strideM)) {
      throw new TypeError('createV3Session: strideM debe ser un número finito');
    }
    if (strideM <= 0) {
      throw new RangeError('createV3Session: strideM debe ser > 0');
    }
    return Object.freeze({
      id: null,
      startedAt: nowMs,
      endedAt: null,
      stepsMeasured: 0,
      stepsEstimated: 0,
      strideM,
      status: SESSION_STATUS.ACTIVE,
      totalPausesMs: 0,
      pausedAtMs: null,
      durationS: 0,
      distanceM: 0,
      paceSecPerKm: null,
      pausesS: 0,
      cadenceSpm: 0,
    });
  }

  /**
   * Distancia v3: (stepsMeasured + stepsEstimated) × strideM
   */
  function v3distance(stepsMeasured, stepsEstimated, strideM) {
    if (!Number.isSafeInteger(stepsMeasured) || stepsMeasured < 0) {
      throw new RangeError('v3distance: stepsMeasured debe ser entero ≥ 0');
    }
    if (!Number.isSafeInteger(stepsEstimated) || stepsEstimated < 0) {
      throw new RangeError('v3distance: stepsEstimated debe ser entero ≥ 0');
    }
    if (!Number.isFinite(strideM) || strideM <= 0) {
      throw new RangeError('v3distance: strideM debe ser > 0');
    }
    const total = stepsMeasured + stepsEstimated;
    return +(total * strideM).toFixed(2);
  }

  /**
   * Incrementa stepsMeasured en una sesión v3 activa.
   */
  function addSteps(session, count) {
    assertMutable(session, 'addSteps');
    if (!Number.isSafeInteger(count) || count < 0) {
      throw new RangeError('addSteps: count debe ser entero ≥ 0');
    }
    if (count === 0) return session;
    const newMeasured = session.stepsMeasured + count;
    const dist = v3distance(newMeasured, session.stepsEstimated, session.strideM);
    return mutate(session, { stepsMeasured: newMeasured, distanceM: dist });
  }

  /**
   * Añade pasos estimados a una sesión v3 activa.
   */
  function addEstimatedSteps(session, count) {
    assertMutable(session, 'addEstimatedSteps');
    if (!Number.isSafeInteger(count) || count < 0) {
      throw new RangeError('addEstimatedSteps: count debe ser entero ≥ 0');
    }
    if (count === 0) return session;
    const newEstimated = session.stepsEstimated + count;
    const dist = v3distance(session.stepsMeasured, newEstimated, session.strideM);
    return mutate(session, { stepsEstimated: newEstimated, distanceM: dist });
  }

  /**
   * Finaliza una sesión v3. Calcula duración, distancia, ritmo y cadencia.
   */
  function finishV3(session, nowMs) {
    if (session.status === SESSION_STATUS.FINISHED) {
      throw new Error('finishV3: la sesión ya está finalizada');
    }
    const totalPausesMs = session.pausedAtMs
      ? session.totalPausesMs + (nowMs - session.pausedAtMs)
      : session.totalPausesMs;
    const durS = Math.round(elapsedS(session.startedAt, totalPausesMs, nowMs));
    const dist = v3distance(session.stepsMeasured, session.stepsEstimated, session.strideM);
    const p = dist >= 100 ? pace(durS, Math.round(totalPausesMs / 1000), dist) : null;
    const activeMin = (durS - Math.round(totalPausesMs / 1000)) / 60;
    const cad = activeMin > 0 ? +(session.stepsMeasured / activeMin).toFixed(1) : 0;

    return Object.freeze({
      ...session,
      status: SESSION_STATUS.FINISHED,
      endedAt: nowMs,
      durationS: durS,
      distanceM: dist,
      paceSecPerKm: p,
      pausesS: Math.round(totalPausesMs / 1000),
      totalPausesMs,
      pausedAtMs: null,
      cadenceSpm: cad,
    });
  }

  /**
   * Restaura una sesión v3 desde un snapshot.
   * Snapshot shape: { startedAtMs, stepsMeasured, stepsEstimated, totalPausesMs, paused, strideM }
   */
  function restoreV3Session(snapshot) {
    if (!snapshot || snapshot.startedAtMs == null || snapshot.strideM == null) {
      throw new TypeError('restoreV3Session: snapshot inválido');
    }
    if (!Number.isFinite(snapshot.strideM) || snapshot.strideM <= 0) {
      throw new RangeError('restoreV3Session: strideM debe ser > 0');
    }
    const sM = snapshot.stepsMeasured || 0;
    const sE = snapshot.stepsEstimated || 0;
    const isPaused = !!snapshot.paused;
    return Object.freeze({
      id: null,
      startedAt: snapshot.startedAtMs,
      endedAt: null,
      stepsMeasured: sM,
      stepsEstimated: sE,
      strideM: snapshot.strideM,
      status: isPaused ? SESSION_STATUS.PAUSED : SESSION_STATUS.ACTIVE,
      totalPausesMs: snapshot.totalPausesMs || 0,
      pausedAtMs: isPaused ? snapshot.pausedAtMs || Date.now() : null,
      durationS: 0,
      distanceM: v3distance(sM, sE, snapshot.strideM),
      paceSecPerKm: null,
      pausesS: Math.round((snapshot.totalPausesMs || 0) / 1000),
      cadenceSpm: 0,
    });
  }

  // ═══════════════════════════════════════════════════════
  //  StepDetector — AD-12 (pure domain, accelerometer step detection)
//  ═══════════════════════════════════════════════════════

  /**
   * Creates a pure-domain step detector.
   * 
   * Pipeline: magnitude → low-pass filter (α) → positive delta → adaptive threshold → refractory window
   * 
   * @param {object} [options]
   * @param {number} [options.alpha=0.2]     - low-pass filter coefficient (0-1)
   * @param {number} [options.refractoryMs=300] - anti-bounce window in ms
   * @returns {{ sample, getCount, reset, getOptions }}
   */
  function createStepDetector(options = {}) {
    const alpha = options.alpha ?? 0.2;
    const refractoryMs = options.refractoryMs ?? 300;
    const calibrationSamples = options.calibrationSamples ?? 600;  // configurable, ~10s at 60Hz

    // State (encapsulated in closure)
    let filtered = 0;           // last low-pass filtered value
    let prevFiltered = 0;       // previous filtered value (for delta)
    let count = 0;              // step counter
    let lastStepTime = -Infinity; // timestamp of last detected step
    let threshold = 0;          // adaptive threshold (calibrated from noise floor)
    let calCount = 0;           // calibration samples collected
    let sumSq = 0;              // sum of squares for RMS calculation

    /**
     * Process a single accelerometer magnitude sample.
     * @param {number} magnitude - raw acceleration magnitude (positive expected, negative auto-abs'd)
     * @param {number} nowMs - current timestamp in ms
     * @throws {TypeError} if magnitude is NaN
     */
    function sample(magnitude, nowMs) {
      if (typeof magnitude !== 'number' || isNaN(magnitude)) {
        throw new TypeError('StepDetector.sample: magnitude must be a finite number');
      }
      
      const absMag = Math.abs(magnitude);
      
      // Low-pass filter: smoothed = α × input + (1-α) × prevSmoothed
      prevFiltered = filtered;
      filtered = alpha * absMag + (1 - alpha) * (calCount === 0 ? absMag : filtered);
      
      // Calibration phase — estimate noise floor via RMS
      if (calCount < calibrationSamples) {
        sumSq += absMag * absMag;
        calCount++;
        if (calCount === calibrationSamples) {
          // Set threshold: 3× RMS noise floor, minimum 0.15
          const rms = Math.sqrt(sumSq / calibrationSamples);
          threshold = Math.max(rms * 3, 0.15);
        }
        return;
      }
      
      // Step detection: positive delta crossing threshold + refractory check
      const delta = filtered - prevFiltered;
      const timeSinceLastStep = nowMs - lastStepTime;
      
      if (delta > threshold && timeSinceLastStep >= refractoryMs) {
        count++;
        lastStepTime = nowMs;
      }
      
      // Adaptive threshold: slowly track noise floor
      threshold = threshold * 0.999 + Math.abs(delta) * 0.001;
      if (threshold < 0.15) threshold = 0.15;  // minimum sensitivity floor
    }

    function getCount() {
      return count;
    }

    function reset() {
      filtered = 0;
      prevFiltered = 0;
      count = 0;
      lastStepTime = -Infinity;
      threshold = 0;
      calCount = 0;
      sumSq = 0;
    }

    function getOptions() {
      return { alpha, refractoryMs };
    }

    return Object.freeze({ sample, getCount, reset, getOptions });
  }

  // ═══════════════════════════════════════════════════════
  //  GapEstimator — AD-13 (extrapolación por cadencia)
  //  ═══════════════════════════════════════════════════════

  /**
   * Calcula pasos estimados para un gap de background.
   * @param {number} cadenceSpm - cadencia en pasos/minuto (> 0)
   * @param {number} gapS - duración del gap en segundos (≥ 0)
   * @returns {number} pasos estimados (entero)
   */
  function estimateSteps(cadenceSpm, gapS) {
    if (typeof cadenceSpm !== 'number' || isNaN(cadenceSpm)) {
      throw new TypeError('estimateSteps: cadenceSpm debe ser un número');
    }
    if (typeof gapS !== 'number' || isNaN(gapS)) {
      throw new TypeError('estimateSteps: gapS debe ser un número');
    }
    if (cadenceSpm <= 0 || gapS <= 0) return 0;
    return Math.round(cadenceSpm * (gapS / 60));
  }

  /**
   * Calcula la cadencia media sobre tramos medidos.
   * @param {number} stepsMeasured - pasos medidos (entero ≥ 0)
   * @param {number} activeSeconds - segundos con sensor activo (> 0)
   * @returns {number} cadencia en pasos/minuto (1 decimal)
   */
  function calculateCadence(stepsMeasured, activeSeconds) {
    if (!Number.isFinite(stepsMeasured) || stepsMeasured < 0) {
      throw new RangeError('calculateCadence: stepsMeasured debe ser ≥ 0');
    }
    if (!Number.isFinite(activeSeconds) || activeSeconds < 0) {
      throw new RangeError('calculateCadence: activeSeconds debe ser ≥ 0');
    }
    if (stepsMeasured <= 0 || activeSeconds <= 0) return 0;
    return +(stepsMeasured / (activeSeconds / 60)).toFixed(1);
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
    // V1 (legacy — coexist until migration E0-S5)
    recalibrate,
    averageStepsPerLap,
    createSession,
    lap,
    undo,
    pause,
    resume,
    finish,
    restoreSession,
    DEFAULT_STRIDE,
    DEFAULT_STEPS_PER_LAP,
    // V3 (pasos)
    createV3Session,
    addSteps,
    addEstimatedSteps,
    finishV3,
    restoreV3Session,
    v3distance,
    // Shared
    elapsedS,
    distance,
    pace,
    createStepDetector,
    // GapEstimator
    estimateSteps,
    calculateCadence,
    SESSION_STATUS,
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
