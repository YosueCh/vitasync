import '../models/metricas.dart';

/// Entidad de la caché local (equivalente al `@Entity` de Room en la
/// Práctica 4): una fila por lectura de métricas guardada en el teléfono.
class MetricaLocal {
  const MetricaLocal({
    required this.usuarioId,
    required this.metricas,
    required this.capturadaEn,
  });

  final String usuarioId;
  final Metricas metricas;
  final DateTime capturadaEn;

  Map<String, dynamic> toJson() => {
        'usuarioId': usuarioId,
        'pasos': metricas.pasos,
        'calorias': metricas.calorias,
        'suenoHoras': metricas.suenoHoras,
        'frecuenciaCardiaca': metricas.frecuenciaCardiaca,
        'bateria': metricas.bateria,
        'capturadaEn': capturadaEn.millisecondsSinceEpoch,
      };

  factory MetricaLocal.fromJson(Map<String, dynamic> json) {
    return MetricaLocal(
      usuarioId: json['usuarioId'] as String,
      metricas: Metricas(
        pasos: (json['pasos'] as num).toInt(),
        calorias: (json['calorias'] as num).toInt(),
        suenoHoras: (json['suenoHoras'] as num).toDouble(),
        frecuenciaCardiaca: (json['frecuenciaCardiaca'] as num).toInt(),
        bateria: (json['bateria'] as num?)?.toInt() ?? 0,
      ),
      capturadaEn: DateTime.fromMillisecondsSinceEpoch(
        (json['capturadaEn'] as num).toInt(),
      ),
    );
  }
}
