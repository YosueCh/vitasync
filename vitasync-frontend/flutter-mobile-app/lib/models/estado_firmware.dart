/// Respuesta de `GET /api/firmware/estado` (`EstadoFirmwareDTO.java`):
/// versión que corre el dispositivo frente a la última publicada.
class EstadoFirmware {
  const EstadoFirmware({
    required this.versionActual,
    required this.ultimaVersion,
    required this.notas,
    required this.hayActualizacion,
    required this.ordenPendiente,
  });

  final String? versionActual;
  final String ultimaVersion;
  final String notas;
  final bool hayActualizacion;

  /// Ya se pidió actualizar y el dispositivo todavía no la aplica.
  final bool ordenPendiente;

  factory EstadoFirmware.fromJson(Map<String, dynamic> json) {
    final ultima = json['ultima'] as Map<String, dynamic>? ?? const {};
    return EstadoFirmware(
      versionActual: json['versionActual'] as String?,
      ultimaVersion: ultima['version'] as String? ?? '',
      notas: ultima['notas'] as String? ?? '',
      hayActualizacion: json['hayActualizacion'] as bool? ?? false,
      ordenPendiente: json['ordenPendiente'] as bool? ?? false,
    );
  }
}
