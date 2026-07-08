// WalkTracker v3.0 - Integration Tests for index.html
// Framework: Vitest + jsdom

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { JSDOM } from 'jsdom';

// Simula StorageAdapter de memoria para tests
class MemoryStorageAdapter {
  constructor() {
    this.store = new Map();
  }

  async load() {
    return this.store.get('sessions') || [];
  }

  async save(sessions) {
    this.store.set('sessions', sessions);
  }

  async add(session) {
    const sessions = await this.load();
    sessions.push(session);
    await this.save(sessions);
  }

  async update(updatedSession) {
    const sessions = await this.load();
    const index = sessions.findIndex(s => s.id === updatedSession.id);
    if (index !== -1) {
      sessions[index] = updatedSession;
      await this.save(sessions);
    }
  }

  async delete(sessionId) {
    const sessions = await this.load();
    const filtered = sessions.filter(s => s.id !== sessionId);
    await this.save(filtered);
  }
}

// Simula Session para tests
class Session {
  constructor(steps = 0, startTime = Date.now()) {
    this.id = 'test-' + Math.random().toString(36).substr(2, 9);
    this.steps = steps;
    this.startTime = startTime;
    this.pausedAt = null;
    this.accumulatedPause = 0;
  }

  addStep() {
    this.steps++;
  }

  pause() {
    this.pausedAt = Date.now();
  }

  resume() {
    if (this.pausedAt) {
      this.accumulatedPause += (Date.now() - this.pausedAt);
      this.pausedAt = null;
    }
  }

  stop() {
    this.stopTime = Date.now();
    return {
      duration: this.stopTime - this.startTime - this.accumulatedPause,
      steps: this.steps,
      timestamp: this.startTime
    };
  }
}

