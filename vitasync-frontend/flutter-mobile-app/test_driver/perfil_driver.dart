import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

/// PRÁCTICA 12 · Fase 2: guarda los datos medidos por perfil_p12_test.dart y el resumen de la línea de tiempo de
/// fotogramas (cuántos fotogramas, tiempo de construcción y de rasterizado, fotogramas perdidos) en
/// evidencias-integracion/p12/.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        final etiqueta = (data['perfil'] as Map?)?['etiqueta'] ?? 'sin-etiqueta';
        final carpeta = Directory('evidencias-integracion/p12');
        await carpeta.create(recursive: true);
        await File('${carpeta.path}/perfil-$etiqueta.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data['perfil']));
        if (data['navegacion'] != null) {
          final timeline = driver.Timeline.fromJson(data['navegacion'] as Map<String, dynamic>);
          final resumen = driver.TimelineSummary.summarize(timeline);
          await File('${carpeta.path}/navegacion-resumen-$etiqueta.json')
              .writeAsString(const JsonEncoder.withIndent('  ').convert(resumen.summaryJson));
        }
      },
    );
