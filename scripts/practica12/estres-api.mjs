// PRÁCTICA 12 · Fase 3/6 · Orquestador de la prueba de estrés de la API (lectura y escritura) con muestreo de CPU y memoria.
//   node scripts/practica12/estres-api.mjs <API> <CLAVE_API_WEB> <salida> <k6.exe> <puerto> [niveles=1,5,10,20,40] [lectura=80] [escritura=60] [limite=24]
// Crea una persona y una cuenta de prueba (zz-prueba-estres…) con 24 lecturas; por cada nivel de usuarios concurrentes
// ejecuta k6 (lectura y escritura) y guarda: RPS, latencia (prom, P90, P95, máx), % de errores, códigos HTTP y CPU/RAM del
// servidor. Al final borra todo lo creado. Solo contra un ambiente propio y con datos de prueba.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [API, KEY, SALIDA, K6, PUERTO, NIVELES = '1,5,10,20,40', LECT = '80', ESCR = '60', LIMITE = '24'] = process.argv.slice(2);
if (!API || !KEY || !SALIDA || !K6 || !PUERTO) {
  console.error('Uso: node estres-api.mjs <API> <CLAVE> <salida> <k6.exe> <puerto> [niveles] [lectura] [escritura] [limite]');
  process.exit(2);
}
fs.mkdirSync(SALIDA, { recursive: true });
const aqui = path.dirname(fileURLToPath(import.meta.url));
const muestreador = path.join(aqui, '../whitebox/muestreo-proceso.ps1');
const AUTH = 'https://identitytoolkit.googleapis.com/v1';
const sufijo = Date.now().toString(36);
const r1 = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d;
const niveles = NIVELES.split(',').map(Number);