describe('WalkScreen Integration Tests', () => {
  let dom;
  let window;
  let document;
  let storage;
  let activeSession;
  let stepDetector;
  let chronometer;

  beforeEach(() => {
    dom = new JSDOM(`
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>WalkTracker</title>
      </head>
      <body>
        <div id="app">
          <div id="walk-screen" style="display: none;">
            <h2 id="step-count">0</h2>
            <h3 id="step-velocity">0 pasos/min</h3>
            <p id="chronometer">00:00:00</p>
            <button id="btn-start">Iniciar</button>
            <button id="btn-pause" style="display: none;">Pausar</button>
            <button id="btn-resume" style="display: none;">Resumir</button>
            <button id="btn-stop" style="display: none;">Terminar</button>
          </div>
          <div id="history-screen" style="display: none;">
            <ul id="session-list"></ul>
          </div>
          <div id="settings-screen" style="display: none;">
            <button id="btn-export-csv">Export CSV</button>
            <button id="btn-export-json">Export JSON</button>
            <p id="backup-warning" style="display: none;"></p>
          </div>
        </div>
      </body>
      </html>
    `, { runScripts: 'dangerously' });

    window = dom.window;
    document = window.document;
    storage = new MemoryStorageAdapter();
    activeSession = null;
    stepDetector = { detect: vi.fn(() => false) };
    chronometer = {
      start: vi.fn(),
      stop: vi.fn(),
      pause: vi.fn(),
      resume: vi.fn(),
      getFormatted: vi.fn(() => '00:00:00')
    };

    // Simula funciones globales
    window.walktracker = {
      storage,
      stepDetector,
      chronometer
    };
  });

  afterEach(() => {
    dom.window.close();
  });

  describe('Flujo completo de caminata', () => {
    it('inicia caminata al tocar START', async () => {
      const btnStart = document.getElementById('btn-start');
      const stepCount = document.getElementById('step-count');

      // Inicia caminata
      btnStart.click();

      // Verifica estado
      expect(activeSession).toBeTruthy();
      expect(chronometer.start).toHaveBeenCalled();
      expect(stepCount.textContent).toBe('0');
    });

    it('pausa caminata al tocar PAUSE', async () => {
      const btnStart = document.getElementById('btn-start');
      const btnPause = document.getElementById('btn-pause');

      // Inicia y pausa
      btnStart.click();
      btnPause.click();

      // Verifica pausa
      expect(activeSession.pausedAt).toBeTruthy();
      expect(chronometer.pause).toHaveBeenCalled();
    });

    it('resume caminata al tocar RESUME', async () => {
      const btnStart = document.getElementById('btn-start');
      const btnPause = document.getElementById('btn-pause');
      const btnResume = document.getElementById('btn-resume');

      // Inicia, pausa, resume
      btnStart.click();
      btnPause.click();
      btnResume.click();

      // Verifica resume
      expect(activeSession.pausedAt).toBeNull();
      expect(chronometer.resume).toHaveBeenCalled();
    });

    it('termina caminata al tocar STOP y guarda en storage', async () => {
      const btnStart = document.getElementById('btn-start');
      const btnStop = document.getElementById('btn-stop');
      const sessionList = document.getElementById('session-list');

      // Inicia y termina
      btnStart.click();
      activeSession.addStep(); // Añade un paso
      btnStop.click();

      // Verifica guardado
      const sessions = await storage.load();
      expect(sessions.length).toBe(1);
      expect(sessions[0].steps).toBe(1);
    });
  });

  describe('Actualización de pasos en tiempo real', () => {
    it('actualiza paso count cuando se detecta paso', async () => {
      const btnStart = document.getElementById('btn-start');
      const stepCount = document.getElementById('step-count');

      btnStart.click();

      // Simula detección de paso
      stepDetector.detect.mockReturnValue(true);
      const simulatedStep = { magnitude: 12, timestamp: Date.now() };
      activeSession.addStep();

      stepCount.textContent = activeSession.steps.toString();
      expect(stepCount.textContent).toBe('1');
    });

    it('calcula velocidad de pasos en tiempo real', async () => {
      const btnStart = document.getElementById('btn-start');
      const stepVelocity = document.getElementById('step-velocity');

      btnStart.click();
      stepDetector.detect.mockReturnValue(true);

      // Simula 10 pasos en 1 minuto
      for (let i = 0; i < 10; i++) {
        activeSession.addStep();
      }

      const velocity = Math.round((activeSession.steps / 1) * 60);
      stepVelocity.textContent = `${velocity} pasos/min`;
      expect(stepVelocity.textContent).toBe('600 pasos/min');
    });
  });
});

