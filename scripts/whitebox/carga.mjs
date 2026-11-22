// PRÁCTICA 11 · Fase 5 · Orquestador de la prueba de carga controlada (k6) con medición de CPU y memoria del servidor.
//
//   node scripts/whitebox/carga.mjs <API> <CLAVE_API_WEB> <carpeta-salida> <ruta-k6.exe> <puerto-backend>
//
// Crea una persona y una cuenta de prueba (zz-prueba-carga…) con 24 lecturas, ejecuta 6 escenarios (lectura y escritura,
// con 1, 5 y 10 usuarios concurrentes, 60 solicitudes cada uno) y guarda por escenario: el resumen de k6, el muestreo
// de CPU/memoria del proceso del servidor y un resumen comparativo. Al final borra todo lo creado.
// Solo se debe usar contra un ambiente propio o autorizado y con datos no sensibles.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [API, KEY, SALIDA, K6, PUERTO] = process.argv.slice(2);
if (!API || !KEY || !SALIDA || !K6 || !PUERTO) {
  console.error('Uso: node carga.mjs <API> <CLAVE_API_WEB> <carpeta-salida> <k6.exe> <puerto-backend>');
  process.exit(2);
}
fs.mkdirSync(SALIDA, { recursive: true });
const aqui = path.dirname(fileURLToPath(import.meta.url));
const AUTH = 'https://identitytoolkit.googleapis.com/v1';
const sufijo = Date.now().toString(36);
const redondea = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d;

