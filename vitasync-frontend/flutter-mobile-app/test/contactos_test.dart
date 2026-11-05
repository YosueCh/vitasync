import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/models/contacto.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/contactos_screen.dart';
import 'package:vitasync_mobile/screens/shell_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/contactos_repository.dart';
import 'package:vitasync_mobile/services/firmware_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

/// Actividad 1 dentro de VitaSync: contactos de emergencia (capturar, guardar en la nube y consultar).

const _ana = Usuario(id: 'ana1', nombreCompleto: 'Ana Torres', username: 'ana', habilitado: true);

class _Usuarios implements UsuarioRepository {
  @override
  Future<List<Usuario>> listarHabilitados() async => const [_ana];
}

http.Response _json(Object cuerpo, [int estado = 200]) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json; charset=utf-8'});

/// Servidor falso de contactos: guarda en memoria y puede rechazar con un mensaje (como el servidor real).
class _Contactos implements ContactosRepository {
  _Contactos({List<ContactoEmergencia>? iniciales}) : lista = [...?iniciales];

  final List<ContactoEmergencia> lista;
  String? rechazo;
  int creaciones = 0;

  @override
  Future<List<ContactoEmergencia>> listar() async => List.of(lista);

  @override
  Future<ContactoEmergencia> crear({required String nombre, required String telefono, required String relacion}) async {
    if (rechazo != null) throw ApiException(rechazo!);
    creaciones++;
    final c = ContactoEmergencia(
      id: 'c${lista.length + 1}',
      nombre: nombre,
      telefono: ReglasContacto.normalizarTelefono(telefono),
      relacion: relacion,
    );
    lista.add(c);
    return c;
  }

  @override
  Future<void> eliminar(String id) async => lista.removeWhere((c) => c.id == id);
}

ContactoEmergencia _c(int n) => ContactoEmergencia(id: 'c$n', nombre: 'Contacto $n', telefono: '44211122$n$n', relacion: 'Otro');

Future<void> _abrir(WidgetTester tester, ContactosRepository repo) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ContactosScreen(repositorio: repo))));
  await tester.pumpAndSettle();
}

Future<void> _llenarYGuardar(WidgetTester tester, {required String nombre, required String telefono}) async {
  await tester.tap(find.byKey(const Key('btn-agregar-contacto')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('campo-contacto-nombre')), nombre);
  await tester.enterText(find.byKey(const Key('campo-contacto-telefono')), telefono);
  await tester.tap(find.byKey(const Key('btn-guardar-contacto')));
  await tester.pumpAndSettle();
}

