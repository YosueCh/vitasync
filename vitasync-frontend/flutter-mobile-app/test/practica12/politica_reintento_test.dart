// PRÁCTICA 12 · Fase 5 (reto) · Reintento con espera progresiva: la política en sí y su integración en ApiCliente.
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/politica_reintento.dart';

http.Response _ok() => http.Response('{"ok":true}', 200, headers: {'content-type': 'application/json'});

void main() {
  group('PoliticaReintento.espera', () {
    const sinAzar = PoliticaReintento(maxReintentos: 5, jitter: 0);

    test('la espera crece al doble en cada reintento: 300, 600, 1200 ms', () {
      expect([0, 1, 2].map((i) => sinAzar.espera(i).inMilliseconds), [300, 600, 1200]);
    });

    test('nunca pasa del tope (3 s por omisión)', () {
      expect(sinAzar.espera(4).inMilliseconds, 3000);
      expect(sinAzar.espera(30).inMilliseconds, 3000);
    });

    test('el azar (jitter 20 %) se mantiene dentro de ±20 % de la espera base', () {
      const p = PoliticaReintento(maxReintentos: 3, jitter: 0.2);
      final azar = Random(7);
      for (var i = 0; i < 500; i++) {
        final ms = p.espera(1, azar).inMilliseconds; // base 600
        expect(ms, inInclusiveRange(480, 720));
      }
    });

    test('el azar produce esperas distintas (evita que todos los móviles reintenten a la vez)', () {
      const p = PoliticaReintento(maxReintentos: 3, jitter: 0.5);
      final azar = Random(3);
      final distintas = {for (var i = 0; i < 50; i++) p.espera(2, azar).inMilliseconds};
      expect(distintas.length, greaterThan(10));
    });

    test('«ninguna» no reintenta (comportamiento anterior)', () {
      expect(PoliticaReintento.ninguna.maxReintentos, 0);
    });
  });

  group('ApiCliente con reintentos', () {
    late List<Duration> esperas;
    late int peticiones;

    ApiCliente cliente(MockClientHandler h, {PoliticaReintento p = const PoliticaReintento(maxReintentos: 3, jitter: 0)}) {
      esperas = [];
      peticiones = 0;
      return ApiCliente(
        baseUrl: 'http://x/api',
        cliente: MockClient((r) async {
          peticiones++;
          return h(r);
        }),
        reintentos: p,
        esperar: (d) async => esperas.add(d),
      );
    }

    test('GET: falla 2 veces por red y a la tercera funciona → el usuario no ve error; esperas 300 y 600 ms', () async {
      var n = 0;
      final api = cliente((r) async => ++n <= 2 ? throw const SocketLikeException() : _ok());
      expect(await api.get('/x'), {'ok': true});
      expect(peticiones, 3);
      expect(esperas.map((e) => e.inMilliseconds), [300, 600]);
    });

    test('GET: si el servidor sigue caído, se rinde tras agotar los reintentos (1 + 3 intentos) con «sin conexión»', () async {
      final api = cliente((r) async => throw const SocketLikeException());
      await expectLater(api.get('/x'), throwsA(isA<ApiException>().having((e) => e.sinConexion, 'sinConexion', true)));
      expect(peticiones, 4);
      expect(esperas.length, 3);
    });

    test('GET: 502 y 504 se reintentan', () async {
      for (final codigo in [502, 504]) {
        var n = 0;
        final api = cliente((r) async => ++n == 1 ? http.Response('', codigo) : _ok());
        expect(await api.get('/x'), {'ok': true}, reason: 'HTTP $codigo');
        expect(peticiones, 2);
      }
    });

    test('NO se reintentan las respuestas del servidor que rechazan: 400, 401, 403, 404, 409, 500, 503', () async {
      for (final codigo in [400, 401, 403, 404, 409, 500, 503]) {
        final api = cliente((r) async => http.Response('{"error":"no"}', codigo));
        await expectLater(api.get('/x'), throwsA(isA<ApiException>()), reason: 'HTTP $codigo');
        expect(peticiones, 1, reason: 'HTTP $codigo no debe reintentarse');
        expect(esperas, isEmpty);
      }
    });

    test('POST/PUT sin marca de idempotencia NO se reintentan (podrían duplicar)', () async {
      final api = cliente((r) async => throw const SocketLikeException());
      await expectLater(api.postJson('/x', {'a': 1}), throwsA(isA<ApiException>()));
      expect(peticiones, 1);
      await expectLater(api.putJson('/x', {'a': 1}), throwsA(isA<ApiException>()));
      expect(peticiones, 2);
    });

    test('POST/PUT idempotente SÍ se reintenta', () async {
      var n = 0;
      final api = cliente((r) async => ++n == 1 ? throw const SocketLikeException() : _ok());
      expect(await api.postJson('/x', {'idCliente': 'a'}, idempotente: true), {'ok': true});
      expect(peticiones, 2);
    });

    test('DELETE no se reintenta (repetirlo contestaría «no existe» aunque sí se borró)', () async {
      final api = cliente((r) async => throw const SocketLikeException());
      await expectLater(api.delete('/x'), throwsA(isA<ApiException>()));
      expect(peticiones, 1);
    });

    test('con la política «ninguna» (por omisión) un solo intento, igual que antes', () async {
      final api = cliente((r) async => throw const SocketLikeException(), p: PoliticaReintento.ninguna);
      await expectLater(api.get('/x'), throwsA(isA<ApiException>()));
      expect(peticiones, 1);
    });

    test('un tiempo agotado también se reintenta', () async {
      var n = 0;
      final api = cliente((r) async => ++n == 1 ? Completer<http.Response>().future : _ok());
      // El primer intento nunca contesta: ApiConfig.tiempoLimite (4 s) lo corta.
      expect(await api.get('/x'), {'ok': true});
      expect(peticiones, 2);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}

/// Imita un fallo de red sin depender de dart:io.
class SocketLikeException implements Exception {
  const SocketLikeException();
}
