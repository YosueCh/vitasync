import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:vitasync_firmware_sim/backend_api.dart';
import 'package:vitasync_firmware_sim/firmware.dart';
import 'package:vitasync_firmware_sim/hardware.dart';

class HardwareFalso implements Hardware {
  bool boton = false;
  bool puesto = true;
  final leds = <Led>[];
  final serial = <String>[];

  @override
  bool leerBoton() => boton;

  @override
  bool leerRelojPuesto() => puesto;

  @override
  void escribirLed(Led estado) => leds.add(estado);

  @override
  void imprimir(String mensaje) => serial.add(mensaje);

  bool dijo(String texto) => serial.any((l) => l.contains(texto));
}

class BackendFalso implements BackendApi {
  bool caido = false;
  bool conectado = false;
  String firmware = 'v2.3.1';
  String? orden;
  int conexiones = 0;
  final sincronizaciones = <Map<String, Object>>[];

  void _revisar() {
    if (caido) throw const BackendException('sin conexión con el servidor');
  }

  @override
  Future<EstadoRemoto> estado(String usuarioId) async {
    _revisar();
    return EstadoRemoto(conectado: conectado, firmware: conectado ? firmware : null);
  }

  @override
  Future<void> conectar(String usuarioId) async {
    _revisar();
    conexiones++;
    conectado = true;
  }

  @override
  Future<void> sincronizar(String usuarioId, Map<String, Object> metricas) async {
    _revisar();
    sincronizaciones.add(metricas);
  }

  @override
  Future<OrdenFirmware?> ordenFirmware(String usuarioId) async {
    _revisar();
    return orden == null ? null : OrdenFirmware(orden!);
  }

  @override
  Future<void> reportarFirmware(String usuarioId, String version) async {
    _revisar();
    firmware = version;
    orden = null;
  }
}