async function llamar(metodo, ruta, { token, cuerpo, clave } = {}) {
  const cab = { 'content-type': 'application/json' };
  if (token) cab.Authorization = 'Bearer ' + token;
  if (clave) cab['X-Clave-Dispositivo'] = clave;
  const r = await fetch(API + ruta, { method: metodo, headers: cab, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const t = await r.text();
  let json = null; try { json = JSON.parse(t); } catch { /* sin JSON */ }
  return { estado: r.status, json };
}

const pid = Number(spawnSync('powershell', ['-NoProfile', '-Command',
  `(Get-NetTCPConnection -LocalPort ${PUERTO} -State Listen | Select-Object -First 1).OwningProcess`], { encoding: 'utf8' }).stdout.trim());
if (!pid) { console.error('No hay servidor en el puerto', PUERTO); process.exit(1); }
console.log('Servidor PID', pid, '| niveles', niveles.join(','));

const reg = await (await fetch(`${AUTH}/accounts:signUp?key=${KEY}`, {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ email: `zz-prueba-estres-${sufijo}@uteq.test`, password: 'Clave-Segura-9', returnSecureToken: true }),
})).json();
const token = reg.idToken;
let cuenta;
const resumen = { fecha: new Date().toISOString(), api: API, niveles, solicitudesLectura: Number(LECT), solicitudesEscritura: Number(ESCR), limiteHistorial: Number(LIMITE), escenarios: [] };
try {
  cuenta = (await llamar('POST', '/usuarios', { token, cuerpo: { nombreCompleto: 'Prueba Estres', username: 'zzestres' + sufijo, grupos: [] } })).json?.id;
  const conexion = await llamar('POST', `/smartwatch/connect?usuarioId=${cuenta}`, { token });
  for (let i = 24; i >= 1; i--) {
    await llamar('POST', `/smartwatch/sync?usuarioId=${cuenta}`, { clave: conexion.json.claveDispositivo,
      cuerpo: { pasos: 1000 + i * 100, calorias: 50 + i, sueñoHoras: 7.2, frecuenciaCardiaca: 60 + (i % 25), bateria: 80, timestamp: new Date(Date.now() - i * 900000).toISOString() } });
  }
  for (let i = 0; i < 5; i++) await llamar('GET', `/smartwatch/historial?usuarioId=${cuenta}&limite=${LIMITE}`, { token }); // calentamiento
  await llamar('PUT', `/metas?usuarioId=${cuenta}`, { token, cuerpo: { metaPasos: 8000 } });

  for (const modo of ['lectura', 'escritura']) {
    for (const usuarios of niveles) {
      const nombre = `${modo}-${usuarios}`;
      const csv = path.join(SALIDA, `cpu-memoria-${nombre}.csv`);
      const jsonK6 = path.join(SALIDA, `k6-${nombre}.json`);
      const muestreo = spawn('powershell', ['-NoProfile', '-File', muestreador, '-ProcesoId', String(pid), '-Segundos', '300', '-Salida', csv], { stdio: 'ignore' });
      await new Promise((r) => setTimeout(r, 1500));
      const t0 = Date.now();
      spawnSync(K6, ['run', '--quiet', '--summary-export', jsonK6, path.join(aqui, 'k6-estres.js')], {
        encoding: 'utf8', env: { ...process.env, API, TOKEN: token, CUENTA: cuenta, MODO: modo, USUARIOS: String(usuarios), SOLICITUDES: modo === 'lectura' ? LECT : ESCR, LIMITE },
      });
      const dur = (Date.now() - t0) / 1000;
      muestreo.kill();
      await new Promise((r) => setTimeout(r, 800));
      const m = JSON.parse(fs.readFileSync(jsonK6, 'utf8')).metrics;
      const d = m.http_req_duration;
      const filas = fs.existsSync(csv) ? fs.readFileSync(csv, 'utf8').trim().split(/\r?\n/).slice(1).map((l) => l.split(',').map(Number)) : [];
      const dentro = filas.filter((f) => f[0] <= dur + 1);
      const cpu = dentro.map((f) => f[1]).filter(Number.isFinite), mem = dentro.map((f) => f[2]).filter(Number.isFinite), hilos = dentro.map((f) => f[3]).filter(Number.isFinite);
      const total = m.http_reqs.count;
      const fallidas = Math.round((m.http_req_failed?.value ?? 0) * total);
      const codigos = {};
      for (const [k, v] of Object.entries(m)) if (k.startsWith('estado_') && v.count) codigos[k.slice(7)] = v.count;
      const fila = {
        escenario: nombre, modo, usuarios, solicitudes: total, exitosas: total - fallidas, fallidas, erroresPct: r1((100 * fallidas) / total, 2),
        duracionSeg: r1(dur), rps: r1(total / dur, 2), codigosHttp: codigos,
        latenciaMs: { min: r1(d.min), promedio: r1(d.avg), p90: r1(d['p(90)']), p95: r1(d['p(95)']), max: r1(d.max) },
        servidor: { cpuProm: cpu.length ? r1(cpu.reduce((a, b) => a + b, 0) / cpu.length) : null, cpuMax: cpu.length ? r1(Math.max(...cpu)) : null,
          memIniMB: mem.length ? mem[0] : null, memMaxMB: mem.length ? Math.max(...mem) : null, memFinMB: mem.length ? mem[mem.length - 1] : null, hilosMax: hilos.length ? Math.max(...hilos) : null },
      };
      resumen.escenarios.push(fila);
      console.log(`${nombre.padEnd(13)} ${String(total).padStart(3)} sol | RPS ${fila.rps} | prom ${fila.latenciaMs.promedio} p90 ${fila.latenciaMs.p90} p95 ${fila.latenciaMs.p95} máx ${fila.latenciaMs.max} ms | err ${fila.erroresPct}% | códigos ${JSON.stringify(codigos)} | CPU ${fila.servidor.cpuProm}/${fila.servidor.cpuMax}% | RAM ${fila.servidor.memIniMB}→${fila.servidor.memMaxMB}→${fila.servidor.memFinMB} MB`);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
} finally {
  if (cuenta) await llamar('DELETE', `/usuarios/${cuenta}`, { token });
  await fetch(`${AUTH}/accounts:delete?key=${KEY}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: token }) });
}
fs.writeFileSync(path.join(SALIDA, 'resumen-estres.json'), JSON.stringify(resumen, null, 2));
console.log('Resumen en', path.join(SALIDA, 'resumen-estres.json'));
