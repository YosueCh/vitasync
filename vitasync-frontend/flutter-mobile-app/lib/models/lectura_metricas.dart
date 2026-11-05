import 'metricas.dart';

/// Una lectura de métricas con su origen: cuándo se capturó y si viene del
/// servidor o de la caché local (cuando no hay conexión).
class LecturaMetricas {
  const LecturaMetricas({
    required this.metricas,
    this.capturadaEn,
    this.sinConexion = false,
  });

  final Metricas metricas;
  final DateTime? capturadaEn;

  /// true cuando el servidor no respondió y se muestra la última lectura guardada.
  final bool sinConexion;

  LecturaMetricas comoSinConexion() => LecturaMetricas(
        metricas: metricas,
        capturadaEn: capturadaEn,
        sinConexion: true,
      );
}
