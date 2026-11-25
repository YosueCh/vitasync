// PRÁCTICA 12 · Fase 5 · Matriz de resiliencia RES-01 … RES-08 con SOCKETS REALES (dart:io).
//
// Un servidor HTTP de laboratorio falla de formas controladas y se mide, para cada escenario, el comportamiento
// ANTES (ApiCliente sin reintentos, como estaba) y DESPUÉS (ApiCliente con reintento y espera progresiva +
// idempotencia por idCliente). Cada resultado se imprime como «RES|código|variante|…» para guardarlo como evidencia.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vitasync_mobile/models/mensaje_chat.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/politica_reintento.dart';

// ignore: avoid_print
void res(String codigo, String variante, Object dato) => print('RES|$codigo|$variante|$dato');

/// Servidor de laboratorio. Todo se configura por campos para provocar cada fallo.
class Laboratorio {
  late HttpServer _servidor;
  final List<Socket> _conexiones = [];
  int get puerto => _servidor.port;

  String modo = 'normal'; // normal | cortar | colgar | e500 | e401 | e403
  int fallarPrimeras = 0; // cortar la conexión en las N primeras peticiones y luego funcionar
  int retrasarPrimeras = 0; // contestar con retraso (después de guardar) en las N primeras peticiones de escritura
  Duration retraso = const Duration(seconds: 5);
  int perderRespuestaTrasGuardar = 0; // guardar y luego cortar sin contestar
  bool deduplica = true;

  int peticiones = 0;
  final List<Map<String, dynamic>> guardados = [];
  final Set<String> _ids = {};

  Future<void> iniciar() async {
    _servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _servidor.listen((peticion) async {
      final cuerpo = await utf8.decoder.bind(peticion).join();
      final s = await peticion.response.detachSocket(writeHeaders: false);
      _conexiones.add(s);
      peticiones++;
      if (fallarPrimeras > 0) {
        fallarPrimeras--;
        s.destroy();
        return;
      }
      switch (modo) {
        case 'cortar':
          s.destroy();
          return;
        case 'colgar':
          return;
        case 'e500':
          return _responder(s, 500, {'error': 'Ocurrió un error en el servidor.'});
        case 'e401':
          return _responder(s, 401, {'error': 'Sesión inválida.'});
        case 'e403':
          return _responder(s, 403, {'error': 'Sin permiso.'});
      }
      if (peticion.method == 'POST' && peticion.uri.path.endsWith('/mensajes')) {
        final datos = jsonDecode(cuerpo) as Map<String, dynamic>;
        final id = datos['idCliente'] as String?;
        final repetido = deduplica && id != null && !_ids.add(id);
        if (!repetido) guardados.add(datos);
        if (perderRespuestaTrasGuardar > 0) {
          perderRespuestaTrasGuardar--;
          s.destroy();
          return;
        }
        if (retrasarPrimeras > 0) {
          retrasarPrimeras--;
          await Future<void>.delayed(retraso);
        }
        return _responder(s, 200, {'id': guardados.length, 'emisor': datos['emisor'], 'texto': datos['texto']});
      }
      _responder(s, 200, {'ok': true});
    });
  }

  void _responder(Socket s, int estado, Object cuerpo) {
    final json = jsonEncode(cuerpo);
    try {
      s.write('HTTP/1.1 $estado X\r\ncontent-type: application/json; charset=utf-8\r\ncontent-length: ${utf8.encode(json).length}\r\nconnection: close\r\n\r\n$json');
      s.close();
    } on Object {
      // el cliente ya se fue (tiempo agotado)
    }
  }

  Future<void> detener() async {
    for (final c in _conexiones) {
      c.destroy();
    }
    await _servidor.close(force: true);
  }
}

Future<ApiException> _falla(Future<dynamic> f) async {
  try {
    await f;
  } on ApiException catch (e) {
    return e;
  }
  fail('se esperaba ApiException');
}

