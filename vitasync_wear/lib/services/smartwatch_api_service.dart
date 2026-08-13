import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../auth/usuario_activo.dart';
import '../models/metricas.dart';

/// Cliente HTTP real hacia `vitasync-backend` (`/api/smartwatch/*`),
/// el mismo backend que usa la pantalla "Configuración de Dispositivo"
/// en `vitasync-frontend`. Ambos comparten el mismo dato: el backend
/// guarda la última lectura sincronizada por usuario (`usuarioId`,
/// elegido en `SeleccionarUsuarioScreen`), así que lo que sincroniza el
/// reloj es lo mismo que ve la web PARA ESA CUENTA — ya no un solo
/// dispositivo global compartido por cualquiera que abra la app.
///
/// Si el backend no está corriendo o no responde a tiempo, cada método
/// devuelve `null` en vez de lanzar una excepción — la pantalla usa ese
/// `null` para mostrar datos de ejemplo locales, igual que el patrón
/// `SIMULAR`/`MODO_LOCAL` ya usado en el frontend Angular.
class SmartwatchApiService {
  static const _timeout = Duration(seconds: 4);
  static const _puerto = 8081;

  /// El emulador de Android (incluido el de Wear OS) no puede llegar a
  /// "localhost" del propio emulador para hablar con la PC anfitriona:
  /// necesita el alias especial 10.0.2.2. En escritorio/web, localhost
  /// sí es la máquina donde corre el backend.
  String get _host {
    if (kIsWeb) return 'localhost';
    return Platform.isAndroid ? '10.0.2.2' : 'localhost';
  }

  String get _base => 'http://$_host:$_puerto/api/smartwatch';

  Future<Metricas?> obtenerMetricas() async {
    final usuarioId = UsuarioActivo.id;
    if (usuarioId == null) return null;
    try {
      final resp = await http
          .get(Uri.parse('$_base/metrics?usuarioId=$usuarioId'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        return Metricas.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {
      // Backend no disponible (503 sin Firebase, o sin red): se maneja arriba.
    }
    return null;
  }

  /// Simula una lectura de sensores del reloj y la envía al backend.
  /// Devuelve las métricas ya persistidas (eco del backend) o null si falló.
  Future<Metricas?> sincronizar() async {
    final usuarioId = UsuarioActivo.id;
    if (usuarioId == null) return null;
    final lectura = Metricas(
      pasos: 4000 + Random().nextInt(8000),
      calorias: 250 + Random().nextInt(550),
      suenoHoras: double.parse((5 + Random().nextDouble() * 4).toStringAsFixed(1)),
      frecuenciaCardiaca: 62 + Random().nextInt(33),
      bateria: 40 + Random().nextInt(55),
    );
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/sync?usuarioId=$usuarioId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(lectura.toJson()),
          )
          .timeout(_timeout);
      if (resp.statusCode == 200) return lectura; // el backend guardó justo esta lectura
    } catch (_) {}
    return null;
  }
}
