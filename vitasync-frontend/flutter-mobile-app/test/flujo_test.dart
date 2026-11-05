import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/main.dart';
import 'package:vitasync_mobile/models/estado_dispositivo.dart';
import 'package:vitasync_mobile/models/lectura_metricas.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/services/firmware_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

Future<void> _abrirApp(WidgetTester tester, [VitaSyncMobileApp? app]) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app ?? VitaSyncMobileApp.muestra());
}

Future<void> _elegirCuenta(WidgetTester tester, String nombre) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(nombre));
  await tester.pumpAndSettle();
}

Future<void> _escribirPin(WidgetTester tester, String pin) async {
  for (final digito in pin.split('')) {
    await tester.tap(find.text(digito));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Repositorio que falla las primeras [fallos] consultas y luego responde.
class _SaludInestable extends MuestraSaludRepository {
  _SaludInestable(this.fallos);

  int fallos;

  @override
  Future<LecturaMetricas> obtenerMetricas() async {
    if (fallos > 0) {
      fallos--;
      throw Exception('sin red');
    }
    return super.obtenerMetricas();
  }
}

/// Repositorio que devuelve siempre el mismo estado de dispositivo.
class _SaludConEstado extends MuestraSaludRepository {
  const _SaludConEstado(this.estado);

  final EstadoDispositivo estado;

  @override
  Future<EstadoDispositivo> obtenerEstado() async => estado;
}

VitaSyncMobileApp _appCon({
  SaludRepository? salud,
  FirmwareRepository? firmware,
}) {
  return VitaSyncMobileApp(
    usuarios: const MuestraUsuarioRepository(),
    saludPara: (Usuario _) => salud ?? const MuestraSaludRepository(),
    firmwarePara: (Usuario _) => firmware ?? MuestraFirmwareRepository(),
  );
}

Future<void> _entrar(WidgetTester tester, [VitaSyncMobileApp? app]) async {
  await _abrirApp(tester, app);
  await _elegirCuenta(tester, 'Ana Torres');
  await _escribirPin(tester, '1234');
}

void main() {
  testWidgets('al abrir solo se ve la lista de cuentas', (tester) async {
    await _abrirApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('¿Quién eres?'), findsOneWidget);
    expect(find.text('Ana Torres'), findsOneWidget);
    expect(find.text('Luis Pérez'), findsOneWidget);
    expect(find.text('Resumen'), findsNothing);
  });

  testWidgets('al elegir una cuenta se pide el PIN de esa cuenta', (tester) async {
    await _abrirApp(tester);
    await _elegirCuenta(tester, 'Luis Pérez');

    expect(find.text('Hola, Luis Pérez'), findsOneWidget);
    expect(find.text('Ingresa tu PIN'), findsOneWidget);
    expect(find.text('Resumen'), findsNothing);
  });

  testWidgets('se puede volver a elegir otra cuenta', (tester) async {
    await _abrirApp(tester);
    await _elegirCuenta(tester, 'Ana Torres');

    await tester.tap(find.text('Cambiar de cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('¿Quién eres?'), findsOneWidget);
  });

  testWidgets('con cuenta y PIN de 4 dígitos se entra al resumen', (tester) async {
    await _entrar(tester);

    expect(find.text('Ingresa tu PIN'), findsNothing);
    expect(find.text('Mis datos de salud'), findsOneWidget);
    expect(find.text('6320'), findsOneWidget);
    expect(find.text('Ana Torres'), findsOneWidget);
  });

  testWidgets('el estado de error ofrece reintentar y se recupera', (tester) async {
    await _entrar(tester, _appCon(salud: _SaludInestable(1)));
    expect(find.text('No se pudo conectar al servidor'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Mis datos de salud'), findsOneWidget);
  });

  testWidgets('la pestaña Dispositivo muestra la versión de firmware', (tester) async {
    await _entrar(tester);

    await tester.tap(find.text('Dispositivo'));
    await tester.pumpAndSettle();

    expect(find.text('Versión de firmware'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
  });

  testWidgets('el dispositivo muestra el estado real que reporta el backend', (tester) async {
    await _entrar(
      tester,
      _appCon(
        salud: const _SaludConEstado(
          EstadoDispositivo(estado: 'DESCONECTADO', mensaje: 'Sin dispositivo conectado'),
        ),
      ),
    );

    await tester.tap(find.text('Dispositivo'));
    await tester.pumpAndSettle();

    expect(find.text('Sin dispositivo conectado'), findsWidgets);
    expect(find.text('Versión de firmware'), findsNothing);
  });

  testWidgets('se puede pedir la actualización de firmware', (tester) async {
    await _entrar(tester);
    await tester.tap(find.text('Dispositivo'));
    await tester.pumpAndSettle();

    expect(find.text('Disponible: 1.1.0'), findsOneWidget);
    await tester.tap(find.text('Actualizar firmware'));
    // La barra de progreso anima sin parar: pumpAndSettle nunca terminaría.
    await tester.pump(const Duration(seconds: 1)); // responde el repositorio de muestra
    await tester.pump();
    expect(find.text('Actualizando el reloj…'), findsOneWidget);
    expect(find.text('Actualizar firmware'), findsNothing);
  });

  testWidgets('cerrar sesión regresa a la lista de cuentas', (tester) async {
    await _entrar(tester);

    await tester.tap(find.byTooltip('Cerrar sesión'));
    await tester.pumpAndSettle();

    expect(find.text('¿Quién eres?'), findsOneWidget);
    expect(find.text('Mis datos de salud'), findsNothing);
  });
}
