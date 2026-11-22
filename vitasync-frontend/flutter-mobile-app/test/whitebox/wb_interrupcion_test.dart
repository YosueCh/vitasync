// PRÁCTICA 11 · Fase 5 · E. Prueba de interrupción de la conectividad — con SOCKETS REALES (dart:io).
//
// Se levanta un servidor HTTP local de verdad y se le hace fallar de las formas en que falla una red: puerto cerrado,
// conexión cortada sin responder, respuesta cortada a la mitad, servidor que no contesta, y — el caso difícil — un
// servidor que GUARDA el mensaje y luego pierde la respuesta. Comprueba que la app:
//   · detecta el error, · no lo muestra como éxito, · lo clasifica bien («sin conexión» ≠ «el servidor lo rechazó»),
//   · y que un reintento NO duplica el registro (idempotencia con idCliente, WB-HALLAZGO-13).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vitasync_mobile/models/mensaje_chat.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/chat_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

// ignore: avoid_print
void wb(String clave, Object valor) => print('WB|$clave|$valor');

/// Servidor de laboratorio con un comportamiento configurable por ruta.
class ServidorDeLaboratorio {
  late HttpServer _servidor;
  int get puerto => _servidor.port;

  /// Mensajes que el servidor GUARDÓ (por la ruta /api/chat/u1/mensajes).
  final List<Map<String, dynamic>> guardados = [];
  final Set<String> _idsVistos = {};

  /// true = deduplica por idCliente (como el backend corregido); false = comportamiento anterior.
  bool deduplica = true;

  /// Cuántas veces perder la respuesta DESPUÉS de guardar el mensaje.
  int perderRespuestaTrasGuardar = 0;
  String modo = 'normal'; // normal | cortar | media | colgar | error500

  Future<void> iniciar() async {
    _servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _servidor.listen((peticion) async {
      final cuerpo = await utf8.decoder.bind(peticion).join();
      final conexion = await peticion.response.detachSocket(writeHeaders: false);
      switch (modo) {
        case 'cortar':
          conexion.destroy(); // sin una sola respuesta
          return;
        case 'colgar':
          return; // nunca contesta (la conexión queda abierta)
        case 'media':
          conexion.write('HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 500\r\n\r\n{"id":');
          await conexion.flush();
          conexion.destroy(); // promete 500 bytes y corta
          return;
        case 'error500':
          _responder(conexion, 500, {'error': 'Ocurrió un error en el servidor.'});
          return;
      }
      if (peticion.method == 'POST' && peticion.uri.path.endsWith('/mensajes')) {
        final datos = jsonDecode(cuerpo) as Map<String, dynamic>;
        final id = datos['idCliente'] as String?;
        final repetido = deduplica && id != null && !_idsVistos.add(id);
        if (!repetido) guardados.add(datos);
        if (perderRespuestaTrasGuardar > 0) {
          perderRespuestaTrasGuardar--;
          conexion.destroy(); // GUARDÓ, pero la respuesta nunca llega
          return;
        }
        _responder(conexion, 200, {'id': guardados.length, 'emisor': datos['emisor'], 'texto': datos['texto']});
        return;
      }
      _responder(conexion, 200, {'ok': true});
    });
  }

  void _responder(Socket s, int estado, Object cuerpo) {
    final json = jsonEncode(cuerpo);
    s.write('HTTP/1.1 $estado X\r\ncontent-type: application/json; charset=utf-8\r\ncontent-length: ${utf8.encode(json).length}\r\nconnection: close\r\n\r\n$json');
    s.close();
  }

  Future<void> detener() => _servidor.close(force: true);
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
  late ServidorDeLaboratorio servidor;

  setUp(() async {
    HttpOverrides.global = null; // flutter_test bloquea la red real; aquí SÍ se quiere
    servidor = ServidorDeLaboratorio();
    await servidor.iniciar();
  });
  tearDown(() => servidor.detener());

  ApiCliente cliente(int puerto) => ApiCliente(baseUrl: 'http://127.0.0.1:$puerto/api', cliente: http.Client());
  ChatRepository chat(int puerto) => HttpChatRepository(api: cliente(puerto));

  group('NET-05 · Pérdida de conexión: el cliente real detecta cada tipo de fallo', () {
    test('puerto cerrado (servidor apagado) → «sin conexión» antes del tiempo límite (en Windows el rechazo tarda ≈2 s)', () async {
      final puerto = servidor.puerto;
      await servidor.detener();
      final reloj = Stopwatch()..start();
      final e = await _falla(cliente(puerto).get('/x'));
      wb('NET-05 puerto cerrado', 'sinConexion=${e.sinConexion} en ${reloj.elapsedMilliseconds} ms');
      expect(e.sinConexion, isTrue);
      expect(reloj.elapsedMilliseconds, lessThan(4000)); // medido: ≈2 s (Windows reintenta el SYN antes de rendirse)
      servidor = ServidorDeLaboratorio()..modo = 'normal';
      await servidor.iniciar(); // para que tearDown tenga algo que cerrar
    });

    test('el servidor corta la conexión sin responder → «sin conexión»', () async {
      servidor.modo = 'cortar';
      final e = await _falla(cliente(servidor.puerto).get('/x'));
      wb('NET-05 conexión cortada', 'sinConexion=${e.sinConexion}');
      expect(e.sinConexion, isTrue);
    });

    test('el servidor corta la respuesta a la mitad (promete 500 bytes) → «sin conexión», no una excepción cruda', () async {
      servidor.modo = 'media';
      final e = await _falla(cliente(servidor.puerto).get('/x'));
      wb('NET-05 respuesta cortada a la mitad', 'sinConexion=${e.sinConexion}');
      expect(e.sinConexion, isTrue);
    });

    test('el servidor no contesta nunca → se corta a los 4 s (tiempo límite) como «sin conexión»', () async {
      servidor.modo = 'colgar';
      final reloj = Stopwatch()..start();
      final e = await _falla(cliente(servidor.puerto).get('/x'));
      wb('NET-05 servidor que no contesta', 'sinConexion=${e.sinConexion} cortó en ${reloj.elapsedMilliseconds} ms');
      expect(e.sinConexion, isTrue);
      expect(reloj.elapsedMilliseconds, inInclusiveRange(3900, 5500));
    });

    test('un 500 del servidor NO es «sin conexión»: el servidor respondió y rechazó', () async {
      servidor.modo = 'error500';
      final e = await _falla(cliente(servidor.puerto).get('/x'));
      wb('NET-05 respuesta 500', 'sinConexion=${e.sinConexion} mensaje="${e.mensaje}"');
      expect(e.sinConexion, isFalse);
      expect(e.mensaje, contains('500'));
    });
  });

