// Tests para CapacitorKeepAwakeAdapter
// Story 8.2 Task 2 — contrato { acquire, release, onLost, onAcquired, isAvailable }
// compatible con el WakeLockPort de runtime.js (drop-in replacement en wlPort).
import { describe, it, expect, vi } from 'vitest';
const { createAdapter } = await import('../../adapters/capacitor-keep-awake-adapter.js');

// ── Helpers ──
function makePlugin() {
  return {
    keepAwake: vi.fn().mockResolvedValue(undefined),
    allowSleep: vi.fn().mockResolvedValue(undefined),
  };
}

// ── Tests ──
describe('CapacitorKeepAwakeAdapter', () => {
  describe('contract — interface matches WakeLockPort', () => {
    it('exports createAdapter function', () => {
      expect(createAdapter).toBeTypeOf('function');
    });

    it('produce un objeto con acquire, release, onLost, onAcquired, isAvailable', () => {
      const adapter = createAdapter({ keepAwakePlugin: makePlugin() });
      expect(adapter).toBeTypeOf('object');
      expect(adapter.acquire).toBeTypeOf('function');
      expect(adapter.release).toBeTypeOf('function');
      expect(adapter.onLost).toBeTypeOf('function');
      expect(adapter.onAcquired).toBeTypeOf('function');
      expect(adapter.isAvailable).toBeTypeOf('function');
    });
  });

  describe('acquire()', () => {
    it('llama a keepAwakePlugin.keepAwake() en nativo', async () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      await adapter.acquire();
      expect(plugin.keepAwake).toHaveBeenCalledOnce();
    });

    it('retorna true en success', async () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      const result = await adapter.acquire();
      expect(result).toBe(true);
    });

    it('dispara onAcquired callback tras acquire exitoso', async () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      const cb = vi.fn();
      adapter.onAcquired(cb);
      await adapter.acquire();
      expect(cb).toHaveBeenCalledOnce();
    });

    it('no crashea si keepAwakePlugin rechaza', async () => {
      const plugin = { keepAwake: vi.fn().mockRejectedValue(new Error('failed')) };
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      await expect(adapter.acquire()).resolves.toBe(false);
    });

    it('retorna false si el plugin falla', async () => {
      const plugin = { keepAwake: vi.fn().mockRejectedValue(new Error('failed')) };
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      const result = await adapter.acquire();
      expect(result).toBe(false);
    });

    it('no dispara onAcquired si el plugin falla', async () => {
      const plugin = { keepAwake: vi.fn().mockRejectedValue(new Error('failed')) };
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      const cb = vi.fn();
      adapter.onAcquired(cb);
      await adapter.acquire();
      expect(cb).not.toHaveBeenCalled();
    });

    it('funciona sin crash si no hay plugin (sin deps)', async () => {
      const adapter = createAdapter({});
      const result = await adapter.acquire();
      expect(result).toBe(false);
    });
  });

  describe('release()', () => {
    it('llama a keepAwakePlugin.allowSleep() en nativo', async () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      await adapter.acquire();
      adapter.release();
      expect(plugin.allowSleep).toHaveBeenCalledOnce();
    });

    it('no llama a allowSleep si no hubo acquire previo', () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      adapter.release();
      expect(plugin.allowSleep).not.toHaveBeenCalled();
    });

    it('dispara onLost callback al liberar (si había acquire)', async () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      const cb = vi.fn();
      adapter.onLost(cb);
      await adapter.acquire();
      adapter.release();
      expect(cb).toHaveBeenCalledOnce();
    });

    it('no crashea si release se llama dos veces', async () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      await adapter.acquire();
      adapter.release();
      expect(() => adapter.release()).not.toThrow();
    });

    it('funciona sin crash si no hay plugin', () => {
      const adapter = createAdapter({});
      expect(() => adapter.release()).not.toThrow();
    });
  });

  describe('onLost / onAcquired', () => {
    it('onLost acepta y almacena un callback', () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      const cb = vi.fn();
      expect(() => adapter.onLost(cb)).not.toThrow();
    });

    it('onAcquired acepta y almacena un callback', () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      const cb = vi.fn();
      expect(() => adapter.onAcquired(cb)).not.toThrow();
    });
  });

  describe('isAvailable()', () => {
    it('retorna true si keepAwakePlugin está presente', () => {
      const plugin = makePlugin();
      const adapter = createAdapter({ keepAwakePlugin: plugin });
      expect(adapter.isAvailable()).toBe(true);
    });

    it('retorna false si no hay keepAwakePlugin', () => {
      const adapter = createAdapter({});
      expect(adapter.isAvailable()).toBe(false);
    });
  });
});
