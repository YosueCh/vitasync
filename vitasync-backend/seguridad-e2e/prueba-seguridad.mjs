// Prueba de punta a punta del control de acceso de VitaSync (Práctica 10 aplicada al proyecto):
// dos personas REALES en el emulador de Firebase Authentication hablan con el backend de pruebas
// levantado con vitasync.seguridad.activa=true.
//
//   1) emulador de Authentication:  firebase emulators:start --only auth --project demo-vitasync   (puerto 9099)
//   2) backend:  mvn spring-boot:run -Dspring-boot.run.useTestClasspath=true \
//                  -Dspring-boot.run.main-class=com.vitasync.backend.blackbox.ServidorPruebas \
//                  "-Dspring-boot.run.arguments=--vitasync.seguridad.activa=true"
//   3) node seguridad-e2e/prueba-seguridad.mjs
import fs from 'node:fs';
import path from 'node:path';

const API = process.env.VITASYNC_API ?? 'http://localhost:8081/api';
const AUTH = 'http://localhost:9099/identitytoolkit.googleapis.com/v1';
const SALIDA = path.resolve(import.meta.dirname, 'resultados-e2e.json');
const sufijo = Date.now().toString(36); // permite repetir la corrida sin chocar con cuentas anteriores

const filas = [];
const registrar = (id, descripcion, esperado, obtenido, ok) => {
  filas.push({ id, descripcion, esperado, obtenido, resultado: ok ? 'PASA' : 'FALLA' });
  console.log(`${ok ? 'PASA ' : 'FALLA'}  ${id}  ${descripcion}  →  ${obtenido}  (esperado: ${esperado})`);
};

async function persona(correo, clave) {
  const r = await fetch(`${AUTH}/accounts:signUp?key=x`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: correo, password: clave, returnSecureToken: true }),
  });
  const j = await r.json();
  if (!j.idToken) throw new Error('No se pudo crear la persona ' + correo + ': ' + JSON.stringify(j));
  return { correo, uid: j.localId, token: j.idToken };
}

