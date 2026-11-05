import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/main.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/login_correo_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cuenta_correo_service.dart';
import 'package:vitasync_mobile/services/firmware_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

const _auth = 'http://auth:9099/identitytoolkit.googleapis.com';

http.Response _json(Object cuerpo, [int estado = 200]) => http.Response(
      jsonEncode(cuerpo),
      estado,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object> _sesionOk([String uid = 'uid-ana']) => {
      'localId': uid,
      'email': 'ana@uteq.test',
      'idToken': 'token-1',
      'refreshToken': 'refresco-1',
      'expiresIn': '3600',
    };

Map<String, Object> _errorFirebase(String codigo) => {
      'error': {'code': 400, 'message': codigo},
    };

/// Servicio real de correo contra un Authentication falso. Guarda las peticiones recibidas.
(HttpCuentaCorreoService, List<http.Request>, DateTime Function()) _servicio(
  http.Response Function(http.Request) responder, {
  DateTime Function()? reloj,
}) {
  final pedidas = <http.Request>[];
  final ahora = reloj ?? () => DateTime(2026, 11, 4, 12);
  final s = HttpCuentaCorreoService(
    authBase: _auth,
    apiKey: 'clave-web',
    ahora: ahora,
    cliente: MockClient((r) async {
      pedidas.add(r);
      return responder(r);
    }),
  );
  return (s, pedidas, ahora);
}

class _CorreoFalso implements CuentaCorreoService {
  _CorreoFalso({this.falla});

  final String? falla;
  SesionCorreo? _s;
  int entradas = 0;

  @override
  SesionCorreo? get sesion => _s;

  SesionCorreo _crear(String correo, String uid) => SesionCorreo(
        uid: uid,
        correo: correo,
        idToken: 't',
        refreshToken: 'r',
        expira: DateTime(2030),
      );

  @override
  Future<SesionCorreo> iniciarSesion(String correo, String clave) async {
    entradas++;
    if (falla != null) throw ApiException(falla!);
    return _s = _crear(correo, 'uid-prueba-123');
  }

  @override
  Future<SesionCorreo> registrarse(String correo, String clave) => iniciarSesion(correo, clave);

  @override
  Future<String?> token() async => _s?.idToken;

  @override
  void cerrarSesion() => _s = null;
}

class _UsuariosFalsos implements UsuarioRepository, CreadorDeCuentas {
  _UsuariosFalsos({this.cuentas = const [], this.errorAlCrear});

  final List<Usuario> cuentas;
  final String? errorAlCrear;
  final creadas = <(String, String)>[];

  @override
  Future<List<Usuario>> listarHabilitados() async => [...cuentas, for (final c in creadas) _de(c)];

  Usuario _de((String, String) c) =>
      Usuario(id: 'n-${c.$2}', nombreCompleto: c.$1, username: c.$2, habilitado: true);

  @override
  Future<Usuario> crearCuenta({required String nombreCompleto, required String username}) async {
    if (errorAlCrear != null) throw ApiException(errorAlCrear!);
    creadas.add((nombreCompleto, username));
    return _de((nombreCompleto, username));
  }
}

Widget _app(CuentaCorreoService? correo, UsuarioRepository usuarios) => VitaSyncMobileApp(
      usuarios: usuarios,
      saludPara: (_) => const MuestraSaludRepository(),
      firmwarePara: (_) => MuestraFirmwareRepository(),
      cuentaCorreo: correo,
    );

void main() {
  group('HttpCuentaCorreoService (Firebase Authentication por REST)', () {
    test('iniciar sesión manda correo y contraseña a Firebase y guarda uid y token', () async {
      final (s, pedidas, _) = _servicio((_) => _json(_sesionOk()));

      final sesion = await s.iniciarSesion(' ana@uteq.test ', 'Clave123');

      final p = pedidas.single;
      expect(p.method, 'POST');
      expect(p.url.path, '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword');
      expect(p.url.queryParameters['key'], 'clave-web');
      expect(jsonDecode(p.body), {'email': 'ana@uteq.test', 'password': 'Clave123', 'returnSecureToken': true});
      expect(sesion.uid, 'uid-ana');
      expect(s.sesion?.idToken, 'token-1');
    });

    test('contraseña incorrecta y correo inexistente dan el MISMO mensaje (no revela qué correos existen)', () async {
      for (final codigo in ['INVALID_LOGIN_CREDENTIALS', 'INVALID_PASSWORD', 'EMAIL_NOT_FOUND']) {
        final (s, _, _) = _servicio((_) => _json(_errorFirebase(codigo), 400));

        await expectLater(
          s.iniciarSesion('ana@uteq.test', 'mala'),
          throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'Correo o contraseña incorrectos.')),
        );
        expect(s.sesion, isNull, reason: codigo);
      }
    });

    test('campos vacíos se rechazan sin llamar al servidor', () async {
      final (s, pedidas, _) = _servicio((_) => _json(_sesionOk()));

      await expectLater(s.iniciarSesion('', ''), throwsA(isA<ApiException>()));
      await expectLater(s.iniciarSesion('ana@uteq.test', ''), throwsA(isA<ApiException>()));

      expect(pedidas, isEmpty);
    });

    test('registrarse usa signUp y explica correo repetido y contraseña débil', () async {
      final (s, pedidas, _) = _servicio((_) => _json(_sesionOk('uid-nuevo')));
      expect((await s.registrarse('nuevo@uteq.test', 'Clave123')).uid, 'uid-nuevo');
      expect(pedidas.single.url.path, endsWith('/v1/accounts:signUp'));

      final (repetido, _, _) = _servicio((_) => _json(_errorFirebase('EMAIL_EXISTS'), 400));
      await expectLater(
        repetido.registrarse('ana@uteq.test', 'Clave123'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('Ya existe'))),
      );

      final (debil, _, _) = _servicio((_) => _json(_errorFirebase('WEAK_PASSWORD : Password should be at least 6 characters'), 400));
      await expectLater(
        debil.registrarse('x@uteq.test', '123'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('débil'))),
      );
    });

    test('sin conexión con el servicio se informa claramente', () async {
      final s = HttpCuentaCorreoService(
        authBase: _auth,
        cliente: MockClient((_) async => throw Exception('sin red')),
      );

      await expectLater(
        s.iniciarSesion('ana@uteq.test', 'Clave123'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('inicio de sesión'))),
      );
    });

    test('token(): el vigente se reutiliza; cerca de vencer se renueva con el refresh token', () async {
      var hora = DateTime(2026, 11, 4, 12);
      final (s, pedidas, _) = _servicio((r) {
        if (r.url.path.contains('securetoken')) {
          return _json({'id_token': 'token-2', 'refresh_token': 'refresco-2', 'expires_in': '3600', 'user_id': 'uid-ana'});
        }
        return _json(_sesionOk());
      }, reloj: () => hora);
      await s.iniciarSesion('ana@uteq.test', 'Clave123');

      expect(await s.token(), 'token-1');
      expect(pedidas.length, 1, reason: 'no hace falta renovar todavía');

      hora = hora.add(const Duration(minutes: 59, seconds: 30)); // queda menos de 1 minuto
      expect(await s.token(), 'token-2');
      final renovacion = pedidas.last;
      expect(renovacion.url.host, 'auth');
      expect(renovacion.url.path, '/securetoken.googleapis.com/v1/token');
      expect(renovacion.bodyFields, {'grant_type': 'refresh_token', 'refresh_token': 'refresco-1'});
      expect(s.sesion?.uid, 'uid-ana', reason: 'el uid no cambia al renovar');
    });

    test('token() sin sesión es null y cerrarSesion borra la sesión', () async {
      final (s, _, _) = _servicio((_) => _json(_sesionOk()));
      expect(await s.token(), isNull);

      await s.iniciarSesion('ana@uteq.test', 'Clave123');
      s.cerrarSesion();

      expect(s.sesion, isNull);
      expect(await s.token(), isNull);
    });
  });

  group('ApiCliente con token (Práctica 10)', () {
    ApiCliente cliente(Future<String?> Function()? token, http.Response Function(http.Request) r, List<http.Request> out) =>
        ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          token: token,
          cliente: MockClient((p) async {
            out.add(p);
            return r(p);
          }),
        );

    test('manda Authorization: Bearer en GET, POST y POST con cuerpo', () async {
      final pedidas = <http.Request>[];
      final api = cliente(() async => 'abc', (_) => _json({}), pedidas);

      await api.get('/usuarios');
      await api.post('/smartwatch/connect', {'usuarioId': 'u1'});
      await api.postJson('/usuarios', {'a': 1});

      expect(pedidas.length, 3);
      for (final p in pedidas) {
        expect(p.headers['Authorization'], 'Bearer abc');
      }
      expect(pedidas.last.headers['content-type'], contains('application/json'));
    });

    test('sin token (seguridad apagada) no manda la cabecera', () async {
      final pedidas = <http.Request>[];
      final api = cliente(null, (_) => _json({}), pedidas);

      await api.get('/usuarios');

      expect(pedidas.single.headers.containsKey('Authorization'), isFalse);
    });

    test('401 y 403 se explican con mensajes claros', () async {
      final api401 = cliente(() async => 'viejo', (_) => _json({'error': 'x'}, 401), []);
      final api403 = cliente(() async => 'ok', (_) => _json({'error': 'x'}, 403), []);

      await expectLater(
        api401.get('/usuarios'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('sesión venció'))),
      );
      await expectLater(
        api403.get('/usuarios/otro'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('No tienes permiso'))),
      );
    });
  });

  group('HttpFirmwareRepository.vincularReloj', () {
    test('conecta el reloj y devuelve la clave que entrega el servidor', () async {
      final pedidas = <http.Request>[];
      final repo = HttpFirmwareRepository(
        usuarioId: 'u1',
        puedeVincular: true,
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((p) async {
            pedidas.add(p);
            return _json({'estado': 'CONECTADO', 'mensaje': 'ok', 'claveDispositivo': 'cafe1234'});
          }),
        ),
      );

      final reloj = await repo.vincularReloj();

      expect(pedidas.single.url.path, '/api/smartwatch/connect');
      expect(pedidas.single.url.queryParameters, {'usuarioId': 'u1'});
      expect(reloj?.clave, 'cafe1234');
      expect(reloj?.usuarioId, 'u1');
    });
  });

  group('LoginCorreoScreen', () {
    testWidgets('credenciales incorrectas: muestra el error y no avanza', (tester) async {
      final servicio = _CorreoFalso(falla: 'Correo o contraseña incorrectos.');
      var autenticado = false;
      await tester.pumpWidget(MaterialApp(
        home: LoginCorreoScreen(servicio: servicio, onAutenticado: () => autenticado = true),
      ));

      await tester.enterText(find.byKey(const Key('campo-correo')), 'ana@uteq.test');
      await tester.enterText(find.byKey(const Key('campo-clave')), 'mala');
      await tester.tap(find.byKey(const Key('btn-entrar')));
      await tester.pumpAndSettle();

      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
      expect(autenticado, isFalse);
      expect(servicio.sesion, isNull);
    });

    testWidgets('credenciales correctas: avisa que ya hay sesión', (tester) async {
      final servicio = _CorreoFalso();
      var autenticado = false;
      await tester.pumpWidget(MaterialApp(
        home: LoginCorreoScreen(servicio: servicio, onAutenticado: () => autenticado = true),
      ));

      await tester.enterText(find.byKey(const Key('campo-correo')), 'ana@uteq.test');
      await tester.enterText(find.byKey(const Key('campo-clave')), 'Clave123');
      await tester.tap(find.byKey(const Key('btn-entrar')));
      await tester.pumpAndSettle();

      expect(autenticado, isTrue);
      expect(find.byKey(const Key('error-acceso')), findsNothing);
    });
  });

  group('La app con la seguridad activa', () {
    testWidgets('empieza en el inicio de sesión con correo, no en la lista de cuentas', (tester) async {
      await tester.pumpWidget(_app(_CorreoFalso(), _UsuariosFalsos()));
      await tester.pumpAndSettle();

      expect(find.byType(LoginCorreoScreen), findsOneWidget);
      expect(find.text('¿Quién eres?'), findsNothing);
    });

    testWidgets('tras entrar muestra el correo y el UID de la sesión', (tester) async {
      await tester.pumpWidget(_app(_CorreoFalso(), _UsuariosFalsos()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('campo-correo')), 'ana@uteq.test');
      await tester.enterText(find.byKey(const Key('campo-clave')), 'Clave123');
      await tester.tap(find.byKey(const Key('btn-entrar')));
      await tester.pumpAndSettle();

      expect(find.text('Sesión: ana@uteq.test'), findsOneWidget);
      expect(find.text('UID: uid-prueba-123'), findsOneWidget);
    });

    testWidgets('cerrar sesión de correo vuelve al inicio de sesión', (tester) async {
      final correo = _CorreoFalso();
      await tester.pumpWidget(_app(correo, _UsuariosFalsos()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-correo')), 'ana@uteq.test');
      await tester.enterText(find.byKey(const Key('campo-clave')), 'Clave123');
      await tester.tap(find.byKey(const Key('btn-entrar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-cerrar-sesion-correo')));
      await tester.pumpAndSettle();

      expect(correo.sesion, isNull);
      expect(find.byType(LoginCorreoScreen), findsOneWidget);
    });

    testWidgets('una persona sin cuentas puede crear la suya', (tester) async {
      final usuarios = _UsuariosFalsos();
      await tester.pumpWidget(_app(_CorreoFalso(), usuarios));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-correo')), 'ana@uteq.test');
      await tester.enterText(find.byKey(const Key('campo-clave')), 'Clave123');
      await tester.tap(find.byKey(const Key('btn-entrar')));
      await tester.pumpAndSettle();
      expect(find.text('Aún no tienes ninguna cuenta VitaSync.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-crear-cuenta-vitasync')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-nombre')), 'Ana Pérez');
      await tester.enterText(find.byKey(const Key('campo-usuario')), 'ana.perez');
      await tester.tap(find.byKey(const Key('btn-guardar-cuenta')));
      await tester.pumpAndSettle();

      expect(usuarios.creadas, [('Ana Pérez', 'ana.perez')]);
      expect(find.text('Ana Pérez'), findsOneWidget, reason: 'la cuenta nueva aparece en la lista');
    });

    testWidgets('si el servidor rechaza la cuenta (usuario repetido) se muestra su mensaje', (tester) async {
      final usuarios = _UsuariosFalsos(errorAlCrear: 'Ya existe una cuenta con el usuario «ana».');
      await tester.pumpWidget(_app(_CorreoFalso(), usuarios));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-correo')), 'beto@uteq.test');
      await tester.enterText(find.byKey(const Key('campo-clave')), 'Clave123');
      await tester.tap(find.byKey(const Key('btn-entrar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-crear-cuenta-vitasync')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-nombre')), 'Beto');
      await tester.enterText(find.byKey(const Key('campo-usuario')), 'ana');
      await tester.tap(find.byKey(const Key('btn-guardar-cuenta')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ya existe una cuenta'), findsOneWidget);
      expect(usuarios.creadas, isEmpty);
    });

    testWidgets('sin seguridad (cuentaCorreo null) la app arranca como siempre, sin pedir correo', (tester) async {
      await tester.pumpWidget(_app(null, _UsuariosFalsos(cuentas: const [
        Usuario(id: 'u1', nombreCompleto: 'Ana Torres', username: 'ana', habilitado: true),
      ])));
      await tester.pumpAndSettle();

      expect(find.byType(LoginCorreoScreen), findsNothing);
      expect(find.text('Ana Torres'), findsOneWidget);
      expect(find.byKey(const Key('sesion-uid')), findsNothing);
    });
  });
}
