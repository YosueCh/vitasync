// Diagnóstico de la pirámide de pruebas de VitaSync (Actividad 2): cuenta las pruebas de cada archivo y las
// clasifica por nivel. No ejecuta nada: solo lee el código. Úsalo junto con los resultados de «mvn test»,
// «flutter test» y «dart test» (los totales de ejecución están en el README de pruebas).
//
//   node scripts/diagnostico-piramide.mjs            (tabla)
//   node scripts/diagnostico-piramide.mjs --json     (datos para otros scripts)
import fs from 'node:fs';
import path from 'node:path';

const RAIZ = path.resolve(import.meta.dirname, '..');

/** Clasificación (criterio explícito, ver PIRAMIDE-DE-PRUEBAS.md):
 *  unitaria    = una clase o función sola, con sus dependencias simuladas o en memoria;
 *  integracion = varias piezas reales juntas (controlador + filtro + servicio, o pantalla + repositorio);
 *  e2e         = el sistema de punta a punta (app real en un emulador, o servidor real con personas reales). */
const REGLAS = [
  // --- backend (JUnit): cada clase de prueba se clasifica a mano porque el nombre no lo dice
  { patron: /vitasync-backend\/src\/test\/.*\/(PinServiceTest|ChatServiceTest|FirmwareServiceTest|SmartwatchServiceTest|SmartwatchHistorialTest|EliminarCuentaTest)\.java$/, nivel: 'unitaria', capa: 'Backend' },
  { patron: /vitasync-backend\/src\/test\/.*\/(ChatControllerTest|ControlDeAccesoTest|ContactosTest|CajaNegraApiTest)\.java$/, nivel: 'integracion', capa: 'Backend' },
  // --- firmware simulado
  { patron: /vitasync-firmware-sim\/test\/.*_test\.dart$/, nivel: 'unitaria', capa: 'Firmware' },
  // --- app móvil
  { patron: /flutter-mobile-app\/test\/(servicios_test|sqlite_dao_test|sin_datos_test)\.dart$/, nivel: 'unitaria', capa: 'App móvil' },
  { patron: /flutter-mobile-app\/test\/.*_test\.dart$/, nivel: 'integracion', capa: 'App móvil' },
  { patron: /flutter-mobile-app\/integration_test\/.*_test\.dart$/, nivel: 'e2e', capa: 'App móvil' },
  // --- Angular
  { patron: /vitasync-frontend\/src\/.*\.spec\.ts$/, nivel: 'unitaria', capa: 'Web (Angular)' },
];

function archivos(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    if (['node_modules', 'build', 'target', '.dart_tool', 'dist', '.angular', '.git'].includes(e.name)) return [];
    const ruta = path.join(dir, e.name);
    return e.isDirectory() ? archivos(ruta) : [ruta];
  });
}

function contar(ruta, texto) {
  const sinComentarios = texto.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  if (ruta.endsWith('.java')) return (sinComentarios.match(/^\s*@Test\b/gm) ?? []).length;
  if (ruta.endsWith('.dart')) return (sinComentarios.match(/^\s*(?:test|testWidgets)\s*\(/gm) ?? []).length;
  if (ruta.endsWith('.ts')) return (sinComentarios.match(/^\s*(?:it|test)\s*\(/gm) ?? []).length;
  return 0;
}

const filas = [];
for (const ruta of archivos(RAIZ)) {
  const rel = path.relative(RAIZ, ruta).replaceAll('\\', '/');
  const regla = REGLAS.find((r) => r.patron.test(rel));
  if (!regla) continue;
  const n = contar(rel, fs.readFileSync(ruta, 'utf8'));
  if (n > 0) filas.push({ archivo: rel, capa: regla.capa, nivel: regla.nivel, pruebas: n });
}

// Pruebas de punta a punta que son SCRIPTS (cada «caso» es una llamada de registro, no una función de prueba)
const scripts = [
  ['vitasync-backend/seguridad-e2e/prueba-seguridad.mjs', 'Backend', 'e2e', /espera\('E2E-|registrar\('E2E-/g],
  ['vitasync-backend/seguridad-e2e/prueba-reglas.mjs', 'Backend', 'e2e', /await caso\('RV-/g],
];
for (const [rel, capa, nivel, re] of scripts) {
  const ruta = path.join(RAIZ, rel);
  if (!fs.existsSync(ruta)) continue;
  filas.push({ archivo: rel, capa, nivel, pruebas: (fs.readFileSync(ruta, 'utf8').match(re) ?? []).length });
}

const NIVELES = ['unitaria', 'integracion', 'e2e'];
const total = filas.reduce((a, f) => a + f.pruebas, 0);
const porNivel = Object.fromEntries(NIVELES.map((n) => [n, filas.filter((f) => f.nivel === n).reduce((a, f) => a + f.pruebas, 0)]));
const ci = fs.existsSync(path.join(RAIZ, '.github/workflows/pruebas.yml'));

if (process.argv.includes('--json')) {
  console.log(JSON.stringify({ filas, porNivel, total, integracionContinua: ci }, null, 2));
} else {
  console.log('PIRÁMIDE DE PRUEBAS DE VITASYNC\n');
  for (const f of filas.sort((a, b) => a.nivel.localeCompare(b.nivel) || a.capa.localeCompare(b.capa))) {
    console.log(`${f.nivel.padEnd(12)} ${f.capa.padEnd(14)} ${String(f.pruebas).padStart(3)}  ${f.archivo}`);
  }
  console.log('\nResumen por nivel');
  for (const n of NIVELES) console.log(`  ${n.padEnd(12)} ${String(porNivel[n]).padStart(3)}  (${((porNivel[n] / total) * 100).toFixed(1)} %)`);
  console.log(`  ${'TOTAL'.padEnd(12)} ${String(total).padStart(3)}`);
  console.log(`\nEjecución automática (CI): ${ci ? 'sí (.github/workflows/pruebas.yml)' : 'NO hay'}`);
}
