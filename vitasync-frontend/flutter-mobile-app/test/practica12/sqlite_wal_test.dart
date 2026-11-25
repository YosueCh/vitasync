// PRÁCTICA 12 · PER-11 · SQLite local: el modo WAL se activa en el archivo real, no cambia lo guardado y acelera la
// operación crítica (insertar lecturas). Se compara contra el modo anterior abriendo la misma base SIN WAL.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitasync_mobile/data/metrica_dao_sqlite.dart';
import 'package:vitasync_mobile/data/metrica_local.dart';
import 'package:vitasync_mobile/models/metricas.dart';

// ignore: avoid_print
void medida(String clave, Object valor) => print('P12|$clave|$valor');

MetricaLocal _fila(String cuenta, int i) => MetricaLocal(
      usuarioId: cuenta,
      metricas: Metricas(pasos: 1000 + i, calorias: 100 + i % 50, suenoHoras: 7, frecuenciaCardiaca: 60 + i % 40, bateria: 80),
      capturadaEn: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
    );

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('p12wal'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('el archivo queda en modo WAL con sincronización NORMAL', () async {
    final dao = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: '${tmp.path}/a.db');
    await dao.insertar(_fila('u', 1));
    final db = await databaseFactoryFfi.openDatabase('${tmp.path}/a.db');
    expect((await db.rawQuery('PRAGMA journal_mode')).first.values.first, 'wal');
    await db.close();
    await dao.cerrar();
  });

  test('lo guardado y la retención de 50 filas se comportan igual que antes', () async {
    final dao = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: '${tmp.path}/b.db');
    for (var i = 0; i < 80; i++) {
      await dao.insertar(_fila('u', i));
    }
    final h = await dao.historial('u', limite: 100);
    expect(h.length, MetricaDaoSqlite.maxFilasPorCuenta);
    expect(h.first.metricas.pasos, 1079); // la más reciente
    expect((await dao.ultima('u'))!.metricas.pasos, 1079);
    await dao.eliminarDe('u');
    expect(await dao.historial('u'), isEmpty);
    await dao.cerrar();
  });

  test('la base en memoria (pruebas/web) sigue funcionando: el modo WAL se ignora sin fallar', () async {
    final dao = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: inMemoryDatabasePath);
    await dao.insertar(_fila('u', 1));
    expect((await dao.historial('u')).length, 1);
    await dao.cerrar();
  });

  test('MEDICIÓN en PC: 300 inserciones con WAL frente al modo anterior (diario DELETE + synchronous FULL)', () async {
    // Modo anterior: se abre con el mismo esquema pero se devuelve a DELETE/FULL antes de medir.
    final antes = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: '${tmp.path}/antes.db');
    final dbAntes = await databaseFactoryFfi.openDatabase('${tmp.path}/antes.db');
    await dbAntes.rawQuery('PRAGMA journal_mode=DELETE');
    await dbAntes.execute('PRAGMA synchronous=FULL');
    await dbAntes.close();
    await antes.cerrar();
    final anteriorDao = await MetricaDaoSqlite.abrir(fabrica: _SinWal(), archivo: '${tmp.path}/antes.db');

    final reloj = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      await anteriorDao.insertar(_fila('u', i));
    }
    final msAntes = reloj.elapsedMilliseconds;
    await anteriorDao.cerrar();

    final nuevo = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: '${tmp.path}/despues.db');
    reloj
      ..reset()
      ..start();
    for (var i = 0; i < 300; i++) {
      await nuevo.insertar(_fila('u', i));
    }
    final msDespues = reloj.elapsedMilliseconds;
    await nuevo.cerrar();
    medida('300 inserciones SIN WAL (ms)', msAntes);
    medida('300 inserciones CON WAL (ms)', msDespues);
    expect(msDespues, lessThan(msAntes), reason: 'WAL no debe ser más lento');
  });
}

/// Fábrica que abre la base y deshace la configuración de rendimiento para reproducir el comportamiento anterior.
class _SinWal implements DatabaseFactory {
  final DatabaseFactory _f = databaseFactoryFfi;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) async {
    final db = await _f.openDatabase(path, options: OpenDatabaseOptions(version: options?.version, onCreate: options?.onCreate, onUpgrade: options?.onUpgrade));
    return db; // sin onConfigure: queda en el modo por omisión que dejó el archivo (DELETE/FULL)
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Function.apply((_f as dynamic).noSuchMethod, [invocation]);
}
