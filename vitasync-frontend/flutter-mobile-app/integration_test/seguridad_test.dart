// Prueba de integración REAL de la seguridad (Práctica 10 aplicada a VitaSync): la app corriendo en el
// emulador de Android, hablando con el backend de pruebas con la seguridad activa y con el emulador de
// Firebase Authentication. Nada está simulado en el camino app → red → servidor.
//
//   1) firebase emulators:start --only auth --project demo-vitasync          (puerto 9099)
//   2) backend de pruebas con --vitasync.seguridad.activa=true               (puerto 8081)
//      (ver vitasync-backend/README.md, sección «Seguridad»)
//   3) flutter drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/seguridad_test.dart -d emulator-5554 --dart-define=SEGURIDAD=true
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:vitasync_mobile/config/api_config.dart';
import 'package:vitasync_mobile/data/abrir_dao.dart';
import 'package:vitasync_mobile/data/metrica_dao_sqlite.dart';
import 'package:vitasync_mobile/main.dart';
import 'package:vitasync_mobile/screens/login_correo_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cuenta_correo_service.dart';

/// Espera con tiempo REAL (hay red de por medio) a que aparezca algo en pantalla.
Future<void> esperar(WidgetTester t, Finder f, {int segundos = 20, String? motivo}) async {
  final fin = DateTime.now().add(Duration(seconds: segundos));
  while (DateTime.now().isBefore(fin)) {
    await t.pump(const Duration(milliseconds: 300));
    if (f.evaluate().isNotEmpty) return;
  }
  fail('No apareció ${motivo ?? f.toString()} en $segundos s');
}

