// PRÁCTICA 12 · Fase 4 · Pruebas avanzadas de base de datos (Cloud Firestore REAL) sobre la consulta crítica: el
// historial de lecturas «devices/{cuenta}/historial» (la que la app consulta una y otra vez).
//   node scripts/practica12/bd-avanzado.mjs <API> <CLAVE_API_WEB> <salida.json> [documentos=520]
//
// Consultas (directas a Firestore por REST, sin la caché del servidor, con «explainOptions» para ver lecturas, índices y
// tiempo de ejecución en el servidor):  por id · conjunto pequeño (10) · grande (500) · con filtro de rango · con filtro
// que NECESITA un índice compuesto · sin límite.
// Concurrencia (a través de la API): 10 PUT simultáneos con la MISMA versión · 3 dispositivos cambiando campos
// distintos a la vez (¿se pierde alguna actualización?) · 20 PUT simultáneos al mismo campo · 20 lecturas nuevas a la vez
// (¿se pierde alguna escritura?).
// Crea una persona y una cuenta de prueba («zz…») y las borra al terminar. Solo contra un ambiente propio.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [API, KEY, SALIDA, DOCS = '520'] = process.argv.slice(2);
if (!API || !KEY || !SALIDA) { console.error('Uso: node bd-avanzado.mjs <API> <CLAVE> <salida.json> [documentos]'); process.exit(2); }
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const sa = JSON.parse(fs.readFileSync(path.join(raiz, 'vitasync-backend/src/main/resources/serviceAccountKey.json'), 'utf8'));
const AUTH = 'https://identitytoolkit.googleapis.com/v1';
const sufijo = Date.now().toString(36);
const r1 = (x, d = 1) => Math.round(x * 10 ** d) / 10 ** d;
const pct = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor((p / 100) * s.length))]; };
const media = (a) => a.reduce((x, y) => x + y, 0) / a.length;

