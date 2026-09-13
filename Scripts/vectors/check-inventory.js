#!/usr/bin/env node
'use strict';
/**
 * Contrasta `WalkTrackerTests/Vectors/inventory.json` con la suite JS (AD-6).
 *
 * Falla —sale ≠ 0 nombrando `fichero:línea`— si:
 *   - un sitio de aserción de los cuatro ficheros no está en el inventario, o está dos veces;
 *   - el inventario cita un sitio que ya no existe, o cuyo código cambió;
 *   - una categoría no trae lo suyo: el vector que lo cubre, la historia del escenario
 *     o el motivo de la exclusión;
 *   - un vector cita como fuente un sitio que el inventario no le atribuye (o al revés);
 *   - los totales declarados no cuadran con los contados;
 *   - las ejecuciones declaradas no cuadran con las que cuenta la propia suite al correr.
 *
 * Uso: node Scripts/vectors/check-inventory.js [--root DIR] [--vectors DIR] [--quiet]
 */

const path = require('path');
const { execFileSync } = require('child_process');
const lib = require('./lib.js');

const args = lib.parseArgs(process.argv.slice(2));
const errors = [];
const fail = (msg) => errors.push(msg);

const inventoryPath = path.join(args.vectors, 'inventory.json');
let inventory;
try {
  inventory = lib.readJSON(inventoryPath);
} catch (e) {
  console.error(`check-inventory: no se puede leer ${inventoryPath}: ${e.message}`);
  process.exit(1);
}

// ── Sitios reales ──────────────────────────────────────────────────────────
const actual = new Map();
for (const file of lib.SUITE_FILES) {
  const { sites, errors: scanErrors } = lib.scanSites(args.root, file);
  scanErrors.forEach(fail);
  sites.forEach(s => actual.set(s.site, s));
}

if (JSON.stringify(inventory.files) !== JSON.stringify(lib.SUITE_FILES)) {
  fail(`inventory.json: "files" debe ser exactamente ${JSON.stringify(lib.SUITE_FILES)}`);
}

// ── Vectores: qué sitios cita cada uno ─────────────────────────────────────
const vectorSources = new Map(); // "función#id" -> Set(sitios)
let vectorFiles;
try {
  vectorFiles = lib.loadVectorFiles(args.vectors);
} catch (e) {
  console.error(`check-inventory: ${e.message}`);
  process.exit(1);
}
for (const { file, data } of vectorFiles) {
  for (const v of data.vectors || []) {
    const ref = `${data.function}#${v.id}`;
    vectorSources.set(ref, new Set(v.sources || []));
    for (const s of v.sources || []) {
      if (!actual.has(s)) fail(`${file}#${v.id}: cita como fuente ${s}, que no es un sitio de aserción`);
    }
  }
}

// ── Cada sitio, exactamente una vez ────────────────────────────────────────
const seen = new Map();
for (const entry of inventory.sites || []) {
  const where = entry.site;
  seen.set(where, (seen.get(where) || 0) + 1);

  const real = actual.get(where);
  if (!real) {
    fail(`${where}: está en el inventario pero no es un sitio de aserción (¿cambió la línea?)`);
    continue;
  }
  if (entry.code !== real.code) {
    fail(`${where}: el código no coincide.\n      inventario: ${entry.code}\n      fichero:    ${real.code}`);
  }

  switch (entry.category) {
    case 'vector': {
      const sources = vectorSources.get(entry.vector);
      if (!sources) fail(`${where}: categoría vector, pero el vector '${entry.vector}' no existe`);
      else if (!sources.has(where)) fail(`${where}: el vector '${entry.vector}' no cita este sitio en sus "sources"`);
      break;
    }
    case 'scenario':
      if (!/^1\.[1-6]$/.test(entry.story || '')) {
        fail(`${where}: escenario sin historia del Epic 1 que lo porte ("story": "1.x")`);
      }
      break;
    case 'excluded':
      if (!lib.EXCLUSION_REASONS[entry.reason]) {
        fail(`${where}: excluido sin motivo admitido (${Object.keys(lib.EXCLUSION_REASONS).join(', ')})`);
      }
      break;
    default:
      fail(`${where}: categoría desconocida '${entry.category}' (vector · scenario · excluded)`);
  }
  if (entry.executions !== undefined && !(Number.isInteger(entry.executions) && entry.executions >= 1)) {
    fail(`${where}: "executions" debe ser un entero ≥ 1`);
  }
}

