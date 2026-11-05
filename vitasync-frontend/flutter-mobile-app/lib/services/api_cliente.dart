import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Error de comunicación con el backend, con un mensaje listo para mostrar.
class ApiException implements Exception {
  const ApiException(this.mensaje, {this.sinConexion = false, this.codigo, this.datos});

  final String mensaje;

  /// Código de máquina que manda el servidor en algunos rechazos (p. ej. «CONFLICTO_DE_VERSION»).
  final String? codigo;

  /// Cuerpo completo de la respuesta de rechazo (p. ej. las metas «actual» de un conflicto de versión).
  final Map<String, dynamic>? datos;

  /// true = el servidor no se pudo alcanzar (sin red, apagado, tiempo agotado). Es distinto de una respuesta
  /// del servidor que rechaza la operación (400, 401, 403, 409…): lo primero se puede reintentar, lo segundo no.
  final bool sinConexion;

  @override
  String toString() => mensaje;
}

/// Cliente HTTP mínimo hacia el backend (Práctica 3: petición a una URL
/// definida aparte de la lógica, con tiempo límite y mensaje de error claro).
///
/// Cualquier fallo se traduce a [ApiException]; las pantallas no manejan
/// excepciones de red.
class ApiCliente {
  /// [token] entrega el ID token de la sesión de correo (Práctica 10); si devuelve un valor, se manda en
  /// «Authorization: Bearer». null = la app corre sin inicio de sesión (el backend con seguridad apagada).
  ApiCliente({String? baseUrl, http.Client? cliente, Future<String?> Function()? token})
      : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _cliente = cliente ?? http.Client(),
        _token = token;

  final String baseUrl;
  final http.Client _cliente;
  final Future<String?> Function()? _token;

  Future<dynamic> get(String ruta, [Map<String, String>? query]) =>
      _enviar((h) => _cliente.get(_uri(ruta, query), headers: h));

  Future<dynamic> post(String ruta, [Map<String, String>? query]) =>
      _enviar((h) => _cliente.post(_uri(ruta, query), headers: h));

  Future<dynamic> delete(String ruta, [Map<String, String>? query]) =>
      _enviar((h) => _cliente.delete(_uri(ruta, query), headers: h));

  /// POST con cuerpo JSON. Se usa para el PIN, que nunca va en la URL.
  Future<dynamic> postJson(String ruta, Object cuerpo) => _enviar(
        (h) => _cliente.post(
          _uri(ruta, null),
          headers: {...h, 'content-type': 'application/json'},
          body: jsonEncode(cuerpo),
        ),
      );

  /// PUT con cuerpo JSON (cambios con control de versión).
  Future<dynamic> putJson(String ruta, Object cuerpo) => _enviar(
        (h) => _cliente.put(
          _uri(ruta, null),
          headers: {...h, 'content-type': 'application/json'},
          body: jsonEncode(cuerpo),
        ),
      );

  Uri _uri(String ruta, Map<String, String>? query) =>
      Uri.parse('$baseUrl$ruta').replace(queryParameters: query);

  Future<dynamic> _enviar(Future<http.Response> Function(Map<String, String> cabeceras) peticion) async {
    final http.Response respuesta;
    try {
      final token = await _token?.call();
      final cabeceras = <String, String>{if (token != null) 'Authorization': 'Bearer $token'};
      respuesta = await peticion(cabeceras).timeout(ApiConfig.tiempoLimite);
    } on Exception {
      // Sin red, servidor apagado, CORS o tiempo agotado.
      throw const ApiException('No se pudo conectar al servidor', sinConexion: true);
    }
    // 401: sin sesión o token vencido. 403: la cuenta pedida es de otra persona (Práctica 10).
    if (respuesta.statusCode == 401) {
      throw const ApiException('Tu sesión venció. Vuelve a iniciar sesión.');
    }
    if (respuesta.statusCode == 403) {
      throw const ApiException('No tienes permiso para ver estos datos.');
    }
    if (respuesta.statusCode == 503) {
      throw const ApiException('El servidor no tiene Firebase configurado');
    }
    // 400 (dato inválido), 409 (conflicto) y 429 (cuenta bloqueada) traen en
    // el cuerpo un mensaje pensado para el usuario: se muestra tal cual.
    if (const {400, 409, 429}.contains(respuesta.statusCode)) {
      final mensaje = _mensajeDelServidor(respuesta);
      if (mensaje != null) {
        throw ApiException(mensaje, codigo: _campo(respuesta, 'codigo'), datos: _cuerpo(respuesta));
      }
    }
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw ApiException('El servidor respondió ${respuesta.statusCode}');
    }
    if (respuesta.body.isEmpty) return null;
    return jsonDecode(utf8.decode(respuesta.bodyBytes));
  }

  static Map<String, dynamic>? _cuerpo(http.Response respuesta) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      return cuerpo is Map<String, dynamic> ? cuerpo : null;
    } on Object {
      return null;
    }
  }

  static String? _campo(http.Response respuesta, String nombre) {
    final valor = _cuerpo(respuesta)?[nombre];
    return valor is String ? valor : null;
  }

  static String? _mensajeDelServidor(http.Response respuesta) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final error = cuerpo is Map<String, dynamic> ? cuerpo['error'] : null;
      return error is String && error.isNotEmpty ? error : null;
    } on Object {
      return null;
    }
  }
}
