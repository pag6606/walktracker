/**
 * storage.js — WalkTracker Storage Port (AD-3)
 *
 * Hexagonal-lite: StoragePort es el puerto, los adaptadores implementan la interfaz.
 * IndexedDB para sessions/achievements, localStorage para config/snapshot.
 *
 * Uso en browser:
 *   const port = createStoragePort({ useIndexedDB: true });
 *   const sessions = await port.getSessions();
 *
 * Uso en tests (Node):
 *   const port = createStoragePort(); // usa MemoryAdapter por defecto
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = factory();
  } else {
    root.WT = root.WT || {};
    root.WT.Storage = factory();
  }
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  // ═══════════════════════════════════════════════════════
  //  MemoryAdapter — para tests en Node (sin IndexedDB)
  //  ═══════════════════════════════════════════════════════

  function createMemoryAdapter() {
    const sessions = [];
    const achievements = {};
    let config = { strideM: 0.655, weeklyGoalKm: 10.0, soundEnabled: true, recentQuoteIds: [], lastExportAt: null };
    let activeSession = null;
    let migrated = false;

    return Object.freeze({
      // Config
      getConfig() { return { ...config }; },
      saveConfig(cfg) { config = { ...config, ...cfg }; },

      // Active session
      getActiveSession() { return activeSession ? { ...activeSession } : null; },
      saveActiveSession(s) { activeSession = s ? { ...s } : null; },

      // Sessions
      getSessions() { return [...sessions]; },
      saveSession(s) {
        const idx = sessions.findIndex(x => x.id === s.id);
        if (idx >= 0) sessions[idx] = { ...s };
        else sessions.push({ ...s });
      },
      deleteSession(id) {
        const idx = sessions.findIndex(x => x.id === id);
        if (idx >= 0) sessions.splice(idx, 1);
      },

      // Achievements
      getAchievements() { return Object.values(achievements).map(a => ({ ...a })); },
      saveAchievement(a) { achievements[a.key] = { ...a }; },

      // Migration flag
      isMigrated() { return migrated; },
      setMigrated() { migrated = true; },

      // Persist
      persist() { return Promise.resolve(true); },
    });
  }

  // ═══════════════════════════════════════════════════════
  //  LocalStorage Adapters (browser)
  //  ═══════════════════════════════════════════════════════

  function createLocalStorageConfigAdapter() {
    const KEY = 'wt:config';
    const DEFAULTS = { strideM: 0.655, weeklyGoalKm: 10.0, soundEnabled: true, recentQuoteIds: [], lastExportAt: null };

    function load() {
      try {
        const raw = localStorage.getItem(KEY);
        return raw ? { ...DEFAULTS, ...JSON.parse(raw) } : { ...DEFAULTS };
      } catch { return { ...DEFAULTS }; }
    }

    return Object.freeze({
      getConfig() { return load(); },
      saveConfig(cfg) { localStorage.setItem(KEY, JSON.stringify({ ...load(), ...cfg })); },
      isMigrated() { return localStorage.getItem('wt:migrated') === 'v3'; },
      setMigrated() { localStorage.setItem('wt:migrated', 'v3'); },
    });
  }

  function createLocalStorageActiveSessionAdapter() {
    const KEY = 'wt:activeSession';

    return Object.freeze({
      getActiveSession() {
        try {
          const raw = localStorage.getItem(KEY);
          return raw ? JSON.parse(raw) : null;
        } catch { return null; }
      },
      saveActiveSession(s) {
        if (s) localStorage.setItem(KEY, JSON.stringify(s));
        else localStorage.removeItem(KEY);
      },
    });
  }

  // ═══════════════════════════════════════════════════════
  //  IndexedDB Adapters (browser)
  //  ═══════════════════════════════════════════════════════

  const DB_NAME = 'WalkTrackerDB';
  const DB_VERSION = 1;

  function openDB() {
    return new Promise((resolve, reject) => {
      if (typeof indexedDB === 'undefined') {
        reject(new Error('IndexedDB no disponible'));
        return;
      }
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains('sessions')) {
          db.createObjectStore('sessions', { keyPath: 'id' });
        }
        if (!db.objectStoreNames.contains('achievements')) {
          db.createObjectStore('achievements', { keyPath: 'key' });
        }
      };
      req.onsuccess = (e) => resolve(e.target.result);
      req.onerror = (e) => reject(e.target.error);
    });
  }

  function createIndexedDBSessionAdapter() {
    return Object.freeze({
      async getSessions() {
        const db = await openDB();
        return new Promise((resolve, reject) => {
          const tx = db.transaction('sessions', 'readonly');
          const store = tx.objectStore('sessions');
          const req = store.getAll();
          req.onsuccess = () => { resolve(req.onsuccess || []); db.close(); };
          req.onerror = () => { reject(req.error); db.close(); };
        });
      },
      async saveSession(session) {
        const db = await openDB();
        return new Promise((resolve, reject) => {
          const tx = db.transaction('sessions', 'readwrite');
          const store = tx.objectStore('sessions');
          const req = store.put(session);
          req.onsuccess = () => { resolve(); db.close(); };
          req.onerror = () => { reject(req.error); db.close(); };
        });
      },
      async deleteSession(id) {
        const db = await openDB();
        return new Promise((resolve, reject) => {
          const tx = db.transaction('sessions', 'readwrite');
          const store = tx.objectStore('sessions');
          const req = store.delete(id);
          req.onsuccess = () => { resolve(); db.close(); };
          req.onerror = () => { reject(req.error); db.close(); };
        });
      },
    });
  }

  function createIndexedDBAchievementAdapter() {
    return Object.freeze({
      async getAchievements() {
        const db = await openDB();
        return new Promise((resolve, reject) => {
          const tx = db.transaction('achievements', 'readonly');
          const store = tx.objectStore('achievements');
          const req = store.getAll();
          req.onsuccess = () => { resolve(req.result || []); db.close(); };
          req.onerror = () => { reject(req.error); db.close(); };
        });
      },
      async saveAchievement(achievement) {
        const db = await openDB();
        return new Promise((resolve, reject) => {
          const tx = db.transaction('achievements', 'readwrite');
          const store = tx.objectStore('achievements');
          const req = store.put(achievement);
          req.onsuccess = () => { resolve(); db.close(); };
          req.onerror = () => { reject(req.error); db.close(); };
        });
      },
    });
  }

  // ═══════════════════════════════════════════════════════
  //  StoragePort Factory
  //  ═══════════════════════════════════════════════════════

  /**
   * Crea un StoragePort con adaptadores inyectables.
   *
   * @param {object} [options]
   * @param {boolean} [options.useIndexedDB=false] - usar IndexedDB (browser) o MemoryAdapter (test)
   * @param {object} [options.sessionAdapter]     - adapter para sessions (inyección)
   * @param {object} [options.achievementAdapter] - adapter para achievements (inyección)
   * @param {object} [options.configAdapter]      - adapter para config
   * @param {object} [options.activeSessionAdapter] - adapter para active session
   * @returns {object} StoragePort
   */
  function createStoragePort(options = {}) {
    const useIndexedDB = options.useIndexedDB === true;

    const sessionAdapter = options.sessionAdapter || (useIndexedDB ? createIndexedDBSessionAdapter() : createMemoryAdapter());
    const achievementAdapter = options.achievementAdapter || (useIndexedDB ? createIndexedDBAchievementAdapter() : createMemoryAdapter());
    const configAdapter = options.configAdapter || (useIndexedDB ? createLocalStorageConfigAdapter() : createMemoryAdapter());
    const activeAdapter = options.activeSessionAdapter || (useIndexedDB ? createLocalStorageActiveSessionAdapter() : createMemoryAdapter());

    // When using MemoryAdapter for both, share the same instance
    const shared = !useIndexedDB && !options.sessionAdapter ? createMemoryAdapter() : null;
    const sa = options.sessionAdapter || shared || sessionAdapter;
    const aa = options.achievementAdapter || shared || achievementAdapter;

    return Object.freeze({
      // Config
      getConfig() { return configAdapter.getConfig(); },
      saveConfig(cfg) { configAdapter.saveConfig(cfg); },

      // Active session
      getActiveSession() { return activeAdapter.getActiveSession(); },
      saveActiveSession(s) { activeAdapter.saveActiveSession(s); },

      // Sessions (async — Promise)
      getSessions() { return Promise.resolve(sa.getSessions()); },
      saveSession(s) { return Promise.resolve(sa.saveSession(s)); },
      deleteSession(id) { return Promise.resolve(sa.deleteSession(id)); },

      // Achievements (async — Promise)
      getAchievements() { return Promise.resolve(aa.getAchievements()); },
      saveAchievement(a) { return Promise.resolve(aa.saveAchievement(a)); },

      // Persist — delegate to adapter, fallback to navigator.storage
      async persist() {
        if (sa.persist) return sa.persist();
        if (typeof navigator !== 'undefined' && navigator.storage && navigator.storage.persist) {
          return navigator.storage.persist();
        }
        return false;
      },

      // Migration flag (via config adapter = localStorage, or memory for tests)
      isMigrated() { return configAdapter.isMigrated ? configAdapter.isMigrated() : sa.isMigrated(); },
      setMigrated() {
        if (configAdapter.setMigrated) configAdapter.setMigrated();
        else if (sa.setMigrated) sa.setMigrated();
        else try { localStorage.setItem('wt:migrated', 'v3'); } catch { /* noop */ }
      },

      // Adapter access (for testing)
      _adapter: { session: sa, achievement: aa, config: configAdapter, active: activeAdapter },
    });
  }

  return { createStoragePort, createMemoryAdapter };
}));
