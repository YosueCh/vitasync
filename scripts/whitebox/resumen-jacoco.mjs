// Resume un informe JaCoCo (jacoco.xml) por paquete y por clase: instrucciones, ramas, líneas y complejidad ciclomática.
//   node scripts/whitebox/resumen-jacoco.mjs <jacoco.xml> [filtroDePaquete] [--clases]
import fs from 'node:fs';

const [xmlRuta, filtro = '', ...banderas] = process.argv.slice(2);
if (!xmlRuta) {
  console.error('Uso: node resumen-jacoco.mjs <jacoco.xml> [filtro] [--clases]');
  process.exit(2);
}
const xml = fs.readFileSync(xmlRuta, 'utf8');

function contadores(bloque) {
  const r = {};
  for (const m of bloque.matchAll(/<counter type="(\w+)" missed="(\d+)" covered="(\d+)"\/>/g)) {
    r[m[1]] = { perdidos: Number(m[2]), cubiertos: Number(m[3]) };
  }
  return r;
}
const pct = (c) => (!c || c.perdidos + c.cubiertos === 0 ? '  n/a' : ((100 * c.cubiertos) / (c.perdidos + c.cubiertos)).toFixed(1).padStart(5) + '%');
const num = (c) => (c ? `${c.cubiertos}/${c.cubiertos + c.perdidos}` : '-');

const filas = [];
for (const p of xml.matchAll(/<package name="([^"]+)">([\s\S]*?)<\/package>/g)) {
  const nombre = p[1].replaceAll('/', '.').replace('com.vitasync.backend.', '');
  if (filtro && !nombre.includes(filtro)) continue;
  const cuerpo = p[2];
  const clases = [...cuerpo.matchAll(/<class name="([^"]+)"[^>]*>([\s\S]*?)<\/class>/g)];
  const totalPaquete = contadores(cuerpo.replace(/<class [\s\S]*?<\/class>/g, '').replace(/<sourcefile[\s\S]*?<\/sourcefile>/g, ''));
  filas.push({ nombre, total: totalPaquete, clases: clases.map((c) => ({ nombre: c[1].split('/').pop(), c: contadores(c[2].replace(/<method [\s\S]*?<\/method>/g, '')) })) });
}
console.log('paquete'.padEnd(26), 'instr'.padStart(11), '%'.padStart(7), 'ramas'.padStart(9), '%'.padStart(7), 'líneas'.padStart(10), 'CCN');
for (const f of filas) {
  console.log(f.nombre.padEnd(26), num(f.total.INSTRUCTION).padStart(11), pct(f.total.INSTRUCTION).padStart(7), num(f.total.BRANCH).padStart(9), pct(f.total.BRANCH).padStart(7), num(f.total.LINE).padStart(10), f.total.COMPLEXITY ? f.total.COMPLEXITY.perdidos + f.total.COMPLEXITY.cubiertos : '-');
  if (banderas.includes('--clases')) {
    for (const c of f.clases) {
      console.log('   ' + c.nombre.padEnd(38), num(c.c.INSTRUCTION).padStart(11), pct(c.c.INSTRUCTION).padStart(7), num(c.c.BRANCH).padStart(9), pct(c.c.BRANCH).padStart(7), num(c.c.LINE).padStart(10));
    }
  }
}
const g = contadores(xml.replace(/<package [\s\S]*?<\/package>/g, ''));
console.log('-'.repeat(80));
console.log('TOTAL'.padEnd(26), num(g.INSTRUCTION).padStart(11), pct(g.INSTRUCTION).padStart(7), num(g.BRANCH).padStart(9), pct(g.BRANCH).padStart(7), num(g.LINE).padStart(10));
