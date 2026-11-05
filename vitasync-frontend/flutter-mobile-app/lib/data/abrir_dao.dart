import 'package:flutter/foundation.dart' show kIsWeb;

import 'metrica_dao.dart';
import 'metrica_dao_sqlite.dart';

/// Elige dónde se guarda la caché de métricas según la plataforma:
/// - Android / iOS: SQLite real ([MetricaDaoSqlite]).
/// - Web (la PWA): SQLite no existe en el navegador, así que se usa el `localStorage` ([MetricaDaoPrefs]).
/// Ambos cumplen el mismo contrato [MetricaDao]; el resto de la app no sabe cuál está usando.
Future<MetricaDao> abrirDaoLocal() async {
  if (kIsWeb) return MetricaDaoPrefs.abrir();
  return MetricaDaoSqlite.abrir();
}
