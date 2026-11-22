// Calcula la cobertura de INSTRUCCIONES (líneas ejecutables) y de RAMAS de un rango de líneas dentro de un archivo,
// a partir de un lcov.info (formato de Flutter/Dart generado con --coverage --branch-coverage).
//   node scripts/whitebox/cobertura-metodo.mjs <lcov.info> <archivo-fuente> <linea-inicio> <linea-fin> [etiqueta]
// Instrucciones: líneas «DA:n,hits» dentro del rango; cubierta si hits > 0.
// Ramas:        líneas «BRDA:n,bloque,rama,hits»; cubierta si hits > 0 (si es «-» o 0, no se ejecutó).
import fs from 'node:fs';

const [lcov, archivo, ini, fin, etiqueta = ''] = process.argv.slice(2);
if (!lcov || !archivo || !ini || !fin) {
  console.error('Uso: node cobertura-metodo.mjs <lcov.info> <archivo> <inicio> <fin> [etiqueta]');
  process.exit(2);
}
const a = Number(ini);
const b = Number(fin);
const norm = (s) => s.split(String.fromCharCode(92)).join('/'); // barra invertida de Windows → '/'
const lineas = fs.readFileSync(lcov, 'utf8').split(/\r?\n/);
let dentro = false;
const instr = [];
const ramas = [];
for (const l of lineas) {
  if (l.startsWith('SF:')) {
    dentro = norm(l.slice(3)).endsWith(norm(archivo));
  } else if (dentro && l.startsWith('DA:')) {
    const [n, h] = l.slice(3).split(',').map(Number);
    if (n >= a && n <= b) instr.push({ n, h });
  } else if (dentro && l.startsWith('BRDA:')) {
    const [n, blq, rama, h] = l.slice(5).split(',');
    if (Number(n) >= a && Number(n) <= b) ramas.push({ n: Number(n), blq, rama, h: h === '-' ? 0 : Number(h) });
  }
}
const pct = (c, t) => (t === 0 ? 'n/a' : ((100 * c) / t).toFixed(1) + ' %');
const ci = instr.filter((x) => x.h > 0).length;
const cr = ramas.filter((x) => x.h > 0).length;
console.log(JSON.stringify({
  metodo: etiqueta,
  archivo,
  rango: `${a}-${b}`,
  instrucciones: { cubiertas: ci, total: instr.length, porcentaje: pct(ci, instr.length) },
  ramas: { cubiertas: cr, total: ramas.length, porcentaje: pct(cr, ramas.length) },
  lineasSinCubrir: instr.filter((x) => x.h === 0).map((x) => x.n),
  ramasSinCubrir: ramas.filter((x) => x.h === 0).map((x) => `${x.n}:${x.blq}.${x.rama}`),
}, null, 2));
