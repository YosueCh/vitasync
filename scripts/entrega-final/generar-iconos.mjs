// Genera los íconos de la PWA de VitaSync (corazón con línea de pulso) con un navegador:
//   node scripts/entrega-final/generar-iconos.mjs <carpeta-icons> <ruta-playwright-core> <chrome.exe>
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const [SALIDA, PLAYWRIGHT, CHROME] = process.argv.slice(2);
if (!SALIDA || !PLAYWRIGHT || !CHROME) { console.error('Uso: node generar-iconos.mjs <salida> <playwright-core> <chrome>'); process.exit(2); }
const { chromium } = createRequire(import.meta.url)(PLAYWRIGHT);

const TEAL = '#00897B';
// «escala» reduce el símbolo para la versión maskable (Android recorta hasta el 20 % de los bordes).
const svg = (tam, { maskable = false } = {}) => {
  const esc = maskable ? 0.62 : 0.8;
  const fondo = maskable
    ? `<rect width="512" height="512" fill="${TEAL}"/>`
    : `<rect width="512" height="512" rx="112" fill="${TEAL}"/>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${tam}" height="${tam}" viewBox="0 0 512 512">
${fondo}
<g transform="translate(256 262) scale(${esc}) translate(-256 -262)">
<path d="M256 410 C110 305 85 190 148 138 C198 96 246 124 256 162 C266 124 314 96 364 138 C427 190 402 305 256 410 Z" fill="#FFFFFF"/>
<polyline points="112,262 196,262 226,204 270,330 302,262 400,262" fill="none" stroke="${TEAL}" stroke-width="22" stroke-linecap="round" stroke-linejoin="round"/>
</g></svg>`;
};
const navegador = await chromium.launch({ executablePath: CHROME });
const hacer = async (archivo, tam, opciones) => {
  const p = await navegador.newPage({ viewport: { width: tam, height: tam } });
  await p.setContent(`<html><body style="margin:0;background:transparent">${svg(tam, opciones)}</body></html>`);
  await p.screenshot({ path: path.join(SALIDA, archivo), omitBackground: true });
  await p.close();
  console.log('listo', archivo);
};
await hacer('Icon-192.png', 192);
await hacer('Icon-512.png', 512);
await hacer('Icon-maskable-192.png', 192, { maskable: true });
await hacer('Icon-maskable-512.png', 512, { maskable: true });
await hacer('../favicon.png', 64);
await navegador.close();
