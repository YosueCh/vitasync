import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/chat_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

/// D-06 de la Práctica 8: los cuatro detalles de interfaz (lista de cuentas sin orden estable, selector de rol
/// desalineado, aviso inferior que tapaba «Abrir chat nuevo» y espera larga sin servidor).

const _ana = Usuario(id: 'ana1', nombreCompleto: 'Ana Torres', username: 'ana', habilitado: true);
const _luis = Usuario(id: 'luis1', nombreCompleto: 'Luis Pérez', username: 'luis', habilitado: true);

class _Usuarios implements UsuarioRepository {
  @override
  Future<List<Usuario>> listarHabilitados() async => const [_ana, _luis];
}

http.Response _json(Object cuerpo) =>
    http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, Object> _cuenta(String id, String nombre, String usuario, {bool habilitada = true}) =>
    {'id': id, 'nombreCompleto': nombre, 'username': usuario, 'habilitado': habilitada};

Future<void> _abrirChat(WidgetTester tester, ChatRepository chat, {Size pantalla = const Size(390, 844)}) async {
  tester.view.physicalSize = Size(pantalla.width * 3, pantalla.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: ChatScreen(cuenta: _ana, chat: chat, usuarios: _Usuarios())),
  ));
}

Future<void> _avanzar(WidgetTester tester, [Duration tiempo = Duration.zero]) async {
  await tester.pump(tiempo);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Lista de cuentas con orden estable', () {
    test('se ordena por nombre sin distinguir mayúsculas, sin importar el orden del servidor', () async {
      final repo = HttpUsuarioRepository(
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((_) async => _json([
                _cuenta('3', 'zoe Díaz', 'zoe'),
                _cuenta('1', 'Beto Ruiz', 'beto'),
                _cuenta('2', 'ana Pérez', 'ana'),
                _cuenta('4', 'Carla Soto', 'carla'),
              ])),
        ),
      );

      final nombres = (await repo.listarHabilitados()).map((u) => u.nombreCompleto).toList();

      expect(nombres, ['ana Pérez', 'Beto Ruiz', 'Carla Soto', 'zoe Díaz']);
    });

    test('con el mismo nombre desempata por usuario, y las deshabilitadas no aparecen', () async {
      final repo = HttpUsuarioRepository(
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((_) async => _json([
                _cuenta('2', 'Ana Pérez', 'ana2'),
                _cuenta('9', 'Ana Pérez', 'ana0', habilitada: false),
                _cuenta('1', 'Ana Pérez', 'ana1'),
              ])),
        ),
      );

      expect((await repo.listarHabilitados()).map((u) => u.username), ['ana1', 'ana2']);
    });

    test('dos consultas con respuestas en distinto orden dan la MISMA lista', () async {
      Future<List<String>> consultar(List<Map<String, Object>> respuesta) async {
        final repo = HttpUsuarioRepository(
          api: ApiCliente(baseUrl: 'http://s/api', cliente: MockClient((_) async => _json(respuesta))),
        );
        return (await repo.listarHabilitados()).map((u) => u.id).toList();
      }

      final a = [_cuenta('1', 'Ana', 'a'), _cuenta('2', 'Beto', 'b'), _cuenta('3', 'Carla', 'c')];
      expect(await consultar(a), await consultar(a.reversed.toList()));
    });
  });

  group('Selector de rol del chat', () {
    testWidgets('«Soy:» va arriba y las dos opciones debajo, alineadas a la izquierda, sin desbordes (pantalla angosta)',
        (tester) async {
      await _abrirChat(tester, MuestraChatRepository(), pantalla: const Size(320, 640));

      final soy = tester.getTopLeft(find.text('Soy:'));
      final medico = tester.getTopLeft(find.byKey(const Key('rol-medico')));
      final paciente = tester.getTopLeft(find.byKey(const Key('rol-paciente')));

      expect(tester.takeException(), isNull, reason: 'nada se desborda en 320 px de ancho');
      expect(medico.dy, greaterThan(soy.dy), reason: '«Soy:» queda arriba de las opciones');
      expect(medico.dx, soy.dx, reason: 'la primera opción empieza donde «Soy:»');
      if (paciente.dy > medico.dy) {
        expect(paciente.dx, medico.dx, reason: 'si pasa a otra línea, se alinea con la anterior');
      }
    });

    testWidgets('se puede elegir cada rol', (tester) async {
      await _abrirChat(tester, MuestraChatRepository());

      await tester.tap(find.byKey(const Key('rol-paciente')));
      await _avanzar(tester);

      expect(tester.widget<ChoiceChip>(find.byKey(const Key('rol-paciente'))).selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('rol-medico'))).selected, isFalse);
    });
  });

  group('«Abrir chat nuevo» no queda tapado', () {
    Future<void> cerrarComoPaciente(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('rol-paciente')));
      await _avanzar(tester);
      await tester.tap(find.text('CERRAR CHAT Y BORRAR HISTORIAL'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cerrar chat'));
      await _avanzar(tester, const Duration(milliseconds: 300));
    }

    testWidgets('el botón está arriba (junto al aviso de chat cerrado), lejos de donde aparecen los avisos', (tester) async {
      await _abrirChat(tester, MuestraChatRepository());
      await cerrarComoPaciente(tester);

      final boton = tester.getRect(find.byKey(const Key('abrir-chat-nuevo')));
      expect(find.text('ABRIR CHAT NUEVO'), findsOneWidget);
      expect(boton.bottom, lessThan(844 * 0.5), reason: 'en la mitad superior de la pantalla');
      expect(find.text('Cerraste el chat. El historial se borró.'), findsOneWidget);
    });

    testWidgets('con un aviso en pantalla el botón sigue siendo tocable y abre un chat nuevo', (tester) async {
      final chat = MuestraChatRepository();
      await _abrirChat(tester, chat);
      await cerrarComoPaciente(tester);
      ScaffoldMessenger.of(tester.element(find.byType(ChatScreen))).showSnackBar(
        const SnackBar(content: Text('Un aviso cualquiera, largo, de los que aparecen abajo')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.tap(find.byKey(const Key('abrir-chat-nuevo'))); // si algo lo tapara, el toque no llegaría
      await _avanzar(tester, const Duration(milliseconds: 300));

      expect(find.byKey(const Key('abrir-chat-nuevo')), findsNothing);
      expect((await chat.consultar('ana1')).cerrado, isFalse);
    });

    testWidgets('el médico, en cambio, solo ve «Esperando…» (no puede abrir el chat del paciente)', (tester) async {
      final chat = MuestraChatRepository();
      await chat.cerrar('luis1');
      await _abrirChat(tester, chat);
      await tester.tap(find.byKey(const Key('rol-medico')));
      await _avanzar(tester);
      // el médico (cuenta de Ana) atiende a Luis; su propia cuenta no aparece en la lista
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Luis Pérez').last);
      await _avanzar(tester, const Duration(milliseconds: 500));

      expect(find.byKey(const Key('abrir-chat-nuevo')), findsNothing);
      expect(find.text('Esperando a que el paciente abra un chat nuevo…'), findsOneWidget);
    });
  });

  group('Sin servidor el aviso llega rápido', () {
    testWidgets('si el servidor no responde, el error llega a los 4 segundos (no ~12)', (tester) async {
      final api = ApiCliente(
        baseUrl: 'http://servidor:8081/api',
        cliente: MockClient((_) => Completer<http.Response>().future), // nunca responde
      );
      Object? error;
      final espera = api.get('/usuarios').catchError((Object e) {
        error = e;
        return null;
      });

      await tester.pump(const Duration(seconds: 3));
      expect(error, isNull, reason: 'a los 3 s todavía espera');
      await tester.pump(const Duration(seconds: 2));
      await espera;

      expect(error, isA<ApiException>());
      expect((error! as ApiException).sinConexion, isTrue);
      expect((error! as ApiException).mensaje, 'No se pudo conectar al servidor');
    });
  });
}
