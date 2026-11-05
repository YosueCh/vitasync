import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as ruta;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitasync_mobile/data/metrica_dao_sqlite.dart';
import 'package:vitasync_mobile/data/metrica_local.dart';
import 'package:vitasync_mobile/models/estado_dispositivo.dart';
import 'package:vitasync_mobile/models/lectura_metricas.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/cache_salud_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';

/// Práctica 4 con SQLite REAL: el mismo contrato que la caché anterior, ahora sobre una base de datos de verdad
/// (aquí con el SQLite de escritorio de `sqflite_common_ffi`; en el teléfono es el SQLite de Android).

MetricaLocal _fila(String usuario, int pasos, {int segundos = 0, int bateria = 80}) => MetricaLocal(
      usuarioId: usuario,
      metricas: Metricas(pasos: pasos, calorias: 100, suenoHoras: 7.5, frecuenciaCardiaca: 70, bateria: bateria),
      capturadaEn: DateTime.utc(2026, 11, 4, 12, 0, segundos),
    );

void main() {
  setUpAll(sqfliteFfiInit);

  Future<MetricaDaoSqlite> enMemoria() =>
      MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: inMemoryDatabasePath);

  group('MetricaDaoSqlite (contrato del DAO)', () {
    late MetricaDaoSqlite dao;

    setUp(() async => dao = await enMemoria());
    tearDown(() => dao.cerrar());

    test('insertar y consultar la última lectura', () async {
      expect(await dao.ultima('u1'), isNull);

      await dao.insertar(_fila('u1', 1000));

      final u = (await dao.ultima('u1'))!;
      expect(u.metricas.pasos, 1000);
      expect(u.metricas.suenoHoras, 7.5);
      expect(u.metricas.bateria, 80);
      // el mismo instante (se guarda en milisegundos; al leerla Dart la entrega en hora local)
      expect(u.capturadaEn.isAtSameMomentAs(DateTime.utc(2026, 11, 4, 12)), isTrue);
    });

    test('el historial va de la más reciente a la más antigua y respeta el límite', () async {
      for (var i = 0; i < 5; i++) {
        await dao.insertar(_fila('u1', i * 100, segundos: i));
      }

      expect((await dao.historial('u1')).map((f) => f.metricas.pasos), [400, 300, 200, 100, 0]);
      expect((await dao.historial('u1', limite: 2)).map((f) => f.metricas.pasos), [400, 300]);
    });

    test('con la misma hora gana la que se guardó después (orden estable)', () async {
      await dao.insertar(_fila('u1', 1));
      await dao.insertar(_fila('u1', 2));

      expect((await dao.ultima('u1'))!.metricas.pasos, 2);
    });

    test('cada cuenta ve solo sus lecturas', () async {
      await dao.insertar(_fila('u1', 111));
      await dao.insertar(_fila('u2', 222));

      expect((await dao.historial('u1')).map((f) => f.metricas.pasos), [111]);
      expect((await dao.historial('u2')).map((f) => f.metricas.pasos), [222]);
    });

    test('eliminarDe borra solo las lecturas de esa cuenta', () async {
      await dao.insertar(_fila('u1', 111));
      await dao.insertar(_fila('u2', 222));

      await dao.eliminarDe('u1');

      expect(await dao.historial('u1'), isEmpty);
      expect(await dao.historial('u2'), hasLength(1));
    });

    test('solo se conservan las ${MetricaDaoSqlite.maxFilasPorCuenta} más recientes de cada cuenta', () async {
      await dao.insertar(_fila('u2', 7)); // otra cuenta: no debe verse afectada por el recorte
      for (var i = 0; i < MetricaDaoSqlite.maxFilasPorCuenta + 5; i++) {
        await dao.insertar(_fila('u1', i, segundos: i % 60));
      }

      final h = await dao.historial('u1', limite: 1000);
      expect(h, hasLength(MetricaDaoSqlite.maxFilasPorCuenta));
      expect(h.first.metricas.pasos, MetricaDaoSqlite.maxFilasPorCuenta + 4);
      expect(await dao.historial('u2'), hasLength(1));
    });

    test('un id de cuenta con comillas e instrucciones SQL no rompe nada ni filtra datos (consultas parametrizadas)', () async {
      await dao.insertar(_fila('u1', 123));
      const malicioso = "x' OR '1'='1'; DROP TABLE metricas; --";

      expect(await dao.historial(malicioso), isEmpty, reason: 'no devuelve las filas de otras cuentas');
      await dao.insertar(_fila(malicioso, 5));
      await dao.eliminarDe(malicioso);

      expect(await dao.historial('u1'), hasLength(1), reason: 'la tabla sigue existiendo y sin cambios');
    });
  });

  group('MetricaDaoSqlite (archivo en disco)', () {
    late Directory carpeta;

    setUp(() => carpeta = Directory.systemTemp.createTempSync('vitasync_sqlite_'));
    tearDown(() async {
      try {
        carpeta.deleteSync(recursive: true);
      } on FileSystemException {
        // en Windows el archivo puede tardar en liberarse; es temporal y no afecta la prueba
      }
    });

    test('los datos persisten al cerrar y volver a abrir la base', () async {
      final archivo = ruta.join(carpeta.path, 'cache.db');
      final primera = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: archivo);
      await primera.insertar(_fila('u1', 4321));
      await primera.cerrar();

      final segunda = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: archivo);
      expect((await segunda.ultima('u1'))!.metricas.pasos, 4321);
      await segunda.cerrar();
    });

    test('migración 1→2: una base antigua sin batería se actualiza sin perder filas', () async {
      final archivo = ruta.join(carpeta.path, 'vieja.db');
      // Se crea una base como la dejaba la versión 1: sin la columna «bateria».
      final vieja = await databaseFactoryFfi.openDatabase(
        archivo,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE metricas (
                id INTEGER PRIMARY KEY AUTOINCREMENT, usuario_id TEXT NOT NULL, pasos INTEGER NOT NULL,
                calorias INTEGER NOT NULL, sueno_horas REAL NOT NULL, frecuencia_cardiaca INTEGER NOT NULL,
                capturada_en INTEGER NOT NULL)''');
            await db.insert('metricas', {
              'usuario_id': 'u1', 'pasos': 999, 'calorias': 50, 'sueno_horas': 6.0,
              'frecuencia_cardiaca': 66, 'capturada_en': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
            });
          },
        ),
      );
      await vieja.close();

      final dao = await MetricaDaoSqlite.abrir(fabrica: databaseFactoryFfi, archivo: archivo);
      final u = (await dao.ultima('u1'))!;
      expect(u.metricas.pasos, 999, reason: 'la fila vieja se conservó');
      expect(u.metricas.bateria, 0, reason: 'la columna nueva quedó en 0');

      await dao.insertar(_fila('u1', 1000, bateria: 55)); // y ya se puede guardar con batería
      expect((await dao.ultima('u1'))!.metricas.bateria, 55);
      await dao.cerrar();
    });
  });

  group('CacheSaludRepository sobre SQLite', () {
    late MetricaDaoSqlite dao;
    setUp(() async => dao = await enMemoria());
    tearDown(() => dao.cerrar());

    test('guarda lo que entrega el servidor y, sin conexión, devuelve lo guardado marcado como caché', () async {
      final remoto = _Remoto([
        const LecturaMetricas(
          metricas: Metricas(pasos: 5000, calorias: 200, suenoHoras: 7.0, frecuenciaCardiaca: 68, bateria: 90),
        ),
      ]);
      final cache = CacheSaludRepository(usuarioId: 'u1', remoto: remoto, dao: dao);

      final enLinea = (await cache.obtenerMetricas())!;
      expect(enLinea.sinConexion, isFalse);

      final sinRed = (await cache.obtenerMetricas())!; // el servidor ya no responde
      expect(sinRed.sinConexion, isTrue);
      expect(sinRed.metricas.pasos, 5000);
    });

    test('una cuenta sin lecturas no guarda NADA en SQLite (D-05)', () async {
      final cache = CacheSaludRepository(usuarioId: 'u1', remoto: _Remoto(null), dao: dao);

      expect(await cache.obtenerMetricas(), isNull);
      expect(await dao.historial('u1'), isEmpty);
    });
  });
}

/// Remoto de prueba: entrega las lecturas en orden y después falla (servidor caído). Con `null`: sin lecturas.
class _Remoto implements SaludRepository {
  _Remoto(List<LecturaMetricas>? lecturas) : _lecturas = lecturas;

  final List<LecturaMetricas>? _lecturas;
  int _n = 0;

  @override
  Future<LecturaMetricas?> obtenerMetricas() async {
    final l = _lecturas;
    if (l == null) return null;
    if (_n >= l.length) throw const ApiException('No se pudo conectar al servidor', sinConexion: true);
    return l[_n++];
  }

  @override
  Future<EstadoDispositivo> obtenerEstado() => throw UnimplementedError();

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async => [];
}
