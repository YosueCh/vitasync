import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/main.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/auth_service.dart';
import 'package:vitasync_mobile/services/firmware_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

const _base = 'http://servidor:8081/api';

http.Response _json(Object cuerpo, [int estado = 200]) => http.Response(
      jsonEncode(cuerpo),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Servicio real contra un servidor falso. Guarda las peticiones que recibió.
(HttpAuthService, List<http.Request>) _servicio(
  http.Response Function(http.Request) responder,
) {
  final pedidas = <http.Request>[];
  final api = ApiCliente(
    baseUrl: _base,
    cliente: MockClient((r) async {
      pedidas.add(r);
      return responder(r);
    }),
  );
  return (HttpAuthService(api: api), pedidas);
}

void main() {
  group('HttpAuthService (PIN verificado en el backend)', () {
    test('verificar envía el PIN en el cuerpo, no en la URL', () async {
      final (auth, pedidas) = _servicio(
        (_) => _json({'exito': true, 'mensaje': 'PIN correcto.'}),
      );

      final r = await auth.verificarPin('u1', '1234');

      expect(r.exito, isTrue);
      expect(auth.autenticado, isTrue);
      final pedida = pedidas.single;
      expect(pedida.method, 'POST');
      expect(pedida.url.path, '/api/usuarios/u1/pin/verificar');
      expect(pedida.url.toString(), isNot(contains('1234')));
      expect(pedida.headers['content-type'], contains('application/json'));
      expect(jsonDecode(pedida.body), {'pin': '1234'});
    });

    test('un PIN incorrecto no inicia sesión y trae el mensaje del servidor', () async {
      final (auth, _) = _servicio(
        (_) => _json({'exito': false, 'mensaje': 'PIN incorrecto. Te quedan 4 intentos.'}),
      );

      final r = await auth.verificarPin('u1', '0000');

      expect(r.exito, isFalse);
      expect(r.mensaje, contains('4 intentos'));
      expect(auth.autenticado, isFalse);
    });

    test('una cuenta bloqueada (429) se informa con el mensaje del servidor', () async {
      final (auth, _) = _servicio(
        (_) => _json({'error': 'Demasiados intentos fallidos. Intenta de nuevo en 5 min.'}, 429),
      );

      await expectLater(
        auth.verificarPin('u1', '1234'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('5 min'))),
      );
      expect(auth.autenticado, isFalse);
    });

    test('sin red se informa que no se pudo conectar', () async {
      final auth = HttpAuthService(
        api: ApiCliente(baseUrl: _base, cliente: MockClient((_) async => throw Exception('sin red'))),
      );

      await expectLater(
        auth.verificarPin('u1', '1234'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'No se pudo conectar al servidor')),
      );
    });

    test('registrar crea el PIN y enseguida lo verifica (queda dentro)', () async {
      final (auth, pedidas) = _servicio(
        (_) => _json({'exito': true, 'mensaje': 'ok'}),
      );

      final r = await auth.registrarPin('u1', '1234');

      expect(r.exito, isTrue);
      expect(auth.autenticado, isTrue);
      expect(pedidas.map((p) => p.url.path), [
        '/api/usuarios/u1/pin',
        '/api/usuarios/u1/pin/verificar',
      ]);
    });

    test('si el registro falla (409, ya tenía PIN) no se intenta verificar', () async {
      final (auth, pedidas) = _servicio(
        (_) => _json({'error': 'La cuenta ya tiene un PIN registrado.'}, 409),
      );

      await expectLater(
        auth.registrarPin('u1', '1234'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('ya tiene'))),
      );
      expect(pedidas, hasLength(1));
      expect(auth.autenticado, isFalse);
    });

    test('cerrarSesion deja la sesión cerrada', () async {
      final (auth, _) = _servicio((_) => _json({'exito': true, 'mensaje': ''}));
      await auth.verificarPin('u1', '1234');

      auth.cerrarSesion();

      expect(auth.autenticado, isFalse);
    });
  });

  group('Usuario.tienePin', () {
    test('se lee del DTO', () {
      final u = Usuario.fromJson(const {
        'id': 'u1',
        'nombreCompleto': 'Ana',
        'username': 'ana',
        'tienePin': false,
      });
      expect(u.tienePin, isFalse);
    });

    test('si el servidor no lo informa se asume que sí tiene PIN', () {
      final u = Usuario.fromJson(const {'id': 'u1', 'nombreCompleto': 'Ana', 'username': 'ana'});
      expect(u.tienePin, isTrue);
    });
  });

  group('Pantalla de PIN', () {
    testWidgets('cuenta sin PIN: lo pide dos veces y lo registra', (tester) async {
      final auth = _AuthFalso();
      await _abrir(tester, auth: auth, tienePin: false);

      expect(find.text('Crea tu PIN de 4 dígitos'), findsOneWidget);
      await _escribir(tester, '1234');
      expect(find.text('Confirma tu PIN'), findsOneWidget);
      expect(auth.registrados, isEmpty, reason: 'no se registra hasta confirmar');

      await _escribir(tester, '1234');

      expect(auth.registrados, ['u1:1234']);
      expect(find.text('Mis datos de salud'), findsOneWidget);
    });

    testWidgets('si la confirmación no coincide vuelve a empezar', (tester) async {
      final auth = _AuthFalso();
      await _abrir(tester, auth: auth, tienePin: false);

      await _escribir(tester, '1234');
      await _escribir(tester, '4321');

      expect(find.text('Los PIN no coinciden, intenta de nuevo'), findsOneWidget);
      expect(find.text('Crea tu PIN de 4 dígitos'), findsOneWidget);
      expect(auth.registrados, isEmpty);
    });

    testWidgets('un PIN incorrecto muestra cuántos intentos quedan', (tester) async {
      final auth = _AuthFalso(respuesta: const ResultadoPin(
        exito: false,
        mensaje: 'PIN incorrecto. Te quedan 4 intentos.',
      ));
      await _abrir(tester, auth: auth);

      await _escribir(tester, '0000');

      expect(find.text('PIN incorrecto. Te quedan 4 intentos.'), findsOneWidget);
      expect(find.text('Mis datos de salud'), findsNothing);
    });

    testWidgets('una cuenta bloqueada muestra el aviso del servidor', (tester) async {
      final auth = _AuthFalso(
        error: const ApiException('Demasiados intentos fallidos. Intenta de nuevo en 5 min.'),
      );
      await _abrir(tester, auth: auth);

      await _escribir(tester, '1234');

      expect(find.textContaining('Demasiados intentos fallidos'), findsOneWidget);
      expect(find.text('Mis datos de salud'), findsNothing);
    });
  });

  group('Cierre de sesión por inactividad', () {
    testWidgets('sin tocar la pantalla, la sesión se cierra', (tester) async {
      await _abrir(tester, auth: _AuthFalso(), inactividad: const Duration(seconds: 45));
      await _escribir(tester, '1234');
      expect(find.text('Mis datos de salud'), findsOneWidget);

      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();

      expect(find.text('¿Quién eres?'), findsOneWidget);
      expect(find.text('Tu sesión se cerró por inactividad'), findsOneWidget);
    });

    testWidgets('tocar la pantalla reinicia la cuenta', (tester) async {
      await _abrir(tester, auth: _AuthFalso(), inactividad: const Duration(seconds: 45));
      await _escribir(tester, '1234');

      await tester.pump(const Duration(seconds: 30));
      await tester.tap(find.text('Mis datos de salud'));
      await tester.pump(const Duration(seconds: 30)); // 60 s en total, pero 30 desde el toque

      expect(find.text('Mis datos de salud'), findsOneWidget);

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.text('¿Quién eres?'), findsOneWidget);
    });
  });
}

