import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/models/metas_cuenta.dart';
import 'package:vitasync_mobile/screens/metas_screen.dart';
import 'package:vitasync_mobile/screens/resumen_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/metas_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';

/// Práctica 9 dentro de VitaSync: metas compartidas entre paciente y médico, con control de versión.

http.Response _json(Object cuerpo, [int estado = 200]) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json; charset=utf-8'});

const _v1 = {'metaPasos': 12000, 'metaCalorias': 600, 'metaSueno': 8.0, 'version': 1, 'actualizadaPor': 'Médico'};

HttpMetasRepository _http(MockClient c) =>
    HttpMetasRepository(usuarioId: 'ana1', api: ApiCliente(baseUrl: 'http://x/api', cliente: c));

Widget _pantalla(MetasRepository repo) => MaterialApp(home: MetasScreen(repositorio: repo));

void main() {
  group('Repositorio HTTP', () {
    test('obtener lee GET /metas?usuarioId=', () async {
      late http.Request visto;
      final repo = _http(MockClient((r) async {
        visto = r;
        return _json(_v1);
      }));
      final m = await repo.obtener();
      expect(visto.method, 'GET');
      expect(visto.url.path, '/api/metas');
      expect(visto.url.queryParameters['usuarioId'], 'ana1');
      expect(m.metaPasos, 12000);
      expect(m.version, 1);
      expect(m.actualizadaPor, 'Médico');
    });

    test('guardar manda PUT solo con los campos dados y la versión', () async {
      late http.Request visto;
      final repo = _http(MockClient((r) async {
        visto = r;
        return _json({..._v1, 'version': 2});
      }));
      final m = await repo.guardar(pasos: 9000, version: 1);
      expect(visto.method, 'PUT');
      expect(jsonDecode(visto.body), {'metaPasos': 9000, 'version': 1});
      expect(m.version, 2);
    });

    test('un 409 de versión se vuelve ConflictoDeMetas con lo actual del servidor', () async {
      final repo = _http(MockClient((_) async => _json(
          {'error': 'Otro dispositivo cambió tus metas (versión 1).', 'codigo': 'CONFLICTO_DE_VERSION', 'actual': _v1},
          409)));
      await expectLater(
        repo.guardar(pasos: 7000, version: 0),
        throwsA(isA<ConflictoDeMetas>().having((c) => c.actual.metaPasos, 'actual', 12000)),
      );
    });

    test('un 400 sigue siendo ApiException con el mensaje del servidor', () async {
      final repo = _http(MockClient((_) async => _json({'error': 'La meta de pasos debe estar entre 1000 y 50000.'}, 400)));
      await expectLater(
        repo.guardar(pasos: 5, version: 0),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('1000'))),
      );
    });

    test('sin red es ApiException.sinConexion', () async {
      final repo = _http(MockClient((_) async => throw http.ClientException('sin red')));
      await expectLater(repo.obtener(), throwsA(isA<ApiException>().having((e) => e.sinConexion, 'sinConexion', true)));
    });
  });

  group('Muestra (mismas reglas que el servidor)', () {
    test('conflicto entre médico y paciente con la misma versión', () async {
      final almacen = AlmacenMetasMuestra();
      final medico = MuestraMetasRepository(almacen, quien: 'Médico');
      final paciente = MuestraMetasRepository(almacen);
      await medico.guardar(pasos: 12000, version: 0);
      await expectLater(paciente.guardar(pasos: 7000, version: 0), throwsA(isA<ConflictoDeMetas>()));
      expect((await paciente.obtener()).metaPasos, 12000);
      final ok = await paciente.guardar(pasos: 7000, version: 1);
      expect(ok.version, 2);
      expect(ok.actualizadaPor, 'Paciente');
    });

    test('sin versión se fusiona por campos', () async {
      final almacen = AlmacenMetasMuestra();
      await MuestraMetasRepository(almacen, quien: 'Médico').guardar(pasos: 12000);
      final m = await MuestraMetasRepository(almacen).guardar(sueno: 7.5);
      expect((m.metaPasos, m.metaSueno, m.version), (12000, 7.5, 2));
    });

    test('rangos y campos vacíos se rechazan', () async {
      final repo = MuestraMetasRepository(AlmacenMetasMuestra());
      await expectLater(repo.guardar(), throwsA(isA<ApiException>()));
      await expectLater(repo.guardar(pasos: 999), throwsA(isA<ApiException>()));
      await expectLater(repo.guardar(calorias: 5001), throwsA(isA<ApiException>()));
      await expectLater(repo.guardar(sueno: 3.9), throwsA(isA<ApiException>()));
    });
  });

  group('Pantalla de metas', () {
    testWidgets('muestra la versión vigente y guarda con ella', (t) async {
      final repo = MuestraMetasRepository(AlmacenMetasMuestra());
      await t.pumpWidget(_pantalla(repo));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('metas-version')), findsOneWidget);
      expect(find.textContaining('Versión 0'), findsOneWidget);

      await t.enterText(find.byKey(const Key('meta-pasos')), '8000');
      await t.tap(find.byKey(const Key('guardar-metas')));
      await t.pumpAndSettle();
      expect(find.textContaining('Metas guardadas (versión 1)'), findsOneWidget);
      expect((await repo.obtener()).metaPasos, 8000);
    });

    testWidgets('un valor fuera de rango se avisa sin llamar al servidor', (t) async {
      final almacen = AlmacenMetasMuestra();
      await t.pumpWidget(_pantalla(MuestraMetasRepository(almacen)));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('meta-pasos')), '5');
      await t.tap(find.byKey(const Key('guardar-metas')));
      await t.pumpAndSettle();
      expect(find.textContaining('Pasos: de 1000 a 50000'), findsOneWidget);
      expect(almacen.metas.version, 0);
    });

    testWidgets('conflicto → «Usar las del otro» carga lo del médico y no pisa nada', (t) async {
      final almacen = AlmacenMetasMuestra();
      await t.pumpWidget(_pantalla(MuestraMetasRepository(almacen)));
      await t.pumpAndSettle();
      // Mientras la paciente edita, el médico guarda.
      await MuestraMetasRepository(almacen, quien: 'Médico').guardar(pasos: 12000, version: 0);

      await t.enterText(find.byKey(const Key('meta-pasos')), '7000');
      await t.tap(find.byKey(const Key('guardar-metas')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dialogo-conflicto')), findsOneWidget);
      expect(find.textContaining('Médico guardó otras metas'), findsOneWidget);

      await t.tap(find.byKey(const Key('conflicto-usar-otras')));
      await t.pumpAndSettle();
      expect(almacen.metas.metaPasos, 12000);
      expect(almacen.metas.version, 1);
      expect(find.widgetWithText(TextField, '12000'), findsOneWidget);
    });

    testWidgets('conflicto → «Sobrescribir con las mías» reintenta sobre la versión nueva', (t) async {
      final almacen = AlmacenMetasMuestra();
      await t.pumpWidget(_pantalla(MuestraMetasRepository(almacen)));
      await t.pumpAndSettle();
      await MuestraMetasRepository(almacen, quien: 'Médico').guardar(pasos: 12000, version: 0);

      await t.enterText(find.byKey(const Key('meta-pasos')), '7000');
      await t.tap(find.byKey(const Key('guardar-metas')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('conflicto-sobrescribir')));
      await t.pumpAndSettle();
      expect(almacen.metas.metaPasos, 7000);
      expect(almacen.metas.version, 2);
      expect(almacen.metas.actualizadaPor, 'Paciente');
    });

    testWidgets('si no se puede leer, ofrece reintentar', (t) async {
      final repo = _http(MockClient((_) async => throw http.ClientException('sin red')));
      await t.pumpWidget(_pantalla(repo));
      await t.pumpAndSettle();
      expect(find.text('No se pudo conectar al servidor'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('Resumen', () {
    testWidgets('la tarjeta de pasos usa la meta del servidor y abre «Mis metas»', (t) async {
      final almacen = AlmacenMetasMuestra();
      await MuestraMetasRepository(almacen, quien: 'Médico').guardar(pasos: 12000);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ResumenScreen(repositorio: const MuestraSaludRepository(), metas: MuestraMetasRepository(almacen)),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('/ 12000'), findsOneWidget);

      await t.tap(find.byKey(const Key('abrir-metas')));
      await t.pumpAndSettle();
      expect(find.byType(MetasScreen), findsOneWidget);
    });

    testWidgets('sin repositorio de metas no hay botón y la meta es 10000', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: ResumenScreen(repositorio: MuestraSaludRepository())),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('abrir-metas')), findsNothing);
      expect(find.text('/ 10000'), findsOneWidget);
    });
  });

  test('MetasCuenta.fromJson acepta enteros donde llegan decimales', () {
    final m = MetasCuenta.fromJson({..._v1, 'metaSueno': 8});
    expect(m.metaSueno, 8.0);
  });
}