// --- Acceso administrador a Firestore (REST) ---
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
async function tokenAdmin() {
  const ahora = Math.floor(Date.now() / 1000);
  const cab = { alg: 'RS256', typ: 'JWT', kid: sa.private_key_id };
  const cuerpo = { iss: sa.client_email, scope: 'https://www.googleapis.com/auth/datastore', aud: 'https://oauth2.googleapis.com/token', iat: ahora, exp: ahora + 3000 };
  const firma = crypto.sign('RSA-SHA256', Buffer.from(`${b64(cab)}.${b64(cuerpo)}`), sa.private_key).toString('base64url');
  const r = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${b64(cab)}.${b64(cuerpo)}.${firma}` }) });
  return (await r.json()).access_token;
}
// EMULADOR=1: Firestore local (puerto 8085) y backend sin seguridad (sin tokens). Sirve cuando la cuota diaria del plan gratuito
// de la nube real está agotada; las pruebas de concurrencia usan las mismas transacciones, pero NO miden latencia de red.
const EMU = !!process.env.EMULADOR;
const BASE = EMU ? `http://127.0.0.1:8085/v1/projects/${sa.project_id}/databases/(default)/documents`
  : `https://firestore.googleapis.com/v1/projects/${sa.project_id}/databases/(default)/documents`;
let hAdmin;

async function api(metodo, ruta, { token, cuerpo, clave } = {}) {
  const cab = { 'content-type': 'application/json' };
  if (token) cab.Authorization = 'Bearer ' + token;
  if (clave) cab['X-Clave-Dispositivo'] = clave;
  const t0 = performance.now();
  const r = await fetch(API + ruta, { method: metodo, headers: cab, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const ms = performance.now() - t0;
  const txt = await r.text();
  let json = null; try { json = JSON.parse(txt); } catch { /* */ }
  return { estado: r.status, json, ms };
}

async function consulta(padre, q, explain = false) {
  const url = `${BASE}/${padre}:runQuery`;
  const body = { structuredQuery: q, ...(explain ? { explainOptions: { analyze: true } } : {}) };
  const t0 = performance.now();
  const r = await fetch(url, { method: 'POST', headers: hAdmin, body: JSON.stringify(body) });
  const ms = performance.now() - t0;
  const j = await r.json();
  const arr = Array.isArray(j) ? j : [j];
  const err = arr.find((x) => x.error)?.error ?? null;
  return { http: r.status, ms, docs: arr.filter((x) => x.document).length, metricas: arr.map((x) => x.explainMetrics).find(Boolean) ?? null, error: err ? `${err.status}: ${(err.message || '').slice(0, 160)}` : null };
}

const salida = { entorno: '', fecha: new Date().toISOString(), proyecto: sa.project_id, api: API, documentos: Number(DOCS), consultas: {}, concurrencia: {}, integridad: {} };
const reg = EMU ? { idToken: undefined } : await (await fetch(`${AUTH}/accounts:signUp?key=${KEY}`, { method: 'POST', headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ email: `zz-prueba-bd-${sufijo}@uteq.test`, password: 'Clave-Segura-9', returnSecureToken: true }) })).json();
const token = reg.idToken;
let cuenta;
try {
  hAdmin = { Authorization: 'Bearer ' + (EMU ? 'owner' : await tokenAdmin()), 'content-type': 'application/json' };
  cuenta = (await api('POST', '/usuarios', { token, cuerpo: { nombreCompleto: 'Prueba BD', username: 'zzbd' + sufijo, grupos: [] } })).json?.id;
  const conexion = await api('POST', `/smartwatch/connect?usuarioId=${cuenta}`, { token });
  const clave = conexion.json.claveDispositivo;

  // --- Preparación: N lecturas, una cada 15 minutos hacia atrás (5 en paralelo) ---
  const N = Number(DOCS);
  const t0 = performance.now();
  let siguiente = 1;
  await Promise.all(Array.from({ length: 5 }, async () => {
    while (true) {
      const i = siguiente++;
      if (i > N) return;
      await api('POST', `/smartwatch/sync?usuarioId=${cuenta}`, { clave, cuerpo: { pasos: 1000 + (i * 37) % 9000, calorias: 50 + (i % 400), sueñoHoras: 7.2, frecuenciaCardiaca: 60 + (i % 40), bateria: 80, timestamp: new Date(Date.now() - i * 900000).toISOString() } });
    }
  }));
  salida.preparacionSeg = r1((performance.now() - t0) / 1000);
  console.log(`Preparados ${N} documentos en ${salida.preparacionSeg} s`);

  const padre = `devices/${cuenta}`;
  const hist = { from: [{ collectionId: 'historial' }] };
  const orden = { orderBy: [{ field: { fieldPath: 'ts' }, direction: 'DESCENDING' }] };
  const hace6h = Date.now() - 6 * 3600 * 1000;
  const defs = {
    'Q2 conjunto pequeño: orderBy ts DESC limit 10': { ...hist, ...orden, limit: 10 },
    'Q3 conjunto grande: orderBy ts DESC limit 500': { ...hist, ...orden, limit: 500 },
    'Q4 filtro de rango: ts >= hace 6 h, orderBy ts DESC': { ...hist, where: { fieldFilter: { field: { fieldPath: 'ts' }, op: 'GREATER_THAN_OR_EQUAL', value: { integerValue: String(hace6h) } } }, ...orden },
    'Q5 filtro que exige índice compuesto: pasos > 5000 ORDER BY ts DESC': { ...hist, where: { fieldFilter: { field: { fieldPath: 'pasos' }, op: 'GREATER_THAN', value: { integerValue: '5000' } } }, ...orden, limit: 50 },
    'Q6 sin límite (toda la subcolección)': { ...hist },
  };
  // Q1 por identificador: se toma el id de un documento real.
  const uno = await consulta(padre, { ...hist, ...orden, limit: 1 });
  const idDoc = await (async () => {
    const r = await fetch(`${BASE}/${padre}/historial?pageSize=1`, { headers: hAdmin });
    const j = await r.json();
    return j.documents?.[0]?.name.split('/').pop();
  })();
  {
    const tiempos = [];
    for (let i = 0; i < 15; i++) { const t = performance.now(); const r = await fetch(`${BASE}/${padre}/historial/${idDoc}`, { headers: hAdmin }); await r.json(); tiempos.push(performance.now() - t); }
    salida.consultas['Q1 por identificador (GET del documento)'] = { repeticiones: 15, registros: 1, minMs: r1(Math.min(...tiempos)), mediaMs: r1(media(tiempos)), p95Ms: r1(pct(tiempos, 95)), maxMs: r1(Math.max(...tiempos)), lecturas: 1, indices: 'ID del documento (índice primario)' };
  }
  for (const [nombre, q] of process.env.SALTAR_CONSULTAS ? [] : Object.entries(defs)) {
    const ex = await consulta(padre, q, true);
    const tiempos = [];
    let docs = ex.docs;
    const reps = /^Q[36]/.test(nombre) ? 6 : 12; // las consultas grandes leen cientos de documentos: se cuidan las lecturas facturadas
    if (!ex.error) for (let i = 0; i < reps; i++) { const r = await consulta(padre, q); tiempos.push(r.ms); docs = r.docs; }
    const e = ex.metricas?.executionStats;
    salida.consultas[nombre] = ex.error
      ? { error: ex.error, http: ex.http }
      : { repeticiones: reps, registros: docs, minMs: r1(Math.min(...tiempos)), mediaMs: r1(media(tiempos)), p95Ms: r1(pct(tiempos, 95)), maxMs: r1(Math.max(...tiempos)),
          lecturas: Number(e?.readOperations ?? NaN), ejecucionServidor: e?.executionDuration ?? null, indices: JSON.stringify(ex.metricas?.planSummary?.indexesUsed ?? null) };
    const c = salida.consultas[nombre];
    console.log(`${nombre}\n   ${c.error ? 'ERROR ' + c.error : `registros ${c.registros} | media ${c.mediaMs} ms (p95 ${c.p95Ms}, máx ${c.maxMs}) | lecturas ${c.lecturas} | servidor ${c.ejecucionServidor} | índices ${c.indices}`}`);
  }

  // --- Concurrencia ---
  const m0 = await api('GET', `/metas?usuarioId=${cuenta}`, { token });
  if (m0.estado !== 200) console.log('GET /metas ->', m0.estado, JSON.stringify(m0.json));
  const metas0 = m0.json;
  const v0 = metas0.version;
  const cs = (rs) => rs.reduce((a, r) => { a[r.estado] = (a[r.estado] || 0) + 1; return a; }, {});

  // C1: 10 PUT simultáneos con LA MISMA versión → solo uno debe ganar.
  {
    const t = performance.now();
    const rs = await Promise.all(Array.from({ length: 10 }, (_, i) => api('PUT', `/metas?usuarioId=${cuenta}`, { token, cuerpo: { metaPasos: 6000 + i * 100, version: v0, dispositivo: 'c' + i } })));
    const final = (await api('GET', `/metas?usuarioId=${cuenta}`, { token })).json;
    const ganadores = rs.filter((r) => r.estado === 200);
    salida.concurrencia['C1 10 PUT simultáneos con la MISMA versión'] = {
      tiempoTotalMs: r1(performance.now() - t), codigos: cs(rs), versionInicial: v0, versionFinal: final.version, metaPasosFinal: final.metaPasos,
      consistente: ganadores.length === 1 && final.version === v0 + 1 && ganadores[0].json?.metaPasos === final.metaPasos,
    };
  }
  // C2: 3 dispositivos cambian CAMPOS DISTINTOS a la vez, 5 rondas: ninguna actualización debe perderse.
  {
    let perdidas = 0; const codigos = {}; const tiempos = [];
    for (let ronda = 0; ronda < 5; ronda++) {
      const pasos = 7000 + ronda * 111, cal = 300 + ronda * 7, sueno = 6 + ronda * 0.5;
      const t = performance.now();
      const rs = await Promise.all([
        api('PUT', `/metas?usuarioId=${cuenta}`, { token, cuerpo: { metaPasos: pasos } }),
        api('PUT', `/metas?usuarioId=${cuenta}`, { token, cuerpo: { metaCalorias: cal } }),
        api('PUT', `/metas?usuarioId=${cuenta}`, { token, cuerpo: { metaSueno: sueno } }),
      ]);
      tiempos.push(performance.now() - t);
      for (const r of rs) codigos[r.estado] = (codigos[r.estado] || 0) + 1;
      const f = (await api('GET', `/metas?usuarioId=${cuenta}`, { token })).json;
      const okRonda = rs.every((r) => r.estado === 200) ? (f.metaPasos === pasos && f.metaCalorias === cal && f.metaSueno === sueno) : true;
      if (!okRonda) perdidas++;
    }
    salida.concurrencia['C2 3 dispositivos, campos distintos, 5 rondas'] = { codigos, rondasConActualizacionPerdida: perdidas, mediaRondaMs: r1(media(tiempos)) };
  }
  // C3: 20 PUT simultáneos al MISMO campo sin versión (fusión): ¿esperas, conflictos?
  {
    const valores = Array.from({ length: 20 }, (_, i) => 8000 + i * 10);
    const t = performance.now();
    const rs = await Promise.all(valores.map((v, i) => api('PUT', `/metas?usuarioId=${cuenta}`, { token, cuerpo: { metaPasos: v, dispositivo: 'd' + i } })));
    const total = performance.now() - t;
    const final = (await api('GET', `/metas?usuarioId=${cuenta}`, { token })).json;
    const lat = rs.map((r) => r.ms);
    salida.concurrencia['C3 20 PUT simultáneos al mismo campo'] = {
      tiempoTotalMs: r1(total), codigos: cs(rs), latMediaMs: r1(media(lat)), latMaxMs: r1(Math.max(...lat)),
      valorFinalEntreLosEnviados: valores.includes(final.metaPasos), versionFinal: final.version,
    };
  }
  // C4: 20 lecturas nuevas del reloj a la vez: el historial debe crecer EXACTAMENTE en 20.
  {
    const cuenta0 = async () => {
      const r = await fetch(`${BASE}/${padre}:runAggregationQuery`, { method: 'POST', headers: hAdmin,
        body: JSON.stringify({ structuredAggregationQuery: { structuredQuery: { from: [{ collectionId: 'historial' }] }, aggregations: [{ alias: 'n', count: {} }] } }) });
      const j = await r.json();
      const n = Number(j[0]?.result?.aggregateFields?.n?.integerValue ?? NaN);
      if (Number.isFinite(n)) return n;
      // Alternativa (el emulador puede no tener agregaciones): contar paginando la lista de documentos.
      let total = 0, pagina = '';
      do {
        const l = await (await fetch(`${BASE}/${padre}/historial?pageSize=300&mask.fieldPaths=ts${pagina ? '&pageToken=' + pagina : ''}`, { headers: hAdmin })).json();
        total += (l.documents ?? []).length;
        pagina = l.nextPageToken ?? '';
      } while (pagina);
      return total;
    };
    const antes = await cuenta0();
    const t = performance.now();
    const rs = await Promise.all(Array.from({ length: 20 }, (_, i) => api('POST', `/smartwatch/sync?usuarioId=${cuenta}`, { clave, cuerpo: { pasos: 20000 + i, calorias: 10, sueñoHoras: 7, frecuenciaCardiaca: 70, bateria: 80, timestamp: new Date(Date.now() + i).toISOString() } })));
    const total = performance.now() - t;
    const despues = await cuenta0();
    salida.concurrencia['C4 20 lecturas nuevas simultáneas'] = { tiempoTotalMs: r1(total), codigos: cs(rs), documentosAntes: antes, documentosDespues: despues, crecimiento: despues - antes, escriturasPerdidas: 20 - (despues - antes) };
    salida.integridad = { documentosEsperadosTrasPreparar: N, documentosAntesDeC4: antes, documentosFinal: despues };
  }
  for (const [k, v] of Object.entries(salida.concurrencia)) console.log(k, JSON.stringify(v));
} finally {
  if (cuenta) await api('DELETE', `/usuarios/${cuenta}`, { token });
  if (!EMU) await fetch(`${AUTH}/accounts:delete?key=${KEY}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: token }) });
  salida.entorno = EMU ? 'Firestore EMULADOR local (sin latencia de red; cuota de la nube agotada)' : 'Cloud Firestore real';
  fs.writeFileSync(SALIDA, JSON.stringify(salida, null, 2));
  console.log('Guardado en', SALIDA);
}
