#!/usr/bin/env node
'use strict';
/**
 * Runner JS de los vectores de AD-6: ejecuta la referencia v3 (`domain.js`,
 * `motivation.js`, `climate.js`) contra `WalkTrackerTests/Vectors/*.json`.
 *
 * Reglas (matriz de la historia 8.7):
 *   - vector no divergente que pasa            → ok
 *   - vector no divergente que falla           → FALLO, nombrando fichero y caso
 *   - vector divergente que falla              → divergencia esperada (sale 0)
 *   - vector divergente que PASA               → FALLO: la divergencia ya no existe
 * Solo hay dos familias de divergencia: `localTime` y `wmoCategory`.
 *
 * Además valida el formato de los ficheros, que los 14 logros tengan un vector que
 * desbloquea y otro que no, y que `WalkTracker/Resources/achievements.json` conserve
 * el contenido del catálogo de la referencia.
 *
 * Normaliza `Infinity`/`NaN` de la salida a `null`: en Swift una métrica ausente es
 * `nil` (AD-4), y el vector lleva el valor de Swift.
 *
 * Uso: node Scripts/vectors/run-js.js [--root DIR] [--vectors DIR] [--catalog FICHERO] [--quiet]
 *
 * Un vector divergente fuera de `evaluateAchievements` lleva además `expectedJs`: el
 * valor exacto que da domain.js. Swift lo ignora.
 */

const path = require('path');
const lib = require('./lib.js');

const args = lib.parseArgs(process.argv.slice(2));
const { Domain } = require(path.join(args.root, 'domain.js'));
const Motivation = require(path.join(args.root, 'motivation.js'));
const Climate = require(path.join(args.root, 'climate.js'));

const CATALOG_KEYS = Motivation.getAchievementsCatalog().map(a => a.key);
const TIME_FUNCTIONS = new Set(['evaluateAchievements', 'checkStreak', 'checkTimeOfDay', 'weeklyProgress']);

// ── Entrada neutral → llamada a la referencia ─────────────────────────────
// Los vectores no saben de JS. Esta tabla es la única traducción, y el lado Swift
// tiene la suya en `DomainVectorTests.swift`.

/** El texto que la v3 guardaba en `weather.condition` sale del código WMO, con la función de la propia referencia. */
function toV3Session(s) {
  const out = { startedAt: s.startedAt, distanceM: s.distanceM };
  if ('paceSecPerKm' in s) out.paceSecPerKm = s.paceSecPerKm;
  if (s.weather) out.weather = { condition: Climate.wmoToSpanish(s.weather.wmoCode), tempC: s.weather.tempC };
  return out;
}

const ADAPTERS = {
  elapsedS: (i) => Domain.elapsedS(i.startedAtMs, i.totalPausesMs, i.nowMs, i.pausedAtMs),
  pace: (i) => Domain.pace(i.durationS, i.pausesS, i.distanceM),
  v3distance: (i) => Domain.v3distance(i.stepsMeasured, i.stepsEstimated, i.strideM),
  estimateSteps: (i) => Domain.estimateSteps(i.cadenceSpm, i.gapS),
  calculateCadence: (i) => Domain.calculateCadence(i.stepsMeasured, i.activeSeconds),
  selectQuote: (i) => Motivation.selectQuote(i.quotes, i.recentIds),
  updateRecentIds: (i) => Motivation.updateRecentIds(i.recentIds, i.selectedId),
  achievementCatalog: () => ({ keys: CATALOG_KEYS }),
  evaluateAchievements: (i) => ({
    newlyUnlocked: Motivation.evaluateAchievements(
      toV3Session(i.session),
      i.history.map(toV3Session),
      i.alreadyUnlocked.map(key => ({ key, unlockedAt: '2026-01-01T00:00:00Z' })),
    ).map(a => a.key).sort(),
  }),
  checkStreak: (i) => Motivation.checkStreak(i.startedAts.map(startedAt => ({ startedAt })), i.days),
  checkTimeOfDay: (i) => Motivation.checkTimeOfDay({ startedAt: i.startedAt }, i.hourStart, i.hourEnd),
  weeklyProgress: (i) => Motivation.getWeeklyProgress(i.sessions, i.weeklyGoalKm, i.now),
};

