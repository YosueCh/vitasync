// PRÁCTICA 12 · Fase 2 · Muestrea CPU y memoria de la app en el emulador/teléfono con adb, cada segundo.
//   node scripts/practica12/perfil-adb.mjs <adb.exe> <paquete> <salida.csv> [segundos=240]
// CPU: «top» (% de un núcleo; con varios núcleos puede pasar de 100). Memoria: PSS total de «dumpsys meminfo» en MB.
// Al terminar guarda también «dumpsys gfxinfo» (fotogramas totales y con jank) en <salida>.gfxinfo.txt.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

const [ADB, PAQUETE, SALIDA, SEG = '240'] = process.argv.slice(2);
if (!ADB || !PAQUETE || !SALIDA) { console.error('Uso: node perfil-adb.mjs <adb> <paquete> <salida.csv> [segundos]'); process.exit(2); }
const adb = (...a) => { try { return execFileSync(ADB, a, { encoding: 'utf8', timeout: 8000 }); } catch { return ''; } };
fs.writeFileSync(SALIDA, 'epoch_ms,segundo,cpu_pct,pss_mb,rss_mb\n');
const t0 = Date.now();
while ((Date.now() - t0) / 1000 < Number(SEG)) {
  const pid = adb('shell', 'pidof', PAQUETE).trim().split(/\s+/)[0];
  if (pid) {
    const top = adb('shell', 'top', '-b', '-n', '1', '-p', pid).split('\n').find((l) => l.trim().startsWith(pid)) || '';
    const cols = top.trim().split(/\s+/);
    const cpu = parseFloat(cols[8]); // %CPU en el formato estándar de top de Android
    const mem = adb('shell', 'dumpsys', 'meminfo', pid);
    const pss = /TOTAL PSS:\s+(\d+)/.exec(mem)?.[1] ?? /TOTAL\s+(\d+)/.exec(mem)?.[1];
    const rss = /TOTAL RSS:\s+(\d+)/.exec(mem)?.[1];
    fs.appendFileSync(SALIDA, `${Date.now()},${((Date.now() - t0) / 1000).toFixed(1)},${Number.isFinite(cpu) ? cpu : ''},${pss ? (pss / 1024).toFixed(1) : ''},${rss ? (rss / 1024).toFixed(1) : ''}\n`);
  }
  await new Promise((r) => setTimeout(r, 600));
}
fs.writeFileSync(SALIDA + '.gfxinfo.txt', adb('shell', 'dumpsys', 'gfxinfo', PAQUETE));
console.log('listo', SALIDA);
