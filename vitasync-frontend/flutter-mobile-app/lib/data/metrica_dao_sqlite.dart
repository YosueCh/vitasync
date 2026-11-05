import 'package:path/path.dart' as ruta;
import 'package:sqflite/sqflite.dart';

import '../models/metricas.dart';
import 'metrica_dao.dart';
import 'metrica_local.dart';

/// Caché local de métricas en SQLite REAL (Práctica 4: equivalente a Room). Implementa el mismo contrato
/// [MetricaDao] que la versión anterior con `shared_preferences`, así que nada más de la app cambia.
///
/// Es una CACHÉ, no una segunda fuente de verdad: la única base de datos del sistema es Firestore (en el
/// servidor); aquí solo se guarda lo último que el servidor entregó para poder verlo sin conexión. Si se pierde
/// o se corrompe, se vuelve a llenar sola en la siguiente consulta.
///
/// Esquema (versión 2): tabla `metricas` con índice por cuenta y fecha. La versión 1 no guardaba la batería;
/// al abrir una base antigua `onUpgrade` agrega la columna sin perder las filas (igual que la migración 1→2 de
/// la Práctica 4). Todas las consultas van parametrizadas: ningún dato se concatena en el SQL.
class MetricaDaoSqlite implements MetricaDao {
  MetricaDaoSqlite(this._db);

  static const versionEsquema = 2;
  static const maxFilasPorCuenta = MetricaDaoPrefs.maxFilasPorCuenta;
  static const nombreArchivo = 'vitasync_cache.db';

  final Database _db;

  /// Abre (o crea) la base. En el teléfono, sin argumentos: archivo `vitasync_cache.db` en la carpeta de bases
  /// de datos de la app. En pruebas se pasa una [fabrica] de escritorio y una [archivo] (o la memoria).
  static Future<MetricaDaoSqlite> abrir({DatabaseFactory? fabrica, String? archivo}) async {
    final f = fabrica ?? databaseFactory;
    final destino = archivo ?? ruta.join(await f.getDatabasesPath(), nombreArchivo);
    final db = await f.openDatabase(
      destino,
      options: OpenDatabaseOptions(
        version: versionEsquema,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE metricas (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              usuario_id TEXT NOT NULL,
              pasos INTEGER NOT NULL,
              calorias INTEGER NOT NULL,
              sueno_horas REAL NOT NULL,
              frecuencia_cardiaca INTEGER NOT NULL,
              bateria INTEGER NOT NULL DEFAULT 0,
              capturada_en INTEGER NOT NULL
            )''');
          await db.execute('CREATE INDEX idx_metricas_cuenta_fecha ON metricas (usuario_id, capturada_en DESC)');
        },
        onUpgrade: (db, desde, hasta) async {
          // v1 → v2: se agregó la batería; las filas viejas quedan con 0.
          if (desde < 2) {
            await db.execute('ALTER TABLE metricas ADD COLUMN bateria INTEGER NOT NULL DEFAULT 0');
          }
        },
      ),
    );
    return MetricaDaoSqlite(db);
  }

  Future<void> cerrar() => _db.close();

  @override
  Future<void> insertar(MetricaLocal fila) async {
    await _db.transaction((tx) async {
      await tx.insert('metricas', {
        'usuario_id': fila.usuarioId,
        'pasos': fila.metricas.pasos,
        'calorias': fila.metricas.calorias,
        'sueno_horas': fila.metricas.suenoHoras,
        'frecuencia_cardiaca': fila.metricas.frecuenciaCardiaca,
        'bateria': fila.metricas.bateria,
        'capturada_en': fila.capturadaEn.millisecondsSinceEpoch,
      });
      // Solo se conservan las lecturas más recientes de cada cuenta.
      await tx.rawDelete('''
        DELETE FROM metricas
        WHERE usuario_id = ?
          AND id NOT IN (
            SELECT id FROM metricas WHERE usuario_id = ?
            ORDER BY capturada_en DESC, id DESC LIMIT ?)''',
          [fila.usuarioId, fila.usuarioId, maxFilasPorCuenta]);
    });
  }

  @override
  Future<MetricaLocal?> ultima(String usuarioId) async {
    final lista = await historial(usuarioId, limite: 1);
    return lista.isEmpty ? null : lista.first;
  }

  @override
  Future<List<MetricaLocal>> historial(String usuarioId, {int limite = 20}) async {
    final filas = await _db.query(
      'metricas',
      where: 'usuario_id = ?',
      whereArgs: [usuarioId],
      orderBy: 'capturada_en DESC, id DESC',
      limit: limite,
    );
    return filas.map(_deFila).toList();
  }

  @override
  Future<void> eliminarDe(String usuarioId) async {
    await _db.delete('metricas', where: 'usuario_id = ?', whereArgs: [usuarioId]);
  }

  static MetricaLocal _deFila(Map<String, Object?> f) => MetricaLocal(
        usuarioId: f['usuario_id']! as String,
        metricas: Metricas(
          pasos: (f['pasos']! as num).toInt(),
          calorias: (f['calorias']! as num).toInt(),
          suenoHoras: (f['sueno_horas']! as num).toDouble(),
          frecuenciaCardiaca: (f['frecuencia_cardiaca']! as num).toInt(),
          bateria: (f['bateria'] as num?)?.toInt() ?? 0,
        ),
        capturadaEn: DateTime.fromMillisecondsSinceEpoch((f['capturada_en']! as num).toInt()),
      );
}
