// PRÁCTICA 11 · Fase 5 · Prueba de carga controlada con k6.
// Se ejecuta desde scripts/whitebox/carga.mjs (que crea la cuenta de prueba y pasa API, TOKEN y CUENTA por variables
// de entorno). Un escenario por ejecución: MODO = lectura | escritura, USUARIOS = 1 | 5 | 10, SOLICITUDES = total.
import http from 'k6/http';
import { check } from 'k6';

const API = __ENV.API;
const TOKEN = __ENV.TOKEN;
const CUENTA = __ENV.CUENTA;
const MODO = __ENV.MODO || 'lectura';
const USUARIOS = Number(__ENV.USUARIOS || 1);
const SOLICITUDES = Number(__ENV.SOLICITUDES || 60);

export const options = {
  scenarios: {
    carga: { executor: 'shared-iterations', vus: USUARIOS, iterations: SOLICITUDES, maxDuration: '3m' },
  },
  // Sin umbrales que aborten: se quiere OBSERVAR el comportamiento, no cortar la prueba.
  summaryTrendStats: ['min', 'avg', 'med', 'p(90)', 'p(95)', 'max'],
};

const cab = { headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' } };

export default function () {
  let r;
  if (MODO === 'lectura') {
    r = http.get(`${API}/smartwatch/historial?usuarioId=${CUENTA}&limite=24`, cab);
  } else {
    // Escritura: cambia la meta de pasos SIN versión (fusión por campos); cada solicitud es una transacción de Firestore
    // sobre el mismo documento, el caso más exigente para la concurrencia.
    const meta = 5000 + Math.floor(Math.random() * 10000);
    r = http.put(`${API}/metas?usuarioId=${CUENTA}`, JSON.stringify({ metaPasos: meta }), cab);
  }
  check(r, { 'estado 200': (x) => x.status === 200 });
}
