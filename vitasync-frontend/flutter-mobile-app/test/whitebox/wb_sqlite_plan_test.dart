// PRÁCTICA 11 · Fase 4 · Base de datos LOCAL de la app (SQLite): plan de ejecución y tiempos de consulta.
//
// SQLite sí ofrece EXPLAIN QUERY PLAN (Firestore no). Se abre la base de datos REAL de la app (esquema creado por
// MetricaDaoSqlite: tabla «metricas» e índice «idx_metricas_cuenta_fecha») en un archivo temporal, se llena con 20 cuentas
// x 50 lecturas y se pide el plan de cada consulta que el DAO ejecuta. Imprime líneas «WB|clave|valor» como evidencia.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as ruta;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitasync_mobile/data/metrica_dao_sqlite.dart';
import 'package:vitasync_mobile/data/metrica_local.dart';
import 'package:vitasync_mobile/models/metricas.dart';

// ignore: avoid_print
void wb(String clave, Object valor) => print('WB|$clave|$valor');

String estadisticas(List<double> ms) {
  final o = [...ms]..sort();
  final media = ms.reduce((a, b) => a + b) / ms.length;
  final varianza = ms.map((v) => (v - media) * (v - media)).reduce((a, b) => a + b) / ms.length;
  final p95 = o[math.min(o.length - 1, (0.95 * o.length).ceil() - 1)];
  return 'n=${ms.length} min=${o.first.toStringAsFixed(3)} media=${media.toStringAsFixed(3)} '
      'max=${o.last.toStringAsFixed(3)} p95=${p95.toStringAsFixed(3)} desv=${math.sqrt(varianza).toStringAsFixed(3)}';
}

Future<List<double>> medir(int n, Future<void> Function() operacion) async {
  final r = <double>[];
  for (var i = 0; i < n; i++) {
    final reloj = Stopwatch()..start();
    await operacion();
    r.add(reloj.elapsedMicroseconds / 1000);
  }
  return r;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late String archivo;
  late MetricaDaoSqlite dao;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vitasync_wb_');
    archivo = ruta.join(dir.path, 'metricas.db');
    dao = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: archivo);
    for (var u = 0; u < 20; u++) {
      for (var i = 0; i < 50; i++) {
        await dao.insertar(MetricaLocal(
          usuarioId: 'u$u',
          metricas: Metricas(pasos: 100 * i, calorias: 10 * i, suenoHoras: 7.0, frecuenciaCardiaca: 70, bateria: 80),
          capturadaEn: DateTime.utc(2026, 11, 4, 12, 0, i),
        ));
      }
    }
  });

  tearDown(() async {
    await dao.cerrar();
    await dir.delete(recursive: true);
  });

  Future<String> plan(String sql, List<Object?> args) async {
    final db = await databaseFactoryFfi.openDatabase(archivo, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try {
      final filas = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      return filas.map((f) => f['detail']).join(' ; ');
    } finally {
      await db.close();
    }
  }

  test('DB-02/03: la tabla respeta NOT NULL y la retención de 50 lecturas por cuenta', () async {
    final db = await databaseFactoryFfi.openDatabase(archivo, options: OpenDatabaseOptions(singleInstance: false));
    final total = (await db.rawQuery('SELECT COUNT(*) AS n FROM metricas')).first['n']! as int;
    final porCuenta = (await db.rawQuery('SELECT COUNT(*) AS n FROM metricas WHERE usuario_id = ?', ['u0'])).first['n']! as int;
    wb('SQLITE filas totales / por cuenta', '$total / $porCuenta');
    expect(porCuenta, 50);
    expect(total, 1000);
    // NOT NULL: insertar una fila sin usuario_id debe ser rechazado por la propia base de datos.
    await expectLater(
      db.insert('metricas', {'pasos': 1, 'calorias': 1, 'sueno_horas': 1.0, 'frecuencia_cardiaca': 1, 'capturada_en': 1}),
      throwsA(isA<DatabaseException>()),
    );
    wb('SQLITE restriccion NOT NULL', 'insertar sin usuario_id → DatabaseException (rechazado por SQLite)');
    // Inyección SQL: el id con comillas se trata como DATO (consulta parametrizada), no como instrucción.
    final lista = await dao.historial("u0' OR '1'='1");
    expect(lista, isEmpty);
    wb('SQLITE inyeccion SQL', "historial(\"u0' OR '1'='1\") → 0 filas (parametrizada)");
    await db.close();
  });

  test('DB-03: plan de ejecución (EXPLAIN QUERY PLAN) de las consultas del DAO', () async {
    final consultas = <String, (String, List<Object?>)>{
      'historial/ultima (WHERE usuario_id ORDER BY capturada_en DESC, id DESC LIMIT)':
          ('SELECT * FROM metricas WHERE usuario_id = ? ORDER BY capturada_en DESC, id DESC LIMIT 20', ['u1']),
      'retencion (subconsulta ORDER BY ... LIMIT 50)':
          ('SELECT id FROM metricas WHERE usuario_id = ? ORDER BY capturada_en DESC, id DESC LIMIT 50', ['u1']),
      'eliminarDe (DELETE WHERE usuario_id)': ('DELETE FROM metricas WHERE usuario_id = ?', ['u1']),
      'CONTRASTE sin indice (WHERE pasos > ?)': ('SELECT * FROM metricas WHERE pasos > ?', [3000]),
    };
    final planes = <String, String>{};
    for (final e in consultas.entries) {
      planes[e.key] = await plan(e.value.$1, e.value.$2);
      wb('PLAN ${e.key}', planes[e.key]!);
    }
    // Las consultas por cuenta usan el índice; la de contraste recorre toda la tabla.
    expect(planes.values.elementAt(0), contains('idx_metricas_cuenta_fecha'));
    expect(planes.values.elementAt(2), contains('idx_metricas_cuenta_fecha'));
    expect(planes.values.elementAt(3), contains('SCAN'));
    wb('PLAN hallazgo ORDER BY id DESC',
        planes.values.elementAt(0).contains('TEMP B-TREE')
            ? 'el índice (usuario_id, capturada_en DESC) no cubre «id DESC»: SQLite ordena el último término con un árbol temporal'
            : 'el orden lo cubre el índice');
  });

  test('DB-03/04: tiempos de consulta (ms) con 1000 filas', () async {
    wb('SQLITE Q1 historial(limite 20)', estadisticas(await medir(50, () => dao.historial('u1', limite: 20))));
    wb('SQLITE Q2 ultima', estadisticas(await medir(50, () => dao.ultima('u1'))));
    var n = 0;
    wb('SQLITE Q3 insertar (transaccion: insert + retención)', estadisticas(await medir(50, () async {
      n++;
      await dao.insertar(MetricaLocal(
        usuarioId: 'u2',
        metricas: const Metricas(pasos: 1, calorias: 1, suenoHoras: 7, frecuenciaCardiaca: 70, bateria: 80),
        capturadaEn: DateTime.utc(2026, 11, 5, 12, 0, n),
      ));
    })));
    wb('SQLITE Q4 eliminarDe', estadisticas(await medir(1, () => dao.eliminarDe('u3'))));
    final db = await databaseFactoryFfi.openDatabase(archivo, options: OpenDatabaseOptions(singleInstance: false));
    wb('SQLITE Q5 SIN indice (WHERE pasos > ?)', estadisticas(await medir(50, () async {
      await db.rawQuery('SELECT * FROM metricas WHERE pasos > ?', [3000]);
    })));
    await db.close();
  });
}
