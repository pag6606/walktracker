/**
 * capacitor-motion-adapter.js — WalkTracker Capacitor Motion Adapter (Epic 1, Story 1.2)
 *
 * Implementa el MotionPort para entorno nativo iOS via walktracker-kit (CMPedometer).
 * El dominio no conoce Capacitor — este adapter es el único punto de contacto.
 * Fuente: AR-2, AR-10.
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.CapacitorMotionAdapter = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  function createAdapter(deps) {
    var plugin = (deps && deps.plugin)
      || (typeof WalktrackerKit !== 'undefined' ? WalktrackerKit : null)
      || (typeof Capacitor !== 'undefined' && Capacitor.Plugins && Capacitor.Plugins.WalktrackerKit)
      || (typeof window !== 'undefined' && window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.WalktrackerKit)
      || null;
    if (typeof console !== 'undefined') {
      console.log('[CapacitorMotion] Plugin detection:', {
        hasCapacitor: typeof Capacitor !== 'undefined',
        hasPlugins: !!(Capacitor && Capacitor.Plugins),
        hasWTK: !!(Capacitor && Capacitor.Plugins && Capacitor.Plugins.WalktrackerKit),
        hasWindowWTK: !!(window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.WalktrackerKit)
      });
    }
    var stepsCallback = null;
    var isTracking = false;

    function onSteps(cb) { stepsCallback = cb; }

    async function start() {
      if (!plugin) {
        console.warn('[CapacitorMotion] Plugin no disponible');
        return false;
      }
      if (isTracking) return true;

      try {
        plugin.addListener('onSteps', function (data) {
          if (stepsCallback) {
            stepsCallback(data.steps, data.distanceM || null);
          }
        });

        var result = await plugin.startStepTracking();
        isTracking = result && result.started === true;
        return isTracking;
      } catch (e) {
        console.error('[CapacitorMotion] Error al iniciar:', e);
        return false;
      }
    }

    async function stop() {
      if (!isTracking || !plugin) return;
      try {
        await plugin.stopStepTracking();
        isTracking = false;
      } catch (e) {
        console.error('[CapacitorMotion] Error al detener:', e);
      }
    }

    async function query(startDate, endDate) {
      if (!plugin) return null;
      try {
        var result = await plugin.queryPedometerData({
          startDate: startDate instanceof Date ? startDate.toISOString() : (typeof startDate === 'number' ? new Date(startDate).toISOString() : startDate),
          endDate: endDate instanceof Date ? endDate.toISOString() : (typeof endDate === 'number' ? new Date(endDate).toISOString() : endDate)
        });
        if (!result || result === null || result.null === true) return null;
        return {
          steps: result.steps,
          distanceM: result.distanceM || null
        };
      } catch (e) {
        console.error('[CapacitorMotion] Query error:', e);
        return null;
      }
    }

    async function requestPermission() {
      if (!plugin) return 'unavailable';
      try {
        var result = await plugin.requestPermission();
        return result.status;
      } catch (e) {
        return 'unavailable';
      }
    }

    async function isAvailable() {
      if (!plugin) return false;
      try {
        var result = await plugin.isAvailable();
        return result.stepCounting === true;
      } catch (e) {
        return false;
      }
    }

    return Object.freeze({
      onSteps: onSteps,
      start: start,
      stop: stop,
      query: query,
      requestPermission: requestPermission,
      isAvailable: isAvailable
    });
  }

  return Object.freeze({ createAdapter: createAdapter });
}));
