/**
 * capacitor-keep-awake-adapter.js — WalkTracker Capacitor KeepAwake Adapter (story 8.2)
 *
 * Contrato compatible con WakeLockPort de runtime.js: drop-in replacement en wlPort.
 * En nativo (WebView), el plugin `KeepAwake` es inyectado como variable global por Capacitor.
 * En PWA/web, este adapter NO se usa — se usa directamente WakeLockPort (runtime.js).
 * Fuente: AR-2, AR-10.
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.CapacitorKeepAwake = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  /**
   * Crea un adapter keep-awake para entorno nativo Capacitor.
   * @param {object} [deps]
   * @param {{ keepAwake: () => Promise<void>, allowSleep: () => Promise<void> }} [deps.keepAwakePlugin] — plugin KeepAwake global de Capacitor
   * @returns {{ acquire, release, onLost, onAcquired, isAvailable }}
   */
  function createAdapter(deps) {
    var plugin = (deps && deps.keepAwakePlugin) || null;
    var acquired = false;
    var lostCallback = null;
    var acquiredCallback = null;

    function onLost(cb) { lostCallback = cb; }
    function onAcquired(cb) { acquiredCallback = cb; }

    async function acquire() {
      if (acquired) release();
      if (!plugin) {
        if (lostCallback) lostCallback();
        return false;
      }
      try {
        await plugin.keepAwake();
        acquired = true;
        if (acquiredCallback) acquiredCallback();
        return true;
      } catch {
        acquired = false;
        if (lostCallback) lostCallback();
        return false;
      }
    }

    function release() {
      if (!acquired || !plugin) return;
      try { plugin.allowSleep(); } catch (_) { /* noop */ }
      acquired = false;
      if (lostCallback) lostCallback();
    }

    function isAvailable() {
      return plugin !== null;
    }

    return Object.freeze({ acquire: acquire, release: release, onLost: onLost, onAcquired: onAcquired, isAvailable: isAvailable });
  }

  return Object.freeze({ createAdapter: createAdapter });
}));
