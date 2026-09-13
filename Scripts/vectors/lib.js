'use strict';
/**
 * Utilidades compartidas por el arnés de AD-6 del lado JS.
 *
 * Vive fuera de `test/` a propósito: vitest recoge `test/**\/*.js` y esto no es una suite.
 * Sin paquetes: solo `fs` y `path` de node.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');

/** Los cuatro ficheros de la suite JS que reparte AD-6. Ni uno más, ni uno menos. */
const SUITE_FILES = [
  'test/domain-tests.js',
  'test/session-v3-tests.js',
  'test/motivation-tests.js',
  'test/gapestimator-tests.js',
];

/** Las únicas dos familias de divergencia declaradas (AD-6). */
const DIVERGENCE_FAMILIES = {
  // Hora local en lugar de UTC: horas de logro, rachas y semana de la meta.
  localTime: { functions: ['evaluateAchievements', 'checkStreak', 'checkTimeOfDay', 'weeklyProgress'],
               achievements: ['early_bird', 'night_walker', '7_days_streak'] },
  // Categoría por código WMO en lugar de regex sobre texto localizado.
  wmoCategory: { functions: ['evaluateAchievements'],
                 achievements: ['rain_walker'] },
};

/** Motivos de exclusión admitidos. Un excluido sin uno de estos es un olvido, no una decisión. */
const EXCLUSION_REASONS = {
  'v1-laps': 'Agregada v1 de vueltas: domain-model.md §2 la elimina y no hay runtime Swift contra el que correrla.',
  'js-runtime-introspection': 'Introspección del runtime JS (typeof, undefined, Object.isFrozen): en Swift la garantiza el sistema de tipos.',
  'untypable-argument': 'Argumento que el sistema de tipos de Swift no deja construir.',
  'math-random': 'Depende de Math.random: sin RandomPort no hay entrada fija que vectorizar.',
  'quotes-bundle': 'Afirma el contenido de quotes.json, no una conducta del dominio.',
};

/** Argumentos de CLI compartidos: `--root DIR`, `--vectors DIR` y `--catalog FICHERO`, para las sondas rojas. */
function parseArgs(argv) {
  const args = { root: ROOT, vectors: null, catalog: null, quiet: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--root') args.root = path.resolve(argv[++i]);
    else if (argv[i] === '--vectors') args.vectors = path.resolve(argv[++i]);
    else if (argv[i] === '--catalog') args.catalog = path.resolve(argv[++i]);
    else if (argv[i] === '--quiet') args.quiet = true;
    else throw new Error(`argumento desconocido: ${argv[i]}`);
  }
  if (!args.vectors) args.vectors = path.join(args.root, 'WalkTrackerTests', 'Vectors');
  if (!args.catalog) args.catalog = path.join(args.root, 'WalkTracker', 'Resources', 'achievements.json');
  return args;
}

/**
 * Sitios de aserción de un fichero de test: `fichero:línea` de cada llamada a
 * `assert`, `assertThrows` o `assertApprox`, sin contar sus definiciones ni los
 * comentarios. Dos llamadas en una misma línea harían ambiguo `fichero:línea`: se
 * rechazan en vez de contarse mal.
 */
function scanSites(root, relFile) {
  const text = fs.readFileSync(path.join(root, relFile), 'utf8');
  const sites = [];
  const errors = [];
  text.split('\n').forEach((raw, idx) => {
    const trimmed = raw.trim();
    if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')) return;
    const code = raw.replace(/\/\/.*$/, '');
    const calls = [...code.matchAll(/(^|[^\w.$])(function\s+)?(assert|assertThrows|assertApprox)\s*\(/g)]
      .filter(m => !m[2]);
    if (calls.length === 0) return;
    const site = `${relFile}:${idx + 1}`;
    if (calls.length > 1) {
      errors.push(`${site}: ${calls.length} aserciones en una línea; el inventario no puede distinguirlas`);
    }
    sites.push({ site, code: trimmed });
  });
  return { sites, errors };
}

/** Lee un JSON; si no se puede, el error nombra el fichero en vez de un stack sin contexto. */
function readJSON(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    throw new Error(`${file}: ${e.message}`);
  }
}

/** Todos los ficheros de vectores (todo `.json` de la carpeta salvo el inventario). */
function loadVectorFiles(vectorsDir) {
  return fs.readdirSync(vectorsDir)
    .filter(f => f.endsWith('.json') && f !== 'inventory.json')
    .sort()
    .map(f => ({ file: f, data: readJSON(path.join(vectorsDir, f)) }));
}

module.exports = {
  ROOT, SUITE_FILES, DIVERGENCE_FAMILIES, EXCLUSION_REASONS,
  parseArgs, scanSites, readJSON, loadVectorFiles,
};
