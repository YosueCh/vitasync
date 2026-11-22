// PRÁCTICA 11 · Fase 2 · Método 3 (COMUNICACIÓN CON EL SERVIDOR): ApiCliente._enviarCrudo / _enviar
//
// Código (lib/services/api_cliente.dart) — se ejercita por las vías públicas get/post/postJson/putJson:
//   C1  try { token = await _token?.call(); cabeceras = { if (token != null) 'Authorization': ... };
//             respuesta = await peticion(cabeceras).timeout(tiempoLimite); }          ← condiciones: _token?, token != null
//   C2  on Exception → ApiException(sinConexion: true)                               ← excepción de red / tiempo agotado
//   D1  if (status == 401) throw ...            D2  if (status == 403) throw ...     D3  if (status == 503) throw ...
//   D4  if ({400,409,429}.contains(status)) { mensaje = _mensajeDelServidor(r); if (mensaje != null) throw ... }   ← D4a, D4b
//   D5  if (status < 200 || status >= 300) throw ...                                 ← decisión con 2 condiciones (D5a, D5b)
//   _enviar: if (body.isEmpty) return null; return jsonDecode(...)                   ← D6
//   _cuerpo: try { decode; cuerpo is Map; error is String && isNotEmpty } on Object → null     ← D7, D8
//
// V(G) estimada = 1 + (_token?, token!=null, catch, D1, D2, D3, D4a, D4b, D5a, D5b, D6, D7a, D7b, D8) ≈ 15
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';

http.Response _json(Object cuerpo, int estado) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json; charset=utf-8'});

ApiCliente _api(http.Client c, {Future<String?> Function()? token}) =>
    ApiCliente(baseUrl: 'http://x/api', cliente: c, token: token);

Future<ApiException> _falla(Future<dynamic> f) async {
  try {
    await f;
  } on ApiException catch (e) {
    return e;
  }
  fail('se esperaba ApiException');
}

