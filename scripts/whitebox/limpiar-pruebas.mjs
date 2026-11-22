// Borra los restos de las pruebas de la Práctica 11 en Firebase: SOLO personas cuyo correo empieza por «zz-prueba» o
// «zz.prueba», cuentas cuyo usuario empieza por «zz» (con su reloj, historial, contactos, metas y reserva de usuario).
// Nunca toca datos que no lleven ese prefijo. Sin argumentos muestra lo que borraría; con --borrar lo borra.
//   node scripts/whitebox/limpiar-pruebas.mjs [--borrar]
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const borrar = process.argv.includes('--borrar');
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const k = JSON.parse(fs.readFileSync(path.join(raiz, 'vitasync-backend/src/main/resources/serviceAccountKey.json'), 'utf8'));
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const ahora = Math.floor(Date.now() / 1000);
const cab = { alg: 'RS256', typ: 'JWT', kid: k.private_key_id };
const cuerpo = { iss: k.client_email, scope: 'https://www.googleapis.com/auth/cloud-platform', aud: 'https://oauth2.googleapis.com/token', iat: ahora, exp: ahora + 3000 };
const firma = crypto.sign('RSA-SHA256', Buffer.from(`${b64(cab)}.${b64(cuerpo)}`), k.private_key).toString('base64url');
const r = await fetch('https://oauth2.googleapis.com/token', {
  method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${b64(cab)}.${b64(cuerpo)}.${firma}` }),
});
const h = { Authorization: 'Bearer ' + (await r.json()).access_token, 'content-type': 'application/json' };
const base = `https://firestore.googleapis.com/v1/projects/${k.project_id}/databases/(default)/documents`;
const auth = `https://identitytoolkit.googleapis.com/v1/projects/${k.project_id}`;

async function listar(ruta) {
  const j = await (await fetch(`${base}/${ruta}?pageSize=300&showMissing=true`, { headers: h })).json();
  return (j.documents ?? []).map((d) => ({ id: d.name.split('/').pop(), campos: d.fields ?? {} }));
}
async function eliminarDoc(ruta) {
  if (borrar) await fetch(`${base}/${ruta}`, { method: 'DELETE', headers: h });
}

// Personas
const u = await (await fetch(`${auth}/accounts:batchGet?maxResults=200`, { headers: h })).json();
for (const p of (u.users ?? []).filter((x) => /^zz[-.]prueba/.test(x.email ?? ''))) {
  console.log(`${borrar ? 'borrando' : 'borraría'} persona ${p.email}`);
  if (borrar) await fetch(`${auth}/accounts:delete`, { method: 'POST', headers: h, body: JSON.stringify({ localId: p.localId }) });
}
// Cuentas VitaSync de prueba
for (const c of (await listar('usuarios')).filter((x) => /^zz/i.test(x.campos.username?.stringValue ?? ''))) {
  const username = c.campos.username.stringValue;
  console.log(`${borrar ? 'borrando' : 'borraría'} cuenta ${username} (${c.id}) y sus datos`);
  for (const sub of ['contactos', 'preferencias']) for (const d of await listar(`usuarios/${c.id}/${sub}`)) await eliminarDoc(`usuarios/${c.id}/${sub}/${d.id}`);
  for (const d of await listar(`devices/${c.id}/historial`)) await eliminarDoc(`devices/${c.id}/historial/${d.id}`);
  await eliminarDoc(`devices/${c.id}`);
  await eliminarDoc(`usernames/${username}`);
  await eliminarDoc(`usuarios/${c.id}`);
}
// Reservas de usuario huérfanas con prefijo zz
for (const d of (await listar('usernames')).filter((x) => /^zz/i.test(x.id))) {
  console.log(`${borrar ? 'borrando' : 'borraría'} reserva de usuario ${d.id}`);
  await eliminarDoc(`usernames/${d.id}`);
}
console.log(borrar ? 'Listo.' : 'Simulación: ejecuta con --borrar para aplicar.');
