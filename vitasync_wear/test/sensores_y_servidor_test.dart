// Rúbrica D (dispositivos inteligentes): sensores reales con permisos y respaldo simulado, servidor configurable y clave de dispositivo.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartwatch_auth/auth/usuario_activo.dart';
import 'package:smartwatch_auth/config/configuracion_servidor.dart';
import 'package:smartwatch_auth/screens/configuracion_screen.dart';
import 'package:smartwatch_auth/screens/home_screen.dart';
import 'package:smartwatch_auth/services/sensores_reloj.dart';
import 'package:smartwatch_auth/services/smartwatch_api_service.dart';

const _todo = EstadoSensores(frecuenciaDisponible: true, pasosDisponible: true, permisoCardiaco: true, permisoActividad: true, bateria: 64);

class _SensoresFalsos implements SensoresReloj {
  _SensoresFalsos(this.estadoActual, {this.estadoTrasPermiso});
  EstadoSensores estadoActual;
  final EstadoSensores? estadoTrasPermiso;
  final LecturaSensores lectura = const LecturaSensores(frecuenciaCardiaca: 72, pasos: 1500, bateria: 64);
  int lecturas = 0, peticionesPermiso = 0;
  @override
  Future<EstadoSensores> estado() async => estadoActual;
  @override
  Future<EstadoSensores> pedirPermisos() async {
    peticionesPermiso++;
    return estadoActual = estadoTrasPermiso ?? estadoActual;
  }
  @override
  Future<LecturaSensores> leer() async {
    lecturas++;
    return lectura;
  }
}

SmartwatchApiService _servicio(http.Client cliente, SensoresReloj sensores, {ConfiguracionServidor? config}) => SmartwatchApiService(
      almacen: AlmacenEnMemoria(config ?? ConfiguracionServidor(host: '192.168.1.50', puerto: 8081, clave: 'clave-del-reloj')),
      sensores: sensores,
      cliente: cliente,
    );

