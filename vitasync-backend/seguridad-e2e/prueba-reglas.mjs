// Prueba las reglas de Firestore de VitaSync (vitasync-backend/firestore.rules) hablando DIRECTO con el emulador,
// como lo haría una app con el SDK de cliente. Necesita dos emuladores:
//   Authentication (9099, para obtener tokens de dos personas) y Firestore (8085, con las reglas cargadas aquí).
//
//   node seguridad-e2e/prueba-reglas.mjs
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = path.resolve(import.meta.dirname, '..');
const PROYECTO = 'demo-vitasync';
const FS = `http://localhost:8085/v1/projects/${PROYECTO}/databases/(default)/documents`;
const AUTH = 'http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts';
const OWNER = { Authorization: 'Bearer owner', 'content-type': 'application/json' };
const sufijo = Date.now().toString(36);
const filas = [];

const s = (v) => ({ stringValue: v });
const cab = (token) => ({ 'content-type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) });

async function persona(correo) {
  const r = await fetch(`${AUTH}:signUp?key=x`, { method: 'POST', headers: cab(), body: JSON.stringify({ email: correo, password: 'Clave123!', returnSecureToken: true }) });
  const j = await r.json();
  if (!j.idToken) throw new Error('no se pudo crear ' + correo + ': ' + JSON.stringify(j));
  return { uid: j.localId, token: j.idToken };
}

const caso = async (id, descripcion, esperado, ejecutar, extra = () => true) => {
  const r = await ejecutar();
  const cuerpo = await r.text();
  const obtenido = r.status === 200 ? 'PERMITIDO (200)' : `RECHAZADO (${r.status})`;
  const ok = obtenido.startsWith(esperado) && extra(cuerpo);
  filas.push({ id, descripcion, esperado, obtenido, resultado: ok ? 'PASA' : 'FALLA' });
  console.log(`${ok ? 'PASA ' : 'FALLA'}  ${id}  ${descripcion}  →  ${obtenido}  (esperado: ${esperado})`);
};

// ---- reglas del proyecto cargadas en el emulador
const reglas = fs.readFileSync(path.join(RAIZ, 'firestore.rules'), 'utf8');
const carga = await fetch(`http://localhost:8085/emulator/v1/projects/${PROYECTO}:securityRules`, {
  method: 'PUT', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules', content: reglas }] } }),
});
if (!carga.ok) throw new Error('no se cargaron las reglas: ' + (await carga.text()));
await fetch(`http://localhost:8085/emulator/v1/projects/${PROYECTO}/databases/(default)/documents`, { method: 'DELETE' });

const ana = await persona(`ana.${sufijo}@uteq.test`);
const beto = await persona(`beto.${sufijo}@uteq.test`);

// ---- datos de prueba (los escribe el "servidor": el emulador acepta Bearer owner y se salta las reglas)
const poner = (ruta, campos) => fetch(`${FS}/${ruta}`, { method: 'PATCH', headers: OWNER, body: JSON.stringify({ fields: campos }) });
await poner('usuarios/cuenta-ana', { nombreCompleto: s('Ana Pérez'), username: s('ana'), propietarioUid: s(ana.uid) });
await poner('usuarios/cuenta-beto', { nombreCompleto: s('Beto Ruiz'), username: s('beto'), propietarioUid: s(beto.uid) });
await poner('devices/cuenta-ana', { usuarioId: s('cuenta-ana'), nombre: s('VitaSync Watch R1') });
await poner('devices/cuenta-ana/historial/h1', { nota: s('lectura de prueba') });
await poner('tv_sessions/ABC123', { codigo: s('ABC123') });
await poner('usuarios/cuenta-ana/contactos/c1', { nombre: s('Mamá'), telefono: s('4421234567') });

const consulta = (token) => fetch(`${FS.replace('/documents', '')}/documents:runQuery`, {
  method: 'POST', headers: cab(token),
  body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'usuarios' }],
    where: { fieldFilter: { field: { fieldPath: 'propietarioUid' }, op: 'EQUAL', value: s(ana.uid) } } } }),
});

await caso('RV-01', 'Sin sesión: leer una cuenta', 'RECHAZADO', () => fetch(`${FS}/usuarios/cuenta-ana`, { headers: cab() }));
await caso('RV-02', 'Ana lee SU cuenta', 'PERMITIDO', () => fetch(`${FS}/usuarios/cuenta-ana`, { headers: cab(ana.token) }));
await caso('RV-03', 'Ana lee la cuenta de Beto', 'RECHAZADO', () => fetch(`${FS}/usuarios/cuenta-beto`, { headers: cab(ana.token) }));
await caso('RV-04', 'Ana lista TODAS las cuentas (sin filtro)', 'RECHAZADO', () => fetch(`${FS}/usuarios`, { headers: cab(ana.token) }));
await caso('RV-05', 'Ana consulta con where propietarioUid == su UID', 'PERMITIDO', () => consulta(ana.token),
  (c) => c.includes('cuenta-ana') && !c.includes('cuenta-beto'));
