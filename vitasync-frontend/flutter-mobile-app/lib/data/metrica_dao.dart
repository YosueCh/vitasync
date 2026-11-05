import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'metrica_local.dart';

/// Acceso a la caché local de métricas (equivalente al `@Dao` de Room en la
/// Práctica 4). La app depende de este contrato, no del almacenamiento: hay dos
/// implementaciones, SQLite real en Android/iOS (`MetricaDaoSqlite`) y
/// `shared_preferences` en web (`MetricaDaoPrefs`); la elige `abrirDaoLocal()`.
abstract interface class MetricaDao {
  Future<void> insertar(MetricaLocal fila);

  /// Última lectura guardada de la cuenta, o null si nunca se guardó una.
  Future<MetricaLocal?> ultima(String usuarioId);

  /// Lecturas de la cuenta, de la más reciente a la más antigua.
  Future<List<MetricaLocal>> historial(String usuarioId, {int limite = 20});

  Future<void> eliminarDe(String usuarioId);
}

/// Implementación sobre `shared_preferences` (en web usa el `localStorage`
/// del navegador). El esquema lleva número de versión y se migra al abrir,
/// igual que la migración 1→2 de Room en la Práctica 4.
class MetricaDaoPrefs implements MetricaDao {
  MetricaDaoPrefs(this._prefs);

  static const versionEsquema = 2;
  static const _clave = 'vitasync_metricas';
  static const maxFilasPorCuenta = 50;

  final SharedPreferences _prefs;

  static Future<MetricaDaoPrefs> abrir() async =>
      MetricaDaoPrefs(await SharedPreferences.getInstance());

  @override
  Future<void> insertar(MetricaLocal fila) async {
    final todas = _leer();
    todas.add(fila);
    // Solo se conservan las lecturas más recientes de cada cuenta.
    final deCuenta = todas.where((f) => f.usuarioId == fila.usuarioId).toList()
      ..sort((a, b) => b.capturadaEn.compareTo(a.capturadaEn));
    final sobrantes = deCuenta.skip(maxFilasPorCuenta).toSet();
    todas.removeWhere(sobrantes.contains);
    await _guardar(todas);
  }

  @override
  Future<MetricaLocal?> ultima(String usuarioId) async {
    final lista = await historial(usuarioId, limite: 1);
    return lista.isEmpty ? null : lista.first;
  }

  @override
  Future<List<MetricaLocal>> historial(String usuarioId, {int limite = 20}) async {
    final filas = _leer().where((f) => f.usuarioId == usuarioId).toList()
      ..sort((a, b) => b.capturadaEn.compareTo(a.capturadaEn));
    return filas.take(limite).toList();
  }

  @override
  Future<void> eliminarDe(String usuarioId) async {
    await _guardar(_leer().where((f) => f.usuarioId != usuarioId).toList());
  }

  List<MetricaLocal> _leer() {
    final texto = _prefs.getString(_clave);
    if (texto == null) return [];
    try {
      final json = jsonDecode(texto) as Map<String, dynamic>;
      final filas = migrar(
        (json['filas'] as List<dynamic>).cast<Map<String, dynamic>>(),
        desde: (json['version'] as num?)?.toInt() ?? 1,
      );
      return filas.map(MetricaLocal.fromJson).toList();
    } on Object {
      // Datos dañados: se descartan en vez de romper la app.
      return [];
    }
  }

  Future<void> _guardar(List<MetricaLocal> filas) async {
    await _prefs.setString(
      _clave,
      jsonEncode({
        'version': versionEsquema,
        'filas': filas.map((f) => f.toJson()).toList(),
      }),
    );
  }

  /// Lleva las filas de una versión antigua del esquema a la actual.
  /// v1 no guardaba la batería (se agregó en la v2, como la columna `correo`
  /// del Caso 4 de la Práctica 4); las filas viejas quedan con 0.
  static List<Map<String, dynamic>> migrar(
    List<Map<String, dynamic>> filas, {
    required int desde,
  }) {
    if (desde >= versionEsquema) return filas;
    return [
      for (final fila in filas) {...fila, 'bateria': fila['bateria'] ?? 0},
    ];
  }
}
