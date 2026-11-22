// PRÁCTICA 11 · Fase 3 · Matriz de códigos HTTP del backend REAL (Spring Boot + Firebase de la nube), con personas reales.
//
//   node scripts/whitebox/matriz-http.mjs <API> <CLAVE_API_WEB> <salida.json>
//   ej.: node scripts/whitebox/matriz-http.mjs http://localhost:8084/api <clave> evidencias/matriz-http.json
//
// Crea dos personas de prueba en Firebase Authentication (zz-prueba-wb-…), una cuenta VitaSync de la primera, ejecuta
// los casos y al final borra todo lo creado. Cada caso registra: código esperado (según la tabla de la práctica),
// código obtenido, tiempo, tamaño de la respuesta, tipo de contenido y si la respuesta filtra datos sensibles.
import fs from 'node:fs';
import { performance } from 'node:perf_hooks';

const [API, KEY, SALIDA] = process.argv.slice(2);
if (!API || !KEY || !SALIDA) {
  console.error('Uso: node matriz-http.mjs <API> <CLAVE_API_WEB> <salida.json>');
  process.exit(2);
}
const AUTH = 'https://identitytoolkit.googleapis.com/v1';
const sufijo = Date.now().toString(36);
// Claves JSON EXACTAS que nunca deben viajar en una respuesta (se compara el nombre completo de la clave, no un fragmento:
// «requiereCambioPassword» NO es «password»).
const CLAVES_SENSIBLES = new Set(['pinHash', 'pinSalt', 'pin', 'password', 'idToken', 'refreshToken', 'claveHash', 'claveDispositivoHash', 'private_key', 'privateKey', 'token', 'accessToken', 'secret']);
function filtraSensibles(texto) {
  try {
    const hallazgos = [];
    const recorre = (v) => { if (Array.isArray(v)) v.forEach(recorre); else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) { if (CLAVES_SENSIBLES.has(k)) hallazgos.push(k); recorre(x); } };
    recorre(JSON.parse(texto));
    return hallazgos.length > 0;
  } catch { return /("trace"|at com.vitasync|java.lang.)/.test(texto); }
}
const resultados = [];

async function persona(correo) {
  const r = await fetch(`${AUTH}/accounts:signUp?key=${KEY}`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: correo, password: 'Clave-Segura-9', returnSecureToken: true }),
  });
  const j = await r.json();
  if (!j.idToken) throw new Error('no se pudo crear ' + correo + ': ' + JSON.stringify(j));
  return { correo, uid: j.localId, token: j.idToken };
}
const borrar = (p) => fetch(`${AUTH}/accounts:delete?key=${KEY}`, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: p.token }),
});

/** Una petición medida. */
async function pedir(metodo, ruta, { token, cuerpo, tipo = 'application/json', crudo } = {}) {
  const cab = {};
  if (token) cab.Authorization = 'Bearer ' + token;
  if (cuerpo !== undefined || crudo !== undefined) cab['content-type'] = tipo;
  const t0 = performance.now();
  const r = await fetch(API + ruta, { method: metodo, headers: cab, body: crudo ?? (cuerpo === undefined ? undefined : JSON.stringify(cuerpo)) });
  const texto = await r.text();
  const ms = performance.now() - t0;
  let json = null;
  try { json = JSON.parse(texto); } catch { /* no es JSON */ }
  return { estado: r.status, ms, bytes: Buffer.byteLength(texto), tipo: r.headers.get('content-type') ?? '', texto, json };
}

async function caso(id, descripcion, esperado, metodo, ruta, opciones, nota = '') {
  const r = await pedir(metodo, ruta, opciones);
  const lista = Array.isArray(esperado) ? esperado : [esperado];
  // «trace» (pila de Java) también cuenta como fuga de información interna.
  const filtra = filtraSensibles(r.texto) || /"trace"s*:|at com.vitasync|java.lang.[A-Za-z]+Exception/.test(r.texto);
  const fila = {
    id, descripcion, metodo, ruta: ruta.length > 70 ? ruta.slice(0, 67) + '…' : ruta, esperado: lista.join(' o '), obtenido: r.estado,
    conforme: lista.includes(r.estado), ms: Math.round(r.ms * 10) / 10, bytes: r.bytes,
    tipo: r.tipo.split(';')[0], jsonValido: r.json !== null || r.texto === '', filtraDatosSensibles: filtra, nota,
    respuesta: r.texto.slice(0, 160),
  };
  resultados.push(fila);
  console.log(`${fila.conforme ? 'OK   ' : 'DIFIERE'} ${id.padEnd(4)} ${metodo.padEnd(6)} ${fila.ruta.padEnd(40)} esperado ${fila.esperado.padEnd(8)} obtenido ${r.estado}  ${fila.ms}ms ${r.bytes}B${filtra ? '  ⚠ DATOS SENSIBLES' : ''}`);
  return r;
}