Future<void> escribir(WidgetTester t, String clave, String texto) async {
  await t.enterText(find.byKey(Key(clave)), texto);
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> tocar(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> teclearPin(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.text(d));
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dos personas: sesión con correo, UID, cuenta propia, reloj con clave y aislamiento', (t) async {
    expect(ApiConfig.seguridadActiva, isTrue, reason: 'ejecutar con --dart-define=SEGURIDAD=true');
    await binding.convertFlutterSurfaceToImage();

    final sufijo = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final correoAna = 'ana.$sufijo@uteq.test';
    const claveAna = 'ClaveAna123';
    final servicioAna = HttpCuentaCorreoService();

    // En el emulador de Android esto es SQLite REAL (Práctica 4), no shared_preferences.
    final dao = await abrirDaoLocal();
    expect(dao, isA<MetricaDaoSqlite>(), reason: 'en Android la caché local debe ser SQLite');
    await t.pumpWidget(VitaSyncMobileApp.real(dao: dao, cuentaCorreo: servicioAna));
    await t.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('01_login_correo');

    // ---- SEG-02: una contraseña/correo que no existe se rechaza con un mensaje genérico
    expect(find.byType(LoginCorreoScreen), findsOneWidget);
    await escribir(t, 'campo-correo', correoAna);
    await escribir(t, 'campo-clave', 'contrasena-mala');
    await tocar(t, find.byKey(const Key('btn-entrar')));
    await esperar(t, find.text('Correo o contraseña incorrectos.'));
    await binding.takeScreenshot('02_acceso_rechazado');
    expect(servicioAna.sesion, isNull);

    // ---- Ana crea su cuenta de correo (Firebase Authentication) y entra
    await escribir(t, 'campo-clave', claveAna);
    await tocar(t, find.byKey(const Key('btn-crear-cuenta')));
    await esperar(t, find.byKey(const Key('sesion-uid')), motivo: 'el UID de la sesión');
    final uidAna = (t.widget<Text>(find.byKey(const Key('sesion-uid'))).data ?? '').replaceFirst('UID: ', '');
    expect(find.text('Sesión: $correoAna'), findsOneWidget);
    expect(uidAna, servicioAna.sesion!.uid);
    expect(uidAna.length, greaterThan(10));
    expect(find.text('Aún no tienes ninguna cuenta VitaSync.'), findsOneWidget, reason: 'cada persona ve solo lo suyo');
    await binding.takeScreenshot('03_sesion_con_uid');

    // ---- crea su cuenta VitaSync (dueña: Ana, por el token)
    await tocar(t, find.byKey(const Key('btn-crear-cuenta-vitasync')));
    await t.pumpAndSettle();
    await escribir(t, 'campo-nombre', 'Ana Pérez');
    await escribir(t, 'campo-usuario', 'ana$sufijo');
    await tocar(t, find.byKey(const Key('btn-guardar-cuenta')));
    await esperar(t, find.text('Ana Pérez'), motivo: 'la cuenta recién creada en la lista');
    await binding.takeScreenshot('04_cuenta_vitasync_creada');

    // ---- PIN (se crea y se confirma) y entrada a la app
    await tocar(t, find.text('Ana Pérez'));
    await esperar(t, find.text('Crea tu PIN de 4 dígitos'));
    await teclearPin(t, '2468');
    await esperar(t, find.text('Confirma tu PIN'));
    await teclearPin(t, '2468');
    await esperar(t, find.text('Dispositivo'), motivo: 'la barra de navegación');

    // ---- vincular el reloj: el servidor entrega la clave UNA vez
    await tocar(t, find.text('Dispositivo'));
    await esperar(t, find.byKey(const Key('btn-vincular-reloj')));
    await tocar(t, find.byKey(const Key('btn-vincular-reloj')));
    await esperar(t, find.byKey(const Key('clave-dispositivo')), motivo: 'la clave del dispositivo');
    final clave = t.widget<SelectableText>(find.byKey(const Key('clave-dispositivo'))).data!;
    expect(RegExp(r'^[0-9a-f]{48}$').hasMatch(clave), isTrue, reason: 'clave de 24 bytes en hexadecimal');
    await binding.takeScreenshot('05_reloj_vinculado_con_clave');
    await tocar(t, find.text('Listo'));
    await t.pump(const Duration(seconds: 1));

    // ---- el "firmware" (sin token de persona) manda una lectura con su clave
    final ana = ApiCliente(token: servicioAna.token);
    final cuentas = await ana.get('/usuarios') as List<dynamic>;
    expect(cuentas.length, 1);
    final idAna = (cuentas.single as Map<String, dynamic>)['id'] as String;
    final base = ApiConfig.baseUrl;
    final lectura = jsonEncode({
      'pasos': 4321, 'calorias': 210, 'sueno': 7.5, 'ritmoCardiaco': 72, 'bateria': 88,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    Future<int> enviar(String? claveDisp) async {
      final r = await http.post(
        Uri.parse('$base/smartwatch/sync?usuarioId=$idAna'),
        headers: {'content-type': 'application/json', if (claveDisp != null) 'X-Clave-Dispositivo': claveDisp},
        body: lectura,
      );
      return r.statusCode;
    }
    expect(await enviar(null), 401, reason: 'sin clave ni token no se puede enviar datos');
    expect(await enviar('clave-inventada'), 401);
    expect(await enviar(clave), 200, reason: 'con la clave del reloj sí');

    // ---- la app muestra lo que mandó el reloj
    await tocar(t, find.text('Resumen'));
    await esperar(t, find.textContaining(RegExp(r'4[,.]?321')), segundos: 15, motivo: 'los 4321 pasos del reloj');
    await binding.takeScreenshot('06_resumen_con_datos_del_reloj');

    // ---- la caché local (SQLite del teléfono) guardó lo que el servidor entregó: sirve para verlo sin conexión
    final enCache = await dao.ultima(idAna);
    expect(enCache, isNotNull, reason: 'la lectura quedó guardada en SQLite');
    expect(enCache!.metricas.pasos, 4321);

    // ---- Actividad 1: contactos de emergencia, desde la interfaz hasta el servidor real
    await tocar(t, find.text('Contactos'));
    await esperar(t, find.byKey(const Key('btn-agregar-contacto')), motivo: 'la pestaña de contactos');
    expect(find.byKey(const Key('sin-contactos')), findsOneWidget);
    await tocar(t, find.byKey(const Key('btn-agregar-contacto')));
    await t.pumpAndSettle();
    await escribir(t, 'campo-contacto-nombre', 'Mamá');
    await escribir(t, 'campo-contacto-telefono', '(442) 123-4567');
    await tocar(t, find.byKey(const Key('btn-guardar-contacto')));
    await esperar(t, find.text('Familiar · 4421234567'), motivo: 'el contacto guardado en la lista');
    await binding.takeScreenshot('07_contacto_guardado_en_la_nube');
    final guardados = await ana.get('/contactos', {'usuarioId': idAna}) as List<dynamic>;
    expect(guardados, hasLength(1), reason: 'el servidor tiene el contacto');
    expect((guardados.single as Map<String, dynamic>)['telefono'], '4421234567');
    final idContacto = (guardados.single as Map<String, dynamic>)['id'] as String;

    // ---- Beto: otra persona real. No ve ni toca nada de Ana (403 a través del cliente real de la app)
    final servicioBeto = HttpCuentaCorreoService();
    await servicioBeto.registrarse('beto.$sufijo@uteq.test', 'ClaveBeto456');
    final beto = ApiCliente(token: servicioBeto.token);
    expect(await beto.get('/usuarios') as List<dynamic>, isEmpty, reason: 'Beto no ve la cuenta de Ana');
    for (final ruta in ['/usuarios/$idAna', '/smartwatch/metrics', '/smartwatch/historial', '/firmware/estado']) {
      await expectLater(
        beto.get(ruta, ruta.startsWith('/usuarios') ? null : {'usuarioId': idAna}),
        throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('No tienes permiso'))),
        reason: ruta,
      );
    }
    await expectLater(
      beto.post('/smartwatch/connect', {'usuarioId': idAna}),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('No tienes permiso'))),
    );
    await expectLater(
      beto.get('/contactos', {'usuarioId': idAna}),
      throwsA(isA<ApiException>().having((e) => e.mensaje, 'mensaje', contains('No tienes permiso'))),
      reason: 'Beto no ve los contactos de Ana',
    );
    final igual = await ana.get('/usuarios/$idAna') as Map<String, dynamic>;
    expect(igual['habilitado'], isTrue, reason: 'la cuenta de Ana sigue intacta');

    // ---- Ana elimina su contacto desde la app (con confirmación) y desaparece del servidor
    await tocar(t, find.byKey(Key('eliminar-contacto-$idContacto')));
    await t.pumpAndSettle();
    await tocar(t, find.byKey(const Key('confirmar-eliminar-contacto')));
    await esperar(t, find.byKey(const Key('sin-contactos')), motivo: 'la lista vacía tras eliminar');
    await binding.takeScreenshot('08_contacto_eliminado');
    expect(await ana.get('/contactos', {'usuarioId': idAna}) as List<dynamic>, isEmpty);

    // ---- cerrar la sesión de correo regresa al acceso y borra el token
    servicioAna.cerrarSesion();
    expect(await servicioAna.token(), isNull);
  });
}
