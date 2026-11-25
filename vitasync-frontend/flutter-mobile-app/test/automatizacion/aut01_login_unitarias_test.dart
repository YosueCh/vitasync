// PRÁCTICAS 13 y 14 · AUT-01 · Pruebas UNITARIAS de la función crítica del móvil: inicio de sesión con correo y contraseña
// (HttpCuentaCorreoService). Cliente HTTP simulado (MockClient): se prueba SOLO la lógica del servicio, sin red.
//
// Defectos de auditorías anteriores que estas pruebas impiden que vuelvan:
//   · P11 WB-HALLAZGO-1/2: una excepción cruda (FormatException) llegaba a la pantalla de acceso.
//   · P10: credenciales malas y cuentas inexistentes deben dar el MISMO mensaje (no revelar qué correos existen).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cuenta_correo_service.dart';

http.Response _json(int estado, Object cuerpo) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json'});

Map<String, Object> _sesionOk({String expiresIn = '3600'}) => {
      'localId': 'uid-1',
      'email': 'ana@uteq.test',
      'idToken': 'token-1',
      'refreshToken': 'refresco-1',
      'expiresIn': expiresIn,
    };

Map<String, Object> _error(String mensaje) => {
      'error': {'code': 400, 'message': mensaje}
    };

void main() {
  late DateTime reloj;
  late List<http.Request> llamadas;

  HttpCuentaCorreoService servicio(http.Response Function(http.Request) responder) {
    llamadas = [];
    return HttpCuentaCorreoService(
      authBase: 'http://auth.local',
      apiKey: 'clave',
      cliente: MockClient((r) async {
        llamadas.add(r);
        return responder(r);
      }),
      ahora: () => reloj,
    );
  }

  setUp(() => reloj = DateTime.utc(2026, 11, 25, 12));

  group('AUT-01 · Entrada válida y resultado esperado', () {
    test('credenciales válidas → sesión con uid, correo, token y vencimiento a 3600 s', () async {
      final s = servicio((_) => _json(200, _sesionOk()));
      final sesion = await s.iniciarSesion('ana@uteq.test', 'Clave-123');

      expect(sesion.uid, 'uid-1');
      expect(sesion.correo, 'ana@uteq.test');
      expect(sesion.idToken, 'token-1');
      expect(sesion.expira, reloj.add(const Duration(hours: 1)));
      expect(s.sesion, same(sesion), reason: 'la sesión queda guardada en el servicio');
    });

    test('el correo se recorta y la petición pide el token (returnSecureToken)', () async {
      final s = servicio((_) => _json(200, _sesionOk()));
      await s.iniciarSesion('  ana@uteq.test  ', 'Clave-123');

      final cuerpo = jsonDecode(llamadas.single.body) as Map<String, dynamic>;
      expect(cuerpo['email'], 'ana@uteq.test');
      expect(cuerpo['password'], 'Clave-123');
      expect(cuerpo['returnSecureToken'], true);
      expect(llamadas.single.url.path, '/v1/accounts:signInWithPassword');
    });

    test('registrarse usa la operación signUp', () async {
      final s = servicio((_) => _json(200, _sesionOk()));
      await s.registrarse('ana@uteq.test', 'Clave-123');
      expect(llamadas.single.url.path, '/v1/accounts:signUp');
    });
  });

  group('AUT-01 · Entrada vacía o nula: se rechaza SIN tocar la red', () {
    for (final caso in [
      ('correo vacío', '', 'Clave-123'),
      ('correo solo con espacios', '   ', 'Clave-123'),
      ('contraseña vacía', 'ana@uteq.test', ''),
      ('ambos vacíos', '', ''),
    ]) {
      test(caso.$1, () async {
        final s = servicio((_) => _json(200, _sesionOk()));
        await expectLater(
          s.iniciarSesion(caso.$2, caso.$3),
          throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'Escribe el correo y la contraseña.')),
        );
        expect(llamadas, isEmpty, reason: 'no debe hacerse ninguna petición');
        expect(s.sesion, isNull);
      });
    }
  });

  group('AUT-01 · Valores fuera de lo esperado en la respuesta', () {
    test('expiresIn no numérico → se usa 3600 s por omisión (no se rompe)', () async {
      final s = servicio((_) => _json(200, _sesionOk(expiresIn: 'abc')));
      final sesion = await s.iniciarSesion('ana@uteq.test', 'Clave-123');
      expect(sesion.expira, reloj.add(const Duration(seconds: 3600)));
    });

    test('la respuesta sin correo usa el que escribió la persona', () async {
      final cuerpo = _sesionOk()..remove('email');
      final s = servicio((_) => _json(200, cuerpo));
      expect((await s.iniciarSesion(' bea@uteq.test ', 'Clave-123')).correo, 'bea@uteq.test');
    });
  });

  group('AUT-01 · Manejo de excepciones y mensajes para la persona', () {
    final mensajes = <String, String>{
      'EMAIL_NOT_FOUND': 'Correo o contraseña incorrectos.',
      'INVALID_PASSWORD': 'Correo o contraseña incorrectos.',
      'INVALID_LOGIN_CREDENTIALS': 'Correo o contraseña incorrectos.',
      'EMAIL_EXISTS': 'Ya existe una cuenta con ese correo.',
      'INVALID_EMAIL': 'El correo no es válido.',
      'USER_DISABLED': 'Esta cuenta está deshabilitada.',
      'WEAK_PASSWORD : Password should be at least 6 characters': 'La contraseña es muy débil (mínimo 6 caracteres).',
      'TOO_MANY_ATTEMPTS_TRY_LATER': 'Demasiados intentos. Espera un momento e inténtalo de nuevo.',
      'ALGO_NUEVO_DE_FIREBASE': 'No se pudo iniciar sesión.',
    };
    mensajes.forEach((codigo, esperado) {
      test('$codigo → «$esperado»', () async {
        final s = servicio((_) => _json(400, _error(codigo)));
        await expectLater(s.iniciarSesion('ana@uteq.test', 'x'), throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', esperado)));
        expect(s.sesion, isNull, reason: 'un fallo no deja sesión abierta');
      });
    });

    test('correo inexistente y contraseña incorrecta dan el MISMO mensaje (no revela qué correos existen)', () async {
      Future<String> mensaje(String codigo) async {
        final s = servicio((_) => _json(400, _error(codigo)));
        try {
          await s.iniciarSesion('a@b.c', 'x');
        } on ApiException catch (e) {
          return e.mensaje;
        }
        fail('debía fallar');
      }

      expect(await mensaje('EMAIL_NOT_FOUND'), await mensaje('INVALID_PASSWORD'));
    });

    test('sin red → «No se pudo conectar…» (ApiException, no una excepción cruda)', () async {
      final s = servicio((_) => throw http.ClientException('sin red'));
      await expectLater(
        s.iniciarSesion('ana@uteq.test', 'Clave-123'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('No se pudo conectar'))),
      );
    });

    test('el servicio contesta algo que NO es JSON (portal cautivo, proxy) → ApiException, no FormatException', () async {
      final s = servicio((_) => http.Response('<html>Inicia sesión en el Wi-Fi</html>', 200, headers: {'content-type': 'text/html'}));
      await expectLater(s.iniciarSesion('ana@uteq.test', 'Clave-123'), throwsA(isA<ApiException>()));
    });

    test('HTTP 500 sin cuerpo → mensaje genérico, no revienta', () async {
      final s = servicio((_) => http.Response('', 500));
      await expectLater(s.iniciarSesion('ana@uteq.test', 'Clave-123'), throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'No se pudo iniciar sesión.')));
    });
  });

  group('AUT-01 · Token: vigente, por vencer y cierre de sesión', () {
    test('sin sesión → token nulo', () async {
      expect(await servicio((_) => _json(200, _sesionOk())).token(), isNull);
    });

    test('con más de un minuto de vida → mismo token, sin llamar a la red', () async {
      final s = servicio((_) => _json(200, _sesionOk()));
      await s.iniciarSesion('ana@uteq.test', 'Clave-123');
      llamadas.clear();
      reloj = reloj.add(const Duration(minutes: 30));
      expect(await s.token(), 'token-1');
      expect(llamadas, isEmpty);
    });

    test('a menos de un minuto de vencer → se renueva con el refresh token', () async {
      final s = servicio((r) => r.url.host == 'auth.local' && r.url.path.contains('signInWithPassword')
          ? _json(200, _sesionOk())
          : _json(200, {'id_token': 'token-2', 'refresh_token': 'refresco-2', 'expires_in': '3600'}));
      await s.iniciarSesion('ana@uteq.test', 'Clave-123');
      reloj = reloj.add(const Duration(minutes: 59, seconds: 30));

      expect(await s.token(), 'token-2');
      expect(s.sesion!.refreshToken, 'refresco-2');
      expect(llamadas.last.body, contains('grant_type=refresh_token'));
    });

    test('si no se puede renovar, se entrega el token que había (el servidor dirá 401)', () async {
      var primera = true;
      final s = servicio((_) {
        if (primera) {
          primera = false;
          return _json(200, _sesionOk());
        }
        throw http.ClientException('sin red');
      });
      await s.iniciarSesion('ana@uteq.test', 'Clave-123');
      reloj = reloj.add(const Duration(minutes: 59, seconds: 40));
      expect(await s.token(), 'token-1');
    });

    test('cerrarSesion borra la sesión y el token', () async {
      final s = servicio((_) => _json(200, _sesionOk()));
      await s.iniciarSesion('ana@uteq.test', 'Clave-123');
      s.cerrarSesion();
      expect(s.sesion, isNull);
      expect(await s.token(), isNull);
    });
  });
}