void main() {
  setUp(() => UsuarioActivo.establecer('cuenta-1', 'Ana'));
  tearDown(UsuarioActivo.limpiar);

  group('construirLectura: qué es medido, qué estimado y qué simulado', () {
    test('con sensores y permisos: frecuencia, pasos y batería reales; calorías estimadas de los pasos; sueño simulado', () {
      final r = construirLectura(estado: _todo, sensor: const LecturaSensores(frecuenciaCardiaca: 72, pasos: 1500, bateria: 64), ultimoSueno: 7.4);
      expect(r.metricas.frecuenciaCardiaca, 72);
      expect(r.metricas.pasos, 1500);
      expect(r.metricas.bateria, 64);
      expect(r.metricas.calorias, 60, reason: '1500 pasos × 0,04');
      expect(r.metricas.suenoHoras, 7.4, reason: 'se conserva el último valor conocido');
      expect(r.reales, containsAll(['frecuencia cardíaca', 'pasos', 'batería']));
      expect(r.estimadas, ['calorías']);
      expect(r.simuladas, ['sueño']);
    });

    test('sin sensores: todo simulado (rangos razonables) salvo la batería, que sale del sistema', () {
      final r = construirLectura(estado: const EstadoSensores(bateria: 80), sensor: const LecturaSensores(bateria: 80), azar: Random(1));
      expect(r.reales, ['batería']);
      expect(r.simuladas, containsAll(['frecuencia cardíaca', 'pasos', 'calorías', 'sueño']));
      expect(r.metricas.frecuenciaCardiaca, inInclusiveRange(62, 94));
      expect(r.metricas.pasos, inInclusiveRange(4000, 11999));
      expect(r.metricas.bateria, 80);
    });

    test('con sensor pero SIN permiso: no se usa el dato aunque el sensor lo entregue', () {
      const sinPermiso = EstadoSensores(frecuenciaDisponible: true, pasosDisponible: true);
      final r = construirLectura(estado: sinPermiso, sensor: const LecturaSensores(frecuenciaCardiaca: 150, pasos: 9999), azar: Random(2));
      expect(r.metricas.frecuenciaCardiaca, isNot(150));
      expect(r.simuladas, contains('frecuencia cardíaca'));
      expect(sinPermiso.faltaPermiso, isTrue);
    });

    test('solo ritmo cardíaco real (sin contador de pasos): pasos y calorías simulados', () {
      const soloFc = EstadoSensores(frecuenciaDisponible: true, permisoCardiaco: true);
      final r = construirLectura(estado: soloFc, sensor: const LecturaSensores(frecuenciaCardiaca: 88), azar: Random(3));
      expect(r.metricas.frecuenciaCardiaca, 88);
      expect(r.reales, contains('frecuencia cardíaca'));
      expect(r.simuladas, containsAll(['pasos', 'calorías']));
    });

    test('una muestra inválida (0 o nula) no se toma como medida', () {
      for (final fc in [0, null]) {
        final r = construirLectura(estado: _todo, sensor: LecturaSensores(frecuenciaCardiaca: fc, pasos: 10, bateria: 50), azar: Random(4));
        expect(r.simuladas, contains('frecuencia cardíaca'), reason: 'fc=$fc');
      }
    });

    test('pasos en cero (acaba de empezar el día) son un dato real válido', () {
      final r = construirLectura(estado: _todo, sensor: const LecturaSensores(frecuenciaCardiaca: 70, pasos: 0, bateria: 50));
      expect(r.metricas.pasos, 0);
      expect(r.metricas.calorias, 0);
    });
  });

  group('SensoresRelojAndroid (canal nativo)', () {
    const canal = MethodChannel('vitasync/sensores');
    TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));

    test('traduce el estado y la lectura del canal', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async => switch (c.method) {
            'estado' => {'frecuenciaDisponible': true, 'pasosDisponible': false, 'permisoCardiaco': true, 'permisoActividad': false, 'bateria': 55},
            'leer' => {'frecuenciaCardiaca': 91, 'pasos': null, 'bateria': 55},
            _ => null,
          });
      final s = SensoresRelojAndroid();
      final e = await s.estado();
      expect(e.frecuenciaUsable, isTrue);
      expect(e.pasosUsable, isFalse);
      expect(e.bateria, 55);
      final l = await s.leer();
      expect(l.frecuenciaCardiaca, 91);
      expect(l.pasos, isNull);
    });

    test('pedirPermisos devuelve el estado que deja la persona (concedido o rechazado)', () async {
      var concedido = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async {
        if (c.method == 'pedirPermisos') concedido = true;
        return {'frecuenciaDisponible': true, 'pasosDisponible': true, 'permisoCardiaco': concedido, 'permisoActividad': concedido};
      });
      final e = await SensoresRelojAndroid().pedirPermisos();
      expect(e.faltaPermiso, isFalse);
    });

    test('sin plataforma (pruebas, escritorio) o con error del sistema: no revienta, todo simulado', () async {
      final e = await SensoresRelojAndroid().estado(); // sin manejador → MissingPluginException
      expect(e.hayAlgunSensor, isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (c) async => throw PlatformException(code: 'x'));
      expect((await SensoresRelojAndroid().leer()).frecuenciaCardiaca, isNull);
    });
  });

  group('SmartwatchApiService: servidor configurable y clave de dispositivo', () {
    test('sincroniza a la dirección CONFIGURADA con la cabecera X-Clave-Dispositivo y la lectura medida', () async {
      late http.Request visto;
      final s = _servicio(MockClient((r) async {
        visto = r;
        return http.Response('{}', 200);
      }), _SensoresFalsos(_todo));

      final m = await s.sincronizar(ultimoSueno: 7.0);

      expect(m, isNotNull);
      expect(visto.url.toString(), 'http://192.168.1.50:8081/api/smartwatch/sync?usuarioId=cuenta-1');
      expect(visto.headers['X-Clave-Dispositivo'], 'clave-del-reloj');
      final cuerpo = jsonDecode(visto.body) as Map<String, dynamic>;
      expect(cuerpo['frecuenciaCardiaca'], 72);
      expect(cuerpo['pasos'], 1500);
      expect(cuerpo['timestamp'], isNotNull, reason: 'sin timestamp el backend descarta la lectura y genera una simulada');
      expect(s.ultimaLectura!.hayReales, isTrue);
    });

    test('sin clave configurada no manda la cabecera', () async {
      late http.Request visto;
      final s = _servicio(MockClient((r) async {
        visto = r;
        return http.Response('{}', 200);
      }), _SensoresFalsos(_todo), config: ConfiguracionServidor(host: 'h', puerto: 1, clave: ''));
      await s.sincronizar();
      expect(visto.headers.containsKey('X-Clave-Dispositivo'), isFalse);
    });

    test('401 → mensaje que dice qué hacer, y no se da por sincronizado', () async {
      final s = _servicio(MockClient((_) async => http.Response('', 401)), _SensoresFalsos(_todo));
      expect(await s.sincronizar(), isNull);
      expect(s.ultimoError, contains('Clave de dispositivo inválida'));
    });

    test('servidor inalcanzable → mensaje con la dirección intentada', () async {
      final s = _servicio(MockClient((_) async => throw http.ClientException('sin red')), _SensoresFalsos(_todo));
      expect(await s.sincronizar(), isNull);
      expect(s.ultimoError, 'No se pudo conectar a 192.168.1.50:8081.');
    });

    test('sin cuenta elegida no hace nada', () async {
      UsuarioActivo.limpiar();
      final s = _servicio(MockClient((_) async => fail('no debe llamar')), _SensoresFalsos(_todo));
      expect(await s.sincronizar(), isNull);
    });

    test('si no hay permiso, NO se leen los sensores (no se toca lo que la persona no permitió)', () async {
      final sensores = _SensoresFalsos(const EstadoSensores(frecuenciaDisponible: true, pasosDisponible: true));
      await _servicio(MockClient((_) async => http.Response('{}', 200)), sensores).sincronizar();
      expect(sensores.lecturas, 0);
    });

    test('obtenerMetricas usa la misma dirección y clave', () async {
      late http.Request visto;
      final s = _servicio(MockClient((r) async {
        visto = r;
        return http.Response(jsonEncode({'pasos': 10, 'calorias': 1, 'sueñoHoras': 6.5, 'frecuenciaCardiaca': 70, 'bateria': 50}), 200);
      }), _SensoresFalsos(_todo));
      expect((await s.obtenerMetricas())!.pasos, 10);
      expect(visto.url.host, '192.168.1.50');
      expect(visto.headers['X-Clave-Dispositivo'], 'clave-del-reloj');
    });
  });

  group('ConfiguracionServidor', () {
    test('validar: dirección y puerto', () {
      expect(ConfiguracionServidor.validar('192.168.1.50', '8081'), isNull);
      expect(ConfiguracionServidor.validar('mi-pc.local', '1'), isNull);
      expect(ConfiguracionServidor.validar('', '8081'), isNotNull);
      expect(ConfiguracionServidor.validar('http://192.168.1.50', '8081'), isNotNull, reason: 'sin esquema');
      expect(ConfiguracionServidor.validar('192.168.1.50:8081', '8081'), isNotNull, reason: 'el puerto va aparte');
      expect(ConfiguracionServidor.validar('a b', '8081'), isNotNull);
      for (final p in ['', '0', '65536', 'abc', '-1']) {
        expect(ConfiguracionServidor.validar('h', p), isNotNull, reason: 'puerto «$p»');
      }
    });

    test('la base se arma con host y puerto', () {
      expect(ConfiguracionServidor(host: '10.0.0.5', puerto: 9000, clave: '').base, 'http://10.0.0.5:9000/api/smartwatch');
    });
  });

  group('Pantallas', () {
    testWidgets('configuración: rechaza una dirección inválida y guarda una válida', (t) async {
      final almacen = AlmacenEnMemoria();
      final api = SmartwatchApiService(almacen: almacen, sensores: _SensoresFalsos(_todo), cliente: MockClient((_) async => http.Response('', 200)));
      await t.pumpWidget(MaterialApp(home: ConfiguracionScreen(api: api)));
      await t.pumpAndSettle();

      await t.enterText(find.byKey(const Key('campo-host')), 'http://x');
      await t.tap(find.byKey(const Key('guardar-config')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('error-config')), findsOneWidget);

      await t.enterText(find.byKey(const Key('campo-host')), '192.168.1.77');
      await t.enterText(find.byKey(const Key('campo-puerto')), '8082');
      await t.enterText(find.byKey(const Key('campo-clave')), 'secreta');
      await t.tap(find.byKey(const Key('guardar-config')));
      await t.pumpAndSettle();
      final c = await almacen.cargar();
      expect((c.host, c.puerto, c.clave), ('192.168.1.77', 8082, 'secreta'));
    });

    testWidgets('principal: con sensores sin permiso aparece «Permitir sensores»; al concederlo desaparece y dice que están activos', (t) async {
      t.view.physicalSize = const Size(450, 450);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final sensores = _SensoresFalsos(
        const EstadoSensores(frecuenciaDisponible: true, pasosDisponible: true),
        estadoTrasPermiso: _todo,
      );
      final api = _servicio(MockClient((_) async => http.Response('', 503)), sensores);
      await t.pumpWidget(MaterialApp(home: HomeScreen(onLogout: () {}, api: api)));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('permitir-sensores')), findsOneWidget);
      expect(find.textContaining('Permite los sensores'), findsOneWidget);

      await t.ensureVisible(find.byKey(const Key('permitir-sensores')));
      await t.tap(find.byKey(const Key('permitir-sensores')));
      await t.pumpAndSettle();
      expect(sensores.peticionesPermiso, 1);
      expect(find.byKey(const Key('permitir-sensores')), findsNothing);
      expect(find.textContaining('Sensores del reloj activos'), findsOneWidget);
      // El sondeo periódico de la pantalla sigue vivo: se desmonta para que no queden temporizadores.
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('principal: un reloj sin sensores lo dice claramente y no pide permisos', (t) async {
      t.view.physicalSize = const Size(450, 450);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _servicio(MockClient((_) async => http.Response('', 503)), _SensoresFalsos(const EstadoSensores()));
      await t.pumpWidget(MaterialApp(home: HomeScreen(onLogout: () {}, api: api)));
      await t.pumpAndSettle();
      expect(find.textContaining('no tiene sensores compatibles'), findsOneWidget);
      expect(find.byKey(const Key('permitir-sensores')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });
}
