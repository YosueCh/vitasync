import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitasync_mobile/data/metrica_dao.dart';
import 'package:vitasync_mobile/data/metrica_local.dart';
import 'package:vitasync_mobile/models/estado_dispositivo.dart';
import 'package:vitasync_mobile/models/lectura_metricas.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/models/tipo_metrica.dart';
import 'package:vitasync_mobile/screens/historial_screen.dart';
import 'package:vitasync_mobile/screens/resumen_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cache_salud_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';

const _base = 'http://servidor:8081/api';

LecturaMetricas _lectura(int pasos, {int minutosAtras = 0, bool sinConexion = false}) {
  return LecturaMetricas(
    metricas: Metricas(
      pasos: pasos,
      calorias: pasos ~/ 20,
      suenoHoras: 7.5,
      frecuenciaCardiaca: 60 + pasos ~/ 1000,
      bateria: 80,
    ),
    capturadaEn: DateTime(2026, 10, 22, 12, 0).subtract(Duration(minutes: minutosAtras)),
    sinConexion: sinConexion,
  );
}

/// Repositorio con las lecturas del historial en la mano.
class _Repo implements SaludRepository {
  _Repo(this.historial);

  final List<LecturaMetricas> historial;
  int consultasHistorial = 0;

  @override
  Future<LecturaMetricas> obtenerMetricas() async => historial.first;

  @override
  Future<EstadoDispositivo> obtenerEstado() => throw UnimplementedError();

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async {
    consultasHistorial++;
    return historial;
  }
}

Future<void> _pantalla(WidgetTester tester, Widget hijo) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: hijo));
  await tester.pumpAndSettle();
}

