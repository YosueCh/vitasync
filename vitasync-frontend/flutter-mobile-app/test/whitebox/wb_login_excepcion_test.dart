// PRÁCTICA 11 · Fase 2 · Pruebas de EXCEPCIONES de la pantalla de acceso (WB-04)
//
// LoginCorreoScreen._enviar tenía: try { await servicio.iniciarSesion/registrarse(...) } on ApiException { mostrar } finally { ... }
// Cualquier OTRA excepción (TypeError por un campo que falta en la respuesta, StateError, FormatException…) pasaba de
// largo: el botón se reactivaba sin mostrar nada, y la persona decía «no hace nada» (WB-HALLAZGO-2).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/screens/login_correo_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cuenta_correo_service.dart';

class _ServicioQueFalla implements CuentaCorreoService {
  _ServicioQueFalla(this.falla);
  final Object falla;
  @override
  SesionCorreo? get sesion => null;
  @override
  Future<SesionCorreo> iniciarSesion(String correo, String clave) async => throw falla;
  @override
  Future<SesionCorreo> registrarse(String correo, String clave) async => throw falla;
  @override
  Future<String?> token() async => null;
  @override
  void cerrarSesion() {}
}

Future<void> _intentarEntrar(WidgetTester t, Object falla) async {
  var autenticado = false;
  await t.pumpWidget(MaterialApp(
    home: LoginCorreoScreen(servicio: _ServicioQueFalla(falla), onAutenticado: () => autenticado = true),
  ));
  await t.enterText(find.byKey(const Key('campo-correo')), 'ana@uteq.test');
  await t.enterText(find.byKey(const Key('campo-clave')), 'Clave123');
  await t.tap(find.byKey(const Key('btn-entrar')));
  await t.pumpAndSettle();
  expect(autenticado, isFalse, reason: 'una operación fallida jamás debe mostrarse como exitosa');
}

void main() {
  testWidgets('ApiException → muestra su mensaje (camino ya cubierto)', (t) async {
    await _intentarEntrar(t, const ApiException('Correo o contraseña incorrectos.'));
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
  });

  for (final caso in <String, Object>{
    'StateError': StateError('respuesta sin idToken'),
    'TypeError por un cast (campo ausente)': (() {
      try {
        (null as dynamic) as String;
      } catch (e) {
        return e;
      }
      return StateError('x');
    })(),
    'FormatException': const FormatException('respuesta ilegible'),
    'Exception genérica': Exception('boom'),
  }.entries) {
    testWidgets('HALLAZGO-2: ${caso.key} → se muestra un mensaje y el botón vuelve a estar activo', (t) async {
      await _intentarEntrar(t, caso.value);
      expect(find.byKey(const Key('error-acceso')), findsOneWidget, reason: 'antes: ningún mensaje');
      expect(find.text('No se pudo completar. Inténtalo de nuevo.'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('btn-entrar'))).onPressed, isNotNull);
    });
  }
}