const A = await persona(`zz-prueba-wb-a-${sufijo}@uteq.test`);
const B = await persona(`zz-prueba-wb-b-${sufijo}@uteq.test`);
let cuenta;
try {
  const creada = await pedir('POST', '/usuarios', { token: A.token, cuerpo: { nombreCompleto: 'Prueba WhiteBox', username: 'zzwb' + sufijo, grupos: [] } });
  cuenta = creada.json?.id;
  if (!cuenta) throw new Error('no se pudo crear la cuenta de prueba: ' + creada.estado + ' ' + creada.texto);
  const ta = A.token, tb = B.token;
  const q = `?usuarioId=${cuenta}`;

  // ---------------------------------------------------------------- Endpoint 1: contactos (escritura y lectura)
  await caso('C01', 'Alta válida de un contacto', 201, 'POST', `/contactos${q}`, { token: ta, cuerpo: { nombre: 'Mamá', telefono: '4421234567', relacion: 'Familiar' } }, 'Creación: la API responde 200 en vez de 201');
  const lista = await pedir('GET', `/contactos${q}`, { token: ta });
  const idContacto = lista.json?.[0]?.id;
  await caso('C02', 'Alta duplicada (mismo teléfono)', 409, 'POST', `/contactos${q}`, { token: ta, cuerpo: { nombre: 'Otra', telefono: '442 123 4567', relacion: 'Amigo' } });
  await caso('C03', 'Nombre vacío', [400, 422], 'POST', `/contactos${q}`, { token: ta, cuerpo: { nombre: '', telefono: '4421234567', relacion: 'Amigo' } });
  await caso('C04', 'Teléfono inválido (validación semántica)', [400, 422], 'POST', `/contactos${q}`, { token: ta, cuerpo: { nombre: 'Ana', telefono: 'abc', relacion: 'Amigo' } });
  await caso('C05', 'Sin token', 401, 'POST', `/contactos${q}`, { cuerpo: { nombre: 'Ana', telefono: '4429876543', relacion: 'Amigo' } });
  await caso('C06', 'Token inventado', 401, 'POST', `/contactos${q}`, { token: 'token.inventado.x', cuerpo: { nombre: 'Ana', telefono: '4429876543', relacion: 'Amigo' } });
  await caso('C07', 'Otra persona (token válido, cuenta ajena)', 403, 'POST', `/contactos${q}`, { token: tb, cuerpo: { nombre: 'Ana', telefono: '4429876543', relacion: 'Amigo' } });
  await caso('C08', 'Cuenta inexistente', [403, 404], 'POST', '/contactos?usuarioId=no-existe', { token: ta, cuerpo: { nombre: 'Ana', telefono: '4429876543', relacion: 'Amigo' } }, 'Por diseño 403: no revela qué cuentas existen');
  await caso('C09', 'Cuerpo que no es JSON', 400, 'POST', `/contactos${q}`, { token: ta, crudo: 'esto no es json' });
  await caso('C10', 'Content-Type no soportado', 415, 'POST', `/contactos${q}`, { token: ta, tipo: 'text/plain', crudo: 'hola' });
  await caso('C11', 'Método no permitido', 405, 'PATCH', `/contactos${q}`, { token: ta });
  await caso('C12', 'Falta el parámetro usuarioId', 400, 'GET', '/contactos', { token: ta });
  await caso('C13', 'usuarioId con barra (ruta de Firestore: «a/b»)', [400, 403, 404], 'GET', '/contactos?usuarioId=a%2Fb', { token: ta }, 'Entrada maliciosa: no debe ser 500');
  await caso('C14', 'usuarioId de 2000 caracteres', [400, 403, 404], 'GET', `/contactos?usuarioId=${'x'.repeat(2000)}`, { token: ta }, 'Entrada enorme: no debe ser 500');
  await caso('C15', 'usuarioId reservado por Firestore (__x__)', [400, 403, 404], 'GET', '/contactos?usuarioId=__reservado__', { token: ta }, 'Id reservado: no debe ser 500');
  await caso('C16', 'Baja de un contacto existente', 204, 'DELETE', `/contactos/${idContacto}${q}`, { token: ta }, 'Eliminación: la API responde 200 con cuerpo en vez de 204');
  await caso('C17', 'Baja de un contacto ya eliminado', 404, 'DELETE', `/contactos/${idContacto}${q}`, { token: ta });
  await caso('C18', 'Ruta que no existe', 404, 'GET', '/ruta-que-no-existe', { token: ta });

  // ---------------------------------------------------------------- Endpoint 2: metas (escritura con control de versión)
  await caso('M01', 'Consulta de metas', 200, 'GET', `/metas${q}`, { token: ta });
  await caso('M02', 'Guardar con la versión vigente', 200, 'PUT', `/metas${q}`, { token: ta, cuerpo: { metaPasos: 8000, version: 0 } });
  await caso('M03', 'Guardar con una versión vieja (conflicto)', 409, 'PUT', `/metas${q}`, { token: ta, cuerpo: { metaPasos: 7000, version: 0 } });
  await caso('M04', 'Valor fuera de rango', [400, 422], 'PUT', `/metas${q}`, { token: ta, cuerpo: { metaPasos: 999 } });
  await caso('M05', 'Cuerpo vacío {}', [400, 422], 'PUT', `/metas${q}`, { token: ta, cuerpo: {} });
  await caso('M06', 'Tipo equivocado ("abc" en un número)', 400, 'PUT', `/metas${q}`, { token: ta, cuerpo: { metaPasos: 'abc' } });
  await caso('M07', 'Otra persona intenta cambiar las metas', 403, 'PUT', `/metas${q}`, { token: tb, cuerpo: { metaPasos: 9000 } });
  await caso('M08', 'Sin token', 401, 'PUT', `/metas${q}`, { cuerpo: { metaPasos: 9000 } });

  // ---------------------------------------------------------------- Endpoint 3: usuarios (cuentas)
  await caso('U01', 'Listar mis cuentas', 200, 'GET', '/usuarios', { token: ta });
  const u = await caso('U02', 'Consultar mi cuenta (revisar que no filtre el hash del PIN)', 200, 'GET', `/usuarios/${cuenta}`, { token: ta });
  await caso('U03', 'Consultar la cuenta de otra persona', 403, 'GET', `/usuarios/${cuenta}`, { token: tb });
  await caso('U04', 'Consultar una cuenta inexistente', [403, 404], 'GET', '/usuarios/no-existe', { token: ta }, 'Por diseño 403');
  await caso('U05', 'Alta con usuario repetido', 409, 'POST', '/usuarios', { token: ta, cuerpo: { nombreCompleto: 'Otro Nombre', username: 'zzwb' + sufijo, grupos: [] } });
  await caso('U06', 'Alta con cuerpo vacío', [400, 422], 'POST', '/usuarios', { token: ta, cuerpo: {} });
  await caso('U07', 'Listar cuentas sin token', 401, 'GET', '/usuarios');
  await caso('U08', 'Una paciente intenta la gestión de roles', 403, 'GET', '/admin/personas', { token: ta });
  await caso('U09', 'Sincronizar el reloj sin clave de dispositivo ni token', 401, 'POST', `/smartwatch/sync${q}`, { cuerpo: { pasos: 1 } });

  // ---------------------------------------------------------------- Chat (validaciones y estado)
  await caso('H01', 'Mensaje válido', [200, 201], 'POST', `/chat/${cuenta}/mensajes`, { token: ta, cuerpo: { emisor: 'PACIENTE', texto: 'hola' } });
  // Idempotencia (WB-HALLAZGO-13): el mismo idCliente dos veces devuelve el MISMO mensaje, no crea otro.
  const h1 = await caso('H01b', 'Mensaje con idCliente (primer envío)', [200, 201], 'POST', `/chat/${cuenta}/mensajes`, { token: ta, cuerpo: { emisor: 'PACIENTE', texto: 'idempotente', idCliente: 'wb' + sufijo } });
  const h2 = await caso('H01c', 'Reintento con el MISMO idCliente (la respuesta se había perdido)', [200, 201], 'POST', `/chat/${cuenta}/mensajes`, { token: ta, cuerpo: { emisor: 'PACIENTE', texto: 'idempotente', idCliente: 'wb' + sufijo } });
  const conv = await pedir('GET', `/chat/${cuenta}/mensajes?desde=0`, { token: ta });
  const copias = (conv.json?.mensajes ?? []).filter((m) => m.texto === 'idempotente').length;
  resultados.push({ id: 'H01d', descripcion: 'El reintento no duplicó el mensaje (copias guardadas)', metodo: 'GET', ruta: `/chat/${cuenta}/mensajes`.slice(0, 67), esperado: '1', obtenido: copias, conforme: copias === 1 && h1.json?.id === h2.json?.id, ms: Math.round(conv.ms * 10) / 10, bytes: conv.bytes, tipo: 'application/json', jsonValido: true, filtraDatosSensibles: false, nota: `mismo id de mensaje: ${h1.json?.id} / ${h2.json?.id}`, respuesta: '' });
  console.log(`${copias === 1 ? 'OK   ' : 'DIFIERE'} H01d  copias del mensaje reintentado: ${copias} (esperado 1)`);
  await caso('H01e', 'idCliente con caracteres inválidos', 400, 'POST', `/chat/${cuenta}/mensajes`, { token: ta, cuerpo: { emisor: 'PACIENTE', texto: 'x', idCliente: 'a b/c' } });
  await caso('H02', 'Mensaje de 201 caracteres', 400, 'POST', `/chat/${cuenta}/mensajes`, { token: ta, cuerpo: { emisor: 'PACIENTE', texto: 'x'.repeat(201) } });
  await caso('H03', 'Emisor inválido', 400, 'POST', `/chat/${cuenta}/mensajes`, { token: ta, cuerpo: { emisor: 'ROBOT', texto: 'hola' } });
  await caso('H04', 'Archivo de un tipo no permitido', 400, 'POST', `/chat/${cuenta}/archivos`, { token: ta, cuerpo: { emisor: 'PACIENTE', nombre: 'a.exe', tipo: 'application/x-msdownload', contenidoBase64: 'TVoAAA==' } });
  await caso('H05', 'Archivo con Base64 inválido', 400, 'POST', `/chat/${cuenta}/archivos`, { token: ta, cuerpo: { emisor: 'PACIENTE', nombre: 'a.pdf', tipo: 'application/pdf', contenidoBase64: '%%%' } });
  await caso('H06', 'Descarga de un archivo inexistente', 404, 'GET', `/chat/${cuenta}/archivos/999`, { token: ta });
  await caso('H07', 'Cerrar el chat', 200, 'POST', `/chat/${cuenta}/cerrar`, { token: ta });
  await caso('H08', 'Enviar a un chat cerrado', 409, 'POST', `/chat/${cuenta}/mensajes`, { token: ta, cuerpo: { emisor: 'PACIENTE', texto: 'hola' } });
  await caso('H09', 'Chat con identificador inválido (con espacios)', [400, 403, 404], 'GET', '/chat/id%20invalido/mensajes', { token: ta });

  // ---------------------------------------------------------------- baja de la cuenta de prueba
  await caso('U10', 'Eliminar mi cuenta (borra contactos, metas y chat)', 204, 'DELETE', `/usuarios/${cuenta}`, { token: ta }, 'Eliminación: la API responde 200 con cuerpo en vez de 204');
  cuenta = null;
  await caso('U11', 'Consultar la cuenta ya eliminada', [403, 404], 'GET', `/usuarios/${creada.json.id}`, { token: ta });
} finally {
  if (cuenta) await pedir('DELETE', `/usuarios/${cuenta}`, { token: A.token });
  await borrar(A);
  await borrar(B);
}

const total = resultados.length;
const conformes = resultados.filter((x) => x.conforme).length;
const medias = resultados.map((x) => x.ms);
const resumen = {
  fecha: new Date().toISOString(), api: API, totalCasos: total, conformes, difieren: total - conformes,
  respuestasQueFiltranDatosSensibles: resultados.filter((x) => x.filtraDatosSensibles).map((x) => x.id),
  respuestas500: resultados.filter((x) => x.obtenido >= 500).map((x) => x.id),
  latenciaMediaMs: Math.round((medias.reduce((a, b) => a + b, 0) / medias.length) * 10) / 10,
  codigosObservados: [...new Set(resultados.map((x) => x.obtenido))].sort(),
};
fs.writeFileSync(SALIDA, JSON.stringify({ resumen, resultados }, null, 2));
console.log('\n' + JSON.stringify(resumen, null, 2));