// ── Valores ───────────────────────────────────────────────────────────────

/** JSON no tiene NaN ni Infinity: en la entrada se escriben como cadena. */
function decodeInput(v) {
  if (v === 'NaN') return NaN;
  if (v === 'Infinity') return Infinity;
  if (v === '-Infinity') return -Infinity;
  if (Array.isArray(v)) return v.map(decodeInput);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, decodeInput(x)]));
  return v;
}

function normalizeOutput(v) {
  if (typeof v === 'number' && !Number.isFinite(v)) return null;
  if (v === undefined) return null;
  if (Array.isArray(v)) return v.map(normalizeOutput);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, normalizeOutput(x)]));
  return v;
}

/**
 * Misma semántica que `VectorMatcher` en Swift: números con tolerancia si la hay,
 * arrays elemento a elemento, objetos por las claves que el vector fija.
 */
function matches(expected, actual, tol) {
  if (expected === null) return actual === null;
  if (typeof expected === 'number') {
    return typeof actual === 'number' && (tol !== undefined ? Math.abs(expected - actual) <= tol : expected === actual);
  }
  if (Array.isArray(expected)) {
    return Array.isArray(actual) && actual.length === expected.length && expected.every((e, i) => matches(e, actual[i], tol));
  }
  if (typeof expected === 'object') {
    return actual !== null && typeof actual === 'object' && !Array.isArray(actual) &&
      Object.keys(expected).every(k => Object.prototype.hasOwnProperty.call(actual, k) && matches(expected[k], actual[k], tol));
  }
  return expected === actual;
}

const show = (v) => JSON.stringify(v);

function validTimeZone(tz) {
  try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return true; } catch { return false; }
}

// ── Ejecución ─────────────────────────────────────────────────────────────
const failures = [];
const divergences = [];
let passed = 0;
let total = 0;
const coverage = Object.fromEntries(CATALOG_KEYS.map(k => [k, { true: [], false: [] }]));