void main() {
  group('Caminos de éxito', () {
    test('P1: 200 con JSON → devuelve el objeto decodificado', () async {
      final r = await _api(MockClient((_) async => _json({'a': 1}, 200))).get('/x');
      expect(r, {'a': 1});
    });
    test('P1b: 200 con cuerpo vacío → null (D6=T)', () async {
      expect(await _api(MockClient((_) async => http.Response('', 200))).get('/x'), isNull);
    });
    test('P1c: 204 sin contenido → null', () async {
      expect(await _api(MockClient((_) async => http.Response('', 204))).delete('/x'), isNull);
    });
  });

  group('Encabezado Authorization (condiciones del token)', () {
    test('sin callback de token (_token == null) → no manda Authorization', () async {
      late http.Request visto;
      await _api(MockClient((r) async {
        visto = r;
        return _json({}, 200);
      })).get('/x');
      expect(visto.headers.containsKey('Authorization'), isFalse);
    });
    test('callback que devuelve null (sesión cerrada) → no manda Authorization', () async {
      late http.Request visto;
      await _api(MockClient((r) async {
        visto = r;
        return _json({}, 200);
      }), token: () async => null).get('/x');
      expect(visto.headers.containsKey('Authorization'), isFalse);
    });
    test('callback con token → «Authorization: Bearer <token>»', () async {
      late http.Request visto;
      await _api(MockClient((r) async {
        visto = r;
        return _json({}, 200);
      }), token: () async => 'abc').get('/x');
      expect(visto.headers['Authorization'], 'Bearer abc');
    });
    test('si el callback del token lanza una Exception → se trata como «sin conexión»', () async {
      final e = await _falla(_api(MockClient((_) async => _json({}, 200)), token: () async => throw Exception('x')).get('/x'));
      expect(e.sinConexion, isTrue);
    });
  });

  group('Excepciones de red (C2)', () {
    test('el cliente lanza ClientException → sinConexion', () async {
      final e = await _falla(_api(MockClient((_) async => throw http.ClientException('sin red'))).get('/x'));
      expect(e.sinConexion, isTrue);
      expect(e.mensaje, 'No se pudo conectar al servidor');
    });
    test('tiempo agotado (la respuesta nunca llega) → sinConexion', () async {
      // Tiempo REAL (ApiConfig.tiempoLimite = 4 s): la respuesta nunca llega.
      final completer = Completer<http.Response>();
      final reloj = Stopwatch()..start();
      final e = await _falla(_api(MockClient((_) => completer.future)).get('/x'));
      expect(e.sinConexion, isTrue);
      expect(reloj.elapsedMilliseconds, inInclusiveRange(3900, 4800), reason: 'debe cortar a los 4 s');
    });
  });

  group('Códigos HTTP de rechazo (D1–D5)', () {
    final casos = <int, String>{
      401: 'Tu sesión venció. Vuelve a iniciar sesión.',
      403: 'No tienes permiso para ver estos datos.',
      503: 'El servidor no tiene Firebase configurado',
      500: 'El servidor respondió 500',
      404: 'El servidor respondió 404',
      418: 'El servidor respondió 418',
    };
    for (final c in casos.entries) {
      test('${c.key} → «${c.value}» y NO es sinConexion', () async {
        final e = await _falla(_api(MockClient((_) async => _json({'error': 'x'}, c.key))).get('/x'));
        expect(e.mensaje, c.value);
        expect(e.sinConexion, isFalse);
      });
    }
    for (final c in [400, 409, 429]) {
      test('$c con {"error": ...} → muestra el mensaje del servidor (D4a=T, D4b=T)', () async {
        final e = await _falla(_api(MockClient((_) async => _json({'error': 'Mensaje para la persona', 'codigo': 'K'}, c))).get('/x'));
        expect(e.mensaje, 'Mensaje para la persona');
        expect(e.codigo, 'K');
        expect(e.datos?['error'], 'Mensaje para la persona');
      });
      test('$c SIN mensaje utilizable → cae al genérico «respondió $c» (D4a=T, D4b=F)', () async {
        final e = await _falla(_api(MockClient((_) async => _json({'otro': 1}, c))).get('/x'));
        expect(e.mensaje, 'El servidor respondió $c');
      });
    }
  });

  group('Frontera de D5: status < 200 || status >= 300', () {
    test('199 → error (D5a=T)', () async => expect((await _falla(_api(MockClient((_) async => http.Response('', 199))).get('/x'))).mensaje, contains('199')));
    test('200 → éxito (D5a=F, D5b=F)', () async => expect(await _api(MockClient((_) async => http.Response('', 200))).get('/x'), isNull));
    test('299 → éxito', () async => expect(await _api(MockClient((_) async => http.Response('', 299))).get('/x'), isNull));
    test('300 → error (D5b=T)', () async => expect((await _falla(_api(MockClient((_) async => http.Response('', 300))).get('/x'))).mensaje, contains('300')));
  });

  group('cuerpo de error mal formado (D7, D8): cuerpo de error mal formado', () {
    for (final caso in <String, String>{
      'no es JSON': '<html>Bad Request</html>',
      'es una lista': '["a"]',
      '«error» no es texto': '{"error": 5}',
      '«error» vacío': '{"error": ""}',
      'cuerpo vacío': '',
    }.entries) {
      test('400 con cuerpo que ${caso.key} → genérico, sin lanzar otra excepción', () async {
        final e = await _falla(_api(MockClient((_) async => http.Response(caso.value, 400))).get('/x'));
        expect(e.mensaje, 'El servidor respondió 400');
      });
    }
  });

  group('DEFECTOS ENCONTRADOS (WB-HALLAZGO) — estos casos describen el comportamiento correcto', () {
    test('HALLAZGO-1: un 200 con cuerpo que NO es JSON debe ser ApiException, no FormatException', () async {
      // Antes de la corrección: jsonDecode lanzaba FormatException, que las pantallas que solo atrapan ApiException ignoraban.
      final e = await _falla(_api(MockClient((_) async => http.Response('<html>proxy</html>', 200))).get('/x'));
      expect(e.sinConexion, isFalse);
    });
  });
}
