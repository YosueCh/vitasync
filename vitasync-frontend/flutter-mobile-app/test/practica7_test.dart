import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/models/mensaje_chat.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/chat_screen.dart';
import 'package:vitasync_mobile/screens/roles_screen.dart';
import 'package:vitasync_mobile/screens/shell_screen.dart';
import 'package:vitasync_mobile/services/firmware_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/roles_repository.dart';
import 'package:vitasync_mobile/services/selector_archivo.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

/// Práctica 7 dentro de VitaSync: archivos en el chat y roles asignados en lote por el administrador.

const _ana = Usuario(id: 'ana1', nombreCompleto: 'Ana Torres', username: 'ana', habilitado: true);

class _Usuarios implements UsuarioRepository {
  @override
  Future<List<Usuario>> listarHabilitados() async => const [_ana];
}

http.Response _json(Object cuerpo, [int estado = 200]) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json; charset=utf-8'});

final _pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 prueba'));

Future<void> _abrirChat(WidgetTester t, ChatRepository chat, Future<ArchivoElegido?> Function() elegir) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(body: ChatScreen(cuenta: _ana, chat: chat, usuarios: _Usuarios(), elegirArchivo: elegir)),
  ));
  await t.tap(find.text('Paciente (Dispositivo B)'));
  await t.pump();
  await t.pump();
}

