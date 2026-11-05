import 'package:flutter/material.dart';

/// Mismo color base (teal) que la app del reloj, para que las superficies de
/// VitaSync se perciban como un solo producto.
class AppTheme {
  AppTheme._();

  static ThemeData get claro => _tema(Brightness.light);

  static ThemeData get oscuro => _tema(Brightness.dark);

  static ThemeData _tema(Brightness brillo) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brillo,
      ),
    );
  }
}
