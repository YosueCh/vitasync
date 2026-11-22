// PRÁCTICA 11 · Fase 2 · Genera los grafos de flujo de control (CFG) de los tres métodos analizados como SVG y los
// convierte a PNG con un navegador. Cada grafo incluye N (nodos), E (aristas) y V(G) = E − N + 2.
//   node scripts/whitebox/grafos-flujo.mjs <carpeta-salida> <ruta-playwright-core> <ruta-chrome>
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const [SALIDA, PLAYWRIGHT, CHROME] = process.argv.slice(2);
if (!SALIDA || !PLAYWRIGHT || !CHROME) {
  console.error('Uso: node grafos-flujo.mjs <salida> <playwright-core> <chrome.exe>');
  process.exit(2);
}
fs.mkdirSync(SALIDA, { recursive: true });
const require = createRequire(import.meta.url);
const { chromium } = require(PLAYWRIGHT);

/** Cada grafo: nodos con posición y forma (c = círculo/instrucción, d = decisión, f = fin) y aristas con etiqueta. */
const grafos = [
  {
    archivo: 'cfg-M1-validar.png',
    titulo: 'M1 · ReglasContacto.validar(nombre, telefono)',
    ancho: 760, alto: 640,
    nodos: [
      { id: 1, x: 380, y: 50, t: 'c', et: 'L1-L2: errores = {}; n = trim' },
      { id: 2, x: 380, y: 140, t: 'd', et: 'C1: n.length < 2 ?' },
      { id: 3, x: 560, y: 230, t: 'd', et: 'C2: n.length > 60 ?' },
      { id: 4, x: 380, y: 320, t: 'c', et: 'L3: errores[nombre] = …' },
      { id: 5, x: 380, y: 410, t: 'd', et: 'D2: ¬hasMatch(tel) ?' },
      { id: 6, x: 560, y: 500, t: 'c', et: 'L4: errores[telefono] = …' },
      { id: 7, x: 380, y: 590, t: 'f', et: 'L5: return errores' },
    ],
    aristas: [[1, 2, ''], [2, 4, 'V'], [2, 3, 'F'], [3, 4, 'V'], [3, 5, 'F'], [4, 5, ''], [5, 6, 'V'], [5, 7, 'F'], [6, 7, '']],
  },
  {
    archivo: 'cfg-M2-tiempoTranscurrido.png',
    titulo: 'M2 · tiempoTranscurrido(fecha, {ahora})',
    ancho: 900, alto: 820,
    nodos: [
      { id: 1, x: 340, y: 50, t: 'd', et: 'D1: fecha == null ?' },
      { id: 2, x: 130, y: 140, t: 'c', et: "return 'sin datos'" },
      { id: 3, x: 520, y: 140, t: 'd', et: 'D2: ahora == null ?' },
      { id: 4, x: 400, y: 230, t: 'c', et: 'base = DateTime.now()' },
      { id: 5, x: 640, y: 230, t: 'c', et: 'base = ahora' },
      { id: 6, x: 520, y: 320, t: 'd', et: 'D3: dif.inMinutes < 1 ?' },
      { id: 7, x: 130, y: 410, t: 'c', et: "return 'hace un momento'" },
      { id: 8, x: 520, y: 410, t: 'd', et: 'D4: dif.inHours < 1 ?' },
      { id: 9, x: 130, y: 500, t: 'c', et: "return 'hace N min'" },
      { id: 10, x: 520, y: 500, t: 'd', et: 'D5: dif.inDays < 1 ?' },
      { id: 11, x: 130, y: 590, t: 'c', et: "return 'hace N h'" },
      { id: 12, x: 520, y: 590, t: 'c', et: "return 'hace N d'" },
      { id: 13, x: 340, y: 740, t: 'f', et: 'fin' },
    ],
    aristas: [[1, 2, 'V'], [1, 3, 'F'], [3, 4, 'V'], [3, 5, 'F'], [4, 6, ''], [5, 6, ''], [6, 7, 'V'], [6, 8, 'F'], [8, 9, 'V'], [8, 10, 'F'], [10, 11, 'V'], [10, 12, 'F'],
      [2, 13, ''], [7, 13, ''], [9, 13, ''], [11, 13, ''], [12, 13, '']],
  },
  {
    archivo: 'cfg-M3-ApiCliente.png',
    titulo: 'M3 · ApiCliente._enviarCrudo (comunicación con el servidor)',
    ancho: 1000, alto: 1500,
    // Todas las salidas (throw / return) convergen en un nodo de salida virtual que no se dibuja: se cuenta en N y E.
    salidaVirtual: 7,
    nodos: [
      { id: 1, x: 420, y: 45, t: 'd', et: 'P1: _token == null ?' },
      { id: 22, x: 200, y: 125, t: 'c', et: 'token = null' },
      { id: 23, x: 640, y: 125, t: 'c', et: 'token = await _token()' },
      { id: 2, x: 420, y: 205, t: 'd', et: 'P2: token != null ?' },
      { id: 24, x: 700, y: 285, t: 'c', et: 'cabeceras += Authorization' },
      { id: 3, x: 420, y: 365, t: 'c', et: 'await peticion().timeout(4 s)' },
      { id: 4, x: 420, y: 445, t: 'd', et: 'P3: ¿lanzó Exception? (red/tiempo)' },
      { id: 5, x: 800, y: 445, t: 'f', et: 'throw sinConexion' },
      { id: 6, x: 420, y: 525, t: 'd', et: 'P4: status == 401 ?' },
      { id: 7, x: 800, y: 525, t: 'f', et: 'throw «sesión venció»' },
      { id: 8, x: 420, y: 605, t: 'd', et: 'P5: status == 403 ?' },
      { id: 9, x: 800, y: 605, t: 'f', et: 'throw «sin permiso»' },
      { id: 10, x: 420, y: 685, t: 'd', et: 'P6: status == 503 ?' },
      { id: 11, x: 800, y: 685, t: 'f', et: 'throw «sin Firebase»' },
      { id: 12, x: 420, y: 765, t: 'd', et: 'P7: status ∈ {400,409,429} ?' },
      { id: 13, x: 420, y: 855, t: 'c', et: 'cuerpo = _cuerpo(respuesta)' },
      { id: 14, x: 420, y: 935, t: 'd', et: 'P8: cuerpo != null ?' },
      { id: 15, x: 420, y: 1015, t: 'd', et: 'P9: error is String ?' },
      { id: 16, x: 420, y: 1095, t: 'd', et: 'P10: error.isNotEmpty ?' },
      { id: 17, x: 800, y: 1095, t: 'f', et: 'throw mensaje del servidor' },
      { id: 18, x: 420, y: 1195, t: 'd', et: 'P11: status < 200 ?' },
      { id: 19, x: 420, y: 1275, t: 'd', et: 'P12: status >= 300 ?' },
      { id: 20, x: 800, y: 1235, t: 'f', et: 'throw «respondió N»' },
      { id: 21, x: 420, y: 1370, t: 'f', et: 'return respuesta' },
    ],
    aristas: [[1, 23, 'F'], [1, 22, 'V'], [23, 2, ''], [22, 2, ''], [2, 24, 'V'], [2, 3, 'F'], [24, 3, ''], [3, 4, ''], [4, 5, 'V'], [4, 6, 'F'],
      [6, 7, 'V'], [6, 8, 'F'], [8, 9, 'V'], [8, 10, 'F'], [10, 11, 'V'], [10, 12, 'F'], [12, 13, 'V'], [12, 18, 'F'], [13, 14, ''], [14, 15, 'V'], [14, 18, 'F'],
      [15, 16, 'V'], [15, 18, 'F'], [16, 17, 'V'], [16, 18, 'F'], [18, 20, 'V'], [18, 19, 'F'], [19, 20, 'V'], [19, 21, 'F']],
  },
];