async function llamar(metodo, ruta, { token, cuerpo, clave } = {}) {
  const cab = { 'content-type': 'application/json' };
  if (token) cab.Authorization = 'Bearer ' + token;
  if (clave) cab['X-Clave-Dispositivo'] = clave;
  const r = await fetch(API + ruta, { method: metodo, headers: cab, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const t = await r.text();
  let json = null;
  try { json = JSON.parse(t); } catch { /* sin JSON */ }
  return { estado: r.status, json };
}

// PID del servidor: el proceso que escucha en el puerto indicado.
const pidServidor = Number(spawnSync('powershell', ['-NoProfile', '-Command',
  `(Get-NetTCPConnection -LocalPort ${PUERTO} -State Listen | Select-Object -First 1).OwningProcess`], { encoding: 'utf8' }).stdout.trim());
if (!pidServidor) { console.error('No hay un servidor escuchando en el puerto', PUERTO); process.exit(1); }
console.log('Servidor (PID):', pidServidor);

const reg = await (await fetch(`${AUTH}/accounts:signUp?key=${KEY}`, {
  method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ email: `zz-prueba-carga-${sufijo}@uteq.test`, password: 'Clave-Segura-9', returnSecureToken: true }),
})).json();
const token = reg.idToken;
let cuenta;
const resumen = { fecha: new Date().toISOString(), api: API, escenarios: [] };
try {
  const creada = await llamar('POST', '/usuarios', { token, cuerpo: { nombreCompleto: 'Prueba Carga', username: 'zzcarga' + sufijo, grupos: [] } });
  cuenta = creada.json?.id;
  const conexion = await llamar('POST', `/smartwatch/connect?usuarioId=${cuenta}`, { token });
  for (let i = 24; i >= 1; i--) {
    await llamar('POST', `/smartwatch/sync?usuarioId=${cuenta}`, {
      clave: conexion.json.claveDispositivo,
      cuerpo: { pasos: 1000 + i * 100, calorias: 50 + i, sueñoHoras: 7.2, frecuenciaCardiaca: 60 + (i % 25), bateria: 80, timestamp: new Date(Date.now() - i * 900000).toISOString() },
    });
  }
  // Calentamiento (no cuenta): evita medir el arranque en frío del servidor y de las conexiones.
  for (let i = 0; i < 5; i++) await llamar('GET', `/smartwatch/historial?usuarioId=${cuenta}&limite=24`, { token });
  await llamar('PUT', `/metas?usuarioId=${cuenta}`, { token, cuerpo: { metaPasos: 8000 } });

  for (const modo of ['lectura', 'escritura']) {
    for (const usuarios of [1, 5, 10]) {
      const nombre = `${modo}-${usuarios}`;
      const csv = path.join(SALIDA, `cpu-memoria-${nombre}.csv`);
      const resumenK6 = path.join(SALIDA, `k6-${nombre}.json`);
      const muestreo = spawn('powershell', ['-NoProfile', '-File', path.join(aqui, 'muestreo-proceso.ps1'), '-ProcesoId', String(pidServidor), '-Segundos', '90', '-Salida', csv], { stdio: 'ignore' });
      await new Promise((r) => setTimeout(r, 1500));
      const t0 = Date.now();
      const k6 = spawnSync(K6, ['run', '--quiet', '--summary-export', resumenK6, path.join(aqui, 'k6-carga.js')], {
        encoding: 'utf8', env: { ...process.env, API, TOKEN: token, CUENTA: cuenta, MODO: modo, USUARIOS: String(usuarios), SOLICITUDES: '60' },
      });
      const duracion = (Date.now() - t0) / 1000;
      muestreo.kill();
      await new Promise((r) => setTimeout(r, 800));
      const s = JSON.parse(fs.readFileSync(resumenK6, 'utf8')).metrics;
      const d = s.http_req_duration;
      const filas = fs.existsSync(csv) ? fs.readFileSync(csv, 'utf8').trim().split(/\r?\n/).slice(1).map((l) => l.split(',').map(Number)) : [];
      const durante = filas.filter((f) => f[0] <= duracion + 1);
      const cpus = durante.map((f) => f[1]).filter((x) => Number.isFinite(x));
      const mems = durante.map((f) => f[2]).filter((x) => Number.isFinite(x));
      const fallidas = Math.round((s.http_req_failed?.value ?? 0) * s.http_reqs.count);
      const bytesRecibidos = s.data_received.count;
      const bytesEnviados = s.data_sent.count;
      const fila = {
        escenario: nombre, modo, usuariosConcurrentes: usuarios, solicitudes: s.http_reqs.count, exitosas: s.http_reqs.count - fallidas, fallidas,
        duracionSegundos: redondea(duracion, 1), solicitudesPorSegundo: redondea(s.http_reqs.rate, 2),
        latenciaMs: { min: redondea(d.min), promedio: redondea(d.avg), mediana: redondea(d.med), p90: redondea(d['p(90)']), p95: redondea(d['p(95)']), max: redondea(d.max) },
        transferencia: { bytesRecibidos, bytesEnviados, mbpsRecibido: redondea((bytesRecibidos * 8) / (duracion * 1e6), 3), mbpsEnviado: redondea((bytesEnviados * 8) / (duracion * 1e6), 3) },
        servidor: { cpuPromedioPct: cpus.length ? redondea(cpus.reduce((a, b) => a + b, 0) / cpus.length) : null, cpuMaxPct: cpus.length ? redondea(Math.max(...cpus)) : null, memoriaMaxMB: mems.length ? redondea(Math.max(...mems)) : null, muestras: cpus.length },
        k6SalidaEstandar: k6.status,
      };
      resumen.escenarios.push(fila);
      console.log(`${nombre.padEnd(12)} ${String(fila.solicitudes).padStart(3)} sol | ok ${fila.exitosas} / fallan ${fila.fallidas} | prom ${fila.latenciaMs.promedio} ms | p95 ${fila.latenciaMs.p95} ms | ${fila.solicitudesPorSegundo} sol/s | CPU prom ${fila.servidor.cpuPromedioPct}% máx ${fila.servidor.cpuMaxPct}% | mem máx ${fila.servidor.memoriaMaxMB} MB`);
      await new Promise((r) => setTimeout(r, 2500)); // respiro entre escenarios
    }
  }
} finally {
  if (cuenta) await llamar('DELETE', `/usuarios/${cuenta}`, { token });
  await fetch(`${AUTH}/accounts:delete?key=${KEY}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: token }) });
}
fs.writeFileSync(path.join(SALIDA, 'resumen-carga.json'), JSON.stringify(resumen, null, 2));
console.log('\nResumen guardado en', path.join(SALIDA, 'resumen-carga.json'));
