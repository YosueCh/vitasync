import '../models/estado_firmware.dart';
import 'api_cliente.dart';

/// Contrato para consultar y pedir la actualización del firmware del reloj.
abstract interface class FirmwareRepository {
  Future<EstadoFirmware> obtenerEstado();

  /// Deja la orden de actualizar; el firmware del dispositivo la recoge y
  /// la aplica (flujo OTA simulado, ver `vitasync-firmware-sim/`).
  Future<EstadoFirmware> solicitarActualizacion();
}

/// Clave que el servidor entrega UNA sola vez al vincular el reloj (Práctica 10). El firmware la manda
/// en la cabecera X-Clave-Dispositivo; el servidor solo guarda su hash.
class ClaveDeReloj {
  const ClaveDeReloj({required this.usuarioId, required this.clave});

  final String usuarioId;
  final String clave;
}

/// Capacidad opcional: vincular el reloj de la cuenta y obtener su clave de dispositivo.
abstract interface class VinculaRelojes {
  /// false cuando el servidor no exige clave de dispositivo: ahí el firmware se conecta solo y vincular
  /// desde la app reiniciaría el reloj sin necesidad.
  bool get puedeVincular;

  Future<ClaveDeReloj?> vincularReloj();
}

class HttpFirmwareRepository implements FirmwareRepository, VinculaRelojes {
  HttpFirmwareRepository({required this.usuarioId, ApiCliente? api, this.puedeVincular = false})
      : _api = api ?? ApiCliente();

  final String usuarioId;

  @override
  final bool puedeVincular;
  final ApiCliente _api;

  @override
  Future<EstadoFirmware> obtenerEstado() async {
    final json = await _api.get('/firmware/estado', {'usuarioId': usuarioId})
        as Map<String, dynamic>;
    return EstadoFirmware.fromJson(json);
  }

  @override
  Future<EstadoFirmware> solicitarActualizacion() async {
    final json = await _api.post('/firmware/solicitar', {'usuarioId': usuarioId})
        as Map<String, dynamic>;
    return EstadoFirmware.fromJson(json);
  }

  /// POST /api/smartwatch/connect: vincula el reloj (cada vez genera una clave nueva e invalida la anterior).
  @override
  Future<ClaveDeReloj?> vincularReloj() async {
    final json = await _api.post('/smartwatch/connect', {'usuarioId': usuarioId}) as Map<String, dynamic>;
    final clave = json['claveDispositivo'];
    return clave is String ? ClaveDeReloj(usuarioId: usuarioId, clave: clave) : null;
  }
}

class MuestraFirmwareRepository implements FirmwareRepository {
  MuestraFirmwareRepository();

  bool _pedida = false;

  EstadoFirmware get _estado => EstadoFirmware(
        versionActual: '1.0.0',
        ultimaVersion: '1.1.0',
        notas: 'Notas de ejemplo',
        hayActualizacion: true,
        ordenPendiente: _pedida,
      );

  @override
  Future<EstadoFirmware> obtenerEstado() async => _estado;

  @override
  Future<EstadoFirmware> solicitarActualizacion() async {
    _pedida = true;
    return _estado;
  }
}
