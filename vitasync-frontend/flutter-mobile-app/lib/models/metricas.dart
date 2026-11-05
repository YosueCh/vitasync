/// Métricas de salud, en el formato de `MetricasDTO.java` del backend
/// (`GET /api/smartwatch/metrics`). En el JSON la clave es "sueñoHoras";
/// aquí es solo texto, por lo que no choca con la regla de Dart que no
/// permite "ñ" en identificadores.
class Metricas {
  const Metricas({
    required this.pasos,
    required this.calorias,
    required this.suenoHoras,
    required this.frecuenciaCardiaca,
    required this.bateria,
  });

  final int pasos;
  final int calorias;
  final double suenoHoras;
  final int frecuenciaCardiaca;
  final int bateria;

  factory Metricas.fromJson(Map<String, dynamic> json) {
    return Metricas(
      pasos: (json['pasos'] as num?)?.toInt() ?? 0,
      calorias: (json['calorias'] as num?)?.toInt() ?? 0,
      suenoHoras: (json['sueñoHoras'] as num?)?.toDouble() ?? 0.0,
      frecuenciaCardiaca: (json['frecuenciaCardiaca'] as num?)?.toInt() ?? 0,
      bateria: (json['bateria'] as num?)?.toInt() ?? 0,
    );
  }
}
