import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'politica_reintento.dart';

/// Error de comunicación con el backend, con un mensaje listo para mostrar.
class ApiException implements Exception {
  const ApiException(this.mensaje, {this.sinConexion = false, this.codigo, this.datos, this.estado});

  final String mensaje;

  /// Código de máquina que manda el servidor en algunos rechazos (p. ej. «CONFLICTO_DE_VERSION»).
  final String? codigo;

  /// Cuerpo completo de la respuesta de rechazo (p. ej. las metas «actual» de un conflicto de versión).
  final Map<String, dynamic>? datos;

  /// true = el servidor no se pudo alcanzar (sin red, apagado, tiempo agotado). Es distinto de una respuesta
  /// del servidor que rechaza la operación (400, 401, 403, 409…): lo primero se puede reintentar, lo segundo no.
  final bool sinConexion;

  /// Código HTTP de la respuesta que originó el error (null si no hubo respuesta).
  final int? estado;

  /// true = vale la pena volver a intentar: no se alcanzó al servidor o este contestó 502/504 (puerta de enlace).
  bool get reintentable => sinConexion || estado == 502 || estado == 504;

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
  ApiCliente({
    String? baseUrl,
    http.Client? cliente,
    Future<String?> Function()? token,
    this.reintentos = PoliticaReintento.ninguna,
    Future<void> Function(Duration)? esperar,
  })  : baseUrl = baseUrl ?? ApiConfig.baseUrl,
        _cliente = cliente ?? http.Client(),
        _token = token,
        _esperar = esperar ?? Future<void>.delayed;

  final String baseUrl;
  final http.Client _cliente;
  final Future<String?> Function()? _token;

  /// Reintentos con espera progresiva (Práctica 12). Solo para lecturas y escrituras marcadas como idempotentes.
  final PoliticaReintento reintentos;
  final Future<void> Function(Duration) _esperar;

  Future<dynamic> get(String ruta, [Map<String, String>? query]) =>
      _enviar((h) => _cliente.get(_uri(ruta, query), headers: h), reintentable: true);

  /// GET de un archivo: devuelve los bytes tal cual (sin interpretarlos como JSON).
  Future<Uint8List> getBytes(String ruta, [Map<String, String>? query]) async {
    final r = await _enviarCrudo((h) => _cliente.get(_uri(ruta, query), headers: h), reintentable: true);
    return r.bodyBytes;
  }

  Future<dynamic> post(String ruta, [Map<String, String>? query]) =>
      _enviar((h) => _cliente.post(_uri(ruta, query), headers: h));

  Future<dynamic> delete(String ruta, [Map<String, String>? query]) =>
      _enviar((h) => _cliente.delete(_uri(ruta, query), headers: h));

  /// POST con cuerpo JSON. Se usa para el PIN, que nunca va en la URL.
  ///
  /// [idempotente] = true cuando el cuerpo lleva un identificador que el servidor usa para no repetir la operación
  /// (p. ej. el idCliente del chat): solo entonces se reintenta automáticamente tras un fallo de red.
  Future<dynamic> postJson(String ruta, Object cuerpo, {bool idempotente = false}) => _enviar(
        (h) => _cliente.post(
          _uri(ruta, null),
          headers: {...h, 'content-type': 'application/json'},
          body: jsonEncode(cuerpo),
        ),
        reintentable: idempotente,
      );

  /// PUT con cuerpo JSON (cambios con control de versión).
  Future<dynamic> putJson(String ruta, Object cuerpo, {bool idempotente = false}) => _enviar(
        (h) => _cliente.put(
          _uri(ruta, null),
          headers: {...h, 'content-type': 'application/json'},
          body: jsonEncode(cuerpo),
        ),
        reintentable: idempotente,
      );

  Uri _uri(String ruta, Map<String, String>? query) =>
      Uri.parse('$baseUrl$ruta').replace(queryParameters: query);

  Future<dynamic> _enviar(Future<http.Response> Function(Map<String, String> cabeceras) peticion,
      {bool reintentable = false}) async {
    final respuesta = await _enviarCrudo(peticion, reintentable: reintentable);
    if (respuesta.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(respuesta.bodyBytes));
    } on FormatException {
      // Un proxy, un portal cautivo o un servidor mal configurado pueden contestar 200 con HTML. Sin esta
      // traducción la FormatException se escapaba de las pantallas que solo atrapan ApiException (WB-HALLAZGO-1).
      throw const ApiException('El servidor respondió algo que la aplicación no entiende');
    }
  }

  /// Envía la petición (con reintento y espera progresiva si es seguro repetirla) y devuelve la respuesta exitosa.
  Future<http.Response> _enviarCrudo(Future<http.Response> Function(Map<String, String> cabeceras) peticion,
      {bool reintentable = false}) async {
    for (var intento = 0;; intento++) {
      try {
        return await _enviarUnaVez(peticion);
      } on ApiException catch (e) {
        final reintentar = reintentable && e.reintentable && intento < reintentos.maxReintentos;
        if (!reintentar) rethrow;
        await _esperar(reintentos.espera(intento));
      }
    }
  }

  /// Un solo intento: traduce los fallos a [ApiException].
  Future<http.Response> _enviarUnaVez(Future<http.Response> Function(Map<String, String> cabeceras) peticion) async {
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
      // Se decodifica UNA sola vez (antes eran tres, y el «catch» de _cuerpo no se podía alcanzar: WB-HALLAZGO-3).
      final cuerpo = _cuerpo(respuesta);
      final error = cuerpo?['error'];
      if (cuerpo != null && error is String && error.isNotEmpty) {
        final codigo = cuerpo['codigo'];
        throw ApiException(error, codigo: codigo is String ? codigo : null, datos: cuerpo);
      }
    }
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw ApiException('El servidor respondió ${respuesta.statusCode}', estado: respuesta.statusCode);
    }
    return respuesta;
  }

  static Map<String, dynamic>? _cuerpo(http.Response respuesta) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      return cuerpo is Map<String, dynamic> ? cuerpo : null;
    } on Object {
      return null;
    }
  }

}