async function llamar(metodo, ruta, { token, clave, cuerpo } = {}) {
  const cab = { 'content-type': 'application/json' };
  if (token !== undefined) cab.Authorization = `Bearer ${token}`;
  if (clave !== undefined) cab['X-Clave-Dispositivo'] = clave;
  const r = await fetch(API + ruta, { method: metodo, headers: cab, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const texto = await r.text();
  let json = null;
  try { json = JSON.parse(texto); } catch { /* sin cuerpo JSON */ }
  return { estado: r.status, json, texto };
}

const espera = (id, desc, r, esperado, extra = () => true) =>
  registrar(id, desc, String(esperado), String(r.estado), r.estado === esperado && extra(r));

const ana = await persona(`ana.${sufijo}@uteq.test`, 'ClaveAna123');
const beto = await persona(`beto.${sufijo}@uteq.test`, 'ClaveBeto456');
console.log(`Personas en Authentication: Ana ${ana.uid} · Beto ${beto.uid}\n`);

// ---------------- autenticación
espera('E2E-01', 'Listar cuentas sin token', await llamar('GET', '/usuarios'), 401);
espera('E2E-02', 'Token inventado', await llamar('GET', '/usuarios', { token: 'no.es.un-token' }), 401);

// ---------------- cada persona crea su cuenta VitaSync
const cuentaAna = await llamar('POST', '/usuarios', { token: ana.token, cuerpo: { nombreCompleto: 'Ana Pérez', username: `ana${sufijo}`, grupos: [] } });
espera('E2E-03', 'Ana crea su cuenta VitaSync', cuentaAna, 200, (r) => !!r.json?.id);
const cuentaBeto = await llamar('POST', '/usuarios', { token: beto.token, cuerpo: { nombreCompleto: 'Beto Ruiz', username: `beto${sufijo}`, grupos: [] } });
espera('E2E-04', 'Beto crea su cuenta VitaSync', cuentaBeto, 200, (r) => !!r.json?.id);
const idAna = cuentaAna.json.id;
const idBeto = cuentaBeto.json.id;

const listaAna = await llamar('GET', '/usuarios', { token: ana.token });
espera('E2E-05', 'Ana lista cuentas: solo ve la suya', listaAna, 200, (r) => r.json.length === 1 && r.json[0].id === idAna);

espera('E2E-06', 'Alta con datos vacíos (D-01)', await llamar('POST', '/usuarios', { token: ana.token, cuerpo: { nombreCompleto: '', username: '', grupos: [] } }), 400);
espera('E2E-07', 'Alta con usuario repetido (D-02)', await llamar('POST', '/usuarios', { token: beto.token, cuerpo: { nombreCompleto: 'Otro', username: `ana${sufijo}`.toUpperCase(), grupos: [] } }), 409);

// ---------------- Beto intenta tocar lo de Ana (todo debe dar 403)
const intentos = [
  ['GET', `/usuarios/${idAna}`], ['PATCH', `/usuarios/${idAna}/deshabilitar`], ['DELETE', `/usuarios/${idAna}`],
  ['POST', `/usuarios/${idAna}/pin/verificar`, { pin: '1234' }],
  ['GET', `/smartwatch/status?usuarioId=${idAna}`], ['GET', `/smartwatch/metrics?usuarioId=${idAna}`],
  ['GET', `/smartwatch/historial?usuarioId=${idAna}`], ['POST', `/smartwatch/connect?usuarioId=${idAna}`],
  ['GET', `/chat/${idAna}/mensajes`], ['POST', `/chat/${idAna}/cerrar`], ['GET', `/firmware/estado?usuarioId=${idAna}`],
];
const todos403 = [];
for (const [m, ruta, cuerpo] of intentos) {
  const r = await llamar(m, ruta, { token: beto.token, cuerpo });
  todos403.push(`${m} ${ruta.split('?')[0].replace(idAna, '{ana}')}=${r.estado}`);
}
registrar('E2E-08', 'Beto intenta leer, cambiar y borrar TODO lo de Ana (11 intentos)', '11 × 403',
  todos403.map((x) => x.split('=')[1]).join(','), todos403.every((x) => x.endsWith('=403')));
const sigue = await llamar('GET', `/usuarios/${idAna}`, { token: ana.token });
espera('E2E-09', 'La cuenta de Ana sigue intacta y habilitada', sigue, 200, (r) => r.json.habilitado === true);

// ---------------- reloj: clave de dispositivo
const conectar = await llamar('POST', `/smartwatch/connect?usuarioId=${idAna}`, { token: ana.token });
const claveReloj = conectar.json?.claveDispositivo;
espera('E2E-10', 'Ana vincula su reloj y recibe una clave de dispositivo', conectar, 200, () => typeof claveReloj === 'string' && claveReloj.length >= 32);
espera('E2E-11', 'El estado del reloj NO vuelve a mostrar la clave',
  await llamar('GET', `/smartwatch/status?usuarioId=${idAna}`, { token: ana.token }), 200, (r) => !('claveDispositivo' in r.json));

const lectura = { pasos: 4321, ritmoCardiaco: 72, bateria: 88, timestamp: new Date().toISOString() };
espera('E2E-12', 'El firmware envía una lectura con su clave (sin token de persona)',
  await llamar('POST', `/smartwatch/sync?usuarioId=${idAna}`, { clave: claveReloj, cuerpo: lectura }), 200);
espera('E2E-13', 'Firmware con clave inventada', await llamar('POST', `/smartwatch/sync?usuarioId=${idAna}`, { clave: 'inventada', cuerpo: lectura }), 401);
espera('E2E-14', 'La clave del reloj de Ana no sirve para la cuenta de Beto',
  await llamar('POST', `/smartwatch/sync?usuarioId=${idBeto}`, { clave: claveReloj, cuerpo: lectura }), 401);
espera('E2E-15', 'La clave de dispositivo no abre las métricas (eso es de la persona)',
  await llamar('GET', `/smartwatch/metrics?usuarioId=${idAna}`, { clave: claveReloj }), 401);
espera('E2E-16', 'Firmware consulta su orden de actualización con la clave',
  await llamar('GET', `/firmware/orden?usuarioId=${idAna}`, { clave: claveReloj }), 200);

const metricas = await llamar('GET', `/smartwatch/metrics?usuarioId=${idAna}`, { token: ana.token });
espera('E2E-17', 'Ana ve la lectura que mandó su reloj', metricas, 200, (r) => r.json.pasos === 4321);
espera('E2E-18', 'Beto no ve las métricas de Ana', await llamar('GET', `/smartwatch/metrics?usuarioId=${idAna}`, { token: beto.token }), 403);

// ---------------- chat: dueño y médico
espera('E2E-19', 'Ana escribe en su chat', await llamar('POST', `/chat/${idAna}/mensajes`, { token: ana.token, cuerpo: { emisor: 'PACIENTE', texto: 'hola' } }), 200);
espera('E2E-20', 'Ana lee su chat', await llamar('GET', `/chat/${idAna}/mensajes?desde=0`, { token: ana.token }), 200, (r) => r.json.mensajes.length === 1);

// ---------------- contactos de emergencia (Actividad 1 dentro de VitaSync)
const nuevoContacto = await llamar('POST', `/contactos?usuarioId=${idAna}`, { token: ana.token, cuerpo: { nombre: 'Mamá', telefono: '(442) 123-4567', relacion: 'Familiar' } });
espera('E2E-21', 'Ana guarda un contacto de emergencia (el teléfono se normaliza)', nuevoContacto, 200, (r) => r.json.telefono === '4421234567' && !!r.json.id);
espera('E2E-22', 'Ana consulta sus contactos', await llamar('GET', `/contactos?usuarioId=${idAna}`, { token: ana.token }), 200, (r) => r.json.length === 1 && r.json[0].nombre === 'Mamá');
espera('E2E-23', 'Mismo teléfono con otro formato: rechazado', await llamar('POST', `/contactos?usuarioId=${idAna}`, { token: ana.token, cuerpo: { nombre: 'Otra', telefono: '442 123 4567', relacion: 'Amigo' } }), 409);
espera('E2E-24', 'Contacto con datos vacíos: rechazado', await llamar('POST', `/contactos?usuarioId=${idAna}`, { token: ana.token, cuerpo: { nombre: '', telefono: 'abc', relacion: '' } }), 400);
const intentosContactos = [
  await llamar('GET', `/contactos?usuarioId=${idAna}`, { token: beto.token }),
  await llamar('POST', `/contactos?usuarioId=${idAna}`, { token: beto.token, cuerpo: { nombre: 'Intruso', telefono: '4420000000', relacion: 'Otro' } }),
  await llamar('DELETE', `/contactos/${nuevoContacto.json.id}?usuarioId=${idAna}`, { token: beto.token }),
];
registrar('E2E-25', 'Beto intenta ver, agregar y borrar contactos de Ana', '3 × 403', intentosContactos.map((r) => r.estado).join(','), intentosContactos.every((r) => r.estado === 403));
espera('E2E-26', 'Beto, con su propia cuenta, ve su lista vacía (no la de Ana)', await llamar('GET', `/contactos?usuarioId=${idBeto}`, { token: beto.token }), 200, (r) => r.json.length === 0);
espera('E2E-27', 'Sin token no se puede consultar ningún contacto', await llamar('GET', `/contactos?usuarioId=${idAna}`), 401);
espera('E2E-28', 'Ana elimina su contacto', await llamar('DELETE', `/contactos/${nuevoContacto.json.id}?usuarioId=${idAna}`, { token: ana.token }), 200);
espera('E2E-29', 'Eliminar otra vez el mismo contacto: no existe', await llamar('DELETE', `/contactos/${nuevoContacto.json.id}?usuarioId=${idAna}`, { token: ana.token }), 404);

// ---------------- límite conocido de esta prueba (no se cuenta como caso)
// El servidor de PRUEBAS acepta los tokens SIN FIRMA que emite el emulador de Authentication
// (VerificadorTokenEmulador). Por eso esta corrida NO demuestra que un token fabricado se rechace.
// Eso lo hace en producción FirebaseVerificadorToken (verifyIdToken comprueba la firma), que no se ejercita aquí.
console.log('NOTA: esta prueba no cubre tokens falsificados con firma inválida (el servidor de pruebas no verifica firmas).');

const fallas = filas.filter((f) => f.resultado === 'FALLA');
console.log(`\nRESUMEN: ${filas.length - fallas.length}/${filas.length} pasan${fallas.length ? '; fallan: ' + fallas.map((f) => f.id).join(', ') : ''}`);
fs.writeFileSync(SALIDA, JSON.stringify({ api: API, ana: ana.uid, beto: beto.uid, filas }, null, 2));
process.exit(fallas.length ? 1 : 0);