void main() {
  group('Reglas de los contactos (las mismas que valida el servidor)', () {
    test('un contacto correcto no tiene errores', () {
      expect(ReglasContacto.validar('Mamá', '(442) 123-4567'), isEmpty);
      expect(ReglasContacto.validar('Dra. López', '+52 442 765 4321'), isEmpty);
    });

    test('nombre vacío, de una letra o de más de 60 caracteres', () {
      expect(ReglasContacto.validar('', '4421234567').keys, ['nombre']);
      expect(ReglasContacto.validar(' A ', '4421234567').keys, ['nombre']);
      expect(ReglasContacto.validar('x' * 61, '4421234567').keys, ['nombre']);
    });

    test('teléfono vacío, corto, largo o con letras', () {
      for (final t in ['', '442123', '4421234567890123', '442-ABC-4567']) {
        expect(ReglasContacto.validar('Mamá', t).keys, ['telefono'], reason: t);
      }
    });

    test('el teléfono se normaliza quitando espacios, guiones y paréntesis', () {
      expect(ReglasContacto.normalizarTelefono('(442) 123-4567'), '4421234567');
      expect(ReglasContacto.normalizarTelefono('+52 442.765.4321'), '+524427654321');
    });
  });

  group('HttpContactosRepository', () {
    test('listar: GET con la cuenta y convierte la respuesta', () async {
      http.Request? pedida;
      final repo = HttpContactosRepository(
        usuarioId: 'ana1',
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((r) async {
            pedida = r;
            return _json([
              {'id': 'c1', 'nombre': 'Mamá', 'telefono': '4421234567', 'relacion': 'Familiar'},
            ]);
          }),
        ),
      );

      final lista = await repo.listar();

      expect(pedida!.method, 'GET');
      expect(pedida!.url.path, '/api/contactos');
      expect(pedida!.url.queryParameters, {'usuarioId': 'ana1'});
      expect(lista.single.nombre, 'Mamá');
    });

    test('crear: POST con la cuenta en la URL y los datos en el cuerpo JSON', () async {
      http.Request? pedida;
      final repo = HttpContactosRepository(
        usuarioId: 'ana1',
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((r) async {
            pedida = r;
            return _json({'id': 'c9', 'nombre': 'Mamá', 'telefono': '4421234567', 'relacion': 'Familiar'});
          }),
        ),
      );

      final c = await repo.crear(nombre: 'Mamá', telefono: '442 123 4567', relacion: 'Familiar');

      expect(pedida!.method, 'POST');
      expect(pedida!.url.path, '/api/contactos');
      expect(pedida!.url.queryParameters, {'usuarioId': 'ana1'});
      expect(jsonDecode(pedida!.body), {'nombre': 'Mamá', 'telefono': '442 123 4567', 'relacion': 'Familiar'});
      expect(c.id, 'c9');
    });

    test('eliminar: DELETE /contactos/{id} con la cuenta', () async {
      http.Request? pedida;
      final repo = HttpContactosRepository(
        usuarioId: 'ana1',
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((r) async {
            pedida = r;
            return _json({'mensaje': 'Contacto eliminado.'});
          }),
        ),
      );

      await repo.eliminar('c1');

      expect(pedida!.method, 'DELETE');
      expect(pedida!.url.path, '/api/contactos/c1');
      expect(pedida!.url.queryParameters, {'usuarioId': 'ana1'});
    });

    test('un 409 del servidor llega con su mensaje (teléfono repetido o límite)', () async {
      final repo = HttpContactosRepository(
        usuarioId: 'ana1',
        api: ApiCliente(
          baseUrl: 'http://servidor:8081/api',
          cliente: MockClient((_) async => _json({'error': 'Ya hay un contacto con ese teléfono.'}, 409)),
        ),
      );

      await expectLater(
        repo.crear(nombre: 'Mamá', telefono: '4421234567', relacion: 'Familiar'),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', 'Ya hay un contacto con ese teléfono.')),
      );
    });
  });

  group('Pantalla de contactos', () {
    testWidgets('sin contactos se dice claramente y se puede agregar', (tester) async {
      await _abrir(tester, _Contactos());

      expect(find.byKey(const Key('sin-contactos')), findsOneWidget);
      expect(find.text('0 de 5 · se guardan en la nube'), findsOneWidget);
      expect(find.byKey(const Key('btn-agregar-contacto')), findsOneWidget);
    });

    testWidgets('agregar un contacto: se captura, se envía y aparece en la lista', (tester) async {
      final repo = _Contactos();
      await _abrir(tester, repo);

      await _llenarYGuardar(tester, nombre: 'Mamá', telefono: '(442) 123-4567');

      expect(repo.lista.single.telefono, '4421234567');
      expect(find.text('Mamá'), findsOneWidget);
      expect(find.text('Familiar · 4421234567'), findsOneWidget);
      expect(find.text('1 de 5 · se guardan en la nube'), findsOneWidget);
      expect(find.text('Contacto guardado'), findsOneWidget);
    });

    testWidgets('datos inválidos: se avisa en el formulario y NO se envía nada al servidor', (tester) async {
      final repo = _Contactos();
      await _abrir(tester, repo);

      await _llenarYGuardar(tester, nombre: '', telefono: '123');

      expect(find.text('El nombre es obligatorio (2 a 60 caracteres).'), findsOneWidget);
      expect(find.text('El teléfono debe tener de 7 a 15 dígitos (puede empezar con +).'), findsOneWidget);
      expect(repo.creaciones, 0);
      expect(find.byKey(const Key('campo-contacto-nombre')), findsOneWidget, reason: 'el formulario sigue abierto');
    });

    testWidgets('si el servidor rechaza (teléfono repetido) se muestra su mensaje y la lista no cambia', (tester) async {
      final repo = _Contactos(iniciales: [_c(1)])..rechazo = 'Ya hay un contacto con ese teléfono.';
      await _abrir(tester, repo);

      await _llenarYGuardar(tester, nombre: 'Otra', telefono: '4429998877');

      expect(find.text('Ya hay un contacto con ese teléfono.'), findsOneWidget);
      expect(repo.lista, hasLength(1));
    });

    testWidgets('eliminar pide confirmación y borra el contacto', (tester) async {
      final repo = _Contactos(iniciales: [_c(1), _c(2)]);
      await _abrir(tester, repo);

      await tester.tap(find.byKey(const Key('eliminar-contacto-c1')));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar a Contacto 1?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmar-eliminar-contacto')));
      await tester.pumpAndSettle();

      expect(repo.lista.map((c) => c.id), ['c2']);
      expect(find.byKey(const Key('contacto-c1')), findsNothing);
    });

    testWidgets('cancelar la eliminación no borra nada', (tester) async {
      final repo = _Contactos(iniciales: [_c(1)]);
      await _abrir(tester, repo);

      await tester.tap(find.byKey(const Key('eliminar-contacto-c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.lista, hasLength(1));
    });

    testWidgets('con 5 contactos el botón de agregar se deshabilita', (tester) async {
      await _abrir(tester, _Contactos(iniciales: [for (var i = 1; i <= 5; i++) _c(i)]));

      final boton = tester.widget<FilledButton>(find.byKey(const Key('btn-agregar-contacto')));
      expect(boton.onPressed, isNull);
      expect(find.text('Límite de contactos alcanzado'), findsOneWidget);
    });
  });

  group('Pestaña Contactos en la app', () {
    Future<void> abrirShell(WidgetTester tester, {ContactosRepository? contactos}) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ShellScreen(
          cuenta: _ana,
          repositorio: const MuestraSaludRepository(),
          firmware: MuestraFirmwareRepository(),
          chat: MuestraChatRepository(),
          usuarios: _Usuarios(),
          contactos: contactos,
          onCerrarSesion: () {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('con un repositorio de contactos aparece la pestaña y muestra la pantalla', (tester) async {
      await abrirShell(tester, contactos: _Contactos(iniciales: [_c(1)]));

      await tester.tap(find.text('Contactos'));
      await tester.pumpAndSettle();

      expect(find.byType(ContactosScreen), findsOneWidget);
      expect(find.text('Contacto 1'), findsOneWidget);
    });

    testWidgets('sin repositorio de contactos no hay pestaña (la app anterior no cambia)', (tester) async {
      await abrirShell(tester);

      expect(find.text('Contactos'), findsNothing);
      expect(find.text('Resumen'), findsOneWidget);
    });
  });
}
