# WalkTracker v3.0 — Plan de Implementación de Tests

## 📊 Situación Actual

**COBERTURA ACTUAL:** ~30%

| Capa | Cobertura | Estado |
|------|-----------|--------|
| Dominio (domain.js) | 95% | ✅ Excelente |
| Datos (storage/migration) | 90% | ✅ Excelente |
| UI (index.html) | 0% | ❌ Ninguna |
| E2E/Navegador | 0% | ❌ Ninguna |
| Integration | 0% | ❌ Ninguna |

---

## 🎯 Objetivo

**COBERTURA META:** ~85%

| Capa | Meta | Estado |
|------|------|--------|
| Dominio | 95% | ✅ Completado |
| Datos | 90% | ✅ Completado |
| UI | 80% | ⏳ Pendiente |
| E2E | 70% | ⏳ Pendiente |
| Integration | 75% | ⏳ Pendiente |

---

## 📋 Plan de Implementación

### FASE 1 — Setup de Infraestructura (1 día)

**Objetivo:** Configurar frameworks de testing

**Tareas:**

1. **Instalar dependencias**
   ```bash
   npm install --save-dev vitest @vitest/ui @vitest/coverage-v8 jsdom
   npm install --save-dev @playwright/test
   npx playwright install
   ```

2. **Verificar configuración**
   - `vitest.config.js` ✅
   - `package.json` ✅
   - `test/index-tests.js` ✅
   - `e2e/walk.e2e.js` ✅

3. **Añadir data-testid a index.html**
   - Añadir `data-testid="walk-screen"` a WalkScreen
   - Añadir `data-testid="btn-start"`, `data-testid="btn-pause"`, etc.
   - Añadir `data-testid="history-screen"` a HistoryScreen
   - Añadir `data-testid="session-list"` a HistoryScreen
   - Añadir `data-testid="settings-screen"` a SettingsScreen
   - Añadir `data-testid="nav-walk"`, `data-testid="nav-history"`, etc.

**Tiempo estimado:** 2-4 horas

**Output:**
- Infraestructura de testing configurada
- Scripts de test en `package.json`
- Data-testids añadidos a index.html

---

### FASE 2 — Integration Tests (2-3 días)

**Objetivo:** Probar UI y flujos de usuario con Vitest + jsdom

**Tareas:**

1. **Ejecutar test suite existente**
   ```bash
   npm run test:integration
   ```

2. **Validar tests existentes**
   - WalkScreen: 5 tests ✅
   - HistoryScreen: 3 tests ✅
   - SessionDetail: 2 tests ✅
   - SettingsScreen: 5 tests ✅
   - Persistence: 2 tests ✅

3. **Ajustar tests si es necesario**
   - Verificar que data-testids coinciden con index.html
   - Ajustar selectores si es necesario
   - Corregir mocks si es necesario

4. **Ejecutar tests de unitarios**
   ```bash
   npm run test:unit
   ```

5. **Generar reporte de cobertura**
   ```bash
   npm run test:coverage
   ```

**Tiempo estimado:** 1-2 días (incluye ajustes)

**Output:**
- Integration tests ejecutándose
- Cobertura de UI: ~60-70%
- Reporte de cobertura generado

---

### FASE 3 — E2E Tests (2-3 días)

**Objetivo:** Probar flujos de usuario en navegadores reales con Playwright

**Tareas:**

1. **Instalar Playwright**
   ```bash
   npm install --save-dev @playwright/test
   npx playwright install
   ```

2. **Añadir data-testids faltantes a index.html**
   - Verificar que todos los data-testids están presentes
   - Añadir los que faltan

3. **Ejecutar test suite E2E en headless**
   ```bash
   npm run test:e2e
   ```

4. **Validar tests E2E**
   - Flujos de usuario: 8 tests
   - Persistencia y Datos: 3 tests
   - Comportamiento Offline: 2 tests
   - APIs de navegador: 4 tests
   - Cross-browser: 3 tests
   - Performance: 2 tests
   - Accesibilidad: 2 tests

5. **Ajustar tests si es necesario**
   - Verificar que los selectores funcionan en navegadores reales
   - Ajustar timeouts si es necesario
   - Corregir comportamiento específico del navegador

6. **Ejecutar tests en modo headed (opcional)**
   ```bash
   npm run test:e2e:headed
   ```

7. **Ejecutar tests en navegador específico**
   ```bash
   npm run test:e2e:chromium
   npm run test:e2e:firefox
   npm run test:e2e:webkit
   ```

**Tiempo estimado:** 2-3 días

**Output:**
- E2E tests ejecutándose en 3 navegadores
- Cobertura E2E: ~70%
- Videos/screenshots de fallos (si los hay)

---

### FASE 4 — CI/CD Integration (1 día)

**Objetivo:** Integrar tests en GitHub Actions

**Tareas:**

1. **Crear workflow de GitHub Actions**
   - Ejecutar tests de unitarios en cada PR
   - Ejecutar tests de integración en cada PR
   - Ejecutar tests E2E en cada PR (opcional, en push a main)
   - Generar reportes de cobertura
   - Subir reportes como artifacts

