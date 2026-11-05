// Crea (o reutiliza) una persona en Firebase Authentication y le asigna un rol («admin», «medico» o «paciente»).
// El rol de administrador NO se puede dar desde la app (a propósito: nadie puede ascenderse); se asigna aquí, con la
// clave de servicio del proyecto (vitasync-backend/src/main/resources/serviceAccountKey.json).
//
//   node scripts/crear-admin.mjs <CLAVE_API_WEB> <correo> <contraseña> [rol=admin]
//
// La contraseña no se guarda en ningún archivo. La persona debe cerrar sesión y volver a entrar para que el rol llegue
// a su token.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [KEY, CORREO, CLAVE, ROL = 'admin'] = process.argv.slice(2);
if (!KEY || !CORREO || !CLAVE || !['admin', 'medico', 'paciente'].includes(ROL)) {
  console.error('Uso: node scripts/crear-admin.mjs <CLAVE_API_WEB> <correo> <contraseña> [admin|medico|paciente]');
  process.exit(2);
}
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const k = JSON.parse(fs.readFileSync(path.join(raiz, 'vitasync-backend/src/main/resources/serviceAccountKey.json'), 'utf8'));
const AUTH = 'https://identitytoolkit.googleapis.com/v1';

async function identidad(operacion) {
  const r = await fetch(`${AUTH}/accounts:${operacion}?key=${KEY}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: CORREO, password: CLAVE, returnSecureToken: true }),
  });
  return r.json();
}

async function tokenDeServicio() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const ahora = Math.floor(Date.now() / 1000);
  const cab = { alg: 'RS256', typ: 'JWT', kid: k.private_key_id };
  const cuerpo = { iss: k.client_email, scope: 'https://www.googleapis.com/auth/cloud-platform', aud: 'https://oauth2.googleapis.com/token', iat: ahora, exp: ahora + 3000 };
  const firma = crypto.sign('RSA-SHA256', Buffer.from(b64(cab) + '.' + b64(cuerpo)), k.private_key).toString('base64url');
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${b64(cab)}.${b64(cuerpo)}.${firma}` }),
  });
  return (await r.json()).access_token;
}

let sesion = await identidad('signUp');
if (!sesion.idToken) {
  sesion = await identidad('signInWithPassword');
  if (!sesion.idToken) { console.error('No se pudo crear ni iniciar sesión:', JSON.stringify(sesion.error ?? sesion)); process.exit(1); }
  console.log(`• la persona ${CORREO} ya existía`);
} else {
  console.log(`• persona creada: ${CORREO}`);
}

const acceso = await tokenDeServicio();
const r = await fetch(`${AUTH}/projects/${k.project_id}/accounts:update`, {
  method: 'POST', headers: { Authorization: 'Bearer ' + acceso, 'content-type': 'application/json' },
  body: JSON.stringify({ localId: sesion.localId, customAttributes: JSON.stringify({ rol: ROL }) }),
});
if (!r.ok) { console.error('No se pudo asignar el rol:', r.status, await r.text()); process.exit(1); }

// Comprobación: un token nuevo de esa persona ya trae el rol.
const nueva = await identidad('signInWithPassword');
const claims = JSON.parse(Buffer.from(nueva.idToken.split('.')[1], 'base64url').toString('utf8'));
console.log(claims.rol === ROL ? `• rol «${ROL}» asignado y comprobado en el token` : `✗ el token trae rol=${claims.rol}`);
console.log(`\nEntra con:  ${CORREO}\nSi ya tenía la sesión abierta, ciérrala y vuelve a entrar para que el rol se aplique.`);
process.exit(claims.rol === ROL ? 0 : 1);
