import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitasync_mobile/data/metrica_dao.dart';
import 'package:vitasync_mobile/models/estado_dispositivo.dart';
import 'package:vitasync_mobile/models/lectura_metricas.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/screens/resumen_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cache_salud_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';

/// D-05 de la Práctica 8: una cuenta sin lecturas NO debe mostrar (ni guardar en el teléfono) valores inventados.

class _Remoto implements SaludRepository {
  _Remoto(this.lectura);

  LecturaMetricas? lectura;

  @override
  Future<LecturaMetricas?> obtenerMetricas() async => lectura;

  @override
  Future<EstadoDispositivo> obtenerEstado() => throw UnimplementedError();

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async => [];
}

const _lectura = LecturaMetricas(
  metricas: Metricas(pasos: 1500, calorias: 90, suenoHoras: 6.5, frecuenciaCardiaca: 70, bateria: 80),
);

void main() {
  group('Sin lecturas (D-05)', () {
    test('HttpSaludRepository: el servidor responde 204 → null, no un error ni datos', () async {
      final repo = HttpSaludRepository(
        usuarioId: 'u1',
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((_) async => http.Response('', 204)),
        ),
      );

      expect(await repo.obtenerMetricas(), isNull);
    });

    test('CacheSaludRepository: sin lecturas no guarda NADA en el teléfono', () async {
      SharedPreferences.setMockInitialValues({});
      final dao = await MetricaDaoPrefs.abrir();
      final cache = CacheSaludRepository(usuarioId: 'u1', remoto: _Remoto(null), dao: dao);

      expect(await cache.obtenerMetricas(), isNull);
      expect(await dao.ultima('u1'), isNull, reason: 'la caché sigue vacía: no hay lecturas inventadas');
      expect(await dao.historial('u1'), isEmpty);
    });

    test('CacheSaludRepository: con una lectura real sí la guarda', () async {
      SharedPreferences.setMockInitialValues({});
      final dao = await MetricaDaoPrefs.abrir();
      final cache = CacheSaludRepository(usuarioId: 'u1', remoto: _Remoto(_lectura), dao: dao);

      expect(await cache.obtenerMetricas(), isNotNull);
      expect((await dao.ultima('u1'))?.metricas.pasos, 1500);
    });

    testWidgets('el Resumen dice «Aún no hay lecturas» y no muestra tarjetas con números', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ResumenScreen(repositorio: _Remoto(null)))));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sin-lecturas')), findsOneWidget);
      expect(find.text('Aún no hay lecturas'), findsOneWidget);
      expect(find.text('Pasos'), findsNothing);
    });

    testWidgets('con lecturas el Resumen muestra las tarjetas como siempre', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ResumenScreen(repositorio: _Remoto(_lectura)))));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sin-lecturas')), findsNothing);
      expect(find.text('Pasos'), findsOneWidget);
    });
  });
}
