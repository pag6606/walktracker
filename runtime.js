/**
 * runtime.js — WalkTracker Runtime Module (AD-16, AD-13)
 *
 * WakeLockPort: maneja wake lock screen con re-adquisición
 * BackgroundHandler: maneja transiciones background/foreground
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.Runtime = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ═══════════════════════════════════════════════════════
  //  WakeLockPort
  //  ═══════════════════════════════════════════════════════

  /**
   * Crea un WakeLockPort.
   * @param {object} [deps] - dependencias inyectables
   * @param {object} [deps.wakeLock] - navigator.wakeLock mock (para test)
   * @returns {{ acquire, release, onLost, onAcquired }}
   */
  function createWakeLockPort(deps) {
    const wl = deps && deps.wakeLock !== undefined ? deps.wakeLock :
      (typeof navigator !== 'undefined' && navigator.wakeLock ? navigator.wakeLock : null);

    let sentinel = null;
    let lostCallback = null;
    let acquiredCallback = null;

    function onLost(cb) { lostCallback = cb; }
    function onAcquired(cb) { acquiredCallback = cb; }

    async function acquire() {
      release(); // release previous if any
      if (!wl) {
        if (lostCallback) lostCallback();
        return false;
      }
      try {
        sentinel = await wl.request('screen');
        if (acquiredCallback) acquiredCallback();
        sentinel.addEventListener('release', () => {
          sentinel = null;
          if (lostCallback) lostCallback();
        });
        return true;
      } catch {
        if (lostCallback) lostCallback();
        return false;
      }
    }

    function release() {
      if (sentinel) {
        try { sentinel.release(); } catch { /* noop */ }
        sentinel = null;
      }
    }

    return Object.freeze({ acquire, release, onLost, onAcquired });
  }

  // ═══════════════════════════════════════════════════════
  //  BackgroundHandler
  //  ═══════════════════════════════════════════════════════

  /**
   * Crea un handler de transiciones background/foreground.
   * @param {object} [deps]
   * @param {object} [deps.document] - document mock (para test)
   * @returns {{ start, stop, onBackground, onForeground }}
   */
  function createBackgroundHandler(deps) {
    const doc = deps && deps.document ? deps.document :
      (typeof document !== 'undefined' ? document : null);

    let bgCallback = null;
    let fgCallback = null;
    let started = false;

    function onBackground(cb) { bgCallback = cb; }
    function onForeground(cb) { fgCallback = cb; }

    function handleVisibility(e) {
      if (!doc) return;
      if (doc.hidden || doc.visibilityState === 'hidden') {
        if (bgCallback) bgCallback();
      } else {
        if (fgCallback) fgCallback();
      }
    }

    function start() {
      if (started || !doc) return;
      started = true;
      doc.addEventListener('visibilitychange', handleVisibility);
      // Page visibility API also has 'pageshow' for back-forward cache
      if (doc.addEventListener) {
        doc.addEventListener('pageshow', () => {
          if (fgCallback) fgCallback();
        });
      }
    }

    function stop() {
      if (!started || !doc) return;
      started = false;
      doc.removeEventListener('visibilitychange', handleVisibility);
    }

    return Object.freeze({ start, stop, onBackground, onForeground });
  }

  // ═══════════════════════════════════════════════════════
  //  SessionRecovery — helper para recuperación silenciosa
  //  ═══════════════════════════════════════════════════════

  /**
   * Verifica si hay una sesión activa previa y calcula el gap.
   * @param {object} storage - StoragePort
   * @param {number} nowMs - timestamp actual
   * @returns {{ hasActiveSession: boolean, gapS: number, snapshot: object|null }}
   */
  function checkRecovery(storage, nowMs) {
    const snapshot = storage.getActiveSession();
    if (!snapshot) return { hasActiveSession: false, gapS: 0, snapshot: null };

    const gapS = Math.max(0, (nowMs - (snapshot.lastActiveAtMs || snapshot.startedAtMs)) / 1000);
    return { hasActiveSession: true, gapS, snapshot };
  }

  return {
    createWakeLockPort,
    createBackgroundHandler,
    checkRecovery,
  };
}));
