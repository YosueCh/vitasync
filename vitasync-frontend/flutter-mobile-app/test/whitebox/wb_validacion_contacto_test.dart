// PRÁCTICA 11 · Fase 2 · Método 1 (VALIDACIÓN): ReglasContacto.validar(nombre, telefono)
//
// Código (lib/models/contacto.dart):
//   L1  final errores = <String, String>{};
//   L2  final n = nombre.trim();
//   L3  if (n.length < 2 || n.length > 60) errores['nombre'] = ...;      ← decisión D1 (2 condiciones: C1, C2)
//   L4  if (!_telefono.hasMatch(normalizarTelefono(telefono))) ...;      ← decisión D2 (1 condición: C3)
//   L5  return errores;
//
// Complejidad ciclomática V(G) = decisiones + 1 = (D1: 2 condiciones + D2: 1) + 1 = 4
// Caminos independientes (conjunto base):
//   P1  D1=F, D2=F  → sin errores
//   P2  C1=T        → error de nombre por corto (C2 no se evalúa: cortocircuito)
//   P3  C1=F, C2=T  → error de nombre por largo
//   P4  D1=F, D2=T  → error de teléfono
// Cobertura de condiciones: C1∈{T,F}, C2∈{T,F}, C3∈{T,F}.
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/models/contacto.dart';

void main() {
  const tel = '4421234567';
  const nombre = 'Mamá';

  group('Caminos independientes (conjunto base, V(G)=4)', () {
    test('P1: nombre y teléfono válidos → mapa vacío (D1=F, D2=F)', () {
      expect(ReglasContacto.validar(nombre, tel), isEmpty);
    });

    test('P2: nombre de 1 carácter → solo error de nombre (C1=T)', () {
      final e = ReglasContacto.validar('A', tel);
      expect(e.keys, ['nombre']);
    });

    test('P3: nombre de 61 caracteres → solo error de nombre (C1=F, C2=T)', () {
      final e = ReglasContacto.validar('A' * 61, tel);
      expect(e.keys, ['nombre']);
    });

    test('P4: teléfono inválido con nombre válido → solo error de teléfono (D2=T)', () {
      final e = ReglasContacto.validar(nombre, 'abc');
      expect(e.keys, ['telefono']);
    });
  });

  group('Camino combinado (no independiente, pero real): ambos campos inválidos', () {
    test('se reportan los dos errores a la vez', () {
      final e = ReglasContacto.validar('', '');
      expect(e.keys.toSet(), {'nombre', 'telefono'});
    });
  });

  group('Valores límite del nombre (frontera de C1: <2 y C2: >60)', () {
    for (final caso in {1: false, 2: true, 3: true, 59: true, 60: true, 61: false}.entries) {
      test('${caso.key} caracteres → ${caso.value ? 'válido' : 'inválido'}', () {
        expect(ReglasContacto.validar('N' * caso.key, tel).containsKey('nombre'), !caso.value);
      });
    }
    test('los espacios de los extremos no cuentan (trim): "  A  " es 1 carácter → inválido', () {
      expect(ReglasContacto.validar('  A  ', tel).containsKey('nombre'), isTrue);
    });
    test('"  AB  " es 2 caracteres tras el trim → válido', () {
      expect(ReglasContacto.validar('  AB  ', tel), isEmpty);
    });
    test('cadena vacía y solo espacios → inválido', () {
      expect(ReglasContacto.validar('', tel).containsKey('nombre'), isTrue);
      expect(ReglasContacto.validar('     ', tel).containsKey('nombre'), isTrue);
    });
  });

  group('Valores límite del teléfono (7 a 15 dígitos, "+" opcional al inicio)', () {
    for (final caso in {6: false, 7: true, 8: true, 14: true, 15: true, 16: false}.entries) {
      test('${caso.key} dígitos → ${caso.value ? 'válido' : 'inválido'}', () {
        expect(ReglasContacto.validar(nombre, '1' * caso.key).containsKey('telefono'), !caso.value);
      });
    }
    test('con "+" y 12 dígitos → válido; con "+" y 6 → inválido', () {
      expect(ReglasContacto.validar(nombre, '+524421234567'), isEmpty);
      expect(ReglasContacto.validar(nombre, '+123456').containsKey('telefono'), isTrue);
    });
    test('separadores (espacios, guiones, paréntesis, puntos) se ignoran: "(442) 123-4567"', () {
      expect(ReglasContacto.validar(nombre, '(442) 123-4567'), isEmpty);
      expect(ReglasContacto.validar(nombre, '442.123.4567'), isEmpty);
    });
    test('"+" en medio o doble "+", letras y símbolos → inválido', () {
      for (final malo in ['44+21234567', '++4421234567', '44212a4567', '4421234567x', '442#1234567', '']) {
        expect(ReglasContacto.validar(nombre, malo).containsKey('telefono'), isTrue, reason: malo);
      }
    });
  });

  group('Excepciones y robustez (no debe lanzar nunca)', () {
    test('entradas enormes no lanzan ni se cuelgan (regex sin retroceso catastrófico)', () {
      final reloj = Stopwatch()..start();
      expect(() => ReglasContacto.validar('x' * 1000000, '1' * 1000000), returnsNormally);
      expect(reloj.elapsedMilliseconds, lessThan(2000));
    });
    test('caracteres Unicode raros (emoji, ñ, acentos) no lanzan', () {
      expect(() => ReglasContacto.validar('Ñandú 👩‍⚕️', '٤٤٢١٢٣٤٥٦٧'), returnsNormally);
    });
    test('dígitos NO latinos (árabes) se rechazan como teléfono: [0-9] es solo ASCII', () {
      expect(ReglasContacto.validar(nombre, '٤٤٢١٢٣٤٥٦٧').containsKey('telefono'), isTrue);
    });
  });
}