/// Autenticación de prueba: acepta lo que se le indique y anota los registros.
class _AuthFalso implements AuthService {
  _AuthFalso({this.respuesta, this.error});

  final ResultadoPin? respuesta;
  final ApiException? error;
  final List<String> registrados = [];
  bool _autenticado = false;

  @override
  bool get autenticado => _autenticado;

  @override
  Future<ResultadoPin> registrarPin(String usuarioId, String pin) async {
    registrados.add('$usuarioId:$pin');
    return verificarPin(usuarioId, pin);
  }

  @override
  Future<ResultadoPin> verificarPin(String usuarioId, String pin) async {
    if (error != null) throw error!;
    final r = respuesta ?? const ResultadoPin(exito: true, mensaje: 'PIN correcto.');
    _autenticado = r.exito;
    return r;
  }

  @override
  void cerrarSesion() => _autenticado = false;
}

class _UnaCuenta implements UsuarioRepository {
  const _UnaCuenta({required this.tienePin});

  final bool tienePin;

  @override
  Future<List<Usuario>> listarHabilitados() async => [
        Usuario(
          id: 'u1',
          nombreCompleto: 'Ana Torres',
          username: 'ana',
          habilitado: true,
          tienePin: tienePin,
        ),
      ];
}

Future<void> _abrir(
  WidgetTester tester, {
  required AuthService auth,
  bool tienePin = true,
  Duration? inactividad,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(VitaSyncMobileApp(
    usuarios: _UnaCuenta(tienePin: tienePin),
    saludPara: (_) => const MuestraSaludRepository(),
    firmwarePara: (_) => MuestraFirmwareRepository(),
    auth: auth,
    tiempoInactividad: inactividad,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ana Torres'));
  await tester.pumpAndSettle();
}

Future<void> _escribir(WidgetTester tester, String pin) async {
  for (final digito in pin.split('')) {
    await tester.tap(find.text(digito));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