let vectorFiles;
try {
  vectorFiles = lib.loadVectorFiles(args.vectors);
} catch (e) {
  console.error(`run-js: ${e.message}`);
  process.exit(1);
}
for (const { file, data } of vectorFiles) {
  const fn = data.function;
  const formatError = (msg) => failures.push(`${file}: ${msg}`);

  if (data.schemaVersion !== 1) { formatError(`schemaVersion ${data.schemaVersion} no soportada (1)`); continue; }
  if (`${fn}.json` !== file) { formatError(`el fichero debe llamarse como su función ('${fn}.json')`); continue; }
  const adapter = ADAPTERS[fn];
  if (!adapter) { formatError(`función '${fn}' sin traducción a la referencia en run-js.js`); continue; }
  if (!Array.isArray(data.vectors) || data.vectors.length === 0) { formatError('sin vectores'); continue; }

  const ids = new Set();
  for (const v of data.vectors) {
    total++;
    const where = `${file}#${v.id}`;
    const bad = (msg) => failures.push(`${where}: ${msg}`);

    // Formato
    if (typeof v.id !== 'string' || !/^[a-z0-9][a-z0-9-]*$/.test(v.id)) { bad('id vacío o con caracteres fuera de [a-z0-9-]'); continue; }
    if (ids.has(v.id)) { bad('id repetido'); continue; }
    ids.add(v.id);
    if (!Array.isArray(v.sources)) { bad('"sources" debe ser un array (vacío si el vector es de autoría propia)'); continue; }
    if (('expected' in v) === ('throws' in v)) { bad('lleva "expected" o "throws", exactamente uno'); continue; }
    if ('throws' in v && typeof (v.throws || {}).field !== 'string') { bad('"throws.field" debe nombrar el campo inválido'); continue; }
    if ('tolerance' in v && !(typeof v.tolerance === 'number' && v.tolerance >= 0)) { bad('"tolerance" debe ser un número ≥ 0'); continue; }
    if (TIME_FUNCTIONS.has(fn) && !v.timeZone) { bad('vector de hora sin "timeZone"'); continue; }
    if (v.timeZone !== undefined && !validTimeZone(v.timeZone)) { bad(`timeZone '${v.timeZone}' no es un identificador IANA`); continue; }
    const family = v.divergence === undefined ? null : lib.DIVERGENCE_FAMILIES[v.divergence];
    if (v.divergence !== undefined) {
      if (!family) { bad(`divergencia '${v.divergence}' no declarada (solo ${Object.keys(lib.DIVERGENCE_FAMILIES).join(' · ')})`); continue; }
      if (!family.functions.includes(fn)) { bad(`la familia '${v.divergence}' no aplica a ${fn}`); continue; }
      if (v.divergence === 'localTime' && v.timeZone === 'UTC') { bad('divergencia de hora local en UTC: ahí ambos runtimes coinciden'); continue; }
      if (fn !== 'evaluateAchievements' && !('expectedJs' in v)) {
        bad(`divergente (${v.divergence}) sin "expectedJs": fuera de evaluateAchievements hay que fijar el valor exacto que da domain.js`);
        continue;
      }
    }
    if (!family && 'expectedJs' in v) { bad('"expectedJs" solo tiene sentido en un vector divergente'); continue; }
    if (fn === 'evaluateAchievements' && 'expected' in v) {
      const keys = v.expected.newlyUnlocked || [];
      const unknown = keys.filter(k => !CATALOG_KEYS.includes(k));
      if (unknown.length) { bad(`claves de logro desconocidas: ${unknown.join(', ')}`); continue; }
      if (show(keys) !== show([...keys].sort())) { bad('"newlyUnlocked" debe ir ordenado'); continue; }
    }

    // Cobertura declarada: coherente con lo esperado
    if (v.covers !== undefined) {
      let coherent = true;
      for (const [key, unlocks] of Object.entries(v.covers)) {
        if (!coverage[key]) { bad(`"covers" nombra un logro desconocido: ${key}`); coherent = false; continue; }
        let actualUnlocks;
        if (fn === 'evaluateAchievements') actualUnlocks = v.expected.newlyUnlocked.includes(key);
        else if (fn === 'weeklyProgress' && key === 'weekly_goal') actualUnlocks = v.expected.isComplete;
        else { bad(`"covers" de ${key} no se puede comprobar en ${fn}`); coherent = false; continue; }
        if (actualUnlocks !== unlocks) { bad(`"covers" dice ${key}=${unlocks} y "expected" dice lo contrario`); coherent = false; continue; }
        coverage[key][unlocks].push(where);
      }
      if (!coherent) continue;
    }

    // Ejecución contra la referencia
    let actual;
    let thrown = null;
    try {
      actual = normalizeOutput(adapter(decodeInput(v.input || {})));
    } catch (e) {
      thrown = e;
    }

    let ok;
    let got;
    if ('throws' in v) {
      ok = thrown !== null && (!v.throws.js || thrown.constructor.name === v.throws.js);
      got = thrown ? `${thrown.constructor.name}: ${thrown.message}` : `sin error, devolvió ${show(actual)}`;
    } else {
      ok = thrown === null && matches(v.expected, actual, v.tolerance);
      got = thrown ? `${thrown.constructor.name}: ${thrown.message}` : show(actual);
    }
    const want = 'throws' in v ? `lanza (${v.throws.js || 'error'}) por '${v.throws.field}'` : show(v.expected);

    if (!family) {
      if (ok) passed++;
      else bad(`esperado ${want}, domain.js da ${got}`);
      continue;
    }

    if (ok) {
      bad(`marcado divergente (${v.divergence}) pero domain.js lo pasa: la divergencia ya no existe, retírala de la tabla`);
      continue;
    }
    // Un divergente solo puede fallar por su familia. En logros, la diferencia tiene que
    // limitarse a los logros de esa familia: si falla por otro, es un fallo de verdad.
    if (fn === 'evaluateAchievements' && thrown === null) {
      const exp = new Set(v.expected.newlyUnlocked);
      const act = new Set(actual.newlyUnlocked);
      const diff = [...new Set([...exp, ...act])].filter(k => exp.has(k) !== act.has(k));
      const foreign = diff.filter(k => !family.achievements.includes(k));
      if (foreign.length) {
        bad(`divergente (${v.divergence}), pero domain.js también difiere en ${foreign.join(', ')}, que no son de esa familia`);
        continue;
      }
    } else if (thrown !== null) {
      bad(`divergente (${v.divergence}), pero domain.js lanza: ${got}`);
      continue;
    } else if (!(matches(v.expectedJs, actual) && matches(actual, v.expectedJs))) {
      // Sin esto, cualquier error del vector (un goalKm mal escrito) se escondería
      // detrás de la divergencia: domain.js tiene que dar EXACTAMENTE lo que el vector dice.
      bad(`divergente (${v.divergence}), pero domain.js da ${got} y "expectedJs" dice ${show(v.expectedJs)}`);
      continue;
    }
    divergences.push(`${where} [${v.divergence}]: domain.js da ${got}; el vector lleva ${want}`);
  }
}

