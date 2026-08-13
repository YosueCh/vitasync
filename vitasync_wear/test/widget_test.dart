import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartwatch_auth/main.dart';

void main() {
  testWidgets('Sin PIN configurado, se muestra la pantalla de creación de PIN', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmartwatchAuthApp());
    await tester.pumpAndSettle();

    expect(find.text('Crea tu PIN'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });
}
