import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/config/api_config.dart';
import 'package:vitasync_mobile/models/dispositivo.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/models/usuario.dart';

void main() {
  group('Metricas.fromJson (formato de MetricasDTO.java)', () {
    test('lee todos los campos, incluida la clave con ñ', () {
      final m = Metricas.fromJson({
        'pasos': 6320,
        'calorias': 412,
        'sueñoHoras': 7.2,
        'frecuenciaCardiaca': 78,
        'bateria': 87,
        'timestamp': '2026-09-21T10:00:00Z',
      });
      expect(m.pasos, 6320);
      expect(m.calorias, 412);
      expect(m.suenoHoras, 7.2);
      expect(m.frecuenciaCardiaca, 78);
      expect(m.bateria, 87);
    });

    test('un entero en sueñoHoras se convierte a double', () {
      final m = Metricas.fromJson({'sueñoHoras': 8});
      expect(m.suenoHoras, 8.0);
    });

    test('campos ausentes quedan en cero', () {
      final m = Metricas.fromJson({});
      expect(m.pasos, 0);
      expect(m.suenoHoras, 0.0);
    });
  });

  group('Dispositivo.fromJson (formato de DispositivoDTO.java)', () {
    test('lee firmware y fecha de última sincronización', () {
      final d = Dispositivo.fromJson({
        'id': 'w1',
        'nombre': 'VitaWatch',
        'modelo': 'Wear OS',
        'bateria': 64,
        'firmware': '1.2.3',
        'ultimaSync': '2026-09-21T10:00:00Z',
      });
      expect(d.firmware, '1.2.3');
      expect(d.bateria, 64);
      expect(d.ultimaSync, DateTime.utc(2026, 9, 21, 10));
    });

    test('sin última sincronización queda en null', () {
      final d = Dispositivo.fromJson({'id': 'w1', 'ultimaSync': null});
      expect(d.ultimaSync, isNull);
    });
  });

  group('Usuario.fromJson (formato de UsuarioDTO.java)', () {
    test('lee los campos y asume habilitado si no viene', () {
      final u = Usuario.fromJson({
        'id': 'u1',
        'nombreCompleto': 'Ana Torres',
        'username': 'ana',
      });
      expect(u.id, 'u1');
      expect(u.nombreCompleto, 'Ana Torres');
      expect(u.habilitado, isTrue);
    });

    test('respeta habilitado en false', () {
      final u = Usuario.fromJson({
        'id': 'u2',
        'nombreCompleto': 'Luis',
        'username': 'luis',
        'habilitado': false,
      });
      expect(u.habilitado, isFalse);
    });
  });

  group('ApiConfig', () {
    test('la URL usa el host desde el que se abrió la página', () {
      expect(
        ApiConfig.baseUrlPara('192.168.1.20'),
        'http://192.168.1.20:8081/api',
      );
    });

    test('el sondeo es de 3 segundos, igual que la web y el reloj', () {
      expect(ApiConfig.intervaloSondeo, const Duration(seconds: 3));
    });
  });
}
