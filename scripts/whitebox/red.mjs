// PRÁCTICA 11 · Fase 5 · Mediciones de conectividad y rendimiento desde el EQUIPO CLIENTE.
//
//   node scripts/whitebox/red.mjs <API> <CLAVE_API_WEB> <salida.json> [gateway]
//
// A. Ping (20 paquetes) a la puerta de enlace, a 8.8.8.8, a los servicios de Google que usa VitaSync y a localhost.
// B. Latencia HTTP: 10 solicitudes consecutivas al mismo endpoint (código, tiempo, tamaño) y un endpoint de referencia
//    que no toca la base de datos, para separar el costo del servidor del de Firestore.
// C. Tasa de transferencia efectiva: Mbps = (bytes × 8) / (segundos × 1 000 000), 3 mediciones de subida y de descarga,
//    contra el backend local (archivos del chat) y contra Internet (servicio público de prueba de velocidad).
//
// Crea una persona y una cuenta de prueba (zz-prueba-red…) en Firebase y las borra al terminar.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { performance } from 'node:perf_hooks';

const [API, KEY, SALIDA, GATEWAY = '192.168.1.1'] = process.argv.slice(2);
if (!API || !KEY || !SALIDA) {
  console.error('Uso: node red.mjs <API> <CLAVE_API_WEB> <salida.json> [gateway]');
  process.exit(2);
}
const AUTH = 'https://identitytoolkit.googleapis.com/v1';
const sufijo = Date.now().toString(36);
const informe = { fecha: new Date().toISOString(), api: API, equipo: { so: process.platform, node: process.version }, ping: {}, http: {}, transferencia: {} };

// ------------------------------------------------------------------ utilidades
const redondea = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d;
function estadisticas(v) {
  const o = [...v].sort((a, b) => a - b);
  const media = v.reduce((a, b) => a + b, 0) / v.length;
  const desv = Math.sqrt(v.reduce((a, b) => a + (b - media) ** 2, 0) / v.length);
  return { n: v.length, min: redondea(o[0]), media: redondea(media), max: redondea(o[o.length - 1]), p95: redondea(o[Math.min(o.length - 1, Math.ceil(0.95 * o.length) - 1)]), desviacion: redondea(desv) };
}

function ping(destino, paquetes = 20) {
  const r = spawnSync('ping', ['-n', String(paquetes), destino], { encoding: 'latin1', timeout: 120000 });
  const texto = r.stdout ?? '';
  const tiempos = [...texto.matchAll(/(?:tiempo|time)\s*([=<])\s*(\d+)\s*ms?/gi)].map((m) => (m[1] === '<' ? 0.5 : Number(m[2])));
  const enviados = paquetes;
  const recibidos = tiempos.length;
  return {
    destino, enviados, recibidos, perdidos: enviados - recibidos, perdidosPorcentaje: redondea((100 * (enviados - recibidos)) / enviados),
    ...(tiempos.length ? { ms: estadisticas(tiempos) } : { ms: null, nota: 'sin respuestas ICMP (puede estar bloqueado por el destino o el firewall)' }),
  };
}

