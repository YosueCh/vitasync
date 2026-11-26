// Captura las pantallas interiores de la vista móvil (compilada con datos de muestra: --dart-define=MUESTRA=true --base-href /m/) en un
// navegador con tamaño de teléfono, activando el árbol de accesibilidad de Flutter Web para poder pulsar los controles por nombre.
//   node scripts/entrega-final/capturas-pantallas.mjs <carpeta-build-muestra> <salida> <playwright-core> <chrome.exe> [ancho=390] [alto=844]
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';

const [BUILD, SALIDA, PLAYWRIGHT, CHROME, ANCHO = '390', ALTO = '844'] = process.argv.slice(2);
fs.mkdirSync(SALIDA, { recursive: true });
const tipos = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.wasm': 'application/wasm', '.css': 'text/css' };
const srv = http.createServer((q, r) => {
  let rel = decodeURIComponent(q.url.split('?')[0]).replace(/^\/m\/?/, '');
  if (!rel) rel = 'index.html';
  const f = path.join(BUILD, rel);
  if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { r.writeHead(404); return r.end(); }
  r.writeHead(200, { 'content-type': tipos[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(r);
}).listen(0);
const puerto = srv.address().port;
const { chromium } = createRequire(import.meta.url)(PLAYWRIGHT);
const nav = await chromium.launch({ executablePath: CHROME });
const ctx = await nav.newContext({ viewport: { width: Number(ANCHO), height: Number(ALTO) }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36' });
const p = await ctx.newPage();
const hecho = [];
const foto = async (n) => { await p.waitForTimeout(900); await p.screenshot({ path: path.join(SALIDA, `${n}-${ANCHO}x${ALTO}.png`) }); hecho.push(n); };
await p.goto(`http://localhost:${puerto}/m/`);
await p.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 30000 });
await p.waitForTimeout(2500);
await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); // activa la accesibilidad
await p.waitForTimeout(1200);
// Flutter Web dibuja en un lienzo: se pulsa por coordenadas proporcionales al tamaño de la pantalla (probadas a 390×844).
const W = Number(ANCHO), H = Number(ALTO);
const clic = async (x, y) => { await p.mouse.click(x, y); await p.waitForTimeout(900); };
try {
  await foto('1-seleccionar-cuenta');
  await clic(W / 2, 224); // Ana Torres
  await foto('2-pin');
  for (const col of [0, 1, 2]) {} // (teclado 3×4, filas separadas 88 px)
  await clic(W / 2 - 88, 360); await clic(W / 2, 360); await clic(W / 2 + 88, 360); await clic(W / 2 - 88, 448); // 1 2 3 4
  await p.waitForTimeout(2500);
  await foto('3-resumen');
  const y = H - 38;
  for (const [n, k] of [['4-dispositivo', 1], ['5-chat', 2], ['6-contactos', 3]]) {
    await clic((W * (k + 0.5)) / 4, y);
    await p.waitForTimeout(1200);
    await foto(n);
  }
} catch (e) { console.error('Aviso:', String(e.message).split('\n')[0]); }
const desborde = await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
console.log(JSON.stringify({ capturas: hecho, desbordeHorizontal: desborde, ancho: ANCHO, alto: ALTO }));
await nav.close(); srv.close();
