// PRÁCTICA 12 · Fase 2 · Perfilado de la app en el emulador de Android (modo profile).
//
//   flutter drive --profile --driver=test_driver/perfil_driver.dart --target=integration_test/perfil_p12_test.dart \
//     -d emulator-5554 --dart-define=SEGURIDAD=false --dart-define=API_PORT=8092 --dart-define=PERFIL_ETIQUETA=antes
//
// Requiere el backend con vitasync.seguridad.activa=false en el puerto indicado (10.0.2.2 desde el emulador).
// Mientras corre, scripts/practica12/perfil-adb.mjs muestrea CPU (top) y memoria (dumpsys meminfo) del proceso de la app.
//
// Operaciones medidas (cada una en una «fase» con nombre para poder cruzarla con el muestreo):
//   F1 consulta repetida (GET historial) · F2 escritura (PUT metas) · F3 navegación entre pantallas (UI real con datos de
//   muestra, con línea de tiempo de fotogramas) · F4 procesamiento de datos (SQLite local: insertar y leer lecturas).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:vitasync_mobile/config/api_config.dart';
import 'package:vitasync_mobile/data/abrir_dao.dart';
import 'package:vitasync_mobile/data/metrica_local.dart';
import 'package:vitasync_mobile/main.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/metas_repository.dart';
import 'package:vitasync_mobile/services/politica_reintento.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';

const etiqueta = String.fromEnvironment('PERFIL_ETIQUETA', defaultValue: 'sin-etiqueta');

