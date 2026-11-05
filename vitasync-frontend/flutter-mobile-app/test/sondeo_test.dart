import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/config/api_config.dart';
import 'package:vitasync_mobile/models/estado_dispositivo.dart';
import 'package:vitasync_mobile/models/lectura_metricas.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/screens/resumen_screen.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';

/// Repositorio cuyos pasos cambian en cada consulta, como cuando el reloj
/// sincroniza datos nuevos. Cuenta cuántas veces se le preguntó.
class _SaludQueCambia implements SaludRepository {
  int consultas = 0;

  @override
  Future<LecturaMetricas> obtenerMetricas() async {
    consultas++;
    return LecturaMetricas(
      metricas: Metricas(
        pasos: 1000 * consultas,
        calorias: 300,
        suenoHoras: 7,
        frecuenciaCardiaca: 70,
        bateria: 80,
      ),
    );
  }

  @override
  Future<EstadoDispositivo> obtenerEstado() => throw UnimplementedError();

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async => [];
}

Future<void> _abrir(WidgetTester tester, SaludRepository repo, Duration? intervalo) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: ResumenScreen(repositorio: repo, intervalo: intervalo)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('el intervalo de la app es de 3 segundos, como la web y el reloj', (tester) async {
    expect(ApiConfig.intervaloSondeo, const Duration(seconds: 3));
  });

  testWidgets('un dato nuevo del reloj aparece solo, dentro del intervalo de sondeo', (tester) async {
    final repo = _SaludQueCambia();
    await _abrir(tester, repo, ApiConfig.intervaloSondeo);
    expect(find.text('1000'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(repo.consultas, 2);
    expect(find.text('2000'), findsOneWidget);
    expect(find.text('1000'), findsNothing);
  });

  testWidgets('el sondeo sigue en cada intervalo', (tester) async {
    final repo = _SaludQueCambia();
    await _abrir(tester, repo, ApiConfig.intervaloSondeo);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    await tester.pump();

    expect(repo.consultas, 4);
  });

  testWidgets('entre un sondeo y otro no hay consultas de más', (tester) async {
    final repo = _SaludQueCambia();
    await _abrir(tester, repo, ApiConfig.intervaloSondeo);

    await tester.pump(const Duration(seconds: 2));

    expect(repo.consultas, 1);
  });

  testWidgets('sin intervalo no hay sondeo', (tester) async {
    final repo = _SaludQueCambia();
    await _abrir(tester, repo, null);

    await tester.pump(const Duration(seconds: 10));

    expect(repo.consultas, 1);
  });

  testWidgets('al salir de la pantalla el sondeo se detiene', (tester) async {
    final repo = _SaludQueCambia();
    await _abrir(tester, repo, ApiConfig.intervaloSondeo);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));

    expect(repo.consultas, 1);
  });
}
