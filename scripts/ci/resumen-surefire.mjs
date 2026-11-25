// Resume los informes de JUnit (surefire) de una carpeta: pruebas, fallos, errores, omitidas y tiempo. Si existe la variable
// GITHUB_STEP_SUMMARY, agrega una tabla en la página de la ejecución de GitHub Actions. Sale con código 1 si hay fallos.
//   node scripts/ci/resumen-surefire.mjs <carpeta surefire-reports> [titulo]
import fs from 'node:fs';
import path from 'node:path';

const [DIR, TITULO = 'Backend (JUnit)'] = process.argv.slice(2);
let t = 0, f = 0, e = 0, s = 0, seg = 0;
const malas = [];
for (const n of fs.readdirSync(DIR).filter((x) => x.endsWith('.xml'))) {
  const xml = fs.readFileSync(path.join(DIR, n), 'utf8');
  const cab = /<testsuite [^>]*>/.exec(xml)?.[0] ?? '';
  const num = (k) => Number(new RegExp(' ' + k + '="([0-9.]+)"').exec(cab)?.[1] ?? 0);
  t += num('tests'); f += num('failures'); e += num('errors'); s += num('skipped'); seg += num('time');
  for (const m of xml.matchAll(/<testcase name="([^"]+)" classname="([^"]+)"[^>]*>\s*<(failure|error)/g)) malas.push(`${m[2]}.${m[1]}`);
}
const linea = `${TITULO}: ${t} pruebas · ${t - f - e - s} aprobadas · ${f} fallos · ${e} errores · ${s} omitidas · ${seg.toFixed(1)} s`;
console.log(linea);
for (const x of malas) console.log('  FALLA:', x);
if (process.env.GITHUB_STEP_SUMMARY) {
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    `### ${TITULO}\n\n| Pruebas | Aprobadas | Fallos | Errores | Omitidas | Tiempo |\n|---|---|---|---|---|---|\n| ${t} | ${t - f - e - s} | ${f} | ${e} | ${s} | ${seg.toFixed(1)} s |\n\n` +
    (malas.length ? malas.map((x) => `- ❌ ${x}`).join('\n') + '\n\n' : ''));
}
process.exit(f + e > 0 ? 1 : 0);
