// Rúbrica C3: ¿la PWA abre SIN conexión después de haberse visitado una vez? Sirve vitasync-frontend/public/movil en /movil/, la visita
// (el service worker guarda el cascarón), corta la red, recarga y mira si la app arranca.
//   node scripts/entrega-final/verificar-offline.mjs <carpeta-movil> <salida-png> <playwright-core> <chrome.exe>
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRequire } from 'node:module';

const [CARPETA, PNG, PLAYWRIGHT, CHROME] = process.argv.slice(2);
const tipos = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.wasm': 'application/wasm' };
const srv = http.createServer((q, r) => {
  let rel = decodeURIComponent(q.url.split('?')[0]).replace(/^\/movil\/?/, '') || 'index.html';
  const f = path.join(CARPETA, rel);
  if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { r.writeHead(404); return r.end(); }
  r.writeHead(200, { 'content-type': tipos[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(r);
}).listen(0);
const URL_ = `http://localhost:${srv.address().port}/movil/`;
const { chromium } = createRequire(import.meta.url)(PLAYWRIGHT);
const perfil = fs.mkdtempSync(path.join(process.env.TEMP || '/tmp', 'off-'));
const ctx = await chromium.launchPersistentContext(perfil, { executablePath: CHROME, viewport: { width: 390, height: 844 } });
const p = await ctx.newPage();
await p.goto(URL_, { waitUntil: 'load' });
await p.waitForTimeout(6000); // el service worker se instala y guarda el cascarón
await p.reload({ waitUntil: 'load' }); // segunda visita EN LÍNEA: a partir de aquí la página queda controlada por el service worker
await p.waitForTimeout(8000);
const sw = await p.evaluate(async () => { const r = await navigator.serviceWorker.getRegistration(); const c = await caches.keys(); return { activo: !!r?.active, controlaLaPagina: !!navigator.serviceWorker.controller, caches: c }; });
const entradas = await p.evaluate(async () => { let n = 0; for (const k of await caches.keys()) n += (await (await caches.open(k)).keys()).length; return n; });
await ctx.setOffline(true);
let resultado = { serviceWorker: sw, recursosEnCache: entradas };
try {
  await p.reload({ waitUntil: 'load', timeout: 20000 });
  await p.waitForTimeout(4000);
  resultado.arrancaSinConexion = await p.evaluate(() => !!document.querySelector('flt-glass-pane'));
  await p.screenshot({ path: PNG });
} catch (e) { resultado.arrancaSinConexion = false; resultado.error = String(e.message).split('\n')[0]; }
console.log(JSON.stringify(resultado, null, 2));
await ctx.close(); srv.close();
