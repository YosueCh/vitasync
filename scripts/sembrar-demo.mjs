// Crea (o reutiliza) una cuenta DEMO con datos, para poder probar la app y el sitio viendo información:
// la persona, su cuenta VitaSync, el reloj vinculado con lecturas de las últimas horas, contactos y metas.
//
//   node scripts/sembrar-demo.mjs <API> <CLAVE_API_WEB> <correo> <contraseña> [AUTH_BASE]
//   ej.: node scripts/sembrar-demo.mjs http://localhost:8084/api <clave> demo@ejemplo.test "MiClave123"
//
// Es idempotente en lo posible: si la persona ya existe inicia sesión; si ya tiene cuenta VitaSync la reutiliza.
// La contraseña NO se guarda en ningún archivo: se pasa por la línea de comandos.
const [API, KEY, CORREO, CLAVE, AUTH = 'https://identitytoolkit.googleapis.com'] = process.argv.slice(2);
if (!API || !KEY || !CORREO || !CLAVE) {
  console.error('Uso: node scripts/sembrar-demo.mjs <API> <CLAVE_API_WEB> <correo> <contraseña> [AUTH_BASE]');
  process.exit(2);
}

async function identidad(operacion) {
  const r = await fetch(`${AUTH}/v1/accounts:${operacion}?key=${KEY}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: CORREO, password: CLAVE, returnSecureToken: true }),
  });
  return r.json();
}

async function llamar(metodo, ruta, token, cuerpo, extra = {}) {
  const r = await fetch(API + ruta, {
    method: metodo,
    headers: { 'content-type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}), ...extra },
    body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
  });
  const t = await r.text();
  let json = null;
  try { json = JSON.parse(t); } catch { /* sin cuerpo */ }
  return { estado: r.status, json };
}

const paso = (m) => console.log('•', m);

// 1) la persona
let sesion = await identidad('signUp');
if (!sesion.idToken) {
  sesion = await identidad('signInWithPassword');
  if (!sesion.idToken) { console.error('No se pudo crear ni iniciar sesión:', JSON.stringify(sesion.error ?? sesion)); process.exit(1); }
  paso(`la persona ${CORREO} ya existía: se inició sesión`);
} else {
  paso(`persona creada: ${CORREO}`);
}
const token = sesion.idToken;

// 2) su cuenta VitaSync
let cuentas = await llamar('GET', '/usuarios', token);
if (cuentas.estado !== 200) { console.error('El backend respondió', cuentas.estado, JSON.stringify(cuentas.json)); process.exit(1); }
let cuenta = cuentas.json[0];
if (!cuenta) {
  const c = await llamar('POST', '/usuarios', token, { nombreCompleto: 'Cuenta Demo', username: 'demo' + Date.now().toString(36), grupos: [] });
  if (c.estado !== 200) { console.error('No se pudo crear la cuenta VitaSync:', c.estado, JSON.stringify(c.json)); process.exit(1); }
  cuenta = c.json;
  paso(`cuenta VitaSync creada: ${cuenta.nombreCompleto}`);
} else {
  paso(`cuenta VitaSync existente: ${cuenta.nombreCompleto}`);
}
const id = cuenta.id;

// 3) el reloj: se vincula y se mandan lecturas de las últimas horas con su clave de dispositivo
const conexion = await llamar('POST', `/smartwatch/connect?usuarioId=${id}`, token);
const claveReloj = conexion.json?.claveDispositivo;
if (!claveReloj) { console.error('No se pudo vincular el reloj:', conexion.estado, JSON.stringify(conexion.json)); process.exit(1); }
paso('reloj vinculado (la clave de dispositivo no se guarda en ningún archivo)');
const ahora = Date.now();
const LECTURAS = 24;
let pasos = 800;
for (let i = LECTURAS; i >= 1; i--) {
  pasos += 150 + Math.round(Math.abs(Math.sin(i)) * 260);
  const hora = new Date(ahora - i * 15 * 60 * 1000); // una cada 15 minutos
  const r = await llamar('POST', `/smartwatch/sync?usuarioId=${id}`, null, {
    pasos,
    calorias: Math.round(pasos * 0.045),
    sueñoHoras: 7.4,
    frecuenciaCardiaca: 62 + Math.round(Math.abs(Math.cos(i)) * 26),
    bateria: Math.max(20, 88 - Math.round(i * 1.2)),
    timestamp: hora.toISOString(),
  }, { 'X-Clave-Dispositivo': claveReloj });
  if (r.estado !== 200) { console.error('Falló una lectura:', r.estado, JSON.stringify(r.json)); process.exit(1); }
}
paso(`${LECTURAS} lecturas del reloj enviadas (hasta ${pasos} pasos)`);

// 4) contactos de emergencia
const existentes = await llamar('GET', `/contactos?usuarioId=${id}`, token);
if ((existentes.json ?? []).length === 0) {
  await llamar('POST', `/contactos?usuarioId=${id}`, token, { nombre: 'Mamá', telefono: '4421234567', relacion: 'Familiar' });
  await llamar('POST', `/contactos?usuarioId=${id}`, token, { nombre: 'Dra. López', telefono: '4427654321', relacion: 'Médico' });
  paso('2 contactos de emergencia creados');
} else {
  paso('los contactos ya existían');
}

// 5) metas
const m = await llamar('GET', `/metas?usuarioId=${id}`, token);
if (m.json?.version === 0) {
  const g = await llamar('PUT', `/metas?usuarioId=${id}`, token, { metaPasos: 9000, metaCalorias: 650, metaSueno: 7.5, version: 0 });
  paso(g.estado === 200 ? 'metas fijadas: 9000 pasos, 650 kcal, 7.5 h de sueño' : `no se pudieron fijar las metas (${g.estado})`);
} else {
  paso('las metas ya estaban fijadas');
}

// 6) chat (vive en la memoria del servidor: se pierde si el servidor se reinicia)
await llamar('POST', `/chat/${id}/mensajes`, token, { emisor: 'MEDICO', texto: 'Hola, vi que ayer dormiste 7 horas. ¡Buen ritmo!' });
await llamar('POST', `/chat/${id}/mensajes`, token, { emisor: 'PACIENTE', texto: 'Gracias doctora, hoy quiero llegar a 9000 pasos.' });
paso('2 mensajes en el chat (se pierden al reiniciar el servidor)');

console.log(`\nListo. Entra con:  ${CORREO}\nLa app pedirá crear un PIN de 4 dígitos la primera vez que elijas la cuenta «${cuenta.nombreCompleto}».`);