await caso('RV-06', 'Ana modifica SU propia cuenta desde el cliente', 'RECHAZADO',
  () => fetch(`${FS}/usuarios/cuenta-ana?updateMask.fieldPaths=nombreCompleto`, { method: 'PATCH', headers: cab(ana.token), body: JSON.stringify({ fields: { nombreCompleto: s('Otro') } }) }));
await caso('RV-07', 'Ana crea una cuenta a nombre de Beto (suplantación)', 'RECHAZADO',
  () => fetch(`${FS}/usuarios/cuenta-falsa`, { method: 'PATCH', headers: cab(ana.token), body: JSON.stringify({ fields: { propietarioUid: s(beto.uid), username: s('x') } }) }));
await caso('RV-08', 'Ana elimina la cuenta de Beto', 'RECHAZADO', () => fetch(`${FS}/usuarios/cuenta-beto`, { method: 'DELETE', headers: cab(ana.token) }));
await caso('RV-09', 'Ana elimina SU cuenta desde el cliente', 'RECHAZADO', () => fetch(`${FS}/usuarios/cuenta-ana`, { method: 'DELETE', headers: cab(ana.token) }));
await caso('RV-10', 'Ana lee SU reloj', 'PERMITIDO', () => fetch(`${FS}/devices/cuenta-ana`, { headers: cab(ana.token) }));
await caso('RV-11', 'Beto lee el reloj de Ana', 'RECHAZADO', () => fetch(`${FS}/devices/cuenta-ana`, { headers: cab(beto.token) }));
await caso('RV-12', 'Ana lee SU historial', 'PERMITIDO', () => fetch(`${FS}/devices/cuenta-ana/historial/h1`, { headers: cab(ana.token) }));
await caso('RV-13', 'Beto lee el historial de Ana', 'RECHAZADO', () => fetch(`${FS}/devices/cuenta-ana/historial/h1`, { headers: cab(beto.token) }));
await caso('RV-14', 'Ana inyecta lecturas falsas en su historial desde el cliente', 'RECHAZADO',
  () => fetch(`${FS}/devices/cuenta-ana/historial/falsa`, { method: 'PATCH', headers: cab(ana.token), body: JSON.stringify({ fields: { nota: s('inventada') } }) }));
await caso('RV-15', 'Ana lee una sesión de Smart TV (solo servidor)', 'RECHAZADO', () => fetch(`${FS}/tv_sessions/ABC123`, { headers: cab(ana.token) }));
await caso('RV-16', 'Ana escribe en una colección no prevista', 'RECHAZADO',
  () => fetch(`${FS}/otros/x`, { method: 'PATCH', headers: cab(ana.token), body: JSON.stringify({ fields: { a: s('b') } }) }));
await caso('RV-17', 'Sin sesión: escribir', 'RECHAZADO',
  () => fetch(`${FS}/usuarios/nueva`, { method: 'PATCH', headers: cab(), body: JSON.stringify({ fields: { a: s('b') } }) }));

await caso('RV-18', 'Ana lee SUS contactos de emergencia', 'PERMITIDO', () => fetch(`${FS}/usuarios/cuenta-ana/contactos/c1`, { headers: cab(ana.token) }));
await caso('RV-19', 'Beto lee los contactos de emergencia de Ana', 'RECHAZADO', () => fetch(`${FS}/usuarios/cuenta-ana/contactos/c1`, { headers: cab(beto.token) }));
await caso('RV-20', 'Ana agrega un contacto desde el cliente (solo el backend escribe)', 'RECHAZADO',
  () => fetch(`${FS}/usuarios/cuenta-ana/contactos/falso`, { method: 'PATCH', headers: cab(ana.token), body: JSON.stringify({ fields: { nombre: s('x') } }) }));
await caso('RV-21', 'Sin sesión: leer contactos de emergencia', 'RECHAZADO', () => fetch(`${FS}/usuarios/cuenta-ana/contactos/c1`, { headers: cab() }));
await caso('RV-22', 'Beto elimina un contacto de Ana', 'RECHAZADO', () => fetch(`${FS}/usuarios/cuenta-ana/contactos/c1`, { method: 'DELETE', headers: cab(beto.token) }));

const fallas = filas.filter((f) => f.resultado === 'FALLA');
console.log(`\nRESUMEN: ${filas.length - fallas.length}/${filas.length} pasan${fallas.length ? '; fallan: ' + fallas.map((f) => f.id).join(', ') : ''}`);
fs.writeFileSync(path.join(import.meta.dirname, 'resultados-reglas.json'), JSON.stringify(filas, null, 2));
process.exit(fallas.length ? 1 : 0);