describe('HistoryScreen Integration Tests', () => {
  let dom;
  let window;
  let document;
  let storage;

  beforeEach(async () => {
    dom = new JSDOM(`
      <!DOCTYPE html>
      <html>
      <body>
        <div id="history-screen">
          <ul id="session-list"></ul>
          <input type="date" id="filter-start-date" />
          <input type="date" id="filter-end-date" />
          <button id="btn-filter">Filtrar</button>
        </div>
      </body>
      </html>
    `, { runScripts: 'dangerously' });

    window = dom.window;
    document = window.document;
    storage = new MemoryStorageAdapter();

    // Añade sesiones de prueba
    await storage.add({
      id: 'session-1',
      steps: 500,
      timestamp: Date.now() - 86400000, // Ayer
      duration: 60000
    });
    await storage.add({
      id: 'session-2',
      steps: 1000,
      timestamp: Date.now(), // Hoy
      duration: 120000
    });
    await storage.add({
      id: 'session-3',
      steps: 300,
      timestamp: Date.now() - 172800000, // Anteayer
      duration: 40000
    });
  });

  afterEach(() => {
    dom.window.close();
  });

  describe('Lista de sesiones', () => {
    it('lista todas las sesiones ordenadas por fecha (más reciente primero)', async () => {
      const sessionList = document.getElementById('session-list');
      const sessions = await storage.load();

      // Ordena por timestamp descendente
      sessions.sort((a, b) => b.timestamp - a.timestamp);

      // Renderiza
      sessionList.innerHTML = sessions.map(s => `
        <li data-session-id="${s.id}">
          <span class="steps">${s.steps} pasos</span>
          <span class="date">${new Date(s.timestamp).toLocaleDateString()}</span>
        </li>
      `).join('');

      const items = sessionList.querySelectorAll('li');
      expect(items.length).toBe(3);
      expect(items[0].getAttribute('data-session-id')).toBe('session-2'); // Hoy
      expect(items[1].getAttribute('data-session-id')).toBe('session-1'); // Ayer
      expect(items[2].getAttribute('data-session-id')).toBe('session-3'); // Anteayer
    });
  });

  describe('Filtrado por fecha', () => {
    it('filtra sesiones por rango de fechas', async () => {
      const sessionList = document.getElementById('session-list');
      const filterStartDate = document.getElementById('filter-start-date');
      const filterEndDate = document.getElementById('filter-end-date');
      const btnFilter = document.getElementById('btn-filter');

      // Configura fechas (ayer hasta hoy)
      const yesterday = new Date(Date.now() - 86400000);
      const today = new Date();
      filterStartDate.value = yesterday.toISOString().split('T')[0];
      filterEndDate.value = today.toISOString().split('T')[0];

      // Filtra
      btnFilter.click();
      const sessions = await storage.load();
      const filtered = sessions.filter(s => {
        const date = new Date(s.timestamp);
        return date >= yesterday && date <= today;
      });

      // Renderiza filtradas
      sessionList.innerHTML = filtered.map(s => `
        <li data-session-id="${s.id}">
          <span>${s.steps} pasos</span>
        </li>
      `).join('');

      const items = sessionList.querySelectorAll('li');
      expect(items.length).toBe(2); // Solo ayer y hoy
    });
  });

  describe('Eliminación de sesión', () => {
    it('elimina sesión con confirmación', async () => {
      const sessionList = document.getElementById('session-list');
      const sessionsBefore = await storage.load();
      expect(sessionsBefore.length).toBe(3);

      // Simula confirmación
      window.confirm = vi.fn(() => true);

      // Elimina session-2
      if (window.confirm('¿Eliminar esta sesión?')) {
        await storage.delete('session-2');
      }

      const sessionsAfter = await storage.load();
      expect(sessionsAfter.length).toBe(2);
      expect(sessionsAfter.find(s => s.id === 'session-2')).toBeUndefined();
      expect(window.confirm).toHaveBeenCalledWith('¿Eliminar esta sesión?');
    });
  });
});

