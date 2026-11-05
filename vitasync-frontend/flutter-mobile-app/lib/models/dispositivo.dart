/// Información del smartwatch, en el formato de `DispositivoDTO.java`
/// (dentro de `GET /api/smartwatch/status`). Incluye la versión de firmware.
class Dispositivo {
  const Dispositivo({
    required this.id,
    required this.nombre,
    required this.modelo,
    required this.bateria,
    required this.firmware,
    this.ultimaSync,
  });

  final String id;
  final String nombre;
  final String modelo;
  final int bateria;
  final String firmware;
  final DateTime? ultimaSync;

  factory Dispositivo.fromJson(Map<String, dynamic> json) {
    final sync = json['ultimaSync'] as String?;
    return Dispositivo(
      id: json['id'] as String? ?? '',
      nombre: json['nombre'] as String? ?? 'Smartwatch',
      modelo: json['modelo'] as String? ?? '',
      bateria: (json['bateria'] as num?)?.toInt() ?? 0,
      firmware: json['firmware'] as String? ?? '',
      ultimaSync: sync == null ? null : DateTime.tryParse(sync),
    );
  }
}
