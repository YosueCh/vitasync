import '../models/dispositivo.dart';
import '../models/estado_dispositivo.dart';
import '../models/lectura_metricas.dart';
import '../models/metricas.dart';
import 'api_cliente.dart';

/// Contrato de acceso a los datos de salud de una cuenta.
abstract interface class SaludRepository {
  /// null = la cuenta todavía no tiene ninguna lectura (el servidor responde 204). Nunca se inventan datos.
  Future<LecturaMetricas?> obtenerMetricas();

  Future<EstadoDispositivo> obtenerEstado();

  /// Lecturas guardadas en la base de datos, de la más reciente a la más
  /// antigua. Es lo que se ve al tocar una card del Resumen.
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30});
}

/// Implementación real: consume `GET /api/smartwatch/metrics` y
/// `GET /api/smartwatch/status` del backend, filtrando por cuenta.
class HttpSaludRepository implements SaludRepository {
  HttpSaludRepository({required this.usuarioId, ApiCliente? api})
      : _api = api ?? ApiCliente();

  final String usuarioId;
  final ApiCliente _api;

  @override
  Future<LecturaMetricas?> obtenerMetricas() async {
    final respuesta = await _api.get('/smartwatch/metrics', {'usuarioId': usuarioId});
    if (respuesta == null) return null; // 204: aún no hay lecturas
    final json = respuesta as Map<String, dynamic>;
    return LecturaMetricas(
      metricas: Metricas.fromJson(json),
      capturadaEn: _fecha(json['timestamp']),
    );
  }

  @override
  Future<EstadoDispositivo> obtenerEstado() async {
    final json = await _api.get('/smartwatch/status', {'usuarioId': usuarioId})
        as Map<String, dynamic>;
    return EstadoDispositivo.fromJson(json);
  }

  /// `GET /api/smartwatch/historial`: lecturas guardadas en Firestore.
  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async {
    final lista = await _api.get(
      '/smartwatch/historial',
      {'usuarioId': usuarioId, 'limite': '$limite'},
    ) as List<dynamic>;
    return lista.cast<Map<String, dynamic>>().map((json) {
      return LecturaMetricas(
        metricas: Metricas.fromJson(json),
        capturadaEn: _fecha(json['timestamp']),
      );
    }).toList();
  }

  /// Jackson serializa un `Instant` como texto ISO-8601 o como segundos
  /// desde 1970, según la configuración; se aceptan ambos.
  static DateTime? _fecha(Object? valor) {
    if (valor is String) return DateTime.tryParse(valor);
    if (valor is num) {
      return DateTime.fromMillisecondsSinceEpoch((valor * 1000).round());
    }
    return null;
  }
}

/// Datos de ejemplo para pruebas y para diseñar sin backend.
class MuestraSaludRepository implements SaludRepository {
  const MuestraSaludRepository();

  @override
  Future<LecturaMetricas> obtenerMetricas() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return LecturaMetricas(
      metricas: const Metricas(
        pasos: 6320,
        calorias: 412,
        suenoHoras: 7.2,
        frecuenciaCardiaca: 78,
        bateria: 87,
      ),
      capturadaEn: DateTime.now(),
    );
  }

  @override
  Future<EstadoDispositivo> obtenerEstado() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return EstadoDispositivo(
      estado: 'CONECTADO',
      mensaje: 'Dispositivo activo',
      dispositivo: Dispositivo(
        id: 'muestra',
        nombre: 'VitaWatch',
        modelo: 'Wear OS',
        bateria: 87,
        firmware: '1.0.0',
        ultimaSync: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    );
  }

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async {
    final ahora = DateTime.now();
    // Doce lecturas de ejemplo, una cada 30 min, de la más reciente a la más antigua.
    return [
      for (var i = 0; i < 12 && i < limite; i++)
        LecturaMetricas(
          metricas: Metricas(
            pasos: 6320 - i * 480,
            calorias: 412 - i * 25,
            suenoHoras: 7.2 - (i % 3) * 0.4,
            frecuenciaCardiaca: 78 - (i % 4) * 3,
            bateria: 87 - i,
          ),
          capturadaEn: ahora.subtract(Duration(minutes: 30 * i)),
        ),
    ];
  }
}
