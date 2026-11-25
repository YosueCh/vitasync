// PRÁCTICA 12 · Agrega las repeticiones de la prueba de estrés por versión (ANTES / CACHE / FINAL) y escenario.
//   node scripts/practica12/agregar-estres.mjs <carpeta fase3-api> <salida.json>
// RPS = http_reqs.rate que mide k6 (no incluye el arranque de k6). Promedio ± desviación entre repeticiones.
import fs from 'node:fs';
import path from 'node:path';

const [DIR, SALIDA] = process.argv.slice(2);
const versiones = { ANTES: 'estres-ANTES', CACHE: 'estres-DESPUES', FINAL: 'estres-FINAL' };
const media = (a) => a.reduce((x, y) => x + y, 0) / a.length;
const desv = (a) => (a.length < 2 ? 0 : Math.sqrt(a.reduce((s, x) => s + (x - media(a)) ** 2, 0) / (a.length - 1)));
const r1 = (x) => Math.round(x * 10) / 10;
const sal = { descripcion: 'Promedio entre repeticiones; RPS = http_reqs.rate de k6', versiones: {} };
for (const [nombre, prefijo] of Object.entries(versiones)) {
  const reps = fs.readdirSync(DIR).filter((d) => new RegExp('^' + prefijo + '-r[0-9]+$').test(d));
  if (!reps.length) continue;
  const porEsc = {};
  for (const rep of reps) {
    const resumen = JSON.parse(fs.readFileSync(path.join(DIR, rep, 'resumen-estres.json'), 'utf8'));
    for (const e of resumen.escenarios) {
      const k6 = JSON.parse(fs.readFileSync(path.join(DIR, rep, `k6-${e.escenario}.json`), 'utf8')).metrics;
      (porEsc[e.escenario] ??= []).push({ ...e, rpsK6: k6.http_reqs.rate });
    }
  }
  sal.versiones[nombre] = { repeticiones: reps.length, escenarios: {} };
  for (const [esc, filas] of Object.entries(porEsc)) {
    const codigos = {};
    for (const f of filas) for (const [c, n] of Object.entries(f.codigosHttp)) codigos[c] = (codigos[c] || 0) + n;
    const sol = filas.reduce((a, f) => a + f.solicitudes, 0), fall = filas.reduce((a, f) => a + f.fallidas, 0);
    sal.versiones[nombre].escenarios[esc] = {
      usuarios: filas[0].usuarios, modo: filas[0].modo, solicitudes: sol, fallidas: fall, erroresPct: r1((100 * fall) / sol), codigosHttp: codigos,
      rps: r1(media(filas.map((f) => f.rpsK6))), promMs: r1(media(filas.map((f) => f.latenciaMs.promedio))), promDesv: r1(desv(filas.map((f) => f.latenciaMs.promedio))),
      p90Ms: r1(media(filas.map((f) => f.latenciaMs.p90))), p95Ms: r1(media(filas.map((f) => f.latenciaMs.p95))), maxMs: r1(Math.max(...filas.map((f) => f.latenciaMs.max))),
    };
  }
}
fs.writeFileSync(SALIDA, JSON.stringify(sal, null, 2));
for (const [v, d] of Object.entries(sal.versiones)) {
  console.log(`== ${v} (${d.repeticiones} rep)`);
  for (const [e, x] of Object.entries(d.escenarios)) console.log(`${e.padEnd(13)} RPS ${String(x.rps).padStart(6)} | prom ${String(x.promMs).padStart(7)} ±${x.promDesv} | P90 ${x.p90Ms} P95 ${x.p95Ms} máx ${x.maxMs} | err ${x.erroresPct}% ${JSON.stringify(x.codigosHttp)}`);
}
