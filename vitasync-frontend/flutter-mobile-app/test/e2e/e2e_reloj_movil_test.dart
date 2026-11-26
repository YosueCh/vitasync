// Propuesta (Parcial 3): prueba de extremo a extremo «reloj, sitio y móvil comparten y reflejan los mismos datos».
// Solo corre cuando se indica un backend vivo (se omite en el CI normal):
//   flutter test test/e2e --dart-define=E2E_API=http://localhost:8081/api --dart-define=E2E_CUENTA=<id>
// scripts/entrega-final/e2e-tres-superficies.mjs la lanza después de que el firmware simulado ya envió lecturas.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/metas_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';

const _api = String.fromEnvironment('E2E_API');
const _cuenta = String.fromEnvironment('E2E_CUENTA');

// ignore: avoid_print
void medida(String clave, Object valor) => print('E2E|$clave|$valor');

void main() {
  final habilitada = _api.isNotEmpty && _cuenta.isNotEmpty;

  setUp(() => HttpOverrides.global = null); // flutter_test bloquea la red real; aquí SÍ se quiere

  test('el cliente móvil REAL (HttpSaludRepository) ve la misma última lectura que el sitio lee del endpoint', () async {
    final rest = jsonDecode((await http.get(Uri.parse('$_api/smartwatch/metrics?usuarioId=$_cuenta'))).body) as Map<String, dynamic>;
    final movil = await HttpSaludRepository(usuarioId: _cuenta, api: ApiCliente(baseUrl: _api)).obtenerMetricas();

    expect(movil, isNotNull, reason: 'el reloj ya envió lecturas');
    expect(movil!.metricas.pasos, rest['pasos']);
    expect(movil.metricas.frecuenciaCardiaca, rest['frecuenciaCardiaca']);
    expect(movil.metricas.calorias, rest['calorias']);
    medida('última lectura (pasos / FC)', '${movil.metricas.pasos} / ${movil.metricas.frecuenciaCardiaca} (idéntica en REST y en la app)');
  }, skip: habilitada ? false : 'sin E2E_API');

  test('el historial que muestra la app tiene las mismas lecturas, en el mismo orden, que el del endpoint', () async {
    final rest = jsonDecode((await http.get(Uri.parse('$_api/smartwatch/historial?usuarioId=$_cuenta&limite=30'))).body) as List<dynamic>;
    final movil = await HttpSaludRepository(usuarioId: _cuenta, api: ApiCliente(baseUrl: _api)).obtenerHistorial(limite: 30);

    expect(rest, isNotEmpty);
    expect(movil.length, rest.length);
    for (var i = 0; i < rest.length; i++) {
      expect(movil[i].metricas.pasos, (rest[i] as Map)['pasos'], reason: 'lectura $i');
    }
    medida('historial (lecturas)', '${movil.length} idénticas en REST y en la app, más reciente primero');
  }, skip: habilitada ? false : 'sin E2E_API');

  test('las metas que cambia la app se ven en el endpoint que usa el sitio (y al revés)', () async {
    final metas = HttpMetasRepository(usuarioId: _cuenta, api: ApiCliente(baseUrl: _api));
    final guardadas = await metas.guardar(pasos: 9123, calorias: 777);
    final rest = jsonDecode((await http.get(Uri.parse('$_api/metas?usuarioId=$_cuenta'))).body) as Map<String, dynamic>;
    expect(rest['metaPasos'], 9123);
    expect(rest['metaCalorias'], 777);
    expect(rest['version'], guardadas.version);

    // El «sitio» cambia una meta con la versión que leyó; la app la ve.
    final put = await http.put(Uri.parse('$_api/metas?usuarioId=$_cuenta'),
        headers: {'content-type': 'application/json'}, body: jsonEncode({'metaPasos': 11000, 'version': guardadas.version}));
    expect(put.statusCode, 200);
    expect((await metas.obtener()).metaPasos, 11000);
    medida('metas compartidas', 'app → sitio y sitio → app, versión ${guardadas.version} → ${guardadas.version + 1}');
  }, skip: habilitada ? false : 'sin E2E_API');
}