void main() {
  group('Historial al tocar una card', () {
    testWidgets('tocar la card de Pasos abre su historial con las lecturas de la base de datos',
        (tester) async {
      final repo = _Repo([
        _lectura(9000),
        _lectura(7000, minutosAtras: 30),
        _lectura(4000, minutosAtras: 60),
      ]);
      await _pantalla(tester, Scaffold(body: ResumenScreen(repositorio: repo)));

      await tester.tap(find.text('Pasos'));
      await tester.pumpAndSettle();

      expect(find.text('Historial de Pasos'), findsOneWidget);
      expect(repo.consultasHistorial, 1);
      // Una fila por lectura, con su hora, más recientes primero.
      expect(find.text('9000'), findsWidgets);
      expect(find.text('7000'), findsOneWidget);
      // 4000 aparece en su fila y como mínimo del resumen.
      expect(find.text('4000'), findsNWidgets(2));
      expect(find.text('22/10 12:00:00'), findsOneWidget);
      expect(find.text('22/10 11:30:00'), findsOneWidget);
      expect(find.text('3 lecturas'), findsOneWidget);
      // Resumen: mínimo, promedio y máximo.
      expect(find.text('Mínimo'), findsOneWidget);
      expect(find.text('Promedio'), findsOneWidget);
      expect(find.text('Máximo'), findsOneWidget);
      expect(find.text('6667'), findsOneWidget);
      expect(find.byKey(const Key('grafica-historial')), findsOneWidget);
    });

    testWidgets('cada card abre el historial de SU métrica', (tester) async {
      final repo = _Repo([_lectura(5000), _lectura(4000, minutosAtras: 10)]);
      await _pantalla(tester, Scaffold(body: ResumenScreen(repositorio: repo)));

      await tester.tap(find.text('Ritmo cardíaco'));
      await tester.pumpAndSettle();

      expect(find.text('Historial de Ritmo cardíaco'), findsOneWidget);
      expect(find.text('65 lpm'), findsWidgets);
      expect(find.text('64 lpm'), findsWidgets);
    });

    testWidgets('se puede volver al Resumen desde el historial', (tester) async {
      final repo = _Repo([_lectura(5000)]);
      await _pantalla(tester, Scaffold(body: ResumenScreen(repositorio: repo)));

      await tester.tap(find.text('Calorías'));
      await tester.pumpAndSettle();
      expect(find.text('Historial de Calorías'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Mis datos de salud'), findsOneWidget);
    });

    testWidgets('con una sola lectura no se dibuja la gráfica pero sí la fila', (tester) async {
      final repo = _Repo([_lectura(5000)]);
      await _pantalla(
        tester,
        HistorialScreen(tipo: TipoMetrica.pasos, repositorio: repo),
      );

      expect(find.byKey(const Key('grafica-historial')), findsNothing);
      expect(find.textContaining('al menos 2 lecturas'), findsOneWidget);
      expect(find.text('1 lecturas'), findsOneWidget);
    });

    testWidgets('sin lecturas muestra un mensaje en vez de una lista vacía', (tester) async {
      await _pantalla(
        tester,
        HistorialScreen(tipo: TipoMetrica.sueno, repositorio: _Repo([])),
      );

      expect(find.byKey(const Key('historial-vacio')), findsOneWidget);
    });

    testWidgets('las lecturas guardadas en el teléfono se avisan como sin conexión',
        (tester) async {
      final repo = _Repo([
        _lectura(5000, sinConexion: true),
        _lectura(4000, minutosAtras: 5, sinConexion: true),
      ]);
      await _pantalla(
        tester,
        HistorialScreen(tipo: TipoMetrica.pasos, repositorio: repo),
      );

      expect(find.textContaining('Sin conexión'), findsOneWidget);
    });

    testWidgets('si el servidor falla ofrece reintentar', (tester) async {
      final repo = _RepoQueFalla();
      await _pantalla(
        tester,
        HistorialScreen(tipo: TipoMetrica.pasos, repositorio: repo),
      );

      expect(find.text('No se pudo conectar al servidor'), findsOneWidget);
      repo.falla = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('3000'), findsWidgets);
    });
  });

  group('TipoMetrica', () {
    const m = Metricas(
      pasos: 6320,
      calorias: 412,
      suenoHoras: 7.25,
      frecuenciaCardiaca: 78,
      bateria: 87,
    );

    test('saca el valor de cada métrica y lo muestra con su formato', () {
      expect(TipoMetrica.pasos.formato(TipoMetrica.pasos.valor(m)), '6320');
      expect(TipoMetrica.calorias.formato(TipoMetrica.calorias.valor(m)), '412');
      expect(TipoMetrica.sueno.formato(TipoMetrica.sueno.valor(m)), '7.3');
      expect(TipoMetrica.ritmo.formato(TipoMetrica.ritmo.valor(m)), '78');
    });
  });

  group('HttpSaludRepository.obtenerHistorial', () {
    test('pide el historial de la cuenta y convierte cada lectura', () async {
      final pedidas = <http.Request>[];
      final api = ApiCliente(
        baseUrl: _base,
        cliente: MockClient((r) async {
          pedidas.add(r);
          return http.Response(
            jsonEncode([
              {
                'pasos': 9000,
                'calorias': 450,
                'sueñoHoras': 7.5,
                'frecuenciaCardiaca': 72,
                'bateria': 80,
                'timestamp': '2026-10-22T18:00:00Z',
              },
              {
                'pasos': 7000,
                'calorias': 350,
                'sueñoHoras': 7.0,
                'frecuenciaCardiaca': 70,
                'bateria': 81,
                'timestamp': 1792692000.0,
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final lista = await HttpSaludRepository(usuarioId: 'u1', api: api).obtenerHistorial(limite: 10);

      expect(
        pedidas.single.url.toString(),
        '$_base/smartwatch/historial?usuarioId=u1&limite=10',
      );
      expect(lista, hasLength(2));
      expect(lista.first.metricas.pasos, 9000);
      expect(lista.first.metricas.suenoHoras, 7.5);
      expect(lista.first.capturadaEn!.toUtc(), DateTime.utc(2026, 10, 22, 18));
      expect(lista.last.capturadaEn, isNotNull);
    });
  });

  group('CacheSaludRepository.obtenerHistorial', () {
    Future<MetricaDao> dao() async {
      SharedPreferences.setMockInitialValues({});
      return MetricaDaoPrefs(await SharedPreferences.getInstance());
    }

    test('con servidor devuelve el historial de la base de datos', () async {
      final remoto = _Repo([_lectura(3000), _lectura(2000, minutosAtras: 5)]);
      final repo = CacheSaludRepository(usuarioId: 'u1', remoto: remoto, dao: await dao());

      final lista = await repo.obtenerHistorial();

      expect(lista, hasLength(2));
      expect(lista.any((l) => l.sinConexion), isFalse);
    });

    test('sin servidor devuelve el historial guardado en el teléfono, marcado sin conexión',
        () async {
      final almacen = await dao();
      await almacen.insertar(MetricaLocal(
        usuarioId: 'u1',
        metricas: _lectura(1500).metricas,
        capturadaEn: DateTime(2026, 10, 22, 10),
      ));
      await almacen.insertar(MetricaLocal(
        usuarioId: 'u1',
        metricas: _lectura(2500).metricas,
        capturadaEn: DateTime(2026, 10, 22, 11),
      ));
      final repo = CacheSaludRepository(
        usuarioId: 'u1',
        remoto: _RepoQueFalla(),
        dao: almacen,
      );

      final lista = await repo.obtenerHistorial();

      expect(lista.map((l) => l.metricas.pasos), [2500, 1500]);
      expect(lista.every((l) => l.sinConexion), isTrue);
    });

    test('sin servidor y sin nada guardado, el error llega a la pantalla', () async {
      final repo = CacheSaludRepository(
        usuarioId: 'u1',
        remoto: _RepoQueFalla(),
        dao: await dao(),
      );

      expect(repo.obtenerHistorial, throwsA(isA<ApiException>()));
    });
  });
}

/// Falla mientras [falla] sea true y luego responde (para probar "Reintentar").
class _RepoQueFalla implements SaludRepository {
  bool falla = true;

  @override
  Future<LecturaMetricas> obtenerMetricas() => throw const ApiException('No se pudo conectar al servidor');

  @override
  Future<EstadoDispositivo> obtenerEstado() => throw UnimplementedError();

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async {
    if (falla) throw const ApiException('No se pudo conectar al servidor');
    return [_lectura(3000), _lectura(2000, minutosAtras: 5)];
  }
}
