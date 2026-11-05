import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_cliente.dart' show ApiException;

/// Sesión de una persona con correo y contraseña (Firebase Authentication, Práctica 10).
/// El [uid] lo asigna Firebase; es lo que el backend usa para saber de quién son los datos.
class SesionCorreo {
  const SesionCorreo({
    required this.uid,
    required this.correo,
    required this.idToken,
    required this.refreshToken,
    required this.expira,
  });

  final String uid;
  final String correo;
  final String idToken;
  final String refreshToken;
  final DateTime expira;
}

/// Contrato del inicio de sesión con correo y contraseña. Es una capa DISTINTA del PIN: el correo dice
/// quién eres ante el servidor (token); el PIN sigue siendo el candado de la pantalla.
abstract interface class CuentaCorreoService {
  /// null si nadie ha iniciado sesión.
  SesionCorreo? get sesion;

  Future<SesionCorreo> iniciarSesion(String correo, String clave);

  Future<SesionCorreo> registrarse(String correo, String clave);

  /// Token vigente para el encabezado Authorization; lo renueva si le queda menos de un minuto.
  /// null si no hay sesión.
  Future<String?> token();

  void cerrarSesion();
}

/// Implementación real sobre la API REST de Firebase Authentication (no necesita plugin nativo).
/// Con el emulador, la URL base es http://host:9099/identitytoolkit.googleapis.com (ver [ApiConfig.authBase]).
class HttpCuentaCorreoService implements CuentaCorreoService {
  HttpCuentaCorreoService({
    String? authBase,
    String? apiKey,
    http.Client? cliente,
    DateTime Function()? ahora,
  })  : _base = authBase ?? ApiConfig.authBase,
        _clave = apiKey ?? ApiConfig.firebaseApiKey,
        _cliente = cliente ?? http.Client(),
        _ahora = ahora ?? DateTime.now;

  final String _base;
  final String _clave;
  final http.Client _cliente;
  final DateTime Function() _ahora;

  SesionCorreo? _sesion;

  @override
  SesionCorreo? get sesion => _sesion;

  @override
  Future<SesionCorreo> iniciarSesion(String correo, String clave) =>
      _entrar('accounts:signInWithPassword', correo, clave);

  @override
  Future<SesionCorreo> registrarse(String correo, String clave) =>
      _entrar('accounts:signUp', correo, clave);

  Future<SesionCorreo> _entrar(String operacion, String correo, String clave) async {
    final c = correo.trim();
    if (c.isEmpty || clave.isEmpty) throw const ApiException('Escribe el correo y la contraseña.');
    final json = await _post(
      '$_base/v1/$operacion?key=$_clave',
      jsonEncode({'email': c, 'password': clave, 'returnSecureToken': true}),
      'application/json',
    );
    return _sesion = SesionCorreo(
      uid: json['localId'] as String,
      correo: (json['email'] as String?) ?? c,
      idToken: json['idToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expira: _ahora().add(Duration(seconds: int.tryParse('${json['expiresIn']}') ?? 3600)),
    );
  }

  @override
  Future<String?> token() async {
    final s = _sesion;
    if (s == null) return null;
    if (s.expira.difference(_ahora()) > const Duration(minutes: 1)) return s.idToken;
    // Está por vencer: se renueva con el refresh token (securetoken.googleapis.com).
    final base = _base.replaceFirst('identitytoolkit.googleapis.com', 'securetoken.googleapis.com');
    try {
      final json = await _post(
        '$base/v1/token?key=$_clave',
        'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(s.refreshToken)}',
        'application/x-www-form-urlencoded',
      );
      _sesion = SesionCorreo(
        uid: s.uid,
        correo: s.correo,
        idToken: json['id_token'] as String,
        refreshToken: (json['refresh_token'] as String?) ?? s.refreshToken,
        expira: _ahora().add(Duration(seconds: int.tryParse('${json['expires_in']}') ?? 3600)),
      );
      return _sesion!.idToken;
    } on ApiException {
      // No se pudo renovar: se manda el token que haya; el servidor responderá 401 y la app pedirá volver a entrar.
      return s.idToken;
    }
  }

  @override
  void cerrarSesion() => _sesion = null;

  Future<Map<String, dynamic>> _post(String url, String cuerpo, String tipo) async {
    final http.Response r;
    try {
      r = await _cliente
          .post(Uri.parse(url), headers: {'content-type': tipo}, body: cuerpo)
          .timeout(ApiConfig.tiempoLimite);
    } on Exception {
      throw const ApiException('No se pudo conectar con el servicio de inicio de sesión');
    }
    final dynamic json = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 200 && r.statusCode < 300 && json is Map<String, dynamic>) return json;
    throw ApiException(_mensajeDe(json));
  }

  /// Traduce el código de error de Firebase a un mensaje para la persona. Credenciales malas y cuentas
  /// inexistentes dan el MISMO mensaje: no se revela qué correos están registrados.
  static String _mensajeDe(dynamic json) {
    final codigo = json is Map<String, dynamic> && json['error'] is Map<String, dynamic>
        ? '${(json['error'] as Map<String, dynamic>)['message']}'
        : '';
    if (codigo.startsWith('WEAK_PASSWORD')) return 'La contraseña es muy débil (mínimo 6 caracteres).';
    if (codigo.startsWith('TOO_MANY_ATTEMPTS')) return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
    return switch (codigo) {
      'EMAIL_NOT_FOUND' || 'INVALID_PASSWORD' || 'INVALID_LOGIN_CREDENTIALS' => 'Correo o contraseña incorrectos.',
      'EMAIL_EXISTS' => 'Ya existe una cuenta con ese correo.',
      'INVALID_EMAIL' => 'El correo no es válido.',
      'USER_DISABLED' => 'Esta cuenta está deshabilitada.',
      _ => 'No se pudo iniciar sesión.',
    };
  }
}
