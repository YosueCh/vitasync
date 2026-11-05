import '../data/metrica_dao.dart';
import '../data/metrica_local.dart';
import '../models/estado_dispositivo.dart';
import '../models/lectura_metricas.dart';
import 'salud_repository.dart';

/// Envuelve un [SaludRepository] con la caché local (Práctica 4): cada
/// lectura exitosa se guarda en el teléfono y, si el servidor no responde,
/// se devuelve la última guardada marcada como "sin conexión".
class CacheSaludRepository implements SaludRepository {
  CacheSaludRepository({
    required this.usuarioId,
    required SaludRepository remoto,
    required MetricaDao dao,
  })  : _remoto = remoto,
        _dao = dao;

  final String usuarioId;
  final SaludRepository _remoto;
  final MetricaDao _dao;

  @override
  Future<LecturaMetricas?> obtenerMetricas() async {
    try {
      final lectura = await _remoto.obtenerMetricas();
      // Sin lecturas (null) no se guarda NADA en la caché: no hay datos que conservar (D-05).
      if (lectura != null) await _guardar(lectura);
      return lectura;
    } on Exception {
      final guardada = await _dao.ultima(usuarioId);
      if (guardada == null) rethrow;
      return LecturaMetricas(
        metricas: guardada.metricas,
        capturadaEn: guardada.capturadaEn,
        sinConexion: true,
      );
    }
  }

  @override
  Future<EstadoDispositivo> obtenerEstado() => _remoto.obtenerEstado();

  /// Historial de la base de datos del servidor. Sin conexión se muestra el
  /// que quedó guardado en el teléfono (caché local), marcado como tal.
  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async {
    try {
      return await _remoto.obtenerHistorial(limite: limite);
    } on Exception {
      final guardadas = await _dao.historial(usuarioId, limite: limite);
      if (guardadas.isEmpty) rethrow;
      return [
        for (final fila in guardadas)
          LecturaMetricas(
            metricas: fila.metricas,
            capturadaEn: fila.capturadaEn,
            sinConexion: true,
          ),
      ];
    }
  }

  Future<void> _guardar(LecturaMetricas lectura) async {
    final anterior = await _dao.ultima(usuarioId);
    // El sondeo repite lecturas iguales cada 3 s; solo se guardan los cambios.
    if (anterior != null && _iguales(anterior, lectura)) return;
    await _dao.insertar(MetricaLocal(
      usuarioId: usuarioId,
      metricas: lectura.metricas,
      capturadaEn: lectura.capturadaEn ?? DateTime.now(),
    ));
  }

  static bool _iguales(MetricaLocal fila, LecturaMetricas lectura) {
    final a = fila.metricas;
    final b = lectura.metricas;
    return a.pasos == b.pasos &&
        a.calorias == b.calorias &&
        a.suenoHoras == b.suenoHoras &&
        a.frecuenciaCardiaca == b.frecuenciaCardiaca &&
        a.bateria == b.bateria;
  }
}
