// Genera el bundle web local (webDir de Capacitor) copiando los assets de la web v3.
// La web es estática y vive en la raíz del repo; Capacitor exige un subdirectorio
// como webDir, así que copiamos SOLO los assets de runtime a www/ (AD-C7 bundle local).
// Fuente de verdad de la lista: SHELL en sw.js.
import { cpSync, rmSync, mkdirSync } from 'node:fs';

const FILES = [
  'index.html',
  'domain.js',
  'storage.js',
  'migration.js',
  'climate.js',
  'motivation.js',
  'runtime.js',
  'quotes.json',
  'manifest.webmanifest',
  'sw.js',
];

const DIRS = ['icons', 'adapters'];

const OUT = 'www';

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });

for (const f of FILES) {
  cpSync(f, `${OUT}/${f}`);
}
cpSync('walktracker-kit/dist/plugin.js', `${OUT}/plugin.js`);
for (const d of DIRS) {
  cpSync(d, `${OUT}/${d}`, { recursive: true });
}

console.log(`[build-web] bundle generado en ${OUT}/ (${FILES.length} archivos, ${DIRS.length} directorios)`);
