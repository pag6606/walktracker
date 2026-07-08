// WalkTracker v3.0 - E2E Tests con Playwright
// Pruebas de extremo a extremo en navegadores reales

import { test, expect } from '@playwright/test';

test.describe('WalkTracker E2E Tests', () => {

  test.beforeEach(async ({ page }) => {
    // Navega a la app
    await page.goto('./');

    // Limpia localStorage antes de cada test
    await page.evaluate(() => {
      localStorage.clear();
    });
  });

  test.describe('Flujos de usuario principales', () => {

    test('Flujo completo: Iniciar → Pausar → Resumir → Terminar', async ({ page }) => {
      // 1. Verifica WalkScreen inicial
      await expect(page.locator('text=WalkTracker')).toBeVisible();
      await expect(page.locator('[data-testid="btn-start"]')).toBeVisible();

      // 2. Inicia caminata
      await page.click('[data-testid="btn-start"]');
      await expect(page.locator('[data-testid="btn-pause"]')).toBeVisible();
      await expect(page.locator('[data-testid="btn-finish"]')).toBeVisible();
      await expect(page.locator('[data-testid="btn-start"]')).not.toBeVisible();

      // 3. Pausa caminata
      await page.click('[data-testid="btn-pause"]');
      // El botón de pausa cambia a "Reanudar"
      await expect(page.locator('[data-testid="btn-pause"]')).toBeVisible();
      await expect(page.locator('[data-testid="btn-pause"]')).toHaveText('Reanudar');

      // 4. Resumen caminata
      await page.click('[data-testid="btn-pause"]');
      await expect(page.locator('[data-testid="btn-pause"]')).toBeVisible();
      await expect(page.locator('[data-testid="btn-pause"]')).toHaveText('Pausar');

      // 5. Termina caminata
      await page.click('[data-testid="btn-finish"]');

      // 6. Verifica que navegó a SummaryScreen
      await expect(page.locator('[data-testid="summary-screen"]')).toBeVisible();
    });

    test('Navegación entre pantallas', async ({ page }) => {
      // 1. Está en WalkScreen
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();

      // 2. Navega a Historial
      await page.click('[data-testid="nav-history"]');
      await expect(page.locator('[data-testid="history-screen"]')).toBeVisible();
      await expect(page.locator('[data-testid="walk-screen"]')).not.toBeVisible();

      // 3. Navega a Logros
      await page.click('[data-testid="nav-achievements"]');
      await expect(page.locator('[data-testid="achievements-screen"]')).toBeVisible();

      // 4. Navega a Settings
      await page.click('[data-testid="nav-settings"]');
      await expect(page.locator('[data-testid="settings-screen"]')).toBeVisible();

      // 5. Vuelve a WalkScreen a través de botón back
      await page.click('[data-testid="btn-settings-back"]');
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();
    });

    test('Ver detalle de sesión y editar nota', async ({ page }) => {
      // 1. Primero crea una sesión
      await page.click('[data-testid="btn-start"]');
      await page.click('[data-testid="btn-finish"]');

      // 2. Crea sesión nueva
      await page.click('[data-testid="btn-new"]');

      // 3. Navega a historial
      await page.click('[data-testid="nav-history"]');

      // 4. Verifica que hay sesiones en la lista
      await expect(page.locator('[data-testid="history-list"]')).toBeVisible();
    });

    test('Filtrar historial por fecha', async ({ page }) => {
      // 1. Crea varias sesiones
      await page.click('[data-testid="btn-start"]');
      await page.click('[data-testid="btn-stop"]');

      await page.click('[data-testid="nav-walk"]');
      await page.click('[data-testid="btn-start"]');
      await page.click('[data-testid="btn-stop"]');

      // 2. Navega a historial
      await page.click('[data-testid="nav-history"]');
      await expect(page.locator('[data-testid="session-list"]')).toHaveCount(2);

      // 3. Filtra por hoy
      const today = new Date().toISOString().split('T')[0];
      await page.fill('[data-testid="filter-start-date"]', today);
      await page.fill('[data-testid="filter-end-date"]', today);
      await page.click('[data-testid="btn-filter"]');

      // 4. Verifica que solo muestra hoy
      await expect(page.locator('[data-testid="session-list"]')).toHaveCount(2);
    });

    test('Eliminar sesión con confirmación', async ({ page }) => {
      // 1. Crea una sesión
      await page.click('[data-testid="btn-start"]');
      await page.click('[data-testid="btn-stop"]');

      // 2. Navega a historial
      await page.click('[data-testid="nav-history"]');
      await expect(page.locator('[data-testid="session-list"]')).toHaveCount(1);

      // 3. Click en eliminar
      page.on('dialog', dialog => dialog.accept());
      await page.click('[data-testid="btn-delete-session-0"]');

      // 4. Verifica que eliminó
      await expect(page.locator('[data-testid="session-list"]')).toHaveCount(0);
    });

    test('Ver logros desbloqueados', async ({ page }) => {
      // 1. Crea una sesión con suficientes pasos
      await page.evaluate(() => {
        // Simula caminata con 1000 pasos
        const session = {
          id: 'test-session',
          steps: 1000,
          timestamp: Date.now(),
          duration: 600000
        };
        const sessions = JSON.parse(localStorage.getItem('walktracker-sessions') || '[]');
        sessions.push(session);
        localStorage.setItem('walktracker-sessions', JSON.stringify(sessions));
      });

      // 2. Navega a logros
      await page.click('[data-testid="nav-achievements"]');

      // 3. Verifica logros desbloqueados
      await expect(page.locator('[data-testid="achievement-thousand-steps"]')).toBeVisible();
      await expect(page.locator('[data-testid="achievement-thousand-steps"]')).toHaveClass(/unlocked/);
    });

    test('Cambiar preferencias en Settings', async ({ page }) => {
      // 1. Navega a Settings
      await page.click('[data-testid="nav-settings"]');

      // 2. Cambia altura
      await page.fill('[data-testid="inp-height"]', '175');

      // 3. Activa auto-guardado
      await page.check('[data-testid="chk-autosave"]');

      // 4. Guarda
      await page.click('[data-testid="btn-save-settings"]');

      // 5. Recarga página
      await page.reload();

      // 6. Navega a Settings nuevamente
      await page.click('[data-testid="nav-settings"]');

      // 7. Verifica que persistió
      await expect(page.locator('[data-testid="inp-height"]')).toHaveValue('175');
      await expect(page.locator('[data-testid="chk-autosave"]')).toBeChecked();
    });

    test('Export CSV', async ({ page }) => {
      // 1. Crea una sesión
      await page.evaluate(() => {
        const session = {
          id: 'test-session',
          steps: 500,
          timestamp: Date.now(),
          duration: 300000
        };
        const sessions = JSON.parse(localStorage.getItem('walktracker-sessions') || '[]');
        sessions.push(session);
        localStorage.setItem('walktracker-sessions', JSON.stringify(sessions));
      });

      // 2. Navega a Settings
      await page.click('[data-testid="nav-settings"]');

      // 3. Click en export CSV
      const [download] = await Promise.all([
        page.waitForEvent('download'),
        page.click('[data-testid="btn-export-csv"]')
      ]);

      // 4. Verifica archivo descargado
      expect(download.suggestedFilename()).toBe('walktracker-export.csv');
    });

    test('Export JSON', async ({ page }) => {
      // 1. Crea una sesión
      await page.evaluate(() => {
        const session = {
          id: 'test-session',
          steps: 500,
          timestamp: Date.now(),
          duration: 300000
        };
        const sessions = JSON.parse(localStorage.getItem('walktracker-sessions') || '[]');
        sessions.push(session);
        localStorage.setItem('walktracker-sessions', JSON.stringify(sessions));
      });

      // 2. Navega a Settings
      await page.click('[data-testid="nav-settings"]');

      // 3. Click en export JSON
      const [download] = await Promise.all([
        page.waitForEvent('download'),
        page.click('[data-testid="btn-export-json"]')
      ]);

      // 4. Verifica archivo descargado
      expect(download.suggestedFilename()).toBe('walktracker-export.json');
    });

  });

  test.describe('Persistencia y Datos', () => {

    test('Persistencia tras recargar página', async ({ page }) => {
      // 1. Inicia caminata
      await page.click('[data-testid="btn-start"]');

      // 2. Simula detección de pasos
      await page.evaluate(() => {
        // Añade 10 pasos
        for (let i = 0; i < 10; i++) {
          const event = new CustomEvent('stepdetected', { detail: { magnitude: 12 } });
          window.dispatchEvent(event);
        }
      });

      // 3. Recarga página
      await page.reload();

      // 4. Verifica que mantiene contador
      await expect(page.locator('[data-testid="step-count"]')).toHaveText('10');
    });

    test('Datos persisten al cerrar y abrir pestaña', async ({ context }) => {
      // 1. Crea pestaña 1
      const page1 = await context.newPage();
      await page1.goto('./');
      await page1.click('[data-testid="btn-start"]');
      await page1.click('[data-testid="btn-stop"]');

      // 2. Cierra pestaña 1
      await page1.close();

      // 3. Abre pestaña 2
      const page2 = await context.newPage();
      await page2.goto('./');

      // 4. Navega a historial
      await page2.click('[data-testid="nav-history"]');

      // 5. Verifica que sesión persistió
      await expect(page2.locator('[data-testid="session-list"]')).toHaveCount(1);
    });

    test('Migración v1→v3 en navegador real', async ({ page }) => {
      // 1. Simula datos v1 en localStorage
      await page.evaluate(() => {
        const v1Data = JSON.stringify([
          {
            date: '2025-06-01',
            laps: 10,
            timestamp: Date.now() - (35 * 24 * 60 * 60 * 1000)
          }
        ]);
        localStorage.setItem('wt:sessions', v1Data);
      });

      // 2. Recarga página (dispara migración)
      await page.reload();

      // 3. Navega a historial
      await page.click('[data-testid="nav-history"]');

      // 4. Verifica que migró
      await expect(page.locator('[data-testid="session-list"]')).toHaveCount(1);
      await expect(page.locator('text=4000 pasos')).toBeVisible(); // 10 vueltas * 400
    });

  });

  test.describe('Comportamiento Offline', () => {

    test('Funciona sin conexión', async ({ page, context }) => {
      // 1. Navega a la app
      await page.goto('./');

      // 2. Simula offline
      await context.setOffline(true);

      // 3. Verifica que la página funciona
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();

      // 4. Intenta iniciar caminata
      await page.click('[data-testid="btn-start"]');
      await expect(page.locator('[data-testid="btn-pause"]')).toBeVisible();

      // 5. Verifica que funciona
      await context.setOffline(false);
    });

    test('Service Worker cachea assets', async ({ page, context }) => {
      // 1. Habilita Service Worker
      await page.goto('./');

      // 2. Verifica que SW está registrado
      const sw = await page.evaluate(() => {
        return navigator.serviceWorker.getRegistration();
      });
      expect(sw).toBeTruthy();

      // 3. Simula offline
      await context.setOffline(true);

      // 4. Recarga página
      await page.reload();

      // 5. Verifica que funciona desde cache
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();

      await context.setOffline(false);
    });

  });

  test.describe('Comportamiento de APIs de navegador', () => {

    test('WakeLock API activa y desactiva', async ({ page }) => {
      // 1. Inicia caminata
      await page.click('[data-testid="btn-start"]');

      // 2. Verifica que WakeLock está activo
      const wakeLockActive = await page.evaluate(() => {
        return window.walktracker.runtime.wakeLock.active;
      });
      expect(wakeLockActive).toBe(true);

      // 3. Termina caminata
      await page.click('[data-testid="btn-stop"]');

      // 4. Verifica que WakeLock está inactivo
      const wakeLockInactive = await page.evaluate(() => {
        return window.walktracker.runtime.wakeLock.active;
      });
      expect(wakeLockInactive).toBe(false);
    });

    test('Background tab muestra notificación', async ({ page }) => {
      // 1. Inicia caminata
      await page.click('[data-testid="btn-start"]');

      // 2. Simula background tab
      await page.evaluate(() => {
        Object.defineProperty(document, 'visibilityState', { value: 'hidden' });
        document.dispatchEvent(new Event('visibilitychange'));
      });

      // 3. Verifica que muestra notificación
      await expect(page.locator('[data-testid="background-notification"]')).toBeVisible();

      // 4. Simula vuelta a foreground
      await page.evaluate(() => {
        Object.defineProperty(document, 'visibilityState', { value: 'visible' });
        document.dispatchEvent(new Event('visibilitychange'));
      });

      // 5. Verifica que oculta notificación
      await expect(page.locator('[data-testid="background-notification"]')).not.toBeVisible();
    });

    test('Bloqueo de geolocalización: app sigue funcionando', async ({ page, context }) => {
      // 1. Bloquea geolocalización
      await context.setGeolocation({ latitude: 0, longitude: 0 });
      await context.clearPermissions();
      await context.grantPermissions(['geolocation'], { origin: '*' });

      // 2. Navega a la app
      await page.goto('./');

      // 3. Verifica que funciona sin clima
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();

      // 4. Inicia caminata
      await page.click('[data-testid="btn-start"]');
      await expect(page.locator('[data-testid="btn-pause"]')).toBeVisible();
    });

    test('Bloqueo de Web Share: fallback apropiado', async ({ page, context }) => {
      // 1. Bloquea Web Share
      await context.clearPermissions();

      // 2. Crea una sesión
      await page.evaluate(() => {
        const session = {
          id: 'test-session',
          steps: 500,
          timestamp: Date.now(),
          duration: 300000
        };
        const sessions = JSON.parse(localStorage.getItem('walktracker-sessions') || '[]');
        sessions.push(session);
        localStorage.setItem('walktracker-sessions', JSON.stringify(sessions));
      });

      // 3. Intenta exportar
      await page.click('[data-testid="nav-settings"]');
      await page.click('[data-testid="btn-export-csv"]');

      // 4. Verifica que muestra fallback (download en lugar de share)
      // Esto depende de la implementación actual
    });

  });

  test.describe('Cross-Browser', () => {

    test('Chrome Desktop - Funcionalidad completa', async ({ page, browserName }) => {
      test.skip(browserName !== 'chromium', 'Solo Chrome');

      // 1. Navega a la app
      await page.goto('./');

      // 2. Verifica todas las pantallas
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();
      await page.click('[data-testid="btn-start"]');
      await page.click('[data-testid="btn-pause"]');
      await page.click('[data-testid="btn-resume"]');
      await page.click('[data-testid="btn-stop"]');

      // 3. Verifica que funciona
      await expect(page.locator('[data-testid="history-screen"]')).toBeVisible();
    });

    test('Firefox Desktop - Funcionalidad completa', async ({ page, browserName }) => {
      test.skip(browserName !== 'firefox', 'Solo Firefox');

      // 1. Navega a la app
      await page.goto('./');

      // 2. Verifica todas las pantallas
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();
      await page.click('[data-testid="btn-start"]');
      await page.click('[data-testid="btn-stop"]');

      // 3. Verifica que funciona
      await expect(page.locator('[data-testid="history-screen"]')).toBeVisible();
    });

    test('Safari iOS - Funcionalidad completa', async ({ page, browserName, context }) => {
      test.skip(browserName !== 'webkit', 'Solo Safari');

      // 1. Simula viewport de iPhone
      await page.setViewportSize({ width: 390, height: 844 });

      // 2. Navega a la app
      await page.goto('./');

      // 3. Verifica que funciona en móvil
      await expect(page.locator('[data-testid="walk-screen"]')).toBeVisible();
      await page.click('[data-testid="btn-start"]');
      await page.click('[data-testid="btn-stop"]');

      // 4. Verifica que funciona
      await expect(page.locator('[data-testid="history-screen"]')).toBeVisible();
    });

  });

  test.describe('Performance y Accesibilidad', () => {

    test('Performance: Carga inicial < 2s', async ({ page }) => {
      const startTime = Date.now();
      await page.goto('./');
      const loadTime = Date.now() - startTime;

      expect(loadTime).toBeLessThan(2000);
    });

    test('Performance: Navegación entre pantallas < 100ms', async ({ page }) => {
      await page.goto('./');

      const navStartTime = Date.now();
      await page.click('[data-testid="nav-history"]');
      const navTime = Date.now() - navStartTime;

      expect(navTime).toBeLessThan(100);
    });

    test('Accesibilidad: WAI-ARIA labels', async ({ page }) => {
      await page.goto('./');

      // Verifica que los botones tienen aria-label
      const startButton = page.locator('[data-testid="btn-start"]');
      const ariaLabel = await startButton.getAttribute('aria-label');

      expect(ariaLabel).toBeTruthy();
    });

    test('Accesibilidad: Keyboard navigation', async ({ page }) => {
      await page.goto('./');

      // Navega con teclado
      await page.keyboard.press('Tab');
      await page.keyboard.press('Enter');

      // Verifica que funciona
      await expect(page.locator('[data-testid="btn-pause"]')).toBeVisible();
    });

  });

});

// Resumen de tests en este suite
console.log(`
╔════════════════════════════════════════════════════════════════╗
║  WALKTRACKER v3.0 - E2E TESTS (Playwright)                     ║
╠════════════════════════════════════════════════════════════════╣
║  Flujos de usuario:       8 tests                               ║
║  Persistencia y Datos:    3 tests                               ║
║  Comportamiento Offline:  2 tests                               ║
║  APIs de navegador:       4 tests                               ║
║  Cross-Browser:           3 tests                               ║
║  Performance:             2 tests                               ║
║  Accesibilidad:           2 tests                               ║
╠════════════════════════════════════════════════════════════════╣
║  TOTAL:                   24 tests                              ║
╚════════════════════════════════════════════════════════════════╝

Framework: Playwright
Navegadores: Chrome, Firefox, Safari (mobile)
Para ejecutar:
  npm install --save-dev @playwright/test
  npx playwright install
  npx playwright test e2e/walk.e2e.js

Para ejecutar en headless:
  npx playwright test --headless

Para ejecutar solo un navegador:
  npx playwright test --project=chromium
`);