// ── Los 14 logros, cada uno con un vector que desbloquea y otro que no ────
for (const [key, c] of Object.entries(coverage)) {
  if (c.true.length === 0) failures.push(`cobertura: ningún vector desbloquea '${key}' ("covers": { "${key}": true })`);
  if (c.false.length === 0) failures.push(`cobertura: ningún vector comprueba que '${key}' NO se desbloquea ("covers": { "${key}": false })`);
}

// ── achievements.json conserva el contenido del catálogo de la referencia ─
// Es exactamente el incidente de AD-5: un catálogo reteclado a mano. Las claves van
// en el orden de achievements.md; las descripciones se comparan sin espacios porque
// achievements.md escribe "30 °C" y la v3 "30°C".
try {
  const bundled = lib.readJSON(args.catalog);
  const ref = Motivation.getAchievementsCatalog();
  const list = bundled.achievements || [];
  if (show(list.map(a => a.key)) !== show(ref.map(a => a.key))) {
    failures.push(`achievements.json: las claves ${show(list.map(a => a.key))} no son las de la referencia ${show(ref.map(a => a.key))}`);
  } else {
    const squash = (s) => String(s).replace(/\s+/g, '');
    ref.forEach((r, i) => {
      const b = list[i];
      if (b.name !== r.name) failures.push(`achievements.json#${r.key}: name '${b.name}' ≠ referencia '${r.name}'`);
      if (b.icon !== r.icon) failures.push(`achievements.json#${r.key}: icon '${b.icon}' ≠ referencia '${r.icon}'`);
      if (squash(b.description) !== squash(r.desc)) failures.push(`achievements.json#${r.key}: description '${b.description}' ≠ referencia '${r.desc}'`);
    });
  }
} catch (e) {
  failures.push(`achievements.json: no se puede leer (${e.message})`);
}

// ── Veredicto ─────────────────────────────────────────────────────────────
if (!args.quiet || failures.length) {
  if (divergences.length) {
    console.log('Divergencias esperadas (domain.js falla a propósito; el vector lleva el valor de Swift):');
    divergences.forEach(d => console.log(`  ≈ ${d}`));
  }
}
if (failures.length) {
  console.error('Fallos:');
  failures.forEach(f => console.error(`  ✗ ${f}`));
  console.error(`run-js: ${failures.length} fallo(s) en ${total} vectores.`);
  process.exit(1);
}
const byFamily = {};
divergences.forEach(d => { const f = d.match(/\[(\w+)\]/)[1]; byFamily[f] = (byFamily[f] || 0) + 1; });
console.log(`run-js: ${total} vectores — ${passed} pasan en domain.js, ${divergences.length} divergencias esperadas ` +
  `(${Object.entries(byFamily).map(([f, n]) => `${f}: ${n}`).join(', ') || 'ninguna'}). Los 14 logros cubiertos en ambos sentidos.`);
