import 'package:flutter/material.dart';

import 'stats_widget.dart';

/// Punto de entrada del micro-frontend Flutter Web. Se compila con
/// `flutter build web` y se incrusta vía <iframe> en el dashboard Angular
/// (vitasync-frontend), tal como se documenta en la Practica 7-8.
///
/// El estado (tareas pendientes / en progreso / completadas) llega por
/// Query Parameters en la URL del iframe:
///   flutter_stats/index.html?pending=5&progress=3&completed=12
/// Cada vez que el host Angular actualiza esos valores y cambia el `src`
/// del iframe, esta app vuelve a arrancar con los nuevos parámetros.
void main() => runApp(const VitaSyncStatsApp());

class VitaSyncStatsApp extends StatelessWidget {
  const VitaSyncStatsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final params = Uri.base.queryParameters;
    final pendientes = int.tryParse(params['pending'] ?? '') ?? 0;
    final enProgreso = int.tryParse(params['progress'] ?? '') ?? 0;
    final completadas = int.tryParse(params['completed'] ?? '') ?? 0;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF14B88A)),
      home: Scaffold(
        // Transparente para que el widget se integre visualmente en la
        // tarjeta del host en vez de mostrar un fondo blanco de app completa.
        backgroundColor: Colors.transparent,
        body: Center(
          child: StatsWidget(
            tareasCompletadas: completadas,
            tareasPendientes: pendientes,
            tareasEnProgreso: enProgreso,
          ),
        ),
      ),
    );
  }
}