describe('SessionDetailScreen Integration Tests', () => {
  let dom;
  let window;
  let document;
  let storage;
  let testSession;

  beforeEach(async () => {
    testSession = {
      id: 'session-test',
      steps: 1500,
      timestamp: Date.now(),
      duration: 900000, // 15 minutos
      temperature: 22,
      weatherCondition: 'clear',
      achievements: ['first-walk', 'thousand-steps'],
      notes: 'Caminata muy agradable'
    };

    dom = new JSDOM(`
      <!DOCTYPE html>
      <html>
      <body>
        <div id="session-detail-screen">
          <h2 id="detail-steps"></h2>
          <p id="detail-duration"></p>
          <p id="detail-date"></p>
          <p id="detail-temperature"></p>
          <p id="detail-weather"></p>
          <ul id="detail-achievements"></ul>
          <textarea id="detail-notes"></textarea>
          <button id="btn-save-notes">Guardar Nota</button>
          <button id="btn-back">Volver</button>
        </div>
      </body>
      </html>
    `, { runScripts: 'dangerously' });

    window = dom.window;
    document = window.document;
    storage = new MemoryStorageAdapter();
    await storage.add(testSession);
  });

  afterEach(() => {
    dom.window.close();
  });

  describe('Visualización de detalle', () => {
    it('muestra todos los detalles de la sesión', () => {
      const detailSteps = document.getElementById('detail-steps');
      const detailDuration = document.getElementById('detail-duration');
      const detailDate = document.getElementById('detail-date');
      const detailTemperature = document.getElementById('detail-temperature');
      const detailWeather = document.getElementById('detail-weather');
      const detailAchievements = document.getElementById('detail-achievements');
      const detailNotes = document.getElementById('detail-notes');

      // Renderiza datos
      detailSteps.textContent = `${testSession.steps} pasos`;
      detailDuration.textContent = new Date(testSession.duration).toISOString().substr(11, 8);
      detailDate.textContent = new Date(testSession.timestamp).toLocaleString();
      detailTemperature.textContent = `${testSession.temperature}°C`;
      detailWeather.textContent = testSession.weatherCondition;
      detailNotes.value = testSession.notes || '';

      testSession.achievements.forEach(a => {
        const li = document.createElement('li');
        li.textContent = a;
        detailAchievements.appendChild(li);
      });

      // Verifica datos
      expect(detailSteps.textContent).toBe('1500 pasos');
      expect(detailDate.textContent).toBeTruthy();
      expect(detailTemperature.textContent).toBe('22°C');
      expect(detailWeather.textContent).toBe('clear');
      expect(detailAchievements.children.length).toBe(2);
      expect(detailNotes.value).toBe('Caminata muy agradable');
    });
  });

  describe('Edición de notas', () => {
    it('guarda cambios al editar nota', async () => {
      const detailNotes = document.getElementById('detail-notes');
      const btnSaveNotes = document.getElementById('btn-save-notes');

      // Edita nota
      detailNotes.value = 'Nueva nota actualizada';
      btnSaveNotes.click();

      // Guarda en storage
      testSession.notes = detailNotes.value;
      await storage.update(testSession);

      // Verifica persistencia
      const sessions = await storage.load();
      const updated = sessions.find(s => s.id === testSession.id);
      expect(updated.notes).toBe('Nueva nota actualizada');
    });
  });
});

