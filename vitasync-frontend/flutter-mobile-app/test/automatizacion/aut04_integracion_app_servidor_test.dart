// PRÁCTICAS 13 y 14 · AUT-04 · Pruebas de INTEGRACIÓN: los componentes REALES de la app (inicio de sesión, ApiCliente y repositorio de
// metas) hablan por SOCKETS REALES (dart:io) con un servidor HTTP local que imita al backend y a Firebase Authentication.
// Se comprueba lo que viaja por el cable (ruta, cabeceras, cuerpo) y lo que la app hace con cada respuesta.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cuenta_correo_service.dart';
import 'package:vitasync_mobile/services/metas_repository.dart';

typedef Responder = FutureOr<void> Function(HttpRequest peticion, String cuerpo);

class Servidor {
  late HttpServer _s;
  final List<({String metodo, String ruta, Map<String, String> cabeceras, String cuerpo})> recibidas = [];
  Responder responder = (p, _) {};
  int get puerto => _s.port;

  Future<void> iniciar() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((p) async {
      final cuerpo = await utf8.decoder.bind(p).join();
      recibidas.add((
        metodo: p.method,
        ruta: p.uri.toString(),
        cabeceras: {for (final e in {'authorization': p.headers.value('authorization'), 'content-type': p.headers.contentType?.mimeType}.entries) e.key: e.value ?? ''},
        cuerpo: cuerpo,
      ));
      await responder(p, cuerpo);
    });
  }

  Future<void> detener() => _s.close(force: true);
}

Future<void> json(HttpRequest p, int estado, Object cuerpo) async {
  p.response
    ..statusCode = estado
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(cuerpo));
  await p.response.close();
}

const _metas = {'metaPasos': 9000, 'metaCalorias': 500, 'metaSueno': 7.5, 'version': 4, 'actualizadaPor': 'Paciente'};

void main() {
  late Servidor srv;
  setUp(() async {
    HttpOverrides.global = null; // flutter_test bloquea la red real; aquí SÍ se quiere
    srv = Servidor();
    await srv.iniciar();
  });
  tearDown(() => srv.detener());

  ApiCliente api({Future<String?> Function()? token}) => ApiCliente(baseUrl: 'http://127.0.0.1:${srv.puerto}/api', cliente: http.Client(), token: token);
  HttpMetasRepository metas(ApiCliente a) => HttpMetasRepository(usuarioId: 'cuenta-1', api: a);

  test('AUT-04 · la app guarda una meta: viaja PUT /metas con el cuerpo correcto y la respuesta 200 se convierte en MetasCuenta', () async {
    srv.responder = (p, _) => json(p, 200, _metas);
    final r = await metas(api()).guardar(pasos: 9000, version: 3);

    expect(srv.recibidas.single.metodo, 'PUT');
    expect(srv.recibidas.single.ruta, '/api/metas?usuarioId=cuenta-1');
    expect(jsonDecode(srv.recibidas.single.cuerpo), {'metaPasos': 9000, 'version': 3});
    expect(srv.recibidas.single.cabeceras['content-type'], 'application/json');
    expect(r.metaPasos, 9000);
    expect(r.version, 4);
  });

  test('AUT-04 · 409 CONFLICTO_DE_VERSION → ConflictoDeMetas con las metas ACTUALES del servidor', () async {
    srv.responder = (p, _) => json(p, 409, {'error': 'Otro dispositivo cambió tus metas (versión 4).', 'codigo': 'CONFLICTO_DE_VERSION', 'actual': _metas});
    await expectLater(
      metas(api()).guardar(pasos: 8000, version: 3),
      throwsA(isA<ConflictoDeMetas>().having((c) => c.actual.version, 'versión actual', 4).having((c) => c.actual.metaPasos, 'pasos actuales', 9000)),
    );
  });

  test('AUT-04 · 409 OCUPADO (contención) y 400 (dato inválido) muestran el mensaje del servidor, no un código', () async {
    srv.responder = (p, _) => json(p, 409, {'error': 'Hay otra operación en curso con tus metas. Inténtalo de nuevo.', 'codigo': 'OCUPADO'});
    await expectLater(metas(api()).guardar(pasos: 8000),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('Inténtalo de nuevo')).having((e) => e.codigo, 'codigo', 'OCUPADO')));

    srv.responder = (p, _) => json(p, 400, {'error': 'La meta de pasos debe estar entre 1000 y 50000.'});
    await expectLater(metas(api()).guardar(pasos: 5), throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'La meta de pasos debe estar entre 1000 y 50000.')));
  });

  test('AUT-04 · 401 y 403 → mensajes de sesión y de permiso; 500 → mensaje genérico sin detalles internos', () async {
    final casos = {401: 'Tu sesión venció. Vuelve a iniciar sesión.', 403: 'No tienes permiso para ver estos datos.', 500: 'El servidor respondió 500'};
    for (final c in casos.entries) {
      srv.responder = (p, _) => json(p, c.key, {'error': 'detalle interno que no debe mostrarse'});
      await expectLater(metas(api()).obtener(), throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', c.value)), reason: 'HTTP ${c.key}');
    }
  });

  test('AUT-04 · el servidor NO responde (conexión cortada) → mensaje adecuado «No se pudo conectar al servidor» y sinConexion', () async {
    srv.responder = (p, _) async => (await p.response.detachSocket(writeHeaders: false)).destroy();
    await expectLater(
      metas(api()).obtener(),
      throwsA(isA<ApiException>().having((e) => e.sinConexion, 'sinConexion', true).having((e) => e.mensaje, 'mensaje', 'No se pudo conectar al servidor')),
    );
  });

  test('AUT-04 · inicio de sesión → token → API: el token que entrega el servicio de login viaja en «Authorization: Bearer»', () async {
    // El mismo servidor local hace de Firebase Authentication (ruta /v1/accounts:signInWithPassword) y de backend (/api/...).
    srv.responder = (p, _) {
      if (p.uri.path == '/v1/accounts:signInWithPassword') {
        return json(p, 200, {'localId': 'uid-1', 'email': 'ana@uteq.test', 'idToken': 'TOKEN-REAL-1', 'refreshToken': 'r', 'expiresIn': '3600'});
      }
      return json(p, 200, _metas);
    };
    final login = HttpCuentaCorreoService(authBase: 'http://127.0.0.1:${srv.puerto}', apiKey: 'k', cliente: http.Client());
    await login.iniciarSesion('ana@uteq.test', 'Clave-123');
    final m = await metas(api(token: login.token)).obtener();

    final alApi = srv.recibidas.last;
    expect(alApi.ruta, startsWith('/api/metas'));
    expect(alApi.cabeceras['authorization'], 'Bearer TOKEN-REAL-1');
    expect(m.version, 4);
  });

  test('AUT-04 · un correo o contraseña incorrectos en el servicio de login llegan a la app como mensaje claro (y no queda sesión)', () async {
    srv.responder = (p, _) => json(p, 400, {'error': {'code': 400, 'message': 'INVALID_LOGIN_CREDENTIALS'}});
    final login = HttpCuentaCorreoService(authBase: 'http://127.0.0.1:${srv.puerto}', apiKey: 'k', cliente: http.Client());
    await expectLater(login.iniciarSesion('ana@uteq.test', 'mala'), throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'Correo o contraseña incorrectos.')));
    expect(login.sesion, isNull);
  });
}
