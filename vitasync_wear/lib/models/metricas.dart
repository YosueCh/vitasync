/// Métricas de salud, en el mismo formato que expone
/// `vitasync-backend` en `GET/POST /api/smartwatch/*`
/// (`MetricasDTO.java`). El backend serializa el campo Dart
/// `sueñoHoras` como clave JSON "sueñoHoras" (Java sí permite "ñ" en
/// identificadores); aquí solo es una cadena de texto en el JSON, así
/// que no choca con la restricción de identificadores de Dart.
class Metricas {
  final int pasos;
  final int calorias;
  final double suenoHoras;
  final int frecuenciaCardiaca;
  final int bateria;

  const Metricas({
    required this.pasos,
    required this.calorias,
    required this.suenoHoras,
    required this.frecuenciaCardiaca,
    required this.bateria,
  });

  factory Metricas.fromJson(Map<String, dynamic> json) {
    return Metricas(
      pasos: (json['pasos'] as num?)?.toInt() ?? 0,
      calorias: (json['calorias'] as num?)?.toInt() ?? 0,
      suenoHoras: (json['sueñoHoras'] as num?)?.toDouble() ?? 0.0,
      frecuenciaCardiaca: (json['frecuenciaCardiaca'] as num?)?.toInt() ?? 0,
      bateria: (json['bateria'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'pasos': pasos,
        'calorias': calorias,
        'sueñoHoras': suenoHoras,
        'frecuenciaCardiaca': frecuenciaCardiaca,
        'bateria': bateria,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
}
