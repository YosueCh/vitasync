import 'dispositivo.dart';

/// Respuesta de `GET /api/smartwatch/status` (`EstadoRespuestaDTO.java`):
/// un envoltorio con el estado de la conexión y, si existe, el dispositivo.
class EstadoDispositivo {
  const EstadoDispositivo({
    required this.estado,
    required this.mensaje,
    this.dispositivo,
  });

  /// DESCONECTADO | CONECTANDO | CONECTADO | SINCRONIZANDO | ERROR
  final String estado;
  final String mensaje;
  final Dispositivo? dispositivo;

  bool get conectado => estado == 'CONECTADO' || estado == 'SINCRONIZANDO';

  factory EstadoDispositivo.fromJson(Map<String, dynamic> json) {
    final d = json['dispositivo'];
    return EstadoDispositivo(
      estado: json['estado'] as String? ?? 'DESCONECTADO',
      mensaje: json['mensaje'] as String? ?? '',
      dispositivo: d is Map<String, dynamic> ? Dispositivo.fromJson(d) : null,
    );
  }
}