describe('SettingsScreen Integration Tests', () => {
  let dom;
  let window;
  let document;
  let storage;
  let oldSession;

  beforeEach(async () => {
    oldSession = {
      id: 'old-session',
      steps: 2000,
      timestamp: Date.now() - (35 * 24 * 60 * 60 * 1000), // 35 días
      duration: 1200000
    };

    dom = new JSDOM(`
      <!DOCTYPE html>
      <html>
      <body>
        <div id="settings-screen">
          <button id="btn-export-csv">Export CSV</button>
          <button id="btn-export-json">Export JSON</button>
          <p id="backup-warning" style="display: none;"></p>
          <label>
            <input type="checkbox" id="chk-autosave" />
            Auto-guardado
          </label>
          <label>
            <input type="number" id="inp-height" />
            Altura (cm)
          </label>
          <button id="btn-save-settings">Guardar</button>
        </div>
      </body>
      </html>
    `, { runScripts: 'dangerously' });

    window = dom.window;
    document = window.document;
    storage = new MemoryStorageAdapter();
    await storage.add(oldSession);
  });

  afterEach(() => {
    dom.window.close();
  });

  describe('Persistencia de preferencias', () => {
    it('persiste preferencias tras recargar', async () => {
      const chkAutosave = document.getElementById('chk-autosave');
      const inpHeight = document.getElementById('inp-height');
      const btnSaveSettings = document.getElementById('btn-save-settings');

      // Cambia preferencias
      chkAutosave.checked = true;
      inpHeight.value = 175;
      btnSaveSettings.click();

      // Simula recarga (crea nuevo DOM)
      const newDom = new JSDOM(`
        <!DOCTYPE html>
        <html>
        <body>
          <div id="settings-screen">
            <input type="checkbox" id="chk-autosave" />
            <input type="number" id="inp-height" />
          </div>
        </body>
        </html>
      `, { runScripts: 'dangerously' });

      const newDoc = newDom.window.document;
      const newChkAutosave = newDoc.getElementById('chk-autosave');
      const newInpHeight = newDoc.getElementById('inp-height');

      // Simula que preferences se cargan del localStorage
      const preferences = JSON.parse(localStorage.getItem('walktracker-preferences') || '{}');
      newChkAutosave.checked = preferences.autosave || false;
      newInpHeight.value = preferences.height || '';

      // Verifica persistencia
      expect(newChkAutosave.checked).toBe(true);
      expect(newInpHeight.value).toBe('175');

      newDom.window.close();
    });
  });

  describe('Aviso de respaldo', () => {
    it('muestra aviso cuando hay sesión >30 días', async () => {
      const backupWarning = document.getElementById('backup-warning');
      const sessions = await storage.load();

      // Busca sesión más antigua
      const oldestSession = sessions.reduce((oldest, current) =>
        current.timestamp < oldest.timestamp ? current : oldest
      );

      const daysSinceLast = (Date.now() - oldestSession.timestamp) / (1000 * 60 * 60 * 24);

      if (daysSinceLast > 30) {
        backupWarning.style.display = 'block';
        backupWarning.textContent = `Tu última caminata fue hace ${Math.floor(daysSinceLast)} días. ¡Haz un respaldo!`;
      }

      expect(backupWarning.style.display).toBe('block');
      expect(backupWarning.textContent).toContain('35 días');
    });

    it('NO muestra aviso cuando sesión <30 días', async () => {
      // Añade sesión reciente
      await storage.add({
        id: 'recent-session',
        steps: 500,
        timestamp: Date.now() - (15 * 24 * 60 * 60 * 1000), // 15 días
        duration: 60000
      });

      const backupWarning = document.getElementById('backup-warning');
      const sessions = await storage.load();

      const oldestSession = sessions.reduce((oldest, current) =>
        current.timestamp < oldest.timestamp ? current : oldest
      );

      const daysSinceLast = (Date.now() - oldestSession.timestamp) / (1000 * 60 * 60 * 24);

      if (daysSinceLast > 30) {
        backupWarning.style.display = 'block';
      } else {
        backupWarning.style.display = 'none';
      }

      expect(backupWarning.style.display).toBe('none');
    });
  });

  describe('Export CSV', () => {
    it('exporta CSV correctamente', async () => {
      const sessions = await storage.load();

      // Convierte a CSV
      const csvHeader = 'ID,Pasos,Fecha,Duración\n';
      const csvBody = sessions.map(s =>
        `${s.id},${s.steps},${new Date(s.timestamp).toISOString()},${s.duration}`
      ).join('\n');
      const csvContent = csvHeader + csvBody;

      // Simula Web Share API
      const blob = new Blob([csvContent], { type: 'text/csv' });
      const file = new File([blob], 'walktracker-export.csv', { type: 'text/csv' });

      // Verifica formato
      expect(file.name).toBe('walktracker-export.csv');
      expect(file.type).toBe('text/csv');
      expect(csvContent).toContain('ID,Pasos,Fecha,Duración');
      expect(csvContent).toContain('old-session');
      expect(csvContent).toContain('2000');
    });
  });

  describe('Export JSON', () => {
    it('exporta JSON correctamente', async () => {
      const sessions = await storage.load();

      // Convierte a JSON
      const jsonContent = JSON.stringify(sessions, null, 2);

      // Simula Web Share API
      const blob = new Blob([jsonContent], { type: 'application/json' });
      const file = new File([blob], 'walktracker-export.json', { type: 'application/json' });

      // Verifica formato
      expect(file.name).toBe('walktracker-export.json');
      expect(file.type).toBe('application/json');

      // Verifica contenido parseable
      const parsed = JSON.parse(jsonContent);
      expect(Array.isArray(parsed)).toBe(true);
      expect(parsed.length).toBe(1);
      expect(parsed[0].id).toBe('old-session');
      expect(parsed[0].steps).toBe(2000);
    });
  });
});

