// PRÁCTICAS 13 y 14 · AUT-02 · Pruebas UNITARIAS de la lógica de negocio que valida los datos antes de enviarlos:
// ReglasMetas (rangos de las metas) y ReglasContacto (nombre y teléfono). Son las mismas reglas que aplica el servidor.
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/models/contacto.dart';
import 'package:vitasync_mobile/models/metas_cuenta.dart';

void main() {
  group('AUT-02 · ReglasMetas: entrada válida, nula y fuera de rango', () {
    test('valores dentro del rango (incluidos los límites) → sin error', () {
      expect(ReglasMetas.validarPasos(1000), isNull);
      expect(ReglasMetas.validarPasos(50000), isNull);
      expect(ReglasMetas.validarCalorias(100), isNull);
      expect(ReglasMetas.validarCalorias(5000), isNull);
      expect(ReglasMetas.validarSueno(4.0), isNull);
      expect(ReglasMetas.validarSueno(12.0), isNull);
      expect(ReglasMetas.validarPasos(10000), isNull);
    });

    test('valor nulo (campo vacío) → error en los tres campos', () {
      expect(ReglasMetas.validarPasos(null), isNotNull);
      expect(ReglasMetas.validarCalorias(null), isNotNull);
      expect(ReglasMetas.validarSueno(null), isNotNull);
    });

    test('un valor justo por debajo y por encima de cada límite → error con el rango en el mensaje', () {
      expect(ReglasMetas.validarPasos(999), 'Pasos: de 1000 a 50000.');
      expect(ReglasMetas.validarPasos(50001), 'Pasos: de 1000 a 50000.');
      expect(ReglasMetas.validarCalorias(99), 'Calorías: de 100 a 5000.');
      expect(ReglasMetas.validarCalorias(5001), 'Calorías: de 100 a 5000.');
      expect(ReglasMetas.validarSueno(3.9), 'Sueño: de 4 a 12 horas.');
      expect(ReglasMetas.validarSueno(12.1), 'Sueño: de 4 a 12 horas.');
    });

    test('valores absurdos: cero, negativos y enormes', () {
      for (final v in [0, -1, -50000, 2000000000]) {
        expect(ReglasMetas.validarPasos(v), isNotNull, reason: '$v pasos');
        expect(ReglasMetas.validarCalorias(v), isNotNull, reason: '$v calorías');
      }
      expect(ReglasMetas.validarSueno(double.nan), isNotNull, reason: 'NaN no es un número de horas válido');
      expect(ReglasMetas.validarSueno(double.infinity), isNotNull);
    });
  });

  group('AUT-02 · ReglasContacto: nombre y teléfono', () {
    test('datos válidos → mapa de errores vacío', () {
      expect(ReglasContacto.validar('Mamá', '442 123 4567'), isEmpty);
      expect(ReglasContacto.validar('Ana', '+52 (442) 123-4567'), isEmpty);
    });

    test('nombre vacío, de un carácter, solo espacios y de 61 caracteres → error de nombre', () {
      for (final n in ['', 'A', '   ', 'x' * 61]) {
        expect(ReglasContacto.validar(n, '4421234567').keys, contains('nombre'), reason: '«$n»');
      }
      expect(ReglasContacto.validar('x' * 60, '4421234567'), isEmpty, reason: '60 caracteres es el máximo permitido');
      expect(ReglasContacto.validar('Al', '4421234567'), isEmpty, reason: '2 caracteres es el mínimo');
    });

    test('teléfono vacío, con letras, de 6 o de 16 dígitos → error de teléfono', () {
      for (final t in ['', 'abcdefghij', '123456', '1234567890123456', '44212345+67']) {
        expect(ReglasContacto.validar('Mamá', t).keys, contains('telefono'), reason: '«$t»');
      }
      expect(ReglasContacto.validar('Mamá', '1234567'), isEmpty, reason: '7 dígitos es el mínimo');
      expect(ReglasContacto.validar('Mamá', '123456789012345'), isEmpty, reason: '15 dígitos es el máximo');
    });

    test('nombre y teléfono malos a la vez → un error por campo', () {
      expect(ReglasContacto.validar('', '').keys, unorderedEquals(['nombre', 'telefono']));
    });

    test('normalizarTelefono quita espacios, paréntesis, puntos y guiones, pero conserva el +', () {
      expect(ReglasContacto.normalizarTelefono('+52 (442) 123-45.67'), '+524421234567');
    });
  });
}
