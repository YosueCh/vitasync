import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/models/estado_dispositivo.dart';
import 'package:vitasync_mobile/models/lectura_metricas.dart';
import 'package:vitasync_mobile/models/mensaje_chat.dart';
import 'package:vitasync_mobile/models/metricas.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/chat_screen.dart';
import 'package:vitasync_mobile/screens/resumen_screen.dart';
import 'package:vitasync_mobile/services/api_cliente.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

/// Práctica 9 dentro de VitaSync: la app dice la verdad sobre el estado de lo que muestra y de lo que envía.

const _ana = Usuario(id: 'ana1', nombreCompleto: 'Ana Torres', username: 'ana', habilitado: true);

class _Usuarios implements UsuarioRepository {
  @override
  Future<List<Usuario>> listarHabilitados() async => const [_ana];
}

/// Chat cuyo servidor se puede "apagar" (sin conexión) o hacer rechazar lo que llega (409).
class _ChatInestable implements ChatRepository {
  final real = MuestraChatRepository();
  bool caido = false;
  String? rechazo;
  int intentos = 0;

  void _revisar() {
    if (caido) throw const ApiException('No se pudo conectar al servidor', sinConexion: true);
  }

  @override
  Future<ConversacionChat> consultar(String pacienteId, {int desde = 0}) async {
    _revisar();
    return real.consultar(pacienteId, desde: desde);
  }

  @override
  Future<void> enviar(String pacienteId, RolChat emisor, String texto) async {
    intentos++;
    _revisar();
    if (rechazo != null) throw ApiException(rechazo!);
    return real.enviar(pacienteId, emisor, texto);
  }

  @override
  Future<void> enviarArchivo(String pacienteId, RolChat emisor,
          {required String nombre, required String tipo, required Uint8List bytes}) =>
      real.enviarArchivo(pacienteId, emisor, nombre: nombre, tipo: tipo, bytes: bytes);

  @override
  Future<Uint8List> descargar(String pacienteId, int mensajeId) => real.descargar(pacienteId, mensajeId);

  @override
  Future<void> cerrar(String pacienteId) => real.cerrar(pacienteId);

  @override
  Future<void> abrir(String pacienteId) => real.abrir(pacienteId);
}

class _Salud implements SaludRepository {
  _Salud(this.lectura);

  final LecturaMetricas lectura;

  @override
  Future<LecturaMetricas?> obtenerMetricas() async => lectura;

  @override
  Future<EstadoDispositivo> obtenerEstado() => throw UnimplementedError();

  @override
  Future<List<LecturaMetricas>> obtenerHistorial({int limite = 30}) async => [];
}

Future<void> _abrirChat(WidgetTester tester, _ChatInestable chat, {Duration? intervalo}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ChatScreen(cuenta: _ana, chat: chat, usuarios: _Usuarios(), intervalo: intervalo),
    ),
  ));
}

Future<void> _avanzar(WidgetTester tester, [Duration tiempo = Duration.zero]) async {
  await tester.pump(tiempo);
  await tester.pump();
  await tester.pump();
}

const _metricas = Metricas(pasos: 1500, calorias: 90, suenoHoras: 6.5, frecuenciaCardiaca: 70, bateria: 80);