void main() {
  late HardwareFalso hw;
  late BackendFalso api;
  late Firmware fw;

  Firmware crear({int auto = 0}) => Firmware(
        usuarioId: 'u1',
        hardware: hw,
        api: api,
        ticksPorSincronizacionAutomatica: auto,
        azar: Random(1),
        esperar: (_) async {},
      );

  setUp(() {
    hw = HardwareFalso();
    api = BackendFalso();
    fw = crear();
  });

  group('setup()', () {
    test('un dispositivo nuevo se vincula con el servidor y enciende el LED verde', () async {
      await fw.setup();

      expect(api.conexiones, 1);
      expect(fw.iniciado, isTrue);
      expect(hw.leds.last, Led.verde);
      expect(hw.dijo('Firmware iniciado'), isTrue);
    });

    test('un dispositivo ya vinculado conserva la versión instalada', () async {
      api
        ..conectado = true
        ..firmware = 'v2.4.0';

      await fw.setup();

      expect(api.conexiones, 0);
      expect(fw.version, 'v2.4.0');
    });

    test('sin servidor queda con el LED rojo y sin iniciar', () async {
      api.caido = true;

      await fw.setup();

      expect(fw.iniciado, isFalse);
      expect(hw.leds.last, Led.rojo);
      expect(hw.dijo('ERROR'), isTrue);
    });
  });

  group('vinculado con clave de dispositivo (Práctica 10)', () {
    test('arranca sin preguntar estado ni conectarse solo (eso es de la persona dueña)', () async {
      final con = Firmware(
        usuarioId: 'u1',
        hardware: hw,
        api: api,
        vinculadoConClave: true,
        azar: Random(1),
        esperar: (_) async {},
      );

      await con.setup();

      expect(api.conexiones, 0);
      expect(con.iniciado, isTrue);
      expect(hw.leds.last, Led.verde);
    });

    test('sync, orden y aplicar llevan X-Clave-Dispositivo; estado y conectar no', () async {
      final cabeceras = <String, String?>{};
      final cliente = MockClient((http.Request p) async {
        cabeceras['${p.method} ${p.url.path}'] = p.headers['X-Clave-Dispositivo'];
        return http.Response(p.url.path.endsWith('/orden') ? '{"pendiente":false}' : '{}', 200);
      });
      final real = BackendApiHttp(baseUrl: 'http://x/api', cliente: cliente, claveDispositivo: 'abc123');

      await real.sincronizar('u1', {'pasos': 1});
      await real.ordenFirmware('u1');
      await real.reportarFirmware('u1', 'v2.4.0');
      await real.conectar('u1');

      expect(cabeceras['POST /api/smartwatch/sync'], 'abc123');
      expect(cabeceras['GET /api/firmware/orden'], 'abc123');
      expect(cabeceras['POST /api/firmware/aplicar'], 'abc123');
      expect(cabeceras['POST /api/smartwatch/connect'], isNull);
    });

    test('una clave rechazada (401) se explica y no se confunde con "sin conexión"', () async {
      final cliente = MockClient((_) async => http.Response('{"error":"x"}', 401));
      final real = BackendApiHttp(baseUrl: 'http://x/api', cliente: cliente, claveDispositivo: 'mala');

      expect(
        () => real.sincronizar('u1', {'pasos': 1}),
        throwsA(isA<BackendException>().having((e) => e.toString(), 'mensaje', contains('clave'))),
      );
    });
  });

  group('loop()', () {
    setUp(() async => fw.setup());

    test('al presionar el botón con el reloj puesto sincroniza una lectura', () async {
      hw.boton = true;

      await fw.loop();

      expect(api.sincronizaciones, hasLength(1));
      final lectura = api.sincronizaciones.single;
      expect(lectura['pasos'], isA<int>());
      expect(lectura['timestamp'], isNotNull);
      expect(hw.dijo('BOTON PRESIONADO'), isTrue);
      expect(hw.leds, containsAllInOrder([Led.amarillo, Led.verde]));
    });

    test('mantener el botón apretado sincroniza una sola vez (flanco)', () async {
      hw.boton = true;

      await fw.loop();
      await fw.loop();
      await fw.loop();

      expect(api.sincronizaciones, hasLength(1));
    });

    test('con el reloj retirado no se capturan datos y el LED se apaga', () async {
      hw.puesto = false;
      hw.boton = true;

      await fw.loop();

      expect(api.sincronizaciones, isEmpty);
      expect(hw.dijo('RELOJ RETIRADO'), isTrue);
      expect(hw.dijo('SIN RELOJ PUESTO'), isTrue);
      expect(hw.leds, contains(Led.apagado));
    });

    test('los pasos solo aumentan entre sincronizaciones', () async {
      for (var i = 0; i < 3; i++) {
        hw.boton = true;
        await fw.loop();
        hw.boton = false;
        await fw.loop();
      }

      final pasos = api.sincronizaciones.map((m) => m['pasos'] as int).toList();
      expect(pasos, hasLength(3));
      expect(pasos, orderedEquals([...pasos]..sort()));
      expect(pasos.toSet(), hasLength(3));
    });

    test('con sincronización automática envía cada N vueltas', () async {
      fw = crear(auto: 2);
      await fw.setup();

      for (var i = 0; i < 6; i++) {
        await fw.loop();
      }

      expect(api.sincronizaciones, hasLength(3));
    });

    test('si el servidor se cae pasa a LED rojo y se recupera solo', () async {
      api.caido = true;
      hw.boton = true;
      await fw.loop();
      expect(hw.leds.last, Led.rojo);
      expect(fw.iniciado, isFalse);

      api.caido = false;
      hw.boton = false;
      await fw.loop(); // reintenta vincularse

      expect(fw.iniciado, isTrue);
      expect(hw.leds.last, Led.verde);
    });
  });

  group('Actualización de firmware (OTA)', () {
    setUp(() async => fw.setup());

    test('sin orden pendiente no cambia la versión', () async {
      await fw.loop();
      expect(fw.version, 'v2.3.1');
    });

    test('con una orden instala, reporta la versión y se reinicia', () async {
      api.orden = 'v2.4.0';

      await fw.loop();

      expect(fw.version, 'v2.4.0');
      expect(api.firmware, 'v2.4.0');
      expect(api.orden, isNull);
      expect(hw.dijo('ACTUALIZACION DISPONIBLE: v2.3.1 -> v2.4.0'), isTrue);
      expect(hw.dijo('Instalando firmware v2.4.0... 100%'), isTrue);
      expect(hw.dijo('REINICIANDO'), isTrue);
      expect(hw.dijo('Firmware iniciado v2.4.0'), isTrue);
      expect(hw.leds.last, Led.verde);
    });

    test('una orden de la versión que ya corre se ignora', () async {
      api.orden = 'v2.3.1';

      await fw.loop();

      expect(hw.dijo('ACTUALIZACION'), isFalse);
    });
  });
}
