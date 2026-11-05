import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Guarda las capturas que toma la prueba de integración en evidencias-integracion/seguridad/.
Future<void> main() => integrationDriver(
      onScreenshot: (String nombre, List<int> bytes, [Map<String, Object?>? args]) async {
        final archivo = File('evidencias-integracion/seguridad/$nombre.png');
        await archivo.parent.create(recursive: true);
        await archivo.writeAsBytes(bytes);
        return true;
      },
    );