void main() {
  late Laboratorio lab;
  setUp(() async {
    HttpOverrides.global = null;
    lab = Laboratorio();
    await lab.iniciar();
  });
  tearDown(() => lab.detener());

  ApiCliente antes() => ApiCliente(baseUrl: 'http://127.0.0.1:${lab.puerto}/api', cliente: http.Client());
  ApiCliente despues() =>
      ApiCliente(baseUrl: 'http://127.0.0.1:${lab.puerto}/api', cliente: http.Client(), reintentos: PoliticaReintento.estandar);
  ChatRepository chat(ApiCliente a) => HttpChatRepository(api: a);

  group('RES-01 · Pérdida de Internet durante una consulta', () {
    test('caída persistente: error controlado en ambas versiones', () async {
      lab.modo = 'cortar';
      var t = Stopwatch()..start();
      final a = await _falla(antes().get('/x'));
      final tAntes = t.elapsedMilliseconds;
      expect(a.sinConexion, isTrue);
      final peticionesAntes = lab.peticiones;

      lab.peticiones = 0;
      t = Stopwatch()..start();
      final d = await _falla(despues().get('/x'));
      final tDespues = t.elapsedMilliseconds;
      expect(d.sinConexion, isTrue);
      res('RES-01', 'ANTES', 'error sinConexion detectado en $tAntes ms; peticiones al servidor: $peticionesAntes');
      res('RES-01', 'DESPUES', 'error sinConexion tras agotar reintentos en $tDespues ms; peticiones al servidor: ${lab.peticiones} (1 + 2 reintentos con espera 0,3 s y 0,6 s)');
      expect(lab.peticiones, 3);
    });

    test('caída transitoria (2 peticiones cortadas y luego vuelve): ANTES error; DESPUÉS se recupera sola', () async {
      lab.fallarPrimeras = 2;
      final a = await _falla(antes().get('/x'));
      expect(a.sinConexion, isTrue);

      lab.fallarPrimeras = 2;
      lab.peticiones = 0;
      final t = Stopwatch()..start();
      final r = await despues().get('/x');
      res('RES-01', 'ANTES(transitoria)', 'el usuario ve el error «${a.mensaje}»');
      res('RES-01', 'DESPUES(transitoria)', 'respuesta correcta sin intervención en ${t.elapsedMilliseconds} ms con ${lab.peticiones} peticiones');
      expect(r, {'ok': true});
    });
  });

  group('RES-02 · Pérdida de Internet durante una escritura: nunca se confirma falsamente', () {
    test('el servidor no se alcanza: la escritura lanza error y no se guardó nada', () async {
      lab.modo = 'cortar';
      final e = await _falla(chat(despues()).enviar('u1', RolChat.paciente, 'hola'));
      expect(e.sinConexion, isTrue);
      expect(lab.guardados, isEmpty);
      res('RES-02', 'DESPUES', 'escritura sin red → ApiException(sinConexion); el servidor guardó ${lab.guardados.length}; no se confirmó');
    });

    test('el servidor GUARDA pero la respuesta se pierde: sin idCliente no se reintenta (no se arriesga a duplicar)', () async {
      lab.perderRespuestaTrasGuardar = 1;
      final e = await _falla(chat(despues()).enviar('u1', RolChat.paciente, 'hola'));
      expect(e.sinConexion, isTrue);
      res('RES-02', 'DESPUES(sin idCliente)', 'error mostrado; peticiones=${lab.peticiones} (NO se reintenta); guardados=${lab.guardados.length} (estado incierto, la app lo deja pendiente)');
      expect(lab.peticiones, 1);
    });
  });

  group('RES-03 · Servidor sin respuesta: tiempo límite controlado', () {
    test('la app corta a los 4 s (ANTES) y a ≈13 s tras 2 reintentos (DESPUÉS)', () async {
      lab.modo = 'colgar';
      var t = Stopwatch()..start();
      final a = await _falla(antes().get('/x'));
      final tAntes = t.elapsedMilliseconds;
      expect(a.sinConexion, isTrue);
      expect(tAntes, inInclusiveRange(3900, 5000));

      lab.peticiones = 0;
      t = Stopwatch()..start();
      final d = await _falla(despues().get('/x'));
      final tDespues = t.elapsedMilliseconds;
      expect(d.sinConexion, isTrue);
      res('RES-03', 'ANTES', 'timeout controlado en $tAntes ms (1 intento)');
      res('RES-03', 'DESPUES', 'timeout controlado tras $tDespues ms (${lab.peticiones} intentos de 4 s + esperas 0,3 s y 0,6 s)');
    }, timeout: const Timeout(Duration(seconds: 40)));
  });

  group('RES-04 · HTTP 500: error visible y la app sigue estable', () {
    test('500 no se reintenta, el mensaje es claro y la siguiente petición funciona', () async {
      lab.modo = 'e500';
      final e = await _falla(despues().get('/x'));
      expect(e.sinConexion, isFalse);
      expect(e.mensaje, contains('500'));
      expect(lab.peticiones, 1);
      lab.modo = 'normal';
      expect(await despues().get('/x'), {'ok': true});
      res('RES-04', 'ANTES/DESPUES', 'mensaje «${e.mensaje}», sinConexion=false, peticiones=1 (no se reintenta un 500); la petición siguiente responde 200');
    });
  });

  group('RES-05 · HTTP 401 / 403', () {
    test('401 → «sesión venció» y 403 → «sin permiso»; ninguno se reintenta', () async {
      lab.modo = 'e401';
      final e401 = await _falla(despues().get('/x'));
      final p401 = lab.peticiones;
      lab.modo = 'e403';
      lab.peticiones = 0;
      final e403 = await _falla(despues().get('/x'));
      expect(e401.mensaje, contains('sesión'));
      expect(e403.mensaje, contains('permiso'));
      expect(p401, 1);
      expect(lab.peticiones, 1);
      res('RES-05', 'ANTES/DESPUES', '401 → «${e401.mensaje}» (1 petición); 403 → «${e403.mensaje}» (1 petición)');
    });
  });

  group('RES-06 · Recuperación de conexión', () {
    test('el servidor vuelve a los 700 ms: ANTES el usuario debe reintentar a mano; DESPUÉS se restablece solo', () async {
      lab.modo = 'cortar';
      Timer(const Duration(milliseconds: 700), () => lab.modo = 'normal');
      var t = Stopwatch()..start();
      final a = await _falla(antes().get('/x'));
      final tFallo = t.elapsedMilliseconds;
      expect(a.sinConexion, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 800)); // el usuario espera y vuelve a tocar
      expect(await antes().get('/x'), {'ok': true});
      final tManual = t.elapsedMilliseconds;

      lab.modo = 'cortar';
      Timer(const Duration(milliseconds: 700), () => lab.modo = 'normal');
      lab.peticiones = 0;
      t = Stopwatch()..start();
      expect(await despues().get('/x'), {'ok': true});
      final tAuto = t.elapsedMilliseconds;
      res('RES-06', 'ANTES', 'error a los $tFallo ms; la comunicación se restablece solo cuando el usuario vuelve a intentar (≈$tManual ms desde el inicio)');
      res('RES-06', 'DESPUES', 'restablecida automáticamente en $tAuto ms con ${lab.peticiones} peticiones, sin acción del usuario');
    });
  });

  group('RES-07 · Reintento de una escritura sin duplicados', () {
    test('ANTES (sin idCliente): el mensaje guardado queda DUPLICADO al reenviarlo', () async {
      lab.perderRespuestaTrasGuardar = 1;
      final repo = chat(antes());
      await _falla(repo.enviar('u1', RolChat.paciente, 'hola'));
      await repo.enviar('u1', RolChat.paciente, 'hola'); // el usuario reenvía
      res('RES-07', 'ANTES(sin idCliente)', 'mensajes guardados: ${lab.guardados.length}');
      expect(lab.guardados.length, 2);
    });

    test('DESPUÉS (idCliente + reintento automático): 1 solo mensaje y el usuario ni se entera', () async {
      lab.perderRespuestaTrasGuardar = 1;
      final t = Stopwatch()..start();
      await chat(despues()).enviar('u1', RolChat.paciente, 'hola', idCliente: 'abc123def4567890');
      res('RES-07', 'DESPUES(idCliente)', 'mensajes guardados: ${lab.guardados.length}; peticiones: ${lab.peticiones}; tiempo ${t.elapsedMilliseconds} ms');
      expect(lab.guardados.length, 1);
      expect(lab.peticiones, 2);
    });

    test('ANTES con idCliente pero sin reintento automático: el reenvío manual tampoco duplica', () async {
      lab.perderRespuestaTrasGuardar = 1;
      final repo = chat(antes());
      await _falla(repo.enviar('u1', RolChat.paciente, 'hola', idCliente: 'id-manual'));
      await repo.enviar('u1', RolChat.paciente, 'hola', idCliente: 'id-manual');
      expect(lab.guardados.length, 1);
    });
  });

  group('RES-08 · Respuesta tardía: sin duplicados ni inconsistencias', () {
    test('el servidor guarda pero tarda 5 s: la app corta a 4 s y el reintento NO duplica', () async {
      lab.retrasarPrimeras = 1;
      final t = Stopwatch()..start();
      await chat(despues()).enviar('u1', RolChat.paciente, 'tardío', idCliente: 'idtardio000001');
      final ms = t.elapsedMilliseconds;
      // Espera a que la primera respuesta tardía termine de llegar al servidor (se ignora en el cliente).
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      res('RES-08', 'DESPUES', 'confirmado a los $ms ms (timeout 4 s + reintento); mensajes guardados: ${lab.guardados.length}; peticiones: ${lab.peticiones}');
      expect(lab.guardados.length, 1);
      expect(ms, inInclusiveRange(4000, 6500));
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('ANTES sin idCliente: el usuario ve error, reenvía, y el mensaje queda DUPLICADO', () async {
      lab.retrasarPrimeras = 1;
      final repo = chat(antes());
      await _falla(repo.enviar('u1', RolChat.paciente, 'tardío'));
      await repo.enviar('u1', RolChat.paciente, 'tardío');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      res('RES-08', 'ANTES(sin idCliente)', 'mensajes guardados: ${lab.guardados.length}');
      expect(lab.guardados.length, 2);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