2. **Crear archivo `.github/workflows/tests.yml`**

```yaml
name: Tests

on:
  pull_request:
  push:
    branches: [main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm run test:unit

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm run test:integration

  e2e-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npm run test:e2e
```

3. **Verificar ejecución en PR**
   - Crear PR de prueba
   - Verificar que se ejecutan todos los tests
   - Verificar que se generan reportes

**Tiempo estimado:** 4-6 horas

**Output:**
- Workflow de CI/CD configurado
- Tests ejecutándose automáticamente en PRs
- Reportes de cobertura disponibles

---

### FASE 5 — Documentation y Handoff (0.5 día)

**Objetivo:** Documentar tests y preparar para el equipo

**Tareas:**

1. **Actualizar README.md**
   - Añadir sección "Testing"
   - Explicar cómo ejecutar tests
   - Explicar frameworks utilizados

2. **Crear guía de testing**
   - Cómo añadir nuevos tests
   - Cómo ejecutar tests localmente
   - Cómo interpretar reportes de cobertura

3. **Presentar al equipo**
   - Explicar cobertura actual
   - Explicar tests añadidos
   - Explicar cómo mantener tests

**Tiempo estimado:** 2-4 horas

**Output:**
- README.md actualizado
- Guía de testing creada
- Presentación al equipo

---

## 📈 Métricas de Éxito

### Cobertura

| Métrica | Antes | Después | Meta |
|---------|-------|---------|------|
| Cobertura total | 30% | 85% | 85% |
| Cobertura UI | 0% | 80% | 80% |
| Cobertura E2E | 0% | 70% | 70% |
| Tests unitarios | 434 | 434 | 434 |
| Tests integración | 0 | 17 | 15+ |
| Tests E2E | 0 | 24 | 20+ |

### Calidad

| Métrica | Antes | Después | Meta |
|---------|-------|---------|------|
| Bugs detectados por tests | 0 | ? | ? |
| Regresiones detectadas | 0 | ? | ? |
| Tiempo de ejecución | 0s | < 10s | < 10s |
| Tiempo de E2E | 0s | < 60s | < 60s |

---

## 🚀 Comandos Rápidos

```bash
# Ejecutar todos los tests
npm run test:all

# Ejecutar solo tests unitarios
npm run test:unit

# Ejecutar solo tests de integración
npm run test:integration

# Ejecutar solo tests E2E
npm run test:e2e

# Ejecutar tests con UI
npm run test:ui

# Ejecutar tests con reporte de cobertura
npm run test:coverage

# Ejecutar E2E en modo headed
npm run test:e2e:headed

# Ejecutar E2E en navegador específico
npm run test:e2e:chromium
npm run test:e2e:firefox
npm run test:e2e:webkit
```

---

## 📋 Checklist de Implementación

### FASE 1 — Setup
- [ ] Instalar dependencias
- [ ] Verificar vitest.config.js
- [ ] Verificar package.json
- [ ] Añadir data-testids a index.html

### FASE 2 — Integration
- [ ] Ejecutar test suite existente
- [ ] Validar tests existentes
- [ ] Ajustar tests si es necesario
- [ ] Ejecutar tests unitarios
- [ ] Generar reporte de cobertura

### FASE 3 — E2E
- [ ] Instalar Playwright
- [ ] Añadir data-testids faltantes
- [ ] Ejecutar test suite E2E
- [ ] Validar tests E2E
- [ ] Ajustar tests si es necesario
- [ ] Ejecutar tests en modo headed
- [ ] Ejecutar tests en navegadores específicos

### FASE 4 — CI/CD
- [ ] Crear workflow de GitHub Actions
- [ ] Verificar ejecución en PR

### FASE 5 — Documentation
- [ ] Actualizar README.md
- [ ] Crear guía de testing
- [ ] Presentar al equipo

---

## ⏰ Timeline

| Fase | Días | Start Date | End Date |
|------|------|------------|----------|
| FASE 1 — Setup | 1 | TBC | TBC |
| FASE 2 — Integration | 2-3 | TBC | TBC |
| FASE 3 — E2E | 2-3 | TBC | TBC |
| FASE 4 — CI/CD | 1 | TBC | TBC |
| FASE 5 — Documentation | 0.5 | TBC | TBC |
| **TOTAL** | **6.5-8.5** | **TBC** | **TBC** |

---

## 🎓 Conclusión

**COBERTURA ACTUAL:** ~30%
**COBERTURA META:** ~85%
**INCREMENTO:** ~55 puntos porcentuales
**ESFUERZO:** 6.5-8.5 días
**RIESGO:** Bajo (tests bien diseñados)

**RECOMENDACIÓN:**
Implementar FASE 1, 2 y 3 ANTES de liberar v3.0. Es crítico probar la UI y los flujos de usuario.

FASE 4 y 5 pueden ser posteriores, pero FASE 4 es recomendable para asegurar calidad en producción.

---

**Creado:** 2026-07-07
**Versión:** v3.0
**Autor:** Test Architect (BMAD)