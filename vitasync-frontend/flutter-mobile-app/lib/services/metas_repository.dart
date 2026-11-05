import '../models/metas_cuenta.dart';
import 'api_cliente.dart';

/// Otra persona (la paciente o su médico) guardó metas desde que estas se leyeron. Trae lo que hay AHORA en el servidor.
class ConflictoDeMetas implements Exception {
  const ConflictoDeMetas(this.actual);

  final MetasCuenta actual;

  @override
  String toString() => 'Otra persona cambió las metas (versión ${actual.version}).';
}

/// Contrato de las metas de una cuenta compartidas entre paciente y médico (Práctica 9 dentro de VitaSync).
abstract interface class MetasRepository {
  Future<MetasCuenta> obtener();

  /// Guarda los campos que no sean null. Con [version] el servidor solo acepta si sigue siendo la vigente; si no,
  /// lanza [ConflictoDeMetas]. Sin [version] se fusiona campo por campo (último en escribir gana en cada campo).
  Future<MetasCuenta> guardar({int? pasos, int? calorias, double? sueno, int? version});
}

/// Implementación real: `GET/PUT /api/metas?usuarioId=`. La verdad vive en Firestore; no hay copia local.
class HttpMetasRepository implements MetasRepository {
  HttpMetasRepository({required this.usuarioId, ApiCliente? api}) : _api = api ?? ApiCliente();

  final String usuarioId;
  final ApiCliente _api;

  @override
  Future<MetasCuenta> obtener() async =>
      MetasCuenta.fromJson(await _api.get('/metas', {'usuarioId': usuarioId}) as Map<String, dynamic>);

  @override
  Future<MetasCuenta> guardar({int? pasos, int? calorias, double? sueno, int? version}) async {
    try {
      final json = await _api.putJson('/metas?usuarioId=${Uri.encodeQueryComponent(usuarioId)}', {
        if (pasos != null) 'metaPasos': pasos,
        if (calorias != null) 'metaCalorias': calorias,
        if (sueno != null) 'metaSueno': sueno,
        if (version != null) 'version': version,
      });
      return MetasCuenta.fromJson(json as Map<String, dynamic>);
    } on ApiException catch (e) {
      final actual = e.datos?['actual'];
      if (e.codigo == 'CONFLICTO_DE_VERSION' && actual is Map<String, dynamic>) {
        throw ConflictoDeMetas(MetasCuenta.fromJson(actual));
      }
      rethrow;
    }
  }
}

/// Memoria compartida del modo `MUESTRA`: la paciente y el médico ven las mismas metas.
class AlmacenMetasMuestra {
  MetasCuenta metas = MetasCuenta.predeterminadas;
}

/// Datos de ejemplo con las mismas reglas del servidor. [quien] es «Paciente» o «Médico».
class MuestraMetasRepository implements MetasRepository {
  MuestraMetasRepository(this._almacen, {this.quien = 'Paciente'});

  final AlmacenMetasMuestra _almacen;
  final String quien;

  @override
  Future<MetasCuenta> obtener() async => _almacen.metas;

  @override
  Future<MetasCuenta> guardar({int? pasos, int? calorias, double? sueno, int? version}) async {
    if (pasos == null && calorias == null && sueno == null) {
      throw const ApiException('Indica al menos una meta para cambiar.');
    }
    final error = (pasos == null ? null : ReglasMetas.validarPasos(pasos)) ??
        (calorias == null ? null : ReglasMetas.validarCalorias(calorias)) ??
        (sueno == null ? null : ReglasMetas.validarSueno(sueno));
    if (error != null) throw ApiException(error);
    final actual = _almacen.metas;
    if (version != null && version != actual.version) throw ConflictoDeMetas(actual);
    return _almacen.metas = MetasCuenta(
      metaPasos: pasos ?? actual.metaPasos,
      metaCalorias: calorias ?? actual.metaCalorias,
      metaSueno: sueno ?? actual.metaSueno,
      version: actual.version + 1,
      actualizadaPor: quien,
    );
  }
}