async function persona(correo) {
  const r = await fetch(`${AUTH}/accounts:signUp?key=${KEY}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: correo, password: 'Clave-Segura-9', returnSecureToken: true }),
  });
  const j = await r.json();
  if (!j.idToken) throw new Error('no se pudo crear la persona: ' + JSON.stringify(j));
  return { token: j.idToken };
}

async function pedir(metodo, ruta, { token, cuerpo, clave, binario } = {}) {
  const cab = {};
  if (token) cab.Authorization = 'Bearer ' + token;
  if (clave) cab['X-Clave-Dispositivo'] = clave;
  if (cuerpo !== undefined) cab['content-type'] = 'application/json';
  const t0 = performance.now();
  const r = await fetch(API + ruta, { method: metodo, headers: cab, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const buf = Buffer.from(await r.arrayBuffer());
  const ms = performance.now() - t0;
  let json = null;
  if (!binario) { try { json = JSON.parse(buf.toString('utf8')); } catch { /* no es JSON */ } }
  return { estado: r.status, ms, bytes: buf.length, json };
}

const mbps = (bytes, ms) => redondea((bytes * 8) / ((ms / 1000) * 1_000_000), 2);

// ------------------------------------------------------------------ A. PING
console.log('== A. Ping (20 paquetes por destino)');
const destinos = [
  ['puerta de enlace (router)', GATEWAY],
  ['DNS público de referencia', '8.8.8.8'],
  ['Firestore (firestore.googleapis.com)', 'firestore.googleapis.com'],
  ['Authentication (identitytoolkit.googleapis.com)', 'identitytoolkit.googleapis.com'],
  ['localhost (el backend corre en este mismo equipo)', '127.0.0.1'],
];
for (const [nombre, host] of destinos) {
  const p = ping(host);
  informe.ping[nombre] = p;
  console.log(`  ${nombre.padEnd(52)} ${p.ms ? `min ${p.ms.min} / media ${p.ms.media} / max ${p.ms.max} ms, desv ${p.ms.desviacion}` : 'sin respuesta'} | pérdida ${p.perdidosPorcentaje}%`);
}

// ------------------------------------------------------------------ B y C necesitan una cuenta de prueba
const A = await persona(`zz-prueba-red-${sufijo}@uteq.test`);
let cuenta;
try {
  const creada = await pedir('POST', '/usuarios', { token: A.token, cuerpo: { nombreCompleto: 'Prueba Red', username: 'zzred' + sufijo, grupos: [] } });
  cuenta = creada.json?.id;
  if (!cuenta) throw new Error('no se pudo crear la cuenta de prueba: ' + creada.estado);
  const conexion = await pedir('POST', `/smartwatch/connect?usuarioId=${cuenta}`, { token: A.token });
  const claveReloj = conexion.json?.claveDispositivo;
  for (let i = 24; i >= 1; i--) {
    await pedir('POST', `/smartwatch/sync?usuarioId=${cuenta}`, {
      clave: claveReloj, cuerpo: { pasos: 1000 + i * 100, calorias: 50 + i, sueñoHoras: 7.2, frecuenciaCardiaca: 60 + (i % 25), bateria: 80, timestamp: new Date(Date.now() - i * 900000).toISOString() },
    });
  }

  // -------------------------------------------------------------- B. latencia HTTP
  console.log('\n== B. Latencia HTTP: 10 solicitudes consecutivas al mismo endpoint');
  const rutaDb = `/smartwatch/historial?usuarioId=${cuenta}&limite=24`;
  const filas = [];
  for (let i = 1; i <= 10; i++) {
    const r = await pedir('GET', rutaDb, { token: A.token });
    filas.push({ solicitud: i, codigo: r.estado, ms: redondea(r.ms), bytes: r.bytes });
    console.log(`  ${String(i).padStart(2)}  HTTP ${r.estado}  ${String(redondea(r.ms)).padStart(7)} ms  ${r.bytes} B`);
  }
  const base = [];
  for (let i = 0; i < 10; i++) base.push((await pedir('GET', '/firmware/ultima')).ms);
  informe.http = {
    endpoint: 'GET /api/smartwatch/historial?limite=24 (con token; lee Firestore)',
    solicitudes: filas,
    tiempoMs: estadisticas(filas.map((f) => f.ms)),
    exitosas: `${filas.filter((f) => f.codigo === 200).length}/10`,
    bytesRespuesta: { min: Math.min(...filas.map((f) => f.bytes)), max: Math.max(...filas.map((f) => f.bytes)) },
    referencia: { endpoint: 'GET /api/firmware/ultima (sin token ni base de datos)', tiempoMs: estadisticas(base) },
  };
  console.log(`  → media ${informe.http.tiempoMs.media} ms (min ${informe.http.tiempoMs.min}, max ${informe.http.tiempoMs.max}, p95 ${informe.http.tiempoMs.p95}); referencia sin base de datos: media ${informe.http.referencia.tiempoMs.media} ms`);

  // -------------------------------------------------------------- C. tasa de transferencia
  console.log('\n== C. Tasa de transferencia efectiva (Mbps = bytes × 8 / (s × 1 000 000))');
  const pdf = Buffer.concat([Buffer.from('%PDF-1.4\n'), Buffer.alloc(300 * 1024 - 9, 0x20)]); // 300 KB, el máximo del chat
  const subidas = [];
  const descargas = [];
  const ids = [];
  for (let i = 0; i < 3; i++) {
    const cuerpo = { emisor: 'PACIENTE', nombre: `prueba${i}.pdf`, tipo: 'application/pdf', contenidoBase64: pdf.toString('base64') };
    const tamano = Buffer.byteLength(JSON.stringify(cuerpo));
    const r = await pedir('POST', `/chat/${cuenta}/archivos`, { token: A.token, cuerpo });
    ids.push(r.json?.id);
    subidas.push({ medicion: i + 1, codigo: r.estado, bytes: tamano, segundos: redondea(r.ms / 1000, 3), mbps: mbps(tamano, r.ms) });
  }
  for (let i = 0; i < 3; i++) {
    const r = await pedir('GET', `/chat/${cuenta}/archivos/${ids[i]}`, { token: A.token, binario: true });
    descargas.push({ medicion: i + 1, codigo: r.estado, bytes: r.bytes, segundos: redondea(r.ms / 1000, 3), mbps: mbps(r.bytes, r.ms) });
  }
  informe.transferencia.backendLocal = { subida: subidas, descarga: descargas, nota: 'Cliente y servidor en el mismo equipo (loopback): mide el costo del servidor, no de la red.' };
  console.log('  backend local — subida   :', subidas.map((s) => `${s.mbps} Mbps (${s.segundos}s)`).join(' | '));
  console.log('  backend local — descarga :', descargas.map((s) => `${s.mbps} Mbps (${s.segundos}s)`).join(' | '));

  // Internet real: servicio público de prueba de velocidad (carga mínima: 3 × 5 MB y 3 × 2 MB).
  const wanDescarga = [];
  const wanSubida = [];
  try {
    for (let i = 0; i < 3; i++) {
      const t0 = performance.now();
      const r = await fetch('https://speed.cloudflare.com/__down?bytes=5000000');
      const bytes = (await r.arrayBuffer()).byteLength;
      const ms = performance.now() - t0;
      wanDescarga.push({ medicion: i + 1, codigo: r.status, bytes, segundos: redondea(ms / 1000, 3), mbps: mbps(bytes, ms) });
    }
    const dos = Buffer.alloc(2_000_000, 0x61);
    for (let i = 0; i < 3; i++) {
      const t0 = performance.now();
      const r = await fetch('https://speed.cloudflare.com/__up', { method: 'POST', body: dos });
      await r.arrayBuffer();
      const ms = performance.now() - t0;
      wanSubida.push({ medicion: i + 1, codigo: r.status, bytes: dos.length, segundos: redondea(ms / 1000, 3), mbps: mbps(dos.length, ms) });
    }
  } catch (e) {
    informe.transferencia.internetError = String(e);
  }
  informe.transferencia.internet = { servicio: 'speed.cloudflare.com (prueba de velocidad pública)', descarga: wanDescarga, subida: wanSubida };
  console.log('  Internet — descarga      :', wanDescarga.map((s) => `${s.mbps} Mbps (${s.segundos}s)`).join(' | '));
  console.log('  Internet — subida        :', wanSubida.map((s) => `${s.mbps} Mbps (${s.segundos}s)`).join(' | '));
} finally {
  if (cuenta) await pedir('DELETE', `/usuarios/${cuenta}`, { token: A.token });
  await fetch(`${AUTH}/accounts:delete?key=${KEY}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: A.token }) });
}
fs.writeFileSync(SALIDA, JSON.stringify(informe, null, 2));
console.log('\nGuardado en', SALIDA);
