// PRÁCTICA 12 · Fase 3 · Prueba de estrés con k6 (un escenario por ejecución; lo lanza estres-api.mjs).
// Variables: API, TOKEN, CUENTA, MODO = lectura | escritura, USUARIOS, SOLICITUDES, LIMITE (filas del historial).
// Además de latencia, cuenta cuántas respuestas hubo de cada código HTTP (estado_200, estado_409…).
import http from 'k6/http';
import { Counter } from 'k6/metrics';

const API = __ENV.API;
const TOKEN = __ENV.TOKEN;
const CUENTA = __ENV.CUENTA;
const MODO = __ENV.MODO || 'lectura';
const USUARIOS = Number(__ENV.USUARIOS || 1);
const SOLICITUDES = Number(__ENV.SOLICITUDES || 60);
const LIMITE = Number(__ENV.LIMITE || 24);
const DURACION = __ENV.DURACION; // segundos: si se indica, carga sostenida (constant-vus) en lugar de N solicitudes

const CODIGOS = [0, 200, 201, 204, 400, 401, 403, 404, 409, 429, 500, 502, 503, 504];
const contadores = {};
for (const c of CODIGOS) contadores[c] = new Counter('estado_' + c);
const otros = new Counter('estado_otro');

export const options = {
  scenarios: {
    carga: DURACION
      ? { executor: 'constant-vus', vus: USUARIOS, duration: DURACION + 's' }
      : { executor: 'shared-iterations', vus: USUARIOS, iterations: SOLICITUDES, maxDuration: '5m' },
  },
  summaryTrendStats: ['min', 'avg', 'med', 'p(90)', 'p(95)', 'max'],
};

const cab = { headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' }, timeout: '60s' };

export default function () {
  let r;
  if (MODO === 'lectura') {
    r = http.get(`${API}/smartwatch/historial?usuarioId=${CUENTA}&limite=${LIMITE}`, cab);
  } else {
    // Escritura sobre UN solo documento (metas de la cuenta), fusión por campos, transacción de Firestore.
    r = http.put(`${API}/metas?usuarioId=${CUENTA}`, JSON.stringify({ metaPasos: 5000 + Math.floor(Math.random() * 10000) }), cab);
  }
  const c = contadores[r.status];
  if (c) c.add(1); else otros.add(1);
}
