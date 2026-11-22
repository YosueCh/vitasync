// PRÁCTICA 11 · Fase 4 · Plan de ejecución de consultas de Firestore (Query Explain, REST, solo lectura).
// Firestore no tiene EXPLAIN de SQL, pero su API de consultas devuelve «explainMetrics»: índices usados, lecturas y
// tiempo de ejecución en el servidor (executionDuration), separado de la latencia de red.
//   node scripts/whitebox/explain-firestore.mjs <salida.json>
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [SALIDA] = process.argv.slice(2);
if (!SALIDA) {
  console.error('Uso: node explain-firestore.mjs <salida.json>');
  process.exit(2);
}
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const k = JSON.parse(fs.readFileSync(path.join(raiz, 'vitasync-backend/src/main/resources/serviceAccountKey.json'), 'utf8'));
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const ahora = Math.floor(Date.now() / 1000);
const cab = { alg: 'RS256', typ: 'JWT', kid: k.private_key_id };
const cuerpo = { iss: k.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: 'https://oauth2.googleapis.com/token', iat: ahora, exp: ahora + 3000 };
const firma = crypto.sign('RSA-SHA256', Buffer.from(`${b64(cab)}.${b64(cuerpo)}`), k.private_key).toString('base64url');
const r = await fetch('https://oauth2.googleapis.com/token', {
  method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${b64(cab)}.${b64(cuerpo)}.${firma}` }),
});
const h = { Authorization: 'Bearer ' + (await r.json()).access_token, 'content-type': 'application/json' };
const raizDocs = `projects/${k.project_id}/databases/(default)/documents`;
const url = `https://firestore.googleapis.com/v1/${raizDocs}:runQuery`;

// Una cuenta real para consultar su historial (se toma la primera que tenga lecturas).
const lista = await (await fetch(`https://firestore.googleapis.com/v1/${raizDocs}/devices?pageSize=50&showMissing=true`, { headers: h })).json();
let cuentaConHistorial = null;
for (const d of lista.documents ?? []) {
  const id = d.name.split('/').pop();
  const hijo = await (await fetch(`https://firestore.googleapis.com/v1/${raizDocs}/devices/${id}/historial?pageSize=1`, { headers: h })).json();
  if ((hijo.documents ?? []).length) { cuentaConHistorial = id; break; }
}

const consultas = {
  'existeUsername: usuarios WHERE username == X LIMIT 1': { from: [{ collectionId: 'usuarios' }], where: { fieldFilter: { field: { fieldPath: 'username' }, op: 'EQUAL', value: { stringValue: 'demo' } } }, limit: 1 },
  'listarPorPropietario: usuarios WHERE propietarioUid == X': { from: [{ collectionId: 'usuarios' }], where: { fieldFilter: { field: { fieldPath: 'propietarioUid' }, op: 'EQUAL', value: { stringValue: 'uid-que-no-existe' } } } },
  'listarTodos: usuarios (colección completa, la consulta ANTERIOR)': { from: [{ collectionId: 'usuarios' }] },
};
if (cuentaConHistorial) {
  consultas[`historial: devices/{cuenta}/historial ORDER BY timestamp DESC LIMIT 10`] = {
    from: [{ collectionId: 'historial' }], orderBy: [{ field: { fieldPath: 'timestamp' }, direction: 'DESCENDING' }], limit: 10,
  };
}
const salida = { fecha: new Date().toISOString(), proyecto: k.project_id, consultas: {} };
for (const [nombre, q] of Object.entries(consultas)) {
  const esHistorial = nombre.startsWith('historial');
  const cuerpoReq = { structuredQuery: q, explainOptions: { analyze: true } };
  const u = esHistorial ? `https://firestore.googleapis.com/v1/${raizDocs}/devices/${cuentaConHistorial}:runQuery` : url;
  const resp = await fetch(u, { method: 'POST', headers: h, body: JSON.stringify(cuerpoReq) });
  const j = await resp.json();
  const metricas = (Array.isArray(j) ? j : [j]).map((x) => x.explainMetrics).filter(Boolean)[0];
  const resultados = (Array.isArray(j) ? j : [j]).filter((x) => x.document).length;
  salida.consultas[nombre] = { http: resp.status, documentosDevueltos: resultados, planSummary: metricas?.planSummary ?? null, executionStats: metricas?.executionStats ?? null, error: j.error ?? j[0]?.error ?? null };
  const e = metricas?.executionStats;
  console.log(`${nombre}\n   HTTP ${resp.status} | devueltos ${resultados} | lecturas ${e?.readOperations ?? '?'} | ejecución en el servidor ${e?.executionDuration ?? '?'} | índices ${JSON.stringify(metricas?.planSummary?.indexesUsed ?? null)}`);
}
fs.writeFileSync(SALIDA, JSON.stringify(salida, null, 2));
console.log('Guardado en', SALIDA);