void main() {
  group('Reglas de archivo', () {
    test('tipo por extensión, sin importar mayúsculas', () {
      expect(ReglasArchivo.tipoDe('a.PNG'), 'image/png');
      expect(ReglasArchivo.tipoDe('a.jpeg'), 'image/jpeg');
      expect(ReglasArchivo.tipoDe('informe.final.pdf'), 'application/pdf');
      expect(ReglasArchivo.tipoDe('nota.txt'), 'text/plain');
      expect(ReglasArchivo.tipoDe('virus.exe'), isNull);
      expect(ReglasArchivo.tipoDe('sin_extension'), isNull);
    });

    test('tamaño: vacío y mayor a 300 KB se rechazan; el límite exacto es válido', () {
      expect(ReglasArchivo.validar('a.pdf', 0), isNotNull);
      expect(ReglasArchivo.validar('a.pdf', ReglasArchivo.maxBytes + 1), contains('300 KB'));
      expect(ReglasArchivo.validar('a.pdf', ReglasArchivo.maxBytes), isNull);
      expect(ReglasArchivo.validar('a.exe', 10), contains('PNG, JPG, PDF o TXT'));
    });

    test('el mensaje del servidor con archivo se lee; sin archivo queda null', () {
      final con = MensajeChat.fromJson({
        'id': 3, 'emisor': 'MEDICO', 'texto': 'Archivo: a.pdf', 'hora': '2026-11-04T10:00:00Z',
        'archivo': {'nombre': 'a.pdf', 'tipo': 'application/pdf', 'tamano': 20},
      });
      expect(con.archivo?.nombre, 'a.pdf');
      expect(con.archivo?.esImagen, isFalse);
      final sin = MensajeChat.fromJson({'id': 4, 'emisor': 'MEDICO', 'texto': 'hola', 'hora': '2026-11-04T10:00:00Z', 'archivo': null});
      expect(sin.archivo, isNull);
    });
  });

  group('Chat HTTP con archivos', () {
    test('enviarArchivo manda el contenido en Base64 a /archivos', () async {
      late http.Request visto;
      final repo = HttpChatRepository(
          api: ApiCliente(baseUrl: 'http://x/api', cliente: MockClient((r) async {
        visto = r;
        return _json({'id': 1});
      })));
      await repo.enviarArchivo('ana1', RolChat.paciente, nombre: 'a.pdf', tipo: 'application/pdf', bytes: _pdf);
      expect(visto.url.path, '/api/chat/ana1/archivos');
      final cuerpo = jsonDecode(visto.body) as Map<String, dynamic>;
      expect(cuerpo['emisor'], 'PACIENTE');
      expect(base64Decode(cuerpo['contenidoBase64'] as String), _pdf);
    });

    test('descargar devuelve los bytes tal cual, sin leerlos como JSON', () async {
      final repo = HttpChatRepository(
          api: ApiCliente(baseUrl: 'http://x/api', cliente: MockClient((r) async => http.Response.bytes(_pdf, 200))));
      expect(await repo.descargar('ana1', 1), _pdf);
    });

    test('un 404 al descargar es un error claro', () async {
      final repo = HttpChatRepository(
          api: ApiCliente(baseUrl: 'http://x/api', cliente: MockClient((_) async => http.Response('', 404))));
      await expectLater(repo.descargar('ana1', 9), throwsA(isA<ApiException>()));
    });
  });

  group('Pantalla del chat con archivos', () {
    testWidgets('adjuntar un PDF lo manda y aparece como archivo en la conversación', (t) async {
      final chat = MuestraChatRepository();
      await _abrirChat(t, chat, () async => ArchivoElegido(nombre: 'analisis.pdf', bytes: _pdf));
      await t.tap(find.byKey(const Key('adjuntar-archivo')));
      await t.pump();
      await t.pump();
      expect((await chat.consultar('ana1')).mensajes.single.archivo?.nombre, 'analisis.pdf');
      expect(find.textContaining('analisis.pdf'), findsWidgets);
      expect(find.byKey(const Key('archivo-1')), findsOneWidget);
    });

    testWidgets('un tipo no permitido se avisa y no llega al servidor', (t) async {
      final chat = MuestraChatRepository();
      await _abrirChat(t, chat, () async => ArchivoElegido(nombre: 'virus.exe', bytes: Uint8List(10)));
      await t.tap(find.byKey(const Key('adjuntar-archivo')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('PNG, JPG, PDF o TXT'), findsOneWidget);
      expect((await chat.consultar('ana1')).mensajes, isEmpty);
    });

    testWidgets('un archivo demasiado grande se avisa y no se envía', (t) async {
      final chat = MuestraChatRepository();
      await _abrirChat(t, chat, () async => ArchivoElegido(nombre: 'grande.pdf', bytes: Uint8List(ReglasArchivo.maxBytes + 1)));
      await t.tap(find.byKey(const Key('adjuntar-archivo')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('300 KB'), findsOneWidget);
      expect((await chat.consultar('ana1')).mensajes, isEmpty);
    });

    testWidgets('cancelar el selector no hace nada', (t) async {
      final chat = MuestraChatRepository();
      await _abrirChat(t, chat, () async => null);
      await t.tap(find.byKey(const Key('adjuntar-archivo')));
      await t.pump();
      expect((await chat.consultar('ana1')).mensajes, isEmpty);
    });

    testWidgets('tocar un archivo de texto lo descarga y muestra su contenido', (t) async {
      final chat = MuestraChatRepository();
      await chat.enviarArchivo('ana1', RolChat.medico,
          nombre: 'indicaciones.txt', tipo: 'text/plain', bytes: Uint8List.fromList(utf8.encode('Tomar agua ñ')));
      await _abrirChat(t, chat, () async => null);
      await t.pump();
      await t.tap(find.byKey(const Key('archivo-1')));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('visor-archivo')), findsOneWidget);
      expect(find.text('Tomar agua ñ'), findsOneWidget);
    });

    testWidgets('sin conexión al enviar un archivo no queda pendiente: se avisa', (t) async {
      final repo = HttpChatRepository(
          api: ApiCliente(baseUrl: 'http://x/api', cliente: MockClient((_) async => throw http.ClientException('sin red'))));
      await _abrirChat(t, repo, () async => ArchivoElegido(nombre: 'a.pdf', bytes: _pdf));
      await t.tap(find.byKey(const Key('adjuntar-archivo')));
      await t.pump();
      await t.pump();
      expect(find.textContaining('el archivo no se envió'), findsOneWidget);
      expect(find.byKey(const Key('burbuja-pendiente')), findsNothing);
    });
  });

  group('Roles', () {
    test('Muestra: aplica varios cambios y respeta las reglas del servidor', () async {
      final repo = MuestraRolesRepository();
      final r = await repo.asignar({'u1': 'medico', 'u2': 'medico'});
      expect(r.map((p) => p.rol), ['medico', 'medico']);
      await expectLater(repo.asignar({'u1': 'admin'}), throwsA(isA<ApiException>()));
      await expectLater(repo.asignar({'u0': 'paciente'}), throwsA(isA<ApiException>()));
      await expectLater(repo.asignar({'nadie': 'medico'}), throwsA(isA<ApiException>()));
      await expectLater(repo.asignar({}), throwsA(isA<ApiException>()));
    });

    test('HTTP: listar y asignar usan /admin/personas y /admin/roles', () async {
      final vistos = <String>[];
      late Map<String, dynamic> cuerpo;
      final repo = HttpRolesRepository(
          api: ApiCliente(baseUrl: 'http://x/api', cliente: MockClient((r) async {
        vistos.add('${r.method} ${r.url.path}');
        if (r.method == 'PUT') {
          cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
          return _json([{'uid': 'u1', 'correo': 'a@x', 'rol': 'medico'}]);
        }
        return _json([{'uid': 'u1', 'correo': 'a@x', 'rol': 'paciente'}]);
      })));
      expect((await repo.listar()).single.correo, 'a@x');
      await repo.asignar({'u1': 'medico'});
      expect(vistos, ['GET /api/admin/personas', 'PUT /api/admin/roles']);
      expect(cuerpo['cambios'], [{'uid': 'u1', 'rol': 'medico'}]);
    });

    testWidgets('el administrador marca varios cambios, confirma y se aplican juntos', (t) async {
      final repo = MuestraRolesRepository();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: RolesScreen(repositorio: repo))));
      await t.pumpAndSettle();
      expect(find.text('Administrador'), findsOneWidget);

      await t.tap(find.byKey(const Key('rol-u1')));
      await t.pumpAndSettle();
      await t.tap(find.text('Médico').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rol-u2')));
      await t.pumpAndSettle();
      await t.tap(find.text('Médico').last);
      await t.pumpAndSettle();
      expect(find.text('sin aplicar'), findsNWidgets(2));
      expect((await repo.listar()).where((p) => p.rol == 'medico'), isEmpty); // nada se envió todavía

      await t.tap(find.byKey(const Key('aplicar-roles')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('confirmar-roles')), findsOneWidget);
      await t.tap(find.byKey(const Key('confirmar-roles-si')));
      await t.pumpAndSettle();
      expect((await repo.listar()).where((p) => p.rol == 'medico'), hasLength(2));
      expect(find.textContaining('2 rol(es) asignado(s)'), findsOneWidget);
    });

    testWidgets('el administrador genera un código y aparece en la lista como libre', (t) async {
      final repo = MuestraRolesRepository();
      await t.pumpWidget(MaterialApp(home: Scaffold(body: RolesScreen(repositorio: repo))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('crear-invitacion')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('invitacion-MUESTRA1')), findsOneWidget);
      expect(find.textContaining('MUESTRA1 · Médico · libre'), findsOneWidget);
      expect(find.textContaining('caduca en 7 días'), findsOneWidget);
    });

    test('Muestra: un código sirve una vez y uno inventado no existe', () async {
      final repo = MuestraRolesRepository();
      final i = await repo.crearInvitacion('medico');
      expect(await repo.canjear(i.codigo.toLowerCase()), 'medico');
      await expectLater(repo.canjear(i.codigo), throwsA(isA<ApiException>()));
      await expectLater(repo.canjear('NOEXISTE'), throwsA(isA<ApiException>()));
      await expectLater(repo.crearInvitacion('admin'), throwsA(isA<ApiException>()));
      expect((await repo.listarInvitaciones()).single.usada, isTrue);
    });

    test('HTTP: crear, listar y canjear usan las rutas de invitaciones', () async {
      final vistos = <String>[];
      final repo = HttpRolesRepository(
          api: ApiCliente(baseUrl: 'http://x/api', cliente: MockClient((r) async {
        vistos.add('${r.method} ${r.url.path}');
        final inv = {'codigo': 'ABCD2345', 'rol': 'medico', 'venceEn': 1900000000000, 'usadaPor': null};
        if (r.url.path.endsWith('canjear')) return _json({'rol': 'medico'});
        return r.method == 'GET' ? _json([inv]) : _json(inv);
      })));
      expect((await repo.crearInvitacion('medico')).codigo, 'ABCD2345');
      expect((await repo.listarInvitaciones()).single.usada, isFalse);
      expect(await repo.canjear('ABCD2345'), 'medico');
      expect(vistos, ['POST /api/admin/invitaciones', 'GET /api/admin/invitaciones', 'POST /api/invitaciones/canjear']);
    });

    testWidgets('en la app: con roles aparece «Roles» y el botón del código; canjear avisa el rol nuevo', (t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final roles = MuestraRolesRepository();
      final i = await roles.crearInvitacion('medico');
      await t.pumpWidget(MaterialApp(
        home: ShellScreen(
          cuenta: _ana,
          repositorio: const MuestraSaludRepository(),
          firmware: MuestraFirmwareRepository(),
          chat: MuestraChatRepository(),
          usuarios: _Usuarios(),
          roles: roles,
          onCerrarSesion: () {},
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Roles'), findsOneWidget);
      await t.tap(find.byKey(const Key('tengo-codigo')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('campo-codigo')), i.codigo);
      await t.tap(find.byKey(const Key('canjear-codigo')));
      await t.pumpAndSettle();
      expect(find.textContaining('ahora eres Médico'), findsOneWidget);
    });

    testWidgets('en la app: sin repositorio de roles no hay pestaña ni botón de código', (t) async {
      await t.pumpWidget(MaterialApp(
        home: ShellScreen(
          cuenta: _ana,
          repositorio: const MuestraSaludRepository(),
          firmware: MuestraFirmwareRepository(),
          chat: MuestraChatRepository(),
          usuarios: _Usuarios(),
          onCerrarSesion: () {},
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Roles'), findsNothing);
      expect(find.byKey(const Key('tengo-codigo')), findsNothing);
    });

    testWidgets('sin cambios el botón está desactivado', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: RolesScreen(repositorio: MuestraRolesRepository()))));
      await t.pumpAndSettle();
      final boton = t.widget<FilledButton>(find.byKey(const Key('aplicar-roles')));
      expect(boton.onPressed, isNull);
    });

    testWidgets('quien no es administrador ve el aviso del servidor (403)', (t) async {
      final repo = HttpRolesRepository(
          api: ApiCliente(baseUrl: 'http://x/api', cliente: MockClient((_) async => _json({'error': 'Solo el administrador'}, 403))));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: RolesScreen(repositorio: repo))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('roles-error')), findsOneWidget);
      expect(find.textContaining('No tienes permiso'), findsOneWidget);
    });
  });
}
