import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartwatch_auth/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage usa un canal nativo que no existe en `flutter test`: sin respuesta, la pantalla se quedaba cargando y
  // pumpAndSettle nunca terminaba. Se simula un almacén vacío (nadie ha creado un PIN todavía).
  const canal = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (_) async => null));
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));

  testWidgets('Sin PIN configurado, se muestra la pantalla de creación de PIN', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmartwatchAuthApp());
    await tester.pumpAndSettle();

    expect(find.text('Crea tu PIN'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });
}