/// Estadística simple de una lista de milisegundos.
Map<String, num> resumen(List<double> ms) {
  final s = [...ms]..sort();
  double p(double q) => s[((s.length - 1) * q).round()];
  return {
    'n': s.length,
    'minMs': double.parse(s.first.toStringAsFixed(1)),
    'mediaMs': double.parse((s.reduce((a, b) => a + b) / s.length).toStringAsFixed(1)),
    'p95Ms': double.parse(p(0.95).toStringAsFixed(1)),
    'maxMs': double.parse(s.last.toStringAsFixed(1)),
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Perfil de la app: consulta, escritura, navegación y procesamiento', (t) async {
    final datos = <String, Object?>{'etiqueta': etiqueta, 'fecha': DateTime.now().toIso8601String(), 'api': ApiConfig.baseUrl};
    final api = ApiCliente(reintentos: PoliticaReintento.ninguna);

    // ---- Preparación (no se mide): una cuenta de prueba con 24 lecturas, creada directamente en el backend.
    final base = ApiConfig.baseUrl;
    final sufijo = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final creada = jsonDecode((await http.post(Uri.parse('$base/usuarios'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'nombreCompleto': 'Perfil App', 'username': 'zzperf$sufijo', 'grupos': <String>[]})))
        .body) as Map<String, dynamic>;
    final cuenta = creada['id'] as String;
    final conexion = jsonDecode((await http.post(Uri.parse('$base/smartwatch/connect?usuarioId=$cuenta'))).body) as Map<String, dynamic>;
    for (var i = 24; i >= 1; i--) {
      await http.post(Uri.parse('$base/smartwatch/sync?usuarioId=$cuenta'),
          headers: {'content-type': 'application/json', 'X-Clave-Dispositivo': conexion['claveDispositivo'] as String},
          body: jsonEncode({
            'pasos': 1000 + i * 100, 'calorias': 50 + i, 'sueñoHoras': 7.2, 'frecuenciaCardiaca': 60 + i % 25, 'bateria': 80,
            'timestamp': DateTime.now().subtract(Duration(minutes: 15 * i)).toUtc().toIso8601String(),
          }));
    }
    final salud = HttpSaludRepository(usuarioId: cuenta, api: api);
    final metas = HttpMetasRepository(usuarioId: cuenta, api: api);
    await salud.obtenerHistorial(limite: 24); // calentamiento
    datos['rssInicialMB'] = double.parse((ProcessInfo.currentRss / 1048576).toStringAsFixed(1));
    await Future<void>.delayed(const Duration(seconds: 3)); // para que el muestreador externo tome la línea base
    try {
      // ---- F1 · consulta repetida (60 veces, una tras otra) ----
      final sw = Stopwatch();
      final f1 = <double>[];
      datos['f1Inicio'] = DateTime.now().toIso8601String();
      for (var i = 0; i < 60; i++) {
        sw
          ..reset()
          ..start();
        final h = await salud.obtenerHistorial(limite: 24);
        sw.stop();
        expect(h, isNotEmpty);
        f1.add(sw.elapsedMicroseconds / 1000);
      }
      datos['F1 consulta repetida (GET historial x60)'] = resumen(f1);
      await Future<void>.delayed(const Duration(seconds: 2));

      // ---- F2 · escritura (30 PUT de metas) ----
      final f2 = <double>[];
      datos['f2Inicio'] = DateTime.now().toIso8601String();
      for (var i = 0; i < 30; i++) {
        sw
          ..reset()
          ..start();
        await metas.guardar(pasos: 6000 + i * 10);
        sw.stop();
        f2.add(sw.elapsedMicroseconds / 1000);
      }
      datos['F2 escritura (PUT metas x30)'] = resumen(f2);
      await Future<void>.delayed(const Duration(seconds: 2));

      // ---- F4 · procesamiento de datos locales: SQLite real del teléfono ----
      final dao = await abrirDaoLocal();
      final f4 = <String, Object?>{};
      datos['f4Inicio'] = DateTime.now().toIso8601String();
      sw
        ..reset()
        ..start();
      for (var i = 0; i < 400; i++) {
        await dao.insertar(MetricaLocal(
          usuarioId: 'perf-$sufijo',
          metricas: Metricas(pasos: 1000 + i, calorias: 100 + i % 50, suenoHoras: 7, frecuenciaCardiaca: 60 + i % 40, bateria: 80),
          capturadaEn: DateTime.now().subtract(Duration(minutes: i)),
        ));
      }
      sw.stop();
      f4['insertar400Ms'] = sw.elapsedMilliseconds;
      final lecturas = <double>[];
      for (var i = 0; i < 40; i++) {
        sw
          ..reset()
          ..start();
        final h = await dao.historial('perf-$sufijo', limite: 50);
        // procesamiento: promedio, máximo y tendencia de la frecuencia cardiaca y de los pasos
        var suma = 0, max = 0;
        for (final m in h) {
          suma += m.metricas.frecuenciaCardiaca;
          if (m.metricas.pasos > max) max = m.metricas.pasos;
        }
        expect(suma / h.length, greaterThan(0));
        sw.stop();
        lecturas.add(sw.elapsedMicroseconds / 1000);
      }
      f4['leerYProcesar50 (x40)'] = resumen(lecturas);
      await dao.eliminarDe('perf-$sufijo');
      datos['F4 procesamiento de datos (SQLite)'] = f4;
      await Future<void>.delayed(const Duration(seconds: 2));

      // ---- F3 · navegación entre pantallas, con la línea de tiempo de fotogramas ----
      datos['f3Inicio'] = DateTime.now().toIso8601String();
      await binding.convertFlutterSurfaceToImage();
      await t.pumpWidget(VitaSyncMobileApp.muestra());
      await t.pumpAndSettle(const Duration(seconds: 2));
      await t.tap(find.text('Ana Torres'));
      await t.pumpAndSettle(const Duration(seconds: 2));
      // PIN de muestra: cualquier PIN de 4 dígitos.
      for (final d in ['1', '2', '3', '4']) {
        await t.tap(find.text(d));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pumpAndSettle(const Duration(seconds: 2));
      final nav = <double>[];
      await binding.traceAction(() async {
        for (var vuelta = 0; vuelta < 8; vuelta++) {
          for (final pestana in ['Dispositivo', 'Chat', 'Resumen']) {
            final f = find.text(pestana);
            if (f.evaluate().isEmpty) continue;
            final sw2 = Stopwatch()..start();
            await t.tap(f.last);
            await t.pumpAndSettle(const Duration(milliseconds: 300));
            sw2.stop();
            nav.add(sw2.elapsedMicroseconds / 1000);
          }
        }
      }, reportKey: 'navegacion');
      datos['F3 navegación (cambio de pestaña, x${nav.length})'] = nav.isEmpty ? 'sin pestañas visibles' : resumen(nav);
    } finally {
      datos['rssFinalMB'] = double.parse((ProcessInfo.currentRss / 1048576).toStringAsFixed(1));
      await http.delete(Uri.parse('$base/usuarios/$cuenta')); // limpieza
    }
    binding.reportData = {'perfil': datos, ...?binding.reportData};
  }, timeout: const Timeout(Duration(minutes: 10)));
}
