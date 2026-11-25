// PRÁCTICA 12 · Fase 2 · Une, por versión (antes/despues) y repetición, lo medido DENTRO de la app (perfil-*.json, resumen de
// fotogramas) con el muestreo de CPU y memoria hecho desde afuera con adb (adb-*.csv, con la hora de cada muestra).
//   node scripts/practica12/agregar-perfil.mjs <carpeta app> <salida.json>
import fs from 'node:fs';
import path from 'node:path';

const [DIR, SALIDA] = process.argv.slice(2);
const media = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN);
const desv = (a) => (a.length < 2 ? 0 : Math.sqrt(a.reduce((s, x) => s + (x - media(a)) ** 2, 0) / (a.length - 1)));
const r1 = (x) => (Number.isFinite(x) ? Math.round(x * 10) / 10 : null);
const utc = (s) => Date.parse(s.endsWith('Z') ? s : s + 'Z'); // el emulador va en UTC

const reps = fs.readdirSync(DIR).filter((f) => /^perfil-(antes|despues)-r\d+\.json$/.test(f)).sort();
const salida = { descripcion: 'CPU = % de un núcleo (top de Android; puede pasar de 100). Memoria = PSS total del proceso (dumpsys meminfo).', repeticiones: {}, porVersion: {} };
const fases = ['F1', 'F2', 'F4', 'F3'];
const claves = { F1: 'f1Inicio', F2: 'f2Inicio', F4: 'f4Inicio', F3: 'f3Inicio' };

for (const archivo of reps) {
  const [, version, rep] = /^perfil-(antes|despues)-(r\d+)\.json$/.exec(archivo);
  const p = JSON.parse(fs.readFileSync(path.join(DIR, archivo), 'utf8'));
  const nav = JSON.parse(fs.readFileSync(path.join(DIR, `navegacion-resumen-${version}-${rep}.json`), 'utf8'));
  const csvRuta = path.join(DIR, `adb-${version}-${rep}.csv`);
  const muestras = fs.existsSync(csvRuta)
    ? fs.readFileSync(csvRuta, 'utf8').trim().split(/\r?\n/).slice(1).map((l) => l.split(',')).map(([t, , c, pss]) => ({ t: Number(t), cpu: Number(c), pss: Number(pss) })).filter((m) => Number.isFinite(m.t))
    : [];
  const ini = { F1: utc(p.f1Inicio), F2: utc(p.f2Inicio), F4: utc(p.f4Inicio), F3: utc(p.f3Inicio) };
  const fin = { F1: ini.F2, F2: ini.F4, F4: ini.F3, F3: muestras.length ? muestras[muestras.length - 1].t : ini.F3 + 25000 };
  const porFase = {};
  for (const f of fases) {
    const m = muestras.filter((x) => x.t >= ini[f] && x.t <= fin[f] && Number.isFinite(x.cpu));
    const cpu = m.map((x) => x.cpu), mem = m.filter((x) => Number.isFinite(x.pss)).map((x) => x.pss);
    porFase[f] = { muestras: m.length, cpuProm: r1(media(cpu)), cpuMax: r1(Math.max(...cpu)), pssIniMB: mem.length ? mem[0] : null, pssMaxMB: mem.length ? Math.max(...mem) : null, pssFinMB: mem.length ? mem[mem.length - 1] : null };
  }
  const todas = muestras.filter((x) => Number.isFinite(x.cpu) && x.t >= ini.F1);
  salida.repeticiones[`${version}-${rep}`] = {
    f1: p['F1 consulta repetida (GET historial x60)'], f2: p['F2 escritura (PUT metas x30)'], f4: p['F4 procesamiento de datos (SQLite)'],
    f3: p[Object.keys(p).find((k) => k.startsWith('F3'))], rssInicialMB: p.rssInicialMB, rssFinalMB: p.rssFinalMB,
    fotogramas: { total: nav.frame_count, construccionPromMs: r1(nav.average_frame_build_time_millis), construccionP90Ms: r1(nav['90th_percentile_frame_build_time_millis']), construccionP99Ms: r1(nav['99th_percentile_frame_build_time_millis']),
      peorMs: r1(nav.worst_frame_build_time_millis), perdidosConstruccion: nav.missed_frame_build_budget_count, rasterPromMs: r1(nav.average_frame_rasterizer_time_millis), perdidosRaster: nav.missed_frame_rasterizer_budget_count, gcJovenes: nav.new_gen_gc_count },
    cpuGlobal: { prom: r1(media(todas.map((x) => x.cpu))), max: r1(Math.max(...todas.map((x) => x.cpu))) },
    pssGlobalMB: { ini: todas.find((x) => Number.isFinite(x.pss))?.pss ?? null, max: Math.max(...todas.map((x) => x.pss).filter(Number.isFinite)), fin: [...todas].reverse().find((x) => Number.isFinite(x.pss))?.pss ?? null },
    porFase,
  };
}
for (const v of ['antes', 'despues']) {
  const rs = Object.entries(salida.repeticiones).filter(([k]) => k.startsWith(v)).map(([, x]) => x);
  if (!rs.length) continue;
  const m = (f) => r1(media(rs.map(f).filter(Number.isFinite)));
  const d = (f) => r1(desv(rs.map(f).filter(Number.isFinite)));
  salida.porVersion[v] = {
    repeticiones: rs.length,
    f1MediaMs: m((x) => x.f1.mediaMs), f1P95Ms: m((x) => x.f1.p95Ms), f1Desv: d((x) => x.f1.mediaMs),
    f2MediaMs: m((x) => x.f2.mediaMs), f2P95Ms: m((x) => x.f2.p95Ms),
    f4Insertar400Ms: m((x) => x.f4.insertar400Ms), f4Insertar400Desv: d((x) => x.f4.insertar400Ms), f4InsertarPorFilaMs: m((x) => x.f4.insertar400Ms / 400),
    f4LeerProcesarMediaMs: m((x) => x.f4['leerYProcesar50 (x40)'].mediaMs),
    f3CambioPestanaMediaMs: m((x) => x.f3.mediaMs),
    construccionPromMs: m((x) => x.fotogramas.construccionPromMs), construccionP90Ms: m((x) => x.fotogramas.construccionP90Ms), perdidosConstruccion: m((x) => x.fotogramas.perdidosConstruccion), fotogramasTotal: m((x) => x.fotogramas.total), rasterPromMs: m((x) => x.fotogramas.rasterPromMs),
    cpuPromGlobal: m((x) => x.cpuGlobal.prom), cpuMaxGlobal: m((x) => x.cpuGlobal.max),
    pssIniMB: m((x) => x.pssGlobalMB.ini), pssMaxMB: m((x) => x.pssGlobalMB.max), pssFinMB: m((x) => x.pssGlobalMB.fin),
    cpuPorFase: Object.fromEntries(fases.map((f) => [f, { prom: m((x) => x.porFase[f].cpuProm), max: m((x) => x.porFase[f].cpuMax) }])),
  };
}
fs.writeFileSync(SALIDA, JSON.stringify(salida, null, 2));
fs.writeFileSync(SALIDA.replace(/\.json$/, '.txt'), JSON.stringify(salida.porVersion, null, 2));
console.log('listo', Object.keys(salida.repeticiones).join(', '));
