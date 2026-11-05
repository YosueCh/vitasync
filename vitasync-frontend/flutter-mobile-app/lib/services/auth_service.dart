import 'api_cliente.dart';

/// Resultado de registrar o verificar un PIN, en el formato de
/// `LoginResultadoDTO.java` (`exito`, `mensaje`).
class ResultadoPin {
  const ResultadoPin({required this.exito, required this.mensaje});

  final bool exito;
  final String mensaje;

  factory ResultadoPin.fromJson(Map<String, dynamic> json) => ResultadoPin(
        exito: json['exito'] as bool? ?? false,
        mensaje: json['mensaje'] as String? ?? '',
      );
}

/// Contrato de autenticación por PIN de la vista móvil.
///
/// Un fallo de comunicación o un bloqueo por intentos se lanza como
/// [ApiException] con el mensaje listo para mostrar; un PIN equivocado no es
/// una excepción, vuelve como [ResultadoPin] con `exito` en false.
abstract interface class AuthService {
  bool get autenticado;

  /// Registra el PIN de una cuenta que todavía no tiene uno y, si sale bien,
  /// deja la sesión iniciada.
  Future<ResultadoPin> registrarPin(String usuarioId, String pin);

  Future<ResultadoPin> verificarPin(String usuarioId, String pin);

  void cerrarSesion();
}

/// Implementación real: el PIN se verifica en el backend, que guarda el salt
/// y el hash SHA-256 (`POST /api/usuarios/{id}/pin` y `/pin/verificar`).
/// El cliente solo conserva si la sesión está abierta; nunca guarda el PIN.
class HttpAuthService implements AuthService {
  HttpAuthService({ApiCliente? api}) : _api = api ?? ApiCliente();

  final ApiCliente _api;
  bool _autenticado = false;

  @override
  bool get autenticado => _autenticado;

  @override
  Future<ResultadoPin> registrarPin(String usuarioId, String pin) async {
    final registro = await _enviar('/usuarios/$usuarioId/pin', pin);
    if (!registro.exito) return registro;
    // Registrar el PIN equivale a entrar: se verifica de inmediato.
    return verificarPin(usuarioId, pin);
  }

  @override
  Future<ResultadoPin> verificarPin(String usuarioId, String pin) async {
    final resultado = await _enviar('/usuarios/$usuarioId/pin/verificar', pin);
    _autenticado = resultado.exito;
    return resultado;
  }

  @override
  void cerrarSesion() => _autenticado = false;

  Future<ResultadoPin> _enviar(String ruta, String pin) async {
    final json = await _api.postJson(ruta, {'pin': pin}) as Map<String, dynamic>;
    return ResultadoPin.fromJson(json);
  }
}

/// Para diseñar y capturar pantallas sin backend: acepta cualquier PIN de
/// 4 dígitos.
class MuestraAuthService implements AuthService {
  bool _autenticado = false;

  @override
  bool get autenticado => _autenticado;

  @override
  Future<ResultadoPin> registrarPin(String usuarioId, String pin) =>
      verificarPin(usuarioId, pin);

  @override
  Future<ResultadoPin> verificarPin(String usuarioId, String pin) async {
    _autenticado = pin.length == 4;
    return ResultadoPin(
      exito: _autenticado,
      mensaje: _autenticado ? 'PIN correcto.' : 'PIN incorrecto.',
    );
  }

  @override
  void cerrarSesion() => _autenticado = false;
}
