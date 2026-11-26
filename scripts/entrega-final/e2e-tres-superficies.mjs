// Prueba de extremo a extremo (Parcial 3 de la propuesta): el firmware simulado (reloj) envía lecturas REALES al backend y se comprueba
// que (1) aparecen en el endpoint que consultan el sitio y la vista móvil dentro del intervalo de sondeo (3 s) y (2) el cliente móvil
// real de la app ve exactamente los mismos datos. Crea una cuenta de prueba y la borra al terminar.
//   node scripts/entrega-final/e2e-tres-superficies.mjs <API> <salida.json>     (backend con vitasync.seguridad.activa=false)
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [API, SALIDA] = process.argv.slice(2);
if (!API || !SALIDA) { console.error('Uso: node e2e-tres-superficies.mjs <API> <salida.json>'); process.exit(2); }
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const j = async (m, r, cuerpo, cab = {}) => {
  const x = await fetch(API + r, { method: m, headers: { 'content-type': 'application/json', ...cab }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  const t = await x.text(); let json = null; try { json = JSON.parse(t); } catch { /* */ }
  return { estado: x.status, json };
};
const res = { fecha: new Date().toISOString(), api: API, pasos: {} };
const cuenta = (await j('POST', '/usuarios', { nombreCompleto: 'Prueba E2E', username: 'zze2e' + Date.now().toString(36), grupos: [] })).json?.id;
try {
  const clave = (await j('POST', `/smartwatch/connect?usuarioId=${cuenta}`)).json.claveDispositivo;
  res.pasos['1 cuenta y reloj vinculado'] = 'ok';

  // El reloj (firmware simulado real) sincroniza cada segundo; se mide cuánto tarda en verse en el endpoint de lectura.
  const t0 = Date.now();
  const fw = spawn('dart', ['run', 'bin/vitasync_firmware.dart', '--usuario', cuenta, '--servidor', API, '--clave', clave, '--auto', '1'], { cwd: path.join(raiz, 'vitasync-firmware-sim'), shell: true });
  let salidaFw = ''; fw.stdout.on('data', (d) => (salidaFw += d)); fw.stderr.on('data', (d) => (salidaFw += d));
  let aparecio = null;
  while (Date.now() - t0 < 30000 && !aparecio) {
    await new Promise((r) => setTimeout(r, 300));
    const m = await j('GET', `/smartwatch/metrics?usuarioId=${cuenta}`);
    if (m.estado === 200 && m.json) aparecio = Date.now();
  }
  await new Promise((r) => setTimeout(r, 4500)); // deja que se acumulen varias lecturas
  spawnSync('taskkill', ['/PID', String(fw.pid), '/T', '/F'], { shell: true });
  res.pasos['2 firmware real envía lecturas'] = /sincroniz|enviad|lectura/i.test(salidaFw) ? 'ok' : 'revisar la salida';
  res.arranqueAPrimeraLecturaMs = aparecio ? aparecio - t0 : null;
  res.salidaFirmware = salidaFw.split(/\r?\n/).filter(Boolean).slice(-8);

  // Latencia de propagación: una lectura nueva enviada «como el reloj» se ve en el siguiente sondeo
  const antes = Date.now();
  await j('POST', `/smartwatch/sync?usuarioId=${cuenta}`, { pasos: 4321, calorias: 99, sueñoHoras: 7, frecuenciaCardiaca: 71, bateria: 80, timestamp: new Date().toISOString() }, { 'X-Clave-Dispositivo': clave });
  let visible = null;
  while (Date.now() - antes < 8000) {
    const m = await j('GET', `/smartwatch/metrics?usuarioId=${cuenta}`);
    if (m.json?.pasos === 4321) { visible = Date.now() - antes; break; }
    await new Promise((r) => setTimeout(r, 200));
  }
  res.lecturaNuevaVisibleEnMs = visible;
  res.dentroDelSondeoDe3s = visible !== null && visible <= 3000;

  // El cliente móvil REAL de la app (HttpSaludRepository y HttpMetasRepository) contra el mismo backend
  const app = path.join(raiz, 'vitasync-frontend/flutter-mobile-app');
  const r = spawnSync('flutter', ['test', 'test/e2e', `--dart-define=E2E_API=${API}`, `--dart-define=E2E_CUENTA=${cuenta}`, '--reporter', 'expanded'], { cwd: app, shell: true, encoding: 'utf8' });
  res.pruebaFlutter = { codigo: r.status, medidas: (r.stdout || '').split(/\r?\n/).filter((l) => l.startsWith('E2E|')), resumen: (r.stdout || '').trim().split(/\r?\n/).pop() };
  res.aprobada = r.status === 0 && res.dentroDelSondeoDe3s;
} finally {
  if (cuenta) await j('DELETE', `/usuarios/${cuenta}`);
  fs.writeFileSync(SALIDA, JSON.stringify(res, null, 2));
  console.log(JSON.stringify(res, null, 2));
}