function svg(g) {
  const porId = new Map(g.nodos.map((n) => [n.id, n]));
  const N = g.nodos.length + (g.salidaVirtual ? 1 : 0);
  const E = g.aristas.length + (g.salidaVirtual || 0);
  const V = E - N + 2;
  const colores = { c: '#e8f1fb', d: '#fff3cd', f: '#e2f0d9' };
  const lineas = g.aristas.map(([a, b, et]) => {
    const A = porId.get(a), B = porId.get(b);
    const x1 = A.x, y1 = A.y + 18, x2 = B.x, y2 = B.y - 18;
    const dx = x2 - x1, dy = y2 - y1;
    const c1 = `${x1},${y1 + Math.max(10, dy / 3)}`;
    const c2 = `${x2},${y2 - Math.max(10, dy / 3)}`;
    const curva = dy < 30 ? `M ${x1} ${A.y} C ${x1 + dx / 2} ${A.y + 20}, ${x2 - dx / 2} ${B.y - 20}, ${x2} ${B.y}` : `M ${x1} ${y1} C ${c1}, ${c2}, ${x2} ${y2}`;
    const mx = (x1 + x2) / 2 + (dx === 0 ? 14 : 0), my = (y1 + y2) / 2;
    return `<path d="${curva}" fill="none" stroke="#444" stroke-width="1.6" marker-end="url(#flecha)"/>` +
      (et ? `<text x="${mx + 4}" y="${my}" font-size="13" font-weight="700" fill="#b00020">${et}</text>` : '');
  }).join('\n');
  const nodos = g.nodos.map((n) => {
    const w = 240;
    const forma = n.t === 'd'
      ? `<polygon points="${n.x},${n.y - 22} ${n.x + w / 2},${n.y} ${n.x},${n.y + 22} ${n.x - w / 2},${n.y}" fill="${colores.d}" stroke="#7a6a00" stroke-width="1.5"/>`
      : `<rect x="${n.x - w / 2 + 20}" y="${n.y - 18}" width="${w - 40}" height="36" rx="${n.t === 'f' ? 18 : 6}" fill="${colores[n.t]}" stroke="#355e8c" stroke-width="1.5"/>`;
    return `${forma}<text x="${n.x}" y="${n.y + 4}" font-size="12" text-anchor="middle" fill="#111">${n.et.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</text>` +
      `<circle cx="${n.x - (n.t === 'd' ? w / 2 - 6 : w / 2 - 28)}" cy="${n.y - 14}" r="11" fill="#355e8c"/><text x="${n.x - (n.t === 'd' ? w / 2 - 6 : w / 2 - 28)}" y="${n.y - 10}" font-size="11" fill="#fff" text-anchor="middle">${n.id}</text>`;
  }).join('\n');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${g.ancho}" height="${g.alto + 60}" viewBox="0 0 ${g.ancho} ${g.alto + 60}" font-family="Segoe UI, Arial, sans-serif">
<defs><marker id="flecha" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto"><path d="M0,0 L10,4 L0,8 z" fill="#444"/></marker></defs>
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="20" y="28" font-size="17" font-weight="700" fill="#1F4E79">${g.titulo}</text>
<text x="20" y="48" font-size="13" fill="#333">Nodos N = ${N} · Aristas E = ${E} · Complejidad ciclomática V(G) = E − N + 2 = ${V}</text>
<g transform="translate(0,30)">${lineas}\n${nodos}</g>
</svg>`;
}

const navegador = await chromium.launch({ executablePath: CHROME });
for (const g of grafos) {
  const contenido = svg(g);
  fs.writeFileSync(path.join(SALIDA, g.archivo.replace('.png', '.svg')), contenido);
  const pagina = await navegador.newPage({ viewport: { width: g.ancho, height: g.alto + 60 } });
  await pagina.setContent(`<html><body style="margin:0">${contenido}</body></html>`);
  await pagina.screenshot({ path: path.join(SALIDA, g.archivo) });
  await pagina.close();
  const N = g.nodos.length + (g.salidaVirtual ? 1 : 0), E = g.aristas.length + (g.salidaVirtual || 0);
  console.log(`${g.archivo}: N=${N} E=${E} V(G)=${E - N + 2}`);
}
await navegador.close();
