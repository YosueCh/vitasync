// Comprueba (solo lectura) que las pruebas de la Práctica 11 no dejaron restos en Firebase: personas «zz-prueba…» en
// Authentication y documentos «zz…» en Firestore. Usa la clave de servicio de vitasync-backend/src/main/resources.
//   node scripts/whitebox/restos-nube.mjs
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
const h = { Authorization: 'Bearer ' + (await r.json()).access_token };
const u = await (await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${k.project_id}/accounts:batchGet?maxResults=200`, { headers: h })).json();
const correos = (u.users ?? []).map((x) => x.email ?? '');
console.log(`Personas en Authentication: ${correos.length} | restos de prueba (zz…): ${correos.filter((c) => /^zz[-.]/.test(c)).length}`);
const base = `https://firestore.googleapis.com/v1/projects/${k.project_id}/databases/(default)/documents`;
for (const col of ['usuarios', 'devices', 'invitaciones']) {
  const j = await (await fetch(`${base}/${col}?pageSize=300&showMissing=true`, { headers: h })).json();
  const ids = (j.documents ?? []).map((d) => d.name.split('/').pop());
  console.log(`${col.padEnd(13)} ${String(ids.length).padStart(3)} documentos | restos de prueba: ${ids.filter((i) => /^zz|zz-prueba|ZZ-PRUEBA/i.test(i)).length}`);
}
