import 'dart:io';

import 'package:vitasync_firmware_sim/backend_api.dart';
import 'package:vitasync_firmware_sim/consola.dart';
import 'package:vitasync_firmware_sim/firmware.dart';

const _ayuda = '''
Simulador del firmware del reloj VitaSync.

Uso: dart run bin/vitasync_firmware.dart --usuario <id> [opciones]

  --usuario <id>   (obligatorio) id de la cuenta a la que pertenece el reloj
  --servidor <url> URL base del API (por defecto http://localhost:8081/api)
  --clave <clave>  clave del dispositivo que entrega la app al conectar el reloj (obligatoria
                   cuando el servidor tiene la seguridad activa)
  --auto <seg>     sincroniza sola cada <seg> segundos (por defecto 0 = solo con el botón)
  --sin-reloj      arranca con el reloj retirado

Teclas: [s] botón sincronizar   [p] poner/retirar el reloj   [q] apagar
''';

Future<void> main(List<String> args) async {
  final opciones = _leerArgumentos(args);
  final usuario = opciones['usuario'];
  if (usuario == null || opciones.containsKey('ayuda')) {
    stdout.write(_ayuda);
    exit(usuario == null && !opciones.containsKey('ayuda') ? 64 : 0);
  }

  final hardware = HardwareConsola(relojPuesto: !opciones.containsKey('sin-reloj'));
  final firmware = Firmware(
    usuarioId: usuario,
    hardware: hardware,
    api: BackendApiHttp(
      baseUrl: opciones['servidor'] ?? 'http://localhost:8081/api',
      claveDispositivo: opciones['clave'],
    ),
    vinculadoConClave: opciones['clave'] != null,
    ticksPorSincronizacionAutomatica: int.tryParse(opciones['auto'] ?? '') ?? 0,
  );

  hardware.escucharTeclado();
  var apagar = false;
  hardware.apagado.then((_) => apagar = true);

  await firmware.ejecutar(
    periodo: const Duration(seconds: 1),
    seguir: () => !apagar,
  );
  await hardware.cerrar();
  stdout.writeln('Dispositivo apagado.');
  exit(0);
}

/// Lee `--clave valor` y `--bandera` sin dependencias extra.
Map<String, String?> _leerArgumentos(List<String> args) {
  final mapa = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    if (!args[i].startsWith('--')) continue;
    final clave = args[i].substring(2);
    final hayValor = i + 1 < args.length && !args[i + 1].startsWith('--');
    mapa[clave] = hayValor ? args[++i] : null;
  }
  return mapa;
}