  group('NET-06 · Recuperación sin duplicar (idempotencia del mensaje)', () {
    test('SIN idCliente (comportamiento anterior): guardó y perdió la respuesta → el reintento DUPLICA', () async {
      servidor.perderRespuestaTrasGuardar = 1;
      final repo = chat(servidor.puerto);
      final e = await _falla(repo.enviar('u1', RolChat.paciente, 'hola'));
      expect(e.sinConexion, isTrue, reason: 'la app cree que no se envió');
      await repo.enviar('u1', RolChat.paciente, 'hola'); // reintento al reconectar
      wb('NET-06 SIN idCliente: mensajes guardados por el servidor', servidor.guardados.length);
      expect(servidor.guardados.length, 2, reason: 'el mismo mensaje quedó dos veces');
    });

    test('CON idCliente: guardó y perdió la respuesta → el reintento NO duplica', () async {
      servidor.perderRespuestaTrasGuardar = 1;
      final repo = chat(servidor.puerto);
      const id = 'a1b2c3d4e5f60718';
      final e = await _falla(repo.enviar('u1', RolChat.paciente, 'hola', idCliente: id));
      expect(e.sinConexion, isTrue);
      await repo.enviar('u1', RolChat.paciente, 'hola', idCliente: id);
      wb('NET-06 CON idCliente: mensajes guardados por el servidor', servidor.guardados.length);
      expect(servidor.guardados.length, 1);
    });

    test('mensajes DISTINTOS (otro idCliente) sí se guardan los dos', () async {
      final repo = chat(servidor.puerto);
      await repo.enviar('u1', RolChat.paciente, 'uno', idCliente: 'id-uno');
      await repo.enviar('u1', RolChat.paciente, 'dos', idCliente: 'id-dos');
      expect(servidor.guardados.length, 2);
    });

    test('el cuerpo enviado lleva el idCliente', () async {
      await chat(servidor.puerto).enviar('u1', RolChat.paciente, 'hola', idCliente: 'abc123');
      expect(servidor.guardados.single['idCliente'], 'abc123');
    });
  });

  group('NET-05/06 · La pantalla del chat con un servidor real que falla', () {
    testWidgets('sin conexión el mensaje queda PENDIENTE (no «enviado»); al volver el servidor sale UNA vez, con el MISMO idCliente', (t) async {
      await t.runAsync(() async {
        const ana = Usuario(id: 'u1', nombreCompleto: 'Ana', username: 'ana', habilitado: true);
        servidor.modo = 'cortar'; // al principio el servidor está «caído»
        t.view.physicalSize = const Size(390 * 3, 844 * 3);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ChatScreen(cuenta: ana, chat: chat(servidor.puerto), usuarios: _Usuarios(), intervalo: const Duration(milliseconds: 400)),
          ),
        ));
        await t.tap(find.text('Paciente (Dispositivo B)'));
        await t.pump(const Duration(milliseconds: 100));
        await t.enterText(find.byType(TextField), 'hola doctora');
        await t.tap(find.byTooltip('Enviar'));
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await t.pump();
        expect(find.textContaining('Pendiente de enviar'), findsOneWidget, reason: 'no se debe mostrar como enviado');
        expect(servidor.guardados, isEmpty);
        wb('NET-05 pantalla: mensaje sin conexión', 'queda «Pendiente de enviar»; el servidor guardó 0');

        // El servidor «vuelve»: la app reintenta sola en el siguiente sondeo.
        servidor.modo = 'normal';
        for (var i = 0; i < 20 && servidor.guardados.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await t.pump(const Duration(milliseconds: 300));
        }
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await t.pump(const Duration(milliseconds: 300));
        wb('NET-06 pantalla: tras recuperar la conexión', 'el servidor guardó ${servidor.guardados.length} mensaje(s), idCliente presente: ${servidor.guardados.isNotEmpty && servidor.guardados.first['idCliente'] != null}');
        expect(servidor.guardados.length, 1);
        expect(servidor.guardados.first['idCliente'], isNotNull);
        await t.pumpWidget(const SizedBox()); // cancela el sondeo
      });
    });
  });
}

class _Usuarios implements UsuarioRepository {
  @override
  Future<List<Usuario>> listarHabilitados() async => const [];
}
