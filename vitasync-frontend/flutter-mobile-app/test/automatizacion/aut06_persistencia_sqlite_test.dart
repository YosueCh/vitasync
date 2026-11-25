// PRÁCTICAS 13 y 14 · AUT-06 · Pruebas de PERSISTENCIA: la caché local de métricas en SQLite REAL (archivo en disco, no memoria):
// lo guardado sobrevive al cerrar y reabrir la base, se conservan solo las 50 lecturas más recientes por cuenta, las cuentas no se
// mezclan, y el SQL está parametrizado.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitasync_mobile/data/metrica_dao_sqlite.dart';
import 'package:vitasync_mobile/data/metrica_local.dart';
import 'package:vitasync_mobile/models/metricas.dart';

MetricaLocal _fila(String cuenta, int i, {int bateria = 80}) => MetricaLocal(
      usuarioId: cuenta,
      metricas: Metricas(pasos: 1000 + i, calorias: 100 + i % 50, suenoHoras: 7.5, frecuenciaCardiaca: 60 + i % 40, bateria: bateria),
      capturadaEn: DateTime.fromMillisecondsSinceEpoch(1700000000000 + i * 60000),
    );

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  late String archivo;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('aut06');
    archivo = '${tmp.path}/cache.db';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<MetricaDaoSqlite> abrir() => MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: archivo);

  test('AUT-06 · guardar y leer: todos los campos regresan intactos', () async {
    final dao = await abrir();
    await dao.insertar(_fila('ana', 7, bateria: 55));
    final leida = (await dao.ultima('ana'))!;
    expect(leida.metricas.pasos, 1007);
    expect(leida.metricas.suenoHoras, 7.5);
    expect(leida.metricas.frecuenciaCardiaca, 67);
    expect(leida.metricas.bateria, 55);
    expect(leida.capturadaEn, DateTime.fromMillisecondsSinceEpoch(1700000000000 + 7 * 60000));
    await dao.cerrar();
  });

  test('AUT-06 · lo guardado SOBREVIVE al cerrar y volver a abrir la base (persistencia real)', () async {
    var dao = await abrir();
    for (var i = 0; i < 5; i++) {
      await dao.insertar(_fila('ana', i));
    }
    await dao.cerrar();

    dao = await abrir();
    final h = await dao.historial('ana', limite: 10);
    expect(h.length, 5);
    expect(h.first.metricas.pasos, 1004, reason: 'la más reciente primero');
    await dao.cerrar();
  });

  test('AUT-06 · retención: solo las 50 lecturas más recientes de cada cuenta', () async {
    final dao = await abrir();
    for (var i = 0; i < 70; i++) {
      await dao.insertar(_fila('ana', i));
    }
    final h = await dao.historial('ana', limite: 100);
    expect(h.length, MetricaDaoSqlite.maxFilasPorCuenta);
    expect(h.first.metricas.pasos, 1069);
    expect(h.last.metricas.pasos, 1020, reason: 'las 20 más viejas se descartaron');
    await dao.cerrar();
  });

  test('AUT-06 · las cuentas no se mezclan y eliminar una no toca a la otra', () async {
    final dao = await abrir();
    await dao.insertar(_fila('ana', 1));
    await dao.insertar(_fila('beto', 2));
    expect((await dao.historial('ana')).single.metricas.pasos, 1001);
    await dao.eliminarDe('ana');
    expect(await dao.historial('ana'), isEmpty);
    expect((await dao.historial('beto')).single.metricas.pasos, 1002);
    await dao.cerrar();
  });

  test('AUT-06 · cuenta sin lecturas → null / lista vacía (no excepción)', () async {
    final dao = await abrir();
    expect(await dao.ultima('nadie'), isNull);
    expect(await dao.historial('nadie'), isEmpty);
    await dao.cerrar();
  });

  test('AUT-06 · SQL parametrizado: un identificador con comillas no inyecta SQL ni borra datos', () async {
    final dao = await abrir();
    await dao.insertar(_fila('ana', 1));
    expect(await dao.historial("x' OR '1'='1"), isEmpty);
    await dao.eliminarDe("x'; DROP TABLE metricas; --");
    expect((await dao.historial('ana')).length, 1, reason: 'la tabla sigue intacta');
    await dao.insertar(_fila("o'brien", 3)); // un id con comilla también se guarda y se lee bien
    expect((await dao.ultima("o'brien"))!.metricas.pasos, 1003);
    await dao.cerrar();
  });

  test('AUT-06 · la base se abre en modo WAL (optimización de la Práctica 12) y el archivo existe', () async {
    final dao = await abrir();
    await dao.insertar(_fila('ana', 1));
    final db = await databaseFactoryFfi.openDatabase(archivo);
    expect((await db.rawQuery('PRAGMA journal_mode')).first.values.first, 'wal');
    await db.close();
    await dao.cerrar();
    expect(File(archivo).existsSync(), isTrue);
  });
}
