import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/models/mensaje_chat.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/chat_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

const _ana = Usuario(
  id: 'ana1',
  nombreCompleto: 'Ana Torres',
  username: 'ana',
  habilitado: true,
);

const _luis = Usuario(
  id: 'luis1',
  nombreCompleto: 'Luis Pérez',
  username: 'luis',
  habilitado: true,
);

/// Lista de cuentas inmediata (la de muestra tarda 300 ms).
class _Usuarios implements UsuarioRepository {
  @override
  Future<List<Usuario>> listarHabilitados() async => const [_ana, _luis];
}

Future<void> _abrir(
  WidgetTester tester, {
  required ChatRepository chat,
  required Usuario cuenta,
  Duration? intervalo,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ChatScreen(
        cuenta: cuenta,
        chat: chat,
        usuarios: _Usuarios(),
        intervalo: intervalo,
      ),
    ),
  ));
}

/// Deja correr las respuestas asíncronas sin esperar a que "todo se asiente"
/// (con sondeo activo nunca se asienta).
Future<void> _avanzar(WidgetTester tester, [Duration tiempo = Duration.zero]) async {
  await tester.pump(tiempo);
  await tester.pump();
  await tester.pump();
}

/// Cancela el sondeo antes de terminar la prueba.
Future<void> _cerrar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  group('Chat médico-paciente (pantalla)', () {
    testWidgets('sin elegir rol no hay formulario de mensajes', (tester) async {
      await _abrir(tester, chat: MuestraChatRepository(), cuenta: _ana);

      expect(find.textContaining('Elige tu rol'), findsOneWidget);
      expect(find.byTooltip('Enviar'), findsNothing);
    });

    testWidgets('un mensaje vacío o solo con espacios no se envía', (tester) async {
      final chat = MuestraChatRepository();
      await _abrir(tester, chat: chat, cuenta: _ana);
      await tester.tap(find.text('Paciente (Dispositivo B)'));
      await _avanzar(tester);

      await tester.tap(find.byTooltip('Enviar'));
      await _avanzar(tester);
      expect(find.text('El mensaje no puede estar vacío.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '     ');
      await tester.tap(find.byTooltip('Enviar'));
      await _avanzar(tester);
      expect(find.text('El mensaje no puede estar vacío.'), findsOneWidget);

      expect((await chat.consultar('ana1')).mensajes, isEmpty);
    });

    testWidgets('un mensaje de más de 200 caracteres se rechaza', (tester) async {
      final chat = MuestraChatRepository();
      await _abrir(tester, chat: chat, cuenta: _ana);
      await tester.tap(find.text('Paciente (Dispositivo B)'));
      await _avanzar(tester);

      await tester.enterText(find.byType(TextField), 'a' * (maxCaracteresMensaje + 1));
      await tester.tap(find.byTooltip('Enviar'));
      await _avanzar(tester);

      expect(find.textContaining('Máximo'), findsOneWidget);
      expect((await chat.consultar('ana1')).mensajes, isEmpty);
    });

    testWidgets(
      'el paciente envía, recibe la respuesta del médico y al cerrar se borra todo',
      (tester) async {
        final chat = MuestraChatRepository();
        await _abrir(
          tester,
          chat: chat,
          cuenta: _ana,
          intervalo: const Duration(seconds: 1),
        );
        await tester.tap(find.text('Paciente (Dispositivo B)'));
        await _avanzar(tester);

        // Envía: aparece con su emisor, cuenta en su contador y se avisa.
        await tester.enterText(find.byType(TextField), 'Me duele la cabeza');
        await tester.tap(find.byTooltip('Enviar'));
        await _avanzar(tester);
        expect(find.text('Me duele la cabeza'), findsOneWidget);
        expect(find.text('Mensaje enviado: Dispositivo B → Dispositivo A'), findsOneWidget);
        expect(find.text('Dispositivo B (Paciente): 1'), findsOneWidget);
        expect(find.text('Dispositivo A (Médico): 0'), findsOneWidget);

        // El médico (otro teléfono) responde por el servidor; llega por sondeo.
        await chat.enviar('ana1', RolChat.medico, 'Tome agua y descanse');
        await _avanzar(tester, const Duration(seconds: 1));
        expect(find.text('Tome agua y descanse'), findsOneWidget);
        expect(find.text('Nuevo mensaje de Dispositivo A'), findsOneWidget);
        expect(find.text('Dispositivo A (Médico): 1'), findsOneWidget);

        // Cierra el chat: pide confirmación y borra el historial.
        await tester.tap(find.text('CERRAR CHAT Y BORRAR HISTORIAL'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Cerrar chat'));
        await _avanzar(tester, const Duration(milliseconds: 300));

        expect(find.text('Me duele la cabeza'), findsNothing);
        expect(find.text('Tome agua y descanse'), findsNothing);
        expect(find.text('Chat cerrado.'), findsOneWidget);
        expect(find.text('ABRIR CHAT NUEVO'), findsOneWidget);
        final servidor = await chat.consultar('ana1');
        expect(servidor.cerrado, isTrue);
        expect(servidor.mensajes, isEmpty);

        await _cerrar(tester);
      },
    );

    testWidgets('el médico elige paciente, escribe y se entera cuando cierra el chat',
        (tester) async {
      final chat = MuestraChatRepository();
      await chat.enviar('luis1', RolChat.paciente, 'Buenas tardes, doctor');
      await _abrir(
        tester,
        chat: chat,
        cuenta: _ana,
        intervalo: const Duration(seconds: 1),
      );
      await tester.tap(find.text('Médico (Dispositivo A)'));
      await _avanzar(tester);

      // Elige al paciente (la cuenta del propio médico no aparece).
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ana Torres'), findsNothing);
      await tester.tap(find.text('Luis Pérez').last);
      await _avanzar(tester, const Duration(milliseconds: 500));

      // Ve lo que el paciente ya había escrito y le contesta.
      expect(find.text('Buenas tardes, doctor'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Buenas tardes, ¿cómo sigue?');
      await tester.tap(find.byTooltip('Enviar'));
      await _avanzar(tester);
      expect(find.text('Buenas tardes, ¿cómo sigue?'), findsOneWidget);
      expect(find.text('Mensaje enviado: Dispositivo A → Dispositivo B'), findsOneWidget);
      expect((await chat.consultar('luis1')).mensajes, hasLength(2));

      // El paciente cierra el chat desde su teléfono.
      await chat.cerrar('luis1');
      await _avanzar(tester, const Duration(seconds: 1));
      expect(find.text('El paciente cerró el chat'), findsOneWidget);
      expect(find.text('Buenas tardes, doctor'), findsNothing);
      expect(find.byTooltip('Enviar'), findsNothing);

      await _cerrar(tester);
    });
  });

  group('HttpChatRepository (el backend como servidor intermediario)', () {
    const base = 'http://servidor:8081/api';

    (HttpChatRepository, List<http.Request>) crear(
      http.Response Function(http.Request) responder,
    ) {
      final pedidas = <http.Request>[];
      final api = ApiCliente(
        baseUrl: base,
        cliente: MockClient((r) async {
          pedidas.add(r);
          return responder(r);
        }),
      );
      return (HttpChatRepository(api: api), pedidas);
    }

    http.Response json(Object cuerpo, [int estado = 200]) => http.Response(
          jsonEncode(cuerpo),
          estado,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    test('enviar manda el emisor y el texto en el cuerpo de un POST', () async {
      final (repo, pedidas) = crear(
        (_) => json({'id': 1, 'emisor': 'MEDICO', 'texto': 'Hola', 'hora': '2026-10-22T00:00:00Z'}),
      );

      await repo.enviar('ana1', RolChat.medico, 'Hola');

      final r = pedidas.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), '$base/chat/ana1/mensajes');
      expect(jsonDecode(r.body), {'emisor': 'MEDICO', 'texto': 'Hola'});
    });

    test('consultar pide solo los mensajes posteriores y los convierte', () async {
      final (repo, pedidas) = crear(
        (_) => json({
          'cerrado': false,
          'mensajes': [
            {'id': 4, 'emisor': 'PACIENTE', 'texto': 'Me siento mejor', 'hora': '2026-10-22T00:00:00Z'},
          ],
        }),
      );

      final c = await repo.consultar('ana1', desde: 3);

      expect(pedidas.single.url.toString(), '$base/chat/ana1/mensajes?desde=3');
      expect(c.cerrado, isFalse);
      expect(c.mensajes.single.id, 4);
      expect(c.mensajes.single.emisor, RolChat.paciente);
      expect(c.mensajes.single.texto, 'Me siento mejor');
    });

    test('cerrar y abrir llaman a sus rutas', () async {
      final (repo, pedidas) = crear((_) => json({'cerrado': true}));

      await repo.cerrar('ana1');
      await repo.abrir('ana1');

      expect(pedidas.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/chat/ana1/cerrar',
        'POST /api/chat/ana1/abrir',
      ]);
    });

    test('un 409 (chat cerrado) llega como mensaje listo para mostrar', () async {
      final (repo, _) = crear((_) => json({'error': 'El paciente cerró el chat.'}, 409));

      expect(
        () => repo.enviar('ana1', RolChat.medico, 'Hola'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'El paciente cerró el chat.')),
      );
    });

    test('sin servidor lanza ApiException con mensaje claro', () async {
      final api = ApiCliente(
        baseUrl: base,
        cliente: MockClient((_) async => throw http.ClientException('sin red')),
      );

      expect(
        () => HttpChatRepository(api: api).consultar('ana1'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
