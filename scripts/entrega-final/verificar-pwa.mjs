// Verifica en un navegador real (Chrome) la integración de la vista móvil con el sitio (Parcial 3 de la propuesta):
//  1) redirección de teléfonos a /movil/ y respeto de ?escritorio=1; 2) manifiesto y service worker; 3) instalabilidad de la PWA (CDP);
//  4) capturas de la vista móvil en varios tamaños de pantalla.
//   node scripts/entrega-final/verificar-pwa.mjs <sitio> <carpeta-salida> <playwright-core> <chrome.exe>
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const [SITIO, SALIDA, PLAYWRIGHT, CHROME] = process.argv.slice(2);
if (!SITIO || !SALIDA || !PLAYWRIGHT || !CHROME) { console.error('Uso: node verificar-pwa.mjs <sitio> <salida> <playwright-core> <chrome>'); process.exit(2); }
fs.mkdirSync(SALIDA, { recursive: true });
const { chromium } = createRequire(import.meta.url)(PLAYWRIGHT);
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
const resultado = { fecha: new Date().toISOString(), sitio: SITIO, redireccion: {}, pwa: {}, capturas: [] };
const navegador = await chromium.launch({ executablePath: CHROME });
const ruta = (p) => new URL(p.url()).pathname;

async function abrir(opciones, url) {
  const ctx = await navegador.newContext(opciones);
  const p = await ctx.newPage();
  await p.goto(url, { waitUntil: 'load' });
  await p.waitForTimeout(1500);
  return { ctx, p };
}

// 1) Redirección
{
  const e = await abrir({ viewport: { width: 1280, height: 800 } }, SITIO + '/');
  resultado.redireccion['computadora abre «/»'] = ruta(e.p); await e.ctx.close();
  const a = await abrir({ viewport: { width: 390, height: 844 }, userAgent: ANDROID, isMobile: true, hasTouch: true }, SITIO + '/');
  resultado.redireccion['Android abre «/»'] = ruta(a.p); await a.ctx.close();
  const i = await abrir({ viewport: { width: 390, height: 844 }, userAgent: IPHONE, isMobile: true, hasTouch: true }, SITIO + '/nosotros');
  resultado.redireccion['iPhone abre «/nosotros»'] = ruta(i.p); await i.ctx.close();
  const x = await abrir({ viewport: { width: 390, height: 844 }, userAgent: ANDROID, isMobile: true }, SITIO + '/?escritorio=1');
  resultado.redireccion['Android abre «/?escritorio=1»'] = ruta(x.p); await x.ctx.close();
  const d = await abrir({ viewport: { width: 1280, height: 800 } }, SITIO + '/movil/');
  resultado.redireccion['computadora abre «/movil/» directamente'] = ruta(d.p); await d.ctx.close();
}

// 2 y 3) Manifiesto, service worker e instalabilidad
{
  // Perfil persistente: un contexto normal de Playwright es de incógnito y Chrome no ofrece instalar desde incógnito.
  const perfil = fs.mkdtempSync(path.join(process.env.TEMP || '/tmp', 'pwa-'));
  const ctx = await chromium.launchPersistentContext(perfil, { executablePath: CHROME, viewport: { width: 390, height: 844 }, userAgent: ANDROID, isMobile: true, hasTouch: true });
  const p = await ctx.newPage();
  await p.goto(SITIO + '/', { waitUntil: 'load' });
  await p.waitForTimeout(4000); // el service worker se registra al terminar de cargar
  const manifest = await p.evaluate(async () => (await fetch(document.querySelector('link[rel=manifest]').href)).json());
  const sw = await p.evaluate(async () => {
    const r = await navigator.serviceWorker.getRegistration();
    return r ? { alcance: r.scope, activo: !!(r.active || r.installing || r.waiting) } : null;
  });
  const cdp = await ctx.newCDPSession(p);
  const inst = await cdp.send('Page.getInstallabilityErrors');
  resultado.pwa = {
    manifiesto: { nombre: manifest.name, nombreCorto: manifest.short_name, modo: manifest.display, inicio: manifest.start_url, colorTema: manifest.theme_color, iconos: manifest.icons.map((i) => `${i.sizes} ${i.purpose || 'any'}`) },
    serviceWorker: sw,
    erroresDeInstalabilidad: inst.installabilityErrors.map((e) => e.errorId),
    instalable: inst.installabilityErrors.length === 0,
    https: new URL(SITIO).protocol === 'https:' || new URL(SITIO).hostname === 'localhost',
    titulo: await p.title(),
  };
  await ctx.close();
}

// 4) Capturas en tamaños reales de teléfonos
for (const [nombre, w, h] of [['Android pequeño 360x800', 360, 800], ['Android 412x915', 412, 915], ['iPhone 390x844', 390, 844], ['iPhone Pro Max 430x932', 430, 932]]) {
  const { ctx, p } = await abrir({ viewport: { width: w, height: h }, userAgent: nombre.startsWith('iPhone') ? IPHONE : ANDROID, isMobile: true, hasTouch: true, deviceScaleFactor: 2 }, SITIO + '/movil/');
  await p.waitForTimeout(2500);
  const archivo = `movil-${w}x${h}.png`;
  await p.screenshot({ path: path.join(SALIDA, archivo) });
  const desborde = await p.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  resultado.capturas.push({ dispositivo: nombre, archivo, desbordeHorizontal: desborde });
  await ctx.close();
}
await navegador.close();
fs.writeFileSync(path.join(SALIDA, 'verificacion-pwa.json'), JSON.stringify(resultado, null, 2));
console.log(JSON.stringify(resultado, null, 2));