for (const [where, n] of seen) {
  if (n > 1) fail(`${where}: aparece ${n} veces en el inventario`);
}
for (const where of actual.keys()) {
  if (!seen.has(where)) fail(`${where}: sitio de aserción que falta en el inventario`);
}

// Al revés: toda fuente de un vector está inventariada como ese vector.
const byVector = new Map();
for (const e of inventory.sites || []) if (e.category === 'vector') byVector.set(e.site, e.vector);
for (const [ref, sources] of vectorSources) {
  for (const s of sources) {
    if (actual.has(s) && byVector.get(s) !== ref) {
      fail(`${ref}: cita ${s}, pero el inventario lo atribuye a ${byVector.get(s) ? `'${byVector.get(s)}'` : 'otra categoría'}`);
    }
  }
}

// ── Totales ────────────────────────────────────────────────────────────────
const sites = inventory.sites || [];
const counted = {
  sites: sites.length,
  executions: sites.reduce((a, s) => a + (s.executions || 1), 0),
  vector: sites.filter(s => s.category === 'vector').length,
  scenario: sites.filter(s => s.category === 'scenario').length,
  excluded: sites.filter(s => s.category === 'excluded').length,
};
const declared = inventory.totals || {};
for (const k of Object.keys(counted)) {
  if (declared[k] !== counted[k]) fail(`inventory.json: totals.${k} declara ${declared[k]} y se cuentan ${counted[k]}`);
}

// ── Ejecuciones: las que cuenta la propia suite al correr ──────────────────
// Un sitio dentro de un bucle (session-v3-tests.js:345) se ejecuta N veces. Si el
// inventario lo declara mal, el total de ejecutadas no cuadra con el de la suite.
for (const file of lib.SUITE_FILES) {
  let out;
  try {
    out = execFileSync(process.execPath, [path.join(args.root, file)], { cwd: args.root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    out = String(e.stdout || '');
    fail(`${file}: la suite de referencia no está en verde (exit ${e.status})`);
  }
  // Tres de las cuatro suites no ponen exit ≠ 0 al fallar: se lee su resumen.
  const failedRun = out.match(/❌\s*(\d+)\s+failed/);
  if (failedRun && Number(failedRun[1]) > 0) fail(`${file}: la suite de referencia tiene ${failedRun[1]} aserción(es) en rojo`);
  const m = out.match(/Total:\s*(\d+)|:\s*(\d+)\s+tests/);
  if (!m) {
    fail(`${file}: no se encontró el total de aserciones ejecutadas en su salida`);
    continue;
  }
  const ran = Number(m[1] || m[2]);
  const expected = sites.filter(s => s.site.startsWith(file + ':')).reduce((a, s) => a + (s.executions || 1), 0);
  if (ran !== expected) fail(`${file}: la suite ejecuta ${ran} aserciones y el inventario declara ${expected}`);
}

// ── Veredicto ──────────────────────────────────────────────────────────────
if (errors.length) {
  errors.forEach(e => console.error(`  ✗ ${e}`));
  console.error(`check-inventory: ${errors.length} error(es) en el inventario de AD-6.`);
  process.exit(1);
}
if (!args.quiet) {
  console.log(`check-inventory: ${counted.sites} sitios / ${counted.executions} ejecutadas — ` +
    `${counted.vector} vectores, ${counted.scenario} escenarios, ${counted.excluded} excluidos. Cada sitio, una vez.`);
}
