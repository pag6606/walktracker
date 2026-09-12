/**
 * capacitor-feedback-adapter.js — WalkTracker Feedback Adapter (Epic 4, Story 4.2)
 *
 * Implementa el FeedbackPort para entorno nativo iOS via WalktrackerFeedbackPlugin.
 * El dominio no conoce CoreHaptics ni AVFoundation — este adapter es el único punto de contacto.
 * Fuente: AR-10, AR-13.
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.CapacitorFeedbackAdapter = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  function createAdapter(deps) {
    var soundEnabled = true;

    function getPlugin() {
      return (deps && deps.plugin)
        || (typeof WalktrackerKit !== 'undefined' ? WalktrackerKit : null)
        || (typeof Capacitor !== 'undefined' && Capacitor.Plugins && Capacitor.Plugins.WalktrackerKit)
        || (typeof window !== 'undefined' && window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.WalktrackerKit)
        || null;
    }

    function fire(type) {
      var p = getPlugin();
      console.log('[CapacitorFeedback] fire() type:', type, 'plugin found:', !!p);
      if (!p) {
        console.warn('[CapacitorFeedback] Plugin no disponible');
        return;
      }
      p.fireFeedback({ type: type }).then(function(r) {
        console.log('[CapacitorFeedback] fireFeedback resolved:', r);
      }).catch(function(e) {
        console.error('[CapacitorFeedback] Fire error:', e);
      });
    }

    function setSoundEnabled(enabled) {
      soundEnabled = !!enabled;
      var p = getPlugin();
      if (p) {
        p.setSoundEnabled({ enabled: soundEnabled }).catch(function(e) {});
      }
    }

    function isSoundEnabled() {
      return soundEnabled;
    }

    return Object.freeze({
      fire: fire,
      setSoundEnabled: setSoundEnabled,
      isSoundEnabled: isSoundEnabled
    });
  }

  return Object.freeze({ createAdapter: createAdapter });
}));
