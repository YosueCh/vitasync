import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/usuario_activo.dart';
import '../config/configuracion_servidor.dart';
import '../models/metricas.dart';
import 'sensores_reloj.dart';

/// Cliente HTTP real hacia `vitasync-backend` (`/api/smartwatch/*`), el mismo que usan el sitio web y la app del celular.
///
/// Rúbrica D (reloj físico):
///  · la dirección del servidor y la clave de dispositivo vienen de [ConfiguracionServidor] (ya no está fija en 10.0.2.2);
///  · cada sincronización manda la cabecera `X-Clave-Dispositivo` (con la seguridad encendida el backend contesta 401 sin ella);
///  · la lectura sale de los SENSORES del reloj cuando los hay y se permitió su uso (ver [construirLectura]).
///
/// Si el backend no responde, los métodos devuelven null; [ultimoError] dice por qué (red, clave inválida…).
class SmartwatchApiService {
  SmartwatchApiService({
    AlmacenConfiguracion? almacen,
    SensoresReloj? sensores,
    http.Client? cliente,
    Duration tiempoLimite = const Duration(seconds: 4),
  })  : _almacen = almacen ?? AlmacenSeguro(),
        sensores = sensores ?? SensoresRelojAndroid(),
        _cliente = cliente ?? http.Client(),
        _timeout = tiempoLimite;

  final AlmacenConfiguracion _almacen;
  final SensoresReloj sensores;
  final http.Client _cliente;
  final Duration _timeout;

  /// Mensaje legible del último fallo (null si el último intento salió bien).
  String? ultimoError;

  /// De dónde salió la última lectura enviada.
  ResultadoLectura? ultimaLectura;

  Future<ConfiguracionServidor> configuracion() => _almacen.cargar();
  Future<void> guardarConfiguracion(ConfiguracionServidor c) => _almacen.guardar(c);

  Future<Metricas?> obtenerMetricas() async {
    final usuarioId = UsuarioActivo.id;
    if (usuarioId == null) return null;
    final c = await _almacen.cargar();
    try {
      final resp = await _cliente.get(Uri.parse('${c.base}/metrics?usuarioId=$usuarioId'), headers: _cabeceras(c)).timeout(_timeout);
      if (resp.statusCode == 200) {
        ultimoError = null;
        return Metricas.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
      ultimoError = _mensajeDe(resp.statusCode);
    } catch (_) {
      ultimoError = 'No se pudo conectar a ${c.host}:${c.puerto}.';
    }
    return null;
  }

  /// Mide con los sensores del reloj (o simula lo que no se puede medir) y lo envía. Devuelve la lectura enviada o null si falló.
  Future<Metricas?> sincronizar({double? ultimoSueno}) async {
    final usuarioId = UsuarioActivo.id;
    if (usuarioId == null) return null;
    final c = await _almacen.cargar();
    final estado = await sensores.estado();
    final sensor = (estado.frecuenciaUsable || estado.pasosUsable) ? await sensores.leer() : const LecturaSensores();
    final lectura = construirLectura(estado: estado, sensor: sensor, ultimoSueno: ultimoSueno);
    ultimaLectura = lectura;
    try {
      final resp = await _cliente
          .post(
            Uri.parse('${c.base}/sync?usuarioId=$usuarioId'),
            headers: {'Content-Type': 'application/json', ..._cabeceras(c)},
            body: jsonEncode(lectura.metricas.toJson()),
          )
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        ultimoError = null;
        return lectura.metricas; // el backend guardó justo esta lectura
      }
      ultimoError = _mensajeDe(resp.statusCode);
    } catch (_) {
      ultimoError = 'No se pudo conectar a ${c.host}:${c.puerto}.';
    }
    return null;
  }

  Map<String, String> _cabeceras(ConfiguracionServidor c) => {if (c.tieneClave) 'X-Clave-Dispositivo': c.clave};

  static String _mensajeDe(int codigo) => switch (codigo) {
        401 || 403 => 'Clave de dispositivo inválida: vuelve a vincular el reloj.',
        400 => 'El servidor rechazó la lectura.',
        503 => 'El servidor no tiene Firebase configurado.',
        _ => 'El servidor respondió $codigo.',
      };
}
