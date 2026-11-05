import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitasync_mobile/data/metrica_dao.dart';
import 'package:vitasync_mobile/data/metrica_local.dart';
import 'package:vitasync_mobile/models/estado_dispositivo.dart';
import 'package:vitasync_mobile/models/lectura_metricas.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/screens/resumen_screen.dart' show tiempoTranscurrido;
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cache_salud_repository.dart';
import 'package:vitasync_mobile/services/firmware_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

const _base = 'http://servidor:8081/api';

ApiCliente _api(http.Response Function(http.Request) responder) =>
    ApiCliente(baseUrl: _base, cliente: MockClient((r) async => responder(r)));

http.Response _json(Object cuerpo, [int estado = 200]) => http.Response(
      jsonEncode(cuerpo),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _metricas = Metricas(
  pasos: 5000,
  calorias: 300,
  suenoHoras: 7.5,
  frecuenciaCardiaca: 70,
  bateria: 80,
);

void main() {
  group('Consulta HTTP (Práctica 3)', () {
    test('HttpSaludRepository pide /smartwatch/metrics con el usuarioId', () async {
      late Uri pedida;
      final repo = HttpSaludRepository(
        usuarioId: 'u7',
        api: _api((r) {
          pedida = r.url;
          return _json({
            'pasos': 5000,
            'calorias': 300,
            'sueñoHoras': 7.5,
            'frecuenciaCardiaca': 70,
            'bateria': 80,
            'timestamp': '2026-10-07T12:00:00Z',
          });
        }),
      );

      final lectura = (await repo.obtenerMetricas())!;

      expect(pedida.toString(), '$_base/smartwatch/metrics?usuarioId=u7');
      expect(lectura.metricas.pasos, 5000);
      expect(lectura.metricas.suenoHoras, 7.5);
      expect(lectura.capturadaEn, DateTime.utc(2026, 10, 7, 12));
      expect(lectura.sinConexion, isFalse);
    });

    test('el timestamp numérico (segundos) también se interpreta', () async {
      final repo = HttpSaludRepository(
        usuarioId: 'u1',
        api: _api((_) => _json({'pasos': 1, 'timestamp': 1790000000.5})),
      );
      final lectura = (await repo.obtenerMetricas())!;
      expect(lectura.capturadaEn, isNotNull);
    });

    test('HttpSaludRepository desenvuelve el estado y el dispositivo', () async {
      final repo = HttpSaludRepository(
        usuarioId: 'u1',
        api: _api((_) => _json({
              'estado': 'CONECTADO',
              'mensaje': 'Dispositivo activo',
              'dispositivo': {'id': 'W1', 'nombre': 'Watch', 'firmware': 'v2.3.1'},
            })),
      );
      final estado = await repo.obtenerEstado();
      expect(estado.conectado, isTrue);
      expect(estado.dispositivo?.firmware, 'v2.3.1');
    });

    test('un estado DESCONECTADO llega sin dispositivo', () async {
      final repo = HttpSaludRepository(
        usuarioId: 'u1',
        api: _api((_) => _json({
              'estado': 'DESCONECTADO',
              'dispositivo': null,
              'mensaje': 'Sin dispositivo conectado',
            })),
      );
      final estado = await repo.obtenerEstado();
      expect(estado.conectado, isFalse);
      expect(estado.dispositivo, isNull);
    });

    test('HttpUsuarioRepository deja solo las cuentas habilitadas', () async {
      final repo = HttpUsuarioRepository(
        api: _api((_) => _json([
              {'id': 'a', 'nombreCompleto': 'Ana', 'username': 'ana', 'habilitado': true},
              {'id': 'b', 'nombreCompleto': 'Beto', 'username': 'beto', 'habilitado': false},
            ])),
      );
      final cuentas = await repo.listarHabilitados();
      expect(cuentas.map((u) => u.id), ['a']);
    });

    test('un 503 se traduce al mensaje de Firebase no configurado', () async {
      final repo = HttpSaludRepository(
        usuarioId: 'u1',
        api: _api((_) => _json({'error': 'x'}, 503)),
      );
      expect(
        repo.obtenerMetricas(),
        throwsA(isA<ApiException>().having(
          (e) => e.mensaje,
          'mensaje',
          'El servidor no tiene Firebase configurado',
        )),
      );
    });

    test('un fallo de red se traduce a "No se pudo conectar"', () async {
      final api = ApiCliente(
        baseUrl: _base,
        cliente: MockClient((_) async => throw http.ClientException('sin red')),
      );
      expect(
        HttpSaludRepository(usuarioId: 'u1', api: api).obtenerMetricas(),
        throwsA(isA<ApiException>().having(
          (e) => e.mensaje,
          'mensaje',
          'No se pudo conectar al servidor',
        )),
      );
    });

    test('otro código HTTP incluye el número en el mensaje', () async {
      final repo = HttpSaludRepository(
        usuarioId: 'u1',
        api: _api((_) => _json({}, 500)),
      );
      expect(
        repo.obtenerMetricas(),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('500'))),
      );
    });
  });

  group('Firmware (Práctica 1, flujo OTA)', () {
    const estadoJson = {
      'versionActual': 'v2.3.1',
      'ultima': {'version': 'v2.4.0', 'notas': 'Mejoras'},
      'hayActualizacion': true,
      'ordenPendiente': false,
    };

    test('obtenerEstado lee la versión actual y la última', () async {
      final repo = HttpFirmwareRepository(
        usuarioId: 'u1',
        api: _api((_) => _json(estadoJson)),
      );
      final e = await repo.obtenerEstado();
      expect(e.versionActual, 'v2.3.1');
      expect(e.ultimaVersion, 'v2.4.0');
      expect(e.hayActualizacion, isTrue);
    });

    test('solicitarActualizacion hace POST a /firmware/solicitar', () async {
      late http.Request pedida;
      final repo = HttpFirmwareRepository(
        usuarioId: 'u1',
        api: _api((r) {
          pedida = r;
          return _json({...estadoJson, 'ordenPendiente': true});
        }),
      );
      final e = await repo.solicitarActualizacion();
      expect(pedida.method, 'POST');
      expect(pedida.url.path, '/api/firmware/solicitar');
      expect(e.ordenPendiente, isTrue);
    });
  });

  group('Caché local (Práctica 4)', () {
    late MetricaDaoPrefs dao;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dao = await MetricaDaoPrefs.abrir();
    });

    MetricaLocal fila(String usuario, int pasos, DateTime cuando) => MetricaLocal(
          usuarioId: usuario,
          metricas: Metricas(
            pasos: pasos,
            calorias: 1,
            suenoHoras: 1,
            frecuenciaCardiaca: 1,
            bateria: 1,
          ),
          capturadaEn: cuando,
        );

    test('insertar y consultar la última lectura (INSERT / SELECT)', () async {
      await dao.insertar(fila('u1', 100, DateTime(2026, 10, 1)));
      await dao.insertar(fila('u1', 200, DateTime(2026, 10, 2)));

      final ultima = await dao.ultima('u1');
      expect(ultima?.metricas.pasos, 200);
    });

    test('el historial va de la más reciente a la más antigua', () async {
      await dao.insertar(fila('u1', 1, DateTime(2026, 10, 1)));
      await dao.insertar(fila('u1', 3, DateTime(2026, 10, 3)));
      await dao.insertar(fila('u1', 2, DateTime(2026, 10, 2)));

      final h = await dao.historial('u1');
      expect(h.map((f) => f.metricas.pasos), [3, 2, 1]);
    });

    test('cada cuenta ve solo sus lecturas', () async {
      await dao.insertar(fila('u1', 1, DateTime(2026, 10, 1)));
      await dao.insertar(fila('u2', 2, DateTime(2026, 10, 1)));

      expect((await dao.ultima('u1'))?.metricas.pasos, 1);
      expect((await dao.ultima('u2'))?.metricas.pasos, 2);
      expect(await dao.ultima('u3'), isNull);
    });

    test('eliminarDe borra solo las lecturas de esa cuenta (DELETE)', () async {
      await dao.insertar(fila('u1', 1, DateTime(2026, 10, 1)));
      await dao.insertar(fila('u2', 2, DateTime(2026, 10, 1)));

      await dao.eliminarDe('u1');

      expect(await dao.ultima('u1'), isNull);
      expect(await dao.ultima('u2'), isNotNull);
    });

    test('solo se conservan las ${MetricaDaoPrefs.maxFilasPorCuenta} más recientes', () async {
      for (var i = 0; i < MetricaDaoPrefs.maxFilasPorCuenta + 5; i++) {
        await dao.insertar(fila('u1', i, DateTime(2026, 10, 1).add(Duration(minutes: i))));
      }
      final h = await dao.historial('u1', limite: 1000);
      expect(h.length, MetricaDaoPrefs.maxFilasPorCuenta);
      expect(h.first.metricas.pasos, MetricaDaoPrefs.maxFilasPorCuenta + 4);
    });

    test('los datos persisten al volver a abrir la base', () async {
      await dao.insertar(fila('u1', 321, DateTime(2026, 10, 1)));
      final reabierta = await MetricaDaoPrefs.abrir();
      expect((await reabierta.ultima('u1'))?.metricas.pasos, 321);
    });

    test('migración 1→2: las filas sin batería quedan con 0', () async {
      SharedPreferences.setMockInitialValues({
        'vitasync_metricas': jsonEncode({
          'version': 1,
          'filas': [
            {
              'usuarioId': 'u1',
              'pasos': 900,
              'calorias': 50,
              'suenoHoras': 6.0,
              'frecuenciaCardiaca': 66,
              'capturadaEn': DateTime(2026, 9, 1).millisecondsSinceEpoch,
            },
          ],
        }),
      });
      final vieja = await MetricaDaoPrefs.abrir();

      final ultima = await vieja.ultima('u1');
      expect(ultima?.metricas.pasos, 900);
      expect(ultima?.metricas.bateria, 0);
    });

    test('datos dañados se descartan sin romper la app', () async {
      SharedPreferences.setMockInitialValues({'vitasync_metricas': '{no es json'});
      final corrupta = await MetricaDaoPrefs.abrir();
      expect(await corrupta.ultima('u1'), isNull);
    });
  });

  group('CacheSaludRepository', () {
    late MetricaDaoPrefs dao;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dao = await MetricaDaoPrefs.abrir();
    });

    test('guarda cada lectura exitosa en la caché', () async {
      final repo = CacheSaludRepository(
        usuarioId: 'u1',
        remoto: _Remoto([LecturaMetricas(metricas: _metricas, capturadaEn: DateTime(2026, 10, 7))]),
        dao: dao,
      );

      await repo.obtenerMetricas();

      expect((await dao.ultima('u1'))?.metricas.pasos, 5000);
    });

    test('una lectura repetida no se vuelve a guardar', () async {
      final lectura = LecturaMetricas(metricas: _metricas, capturadaEn: DateTime(2026, 10, 7));
      final repo = CacheSaludRepository(
        usuarioId: 'u1',
        remoto: _Remoto([lectura, lectura, lectura]),
        dao: dao,
      );

      await repo.obtenerMetricas();
      await repo.obtenerMetricas();
      await repo.obtenerMetricas();

      expect((await dao.historial('u1')).length, 1);
    });

    test('sin conexión devuelve la última lectura guardada', () async {
      final cuando = DateTime(2026, 10, 7, 9);
      final repo = CacheSaludRepository(
        usuarioId: 'u1',
        remoto: _Remoto([LecturaMetricas(metricas: _metricas, capturadaEn: cuando)]),
        dao: dao,
      );
      await repo.obtenerMetricas(); // conectado: se guarda

      final lectura = (await repo.obtenerMetricas())!; // el servidor ya no responde

      expect(lectura.sinConexion, isTrue);
      expect(lectura.metricas.pasos, 5000);
      expect(lectura.capturadaEn, cuando);
    });

    test('sin conexión y sin nada guardado, el error sigue su curso', () async {
      final repo = CacheSaludRepository(
        usuarioId: 'u1',
        remoto: _Remoto([]),
        dao: dao,
      );
      expect(repo.obtenerMetricas(), throwsA(isA<ApiException>()));
    });
  });

  group('tiempoTranscurrido', () {
    final ahora = DateTime(2026, 10, 7, 12);

    test('textos por rango', () {
      expect(tiempoTranscurrido(null), 'sin datos');
      expect(tiempoTranscurrido(ahora.subtract(const Duration(seconds: 20)), ahora: ahora),
          'hace un momento');
      expect(tiempoTranscurrido(ahora.subtract(const Duration(minutes: 5)), ahora: ahora),
          'hace 5 min');
      expect(tiempoTranscurrido(ahora.subtract(const Duration(hours: 3)), ahora: ahora),
          'hace 3 h');
      expect(tiempoTranscurrido(ahora.subtract(const Duration(days: 2)), ahora: ahora),
          'hace 2 d');
    });
  });
}

/// Remoto de prueba: entrega las lecturas en orden y después falla (servidor caído).
class _Remoto implements SaludRepository {
  _Remoto(this._lecturas);

  final List<LecturaMetricas> _lecturas;

  @override
  Future<LecturaMetricas> obtenerMetricas() async {
    if (_lecturas.isEmpty) throw const ApiException('No se pudo conectar al servidor');
    return _lecturas.removeAt(0);
  }

  @override
  Future<EstadoDispositivo> obtenerEstado() => throw UnimplementedError();

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async => [];
}
