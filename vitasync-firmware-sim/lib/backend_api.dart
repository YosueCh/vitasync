import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fallo al hablar con el backend (red caída o respuesta inesperada).
class BackendException implements Exception {
  const BackendException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Estado del dispositivo registrado en el backend.
class EstadoRemoto {
  const EstadoRemoto({required this.conectado, this.firmware, this.bateria});

  final bool conectado;
  final String? firmware;
  final int? bateria;
}

/// Orden de actualización de firmware pendiente.
class OrdenFirmware {
  const OrdenFirmware(this.version);

  final String version;
}

/// Contrato del firmware hacia el servidor (los mismos endpoints que usan
/// el reloj y la vista móvil). Es una interfaz para poder probar el
/// firmware sin red.
abstract interface class BackendApi {
  Future<EstadoRemoto> estado(String usuarioId);

  Future<void> conectar(String usuarioId);

  Future<void> sincronizar(String usuarioId, Map<String, Object> metricas);

  /// null si el usuario no ha pedido actualizar.
  Future<OrdenFirmware?> ordenFirmware(String usuarioId);

  Future<void> reportarFirmware(String usuarioId, String version);
}

class BackendApiHttp implements BackendApi {
  /// [claveDispositivo]: la clave que entregó el servidor al conectar el reloj (Práctica 10). Con ella el
  /// firmware se identifica en sync, orden y aplicar mediante la cabecera X-Clave-Dispositivo.
  BackendApiHttp({required String baseUrl, http.Client? cliente, this.claveDispositivo})
      : _base = baseUrl,
        _cliente = cliente ?? http.Client();

  final String? claveDispositivo;
  final String _base;
  final http.Client _cliente;

  static const _limite = Duration(seconds: 4);

  @override
  Future<EstadoRemoto> estado(String usuarioId) async {
    final json = await _enviar('GET', '/smartwatch/status', {'usuarioId': usuarioId});
    final mapa = json as Map<String, dynamic>;
    final d = mapa['dispositivo'] as Map<String, dynamic>?;
    return EstadoRemoto(
      conectado: mapa['estado'] == 'CONECTADO',
      firmware: d?['firmware'] as String?,
      bateria: (d?['bateria'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> conectar(String usuarioId) =>
      _enviar('POST', '/smartwatch/connect', {'usuarioId': usuarioId});

  @override
  Future<void> sincronizar(String usuarioId, Map<String, Object> metricas) =>
      _enviar('POST', '/smartwatch/sync', {'usuarioId': usuarioId}, metricas, true);

  @override
  Future<OrdenFirmware?> ordenFirmware(String usuarioId) async {
    final json = await _enviar('GET', '/firmware/orden', {'usuarioId': usuarioId}, null, true)
        as Map<String, dynamic>;
    return json['pendiente'] == true ? OrdenFirmware(json['version'] as String) : null;
  }

  @override
  Future<void> reportarFirmware(String usuarioId, String version) => _enviar(
        'POST',
        '/firmware/aplicar',
        {'usuarioId': usuarioId, 'version': version},
        null,
        true,
      );

  Future<dynamic> _enviar(
    String metodo,
    String ruta,
    Map<String, String> query, [
    Map<String, Object>? cuerpo,
    bool llamadaDeDispositivo = false,
  ]) async {
    final uri = Uri.parse('$_base$ruta').replace(queryParameters: query);
    final http.Response respuesta;
    try {
      final peticion = http.Request(metodo, uri);
      if (llamadaDeDispositivo && claveDispositivo != null) {
        peticion.headers['X-Clave-Dispositivo'] = claveDispositivo!;
      }
      if (cuerpo != null) {
        peticion.headers['content-type'] = 'application/json';
        peticion.body = jsonEncode(cuerpo);
      }
      respuesta = await http.Response.fromStream(
        await _cliente.send(peticion).timeout(_limite),
      );
    } on Exception {
      throw const BackendException('sin conexión con el servidor');
    }
    if (respuesta.statusCode == 401) {
      throw const BackendException('clave de dispositivo rechazada: vuelve a conectar el reloj desde la app');
    }
    if (respuesta.statusCode == 503) {
      throw const BackendException('el servidor no tiene Firebase configurado');
    }
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw BackendException('el servidor respondió ${respuesta.statusCode}');
    }
    return respuesta.body.isEmpty ? null : jsonDecode(utf8.decode(respuesta.bodyBytes));
  }
}
