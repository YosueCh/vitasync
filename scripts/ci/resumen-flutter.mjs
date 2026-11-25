// Resume la salida de «flutter test --reporter json» (un objeto JSON por línea): pruebas, aprobadas, fallidas y tiempo.
// Si existe GITHUB_STEP_SUMMARY, agrega una tabla a la página de la ejecución. Sale con código 1 si hubo fallos.
//   node scripts/ci/resumen-flutter.mjs <archivo.json> [titulo]
import fs from 'node:fs';

const [ARCHIVO, TITULO = 'App móvil (flutter test)'] = process.argv.slice(2);
const nombres = new Map();
let aprobadas = 0, falladas = 0, omitidas = 0, ms = 0;
const malas = [];
for (const l of fs.readFileSync(ARCHIVO, 'utf8').split(/\r?\n/)) {
  let j; try { j = JSON.parse(l); } catch { continue; }
  if (j.type === 'testStart' && j.test && !j.test.name.startsWith('loading ') && j.test.name !== '(setUpAll)' && j.test.name !== '(tearDownAll)') nombres.set(j.test.id, j.test.name);
  if (j.type === 'testDone' && nombres.has(j.testID) && !j.hidden) {
    if (j.skipped) omitidas++;
    else if (j.result === 'success') aprobadas++;
    else { falladas++; malas.push(nombres.get(j.testID)); }
  }
  if (j.type === 'done') ms = j.time;
}
const total = aprobadas + falladas + omitidas;
const linea = `${TITULO}: ${total} pruebas · ${aprobadas} aprobadas · ${falladas} fallidas · ${omitidas} omitidas · ${(ms / 1000).toFixed(1)} s`;
console.log(linea);
for (const x of malas) console.log('  FALLA:', x);
if (process.env.GITHUB_STEP_SUMMARY) {
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `### ${TITULO}\n\n| Pruebas | Aprobadas | Fallidas | Omitidas | Tiempo |\n|---|---|---|---|---|\n| ${total} | ${aprobadas} | ${falladas} | ${omitidas} | ${(ms / 1000).toFixed(1)} s |\n\n` +
    (malas.length ? malas.map((x) => `- ❌ ${x}`).join('\n') + '\n\n' : ''));
}
process.exit(falladas > 0 ? 1 : 0);