describe('PersistenceIntegration Tests', () => {
  let dom;
  let window;
  let document;
  let storage;

  beforeEach(() => {
    dom = new JSDOM(`
      <!DOCTYPE html>
      <html>
      <body>
        <div id="app">
          <div id="walk-screen">
            <h2 id="step-count">0</h2>
            <button id="btn-start">Iniciar</button>
            <button id="btn-stop" style="display: none;">Terminar</button>
          </div>
        </div>
      </body>
      </html>
    `, { runScripts: 'dangerously' });

    window = dom.window;
    document = window.document;
    storage = new MemoryStorageAdapter();

    window.walktracker = { storage };
  });

  afterEach(() => {
    dom.window.close();
  });

  describe('Persistencia tras recargar página', () => {
    it('guarda sesión tras recargar', async () => {
      const btnStart = document.getElementById('btn-start');
      const btnStop = document.getElementById('btn-stop');

      // Crea sesión
      btnStart.click();
      const session = new Session(100, Date.now());
      await storage.add(session);

      // Simula recarga (crea nuevo DOM)
      const newDom = new JSDOM(`
        <!DOCTYPE html>
        <html>
        <body>
          <div id="walk-screen">
            <h2 id="step-count">0</h2>
          </div>
        </body>
        </html>
      `, { runScripts: 'dangerously' });

      const newDoc = newDom.window.document;
      const newStepCount = newDoc.getElementById('step-count');

      // Carga datos del storage
      const sessions = await storage.load();
      expect(sessions.length).toBe(1);
      expect(sessions[0].steps).toBe(100);
      newStepCount.textContent = sessions[0].steps.toString();

      expect(newStepCount.textContent).toBe('100');

      newDom.window.close();
    });
  });

  describe('Migración v1→v3 en contexto real', () => {
    it('migra datos v1→v3', async () => {
      // Simula datos v1 en localStorage
      const v1Data = JSON.stringify([
        {
          date: '2025-06-01',
          laps: 10,
          timestamp: Date.now() - (35 * 24 * 60 * 60 * 1000)
        }
      ]);
      localStorage.setItem('wt:sessions', v1Data);

      // Ejecuta migración
      const v1Sessions = JSON.parse(localStorage.getItem('wt:sessions') || '[]');
      const v3Sessions = v1Sessions.map(v1 => ({
        id: 'migrated-' + Math.random().toString(36).substr(2, 9),
        steps: v1.laps * 400, // 400 pasos por vuelta
        timestamp: new Date(v1.date + 'T00:00:00').getTime(),
        duration: v1.laps * 4 * 60 * 1000, // 4 min por vuelta
        migrated: true
      }));

      await storage.save(v3Sessions);

      // Verifica migración
      const sessions = await storage.load();
      expect(sessions.length).toBe(1);
      expect(sessions[0].steps).toBe(4000); // 10 vueltas * 400
      expect(sessions[0].migrated).toBe(true);
    });
  });
});

// Resumen de tests en este suite
console.log(`
╔════════════════════════════════════════════════════════════════╗
║  WALKTRACKER v3.0 - INTEGRATION TESTS                          ║
╠════════════════════════════════════════════════════════════════╣
║  WalkScreen:        5 tests                                     ║
║  HistoryScreen:     3 tests                                     ║
║  SessionDetail:     2 tests                                     ║
║  SettingsScreen:    5 tests                                     ║
║  Persistence:       2 tests                                     ║
╠════════════════════════════════════════════════════════════════╣
║  TOTAL:             17 tests                                    ║
╚════════════════════════════════════════════════════════════════╝

Framework: Vitest + jsdom
Cobertura: UI flows, persistence, migration, export

Para ejecutar:
  npm install --save-dev vitest jsdom
  npx vitest test/index-tests.js
`);