void main() {
  group('Chat: mensajes pendientes de enviar', () {
    testWidgets('sin conexión el mensaje queda PENDIENTE (no se pierde ni se da por enviado)', (tester) async {
      final chat = _ChatInestable();
      await _abrirChat(tester, chat);
      await tester.tap(find.text('Paciente (Dispositivo B)'));
      await _avanzar(tester);

      chat.caido = true;
      await tester.enterText(find.byType(TextField), 'Me duele la cabeza');
      await tester.tap(find.byTooltip('Enviar'));
      await _avanzar(tester);

      expect(find.byKey(const Key('burbuja-pendiente')), findsOneWidget);
      expect(find.textContaining('Pendiente de enviar'), findsOneWidget);
      expect(find.text('Me duele la cabeza'), findsOneWidget);
      expect(find.textContaining('quedó PENDIENTE'), findsOneWidget);
      expect(find.textContaining('Mensaje enviado'), findsNothing, reason: 'no se dice «enviado» sin confirmación');
      expect((await chat.real.consultar('ana1')).mensajes, isEmpty, reason: 'el servidor no recibió nada');
      expect((tester.widget<TextField>(find.byType(TextField))).controller!.text, isEmpty);
    });

    testWidgets('al volver la conexión se reenvía solo y pasa a «enviado»', (tester) async {
      final chat = _ChatInestable();
      await _abrirChat(tester, chat, intervalo: const Duration(seconds: 1));
      await tester.tap(find.text('Paciente (Dispositivo B)'));
      await _avanzar(tester);
      chat.caido = true;
      await tester.enterText(find.byType(TextField), 'Hola doctora');
      await tester.tap(find.byTooltip('Enviar'));
      await _avanzar(tester);
      expect(find.byKey(const Key('burbuja-pendiente')), findsOneWidget);

      chat.caido = false;
      await _avanzar(tester, const Duration(seconds: 1));

      expect(find.byKey(const Key('burbuja-pendiente')), findsNothing);
      expect(find.textContaining('✓ enviado'), findsOneWidget);
      expect((await chat.real.consultar('ana1')).mensajes.map((m) => m.texto), ['Hola doctora']);
      expect(find.textContaining('Mensaje pendiente enviado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('varios pendientes se envían en el MISMO orden en que se escribieron', (tester) async {
      final chat = _ChatInestable();
      await _abrirChat(tester, chat, intervalo: const Duration(seconds: 1));
      await tester.tap(find.text('Paciente (Dispositivo B)'));
      await _avanzar(tester);
      chat.caido = true;
      for (final t in ['uno', 'dos', 'tres']) {
        await tester.enterText(find.byType(TextField), t);
        await tester.tap(find.byTooltip('Enviar'));
        await _avanzar(tester);
      }
      expect(find.byKey(const Key('burbuja-pendiente')), findsNWidgets(3));

      chat.caido = false;
      await _avanzar(tester, const Duration(seconds: 1));

      expect((await chat.real.consultar('ana1')).mensajes.map((m) => m.texto), ['uno', 'dos', 'tres']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si el servidor RESPONDE y lo rechaza (chat cerrado) no queda pendiente: reintentar no sirve', (tester) async {
      final chat = _ChatInestable()..rechazo = 'El chat está cerrado';
      await _abrirChat(tester, chat);
      await tester.tap(find.text('Paciente (Dispositivo B)'));
      await _avanzar(tester);

      await tester.enterText(find.byType(TextField), 'ya no me ven');
      await tester.tap(find.byTooltip('Enviar'));
      await _avanzar(tester);

      expect(find.byKey(const Key('burbuja-pendiente')), findsNothing);
      expect(find.text('El chat está cerrado'), findsOneWidget);
    });
  });

  group('Resumen: de dónde salen los datos', () {
    Future<void> abrir(WidgetTester tester, LecturaMetricas lectura) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ResumenScreen(repositorio: _Salud(lectura)))));
      await tester.pumpAndSettle();
    }

    testWidgets('datos del servidor: «Confirmado por el servidor»', (tester) async {
      await abrir(tester, LecturaMetricas(metricas: _metricas, capturadaEn: DateTime.now()));

      expect(find.byKey(const Key('procedencia-servidor')), findsOneWidget);
      expect(find.textContaining('Confirmado por el servidor'), findsOneWidget);
      expect(find.byKey(const Key('procedencia-cache')), findsNothing);
    });

    testWidgets('datos de la caché: se dice que NO están confirmados', (tester) async {
      await abrir(tester, const LecturaMetricas(metricas: _metricas, sinConexion: true));

      expect(find.byKey(const Key('procedencia-cache')), findsOneWidget);
      expect(find.textContaining('sin confirmar con el servidor'), findsOneWidget);
      expect(find.byKey(const Key('procedencia-servidor')), findsNothing);
    });
  });
}
