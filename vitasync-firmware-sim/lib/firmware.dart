import 'dart:math';

import 'backend_api.dart';
import 'hardware.dart';

/// Firmware simulado del reloj VitaSync.
///
/// Conserva la estructura de la Práctica 1: [setup] inicializa el
/// dispositivo una sola vez y [loop] se repite indefinidamente, leyendo
/// entradas (botón, sensor de presencia), moviendo salidas (LED) y
/// reportando por el monitor serial. A diferencia de la práctica, en vez de
/// quedarse en el ESP32 también habla con el backend de VitaSync.
class Firmware {
  Firmware({
    required this.usuarioId,
    required Hardware hardware,
    required BackendApi api,
    this.versionInicial = 'v2.3.1',
    this.ticksPorSincronizacionAutomatica = 0,
    this.pausaActualizacion = const Duration(milliseconds: 600),
    this.vinculadoConClave = false,
    Random? azar,
    Future<void> Function(Duration)? esperar,
  })  : _hw = hardware,
        _api = api,
        _azar = azar ?? Random(),
        _esperar = esperar ?? Future<void>.delayed,
        version = versionInicial;

  final String usuarioId;
  final String versionInicial;

  /// true = el reloj ya fue vinculado desde la app y trae su clave de dispositivo (Práctica 10). Con la
  /// seguridad del servidor activa, el firmware no puede preguntar estado ni conectarse solo (eso es de la
  /// persona dueña): arranca directo y solo envía lecturas, consulta órdenes y reporta versiones.
  final bool vinculadoConClave;

  /// Cada cuántas vueltas de [loop] sincroniza sola. 0 = solo con el botón.
  final int ticksPorSincronizacionAutomatica;

  /// Pausa entre cada 20% de la actualización (para que se vea el avance).
  final Duration pausaActualizacion;

  final Hardware _hw;
  final BackendApi _api;
  final Random _azar;
  final Future<void> Function(Duration) _esperar;

  /// Versión que está corriendo el dispositivo.
  String version;

  bool _iniciado = false;
  bool _botonAntes = false;
  bool? _puestoAntes;
  int _ticks = 0;
  int _pasos = 0;
  int _bateria = 90;
  int _lecturas = 0;

  bool get iniciado => _iniciado;

  /// Se ejecuta una vez al encender (y tras cada reinicio por actualización).
  Future<void> setup() async {
    _iniciado = false;
    _hw.escribirLed(Led.apagado);
    _hw.imprimir('Firmware iniciado $version');
    if (vinculadoConClave) {
      _iniciado = true;
      _hw.imprimir('Vinculado con clave de dispositivo. Firmware $version');
      _hw.escribirLed(Led.verde);
      return;
    }
    try {
      final estado = await _api.estado(usuarioId);
      if (!estado.conectado) {
        _hw.imprimir('Dispositivo sin vincular: conectando con el servidor...');
        await _api.conectar(usuarioId);
        // El servidor registra el equipo con su versión de fábrica.
        final registrado = await _api.estado(usuarioId);
        version = registrado.firmware ?? version;
        _bateria = registrado.bateria ?? _bateria;
      } else {
        // La versión instalada vive en el servidor: sobrevive a un reinicio.
        version = estado.firmware ?? version;
        _bateria = estado.bateria ?? _bateria;
      }
      _iniciado = true;
      _hw.imprimir('Conectado al servidor. Firmware $version');
      _hw.escribirLed(Led.verde);
    } on BackendException catch (e) {
      _fallar(e);
    }
  }

  /// Una vuelta del ciclo principal.
  Future<void> loop() async {
    _ticks++;
    if (!_iniciado) {
      // Reintenta vincularse con el servidor en cada vuelta.
      await setup();
      return;
    }

    final puesto = _hw.leerRelojPuesto();
    if (puesto != _puestoAntes) {
      _hw.imprimir(puesto ? 'RELOJ PUESTO' : 'RELOJ RETIRADO');
      _hw.escribirLed(puesto ? Led.verde : Led.apagado);
      _puestoAntes = puesto;
    }

    try {
      await _revisarActualizacion();
      if (!_iniciado) return;

      // El botón dispara al presionarse (flanco), no mientras se mantiene.
      final boton = _hw.leerBoton();
      final presionado = boton && !_botonAntes;
      _botonAntes = boton;

      final automatica = ticksPorSincronizacionAutomatica > 0 &&
          _ticks % ticksPorSincronizacionAutomatica == 0;

      if (presionado) {
        _hw.imprimir('BOTON PRESIONADO');
        await _sincronizar(puesto);
      } else if (automatica) {
        await _sincronizar(puesto);
      }
    } on BackendException catch (e) {
      _fallar(e);
    }
  }

  /// Repite [loop] hasta que [seguir] devuelva false.
  Future<void> ejecutar({
    required Duration periodo,
    bool Function()? seguir,
  }) async {
    await setup();
    while (seguir?.call() ?? true) {
      await _esperar(periodo);
      await loop();
    }
  }

  Future<void> _sincronizar(bool puesto) async {
    if (!puesto) {
      _hw.imprimir('SIN RELOJ PUESTO - no se capturan datos');
      return;
    }
    _hw.escribirLed(Led.amarillo);
    _hw.imprimir('SINCRONIZANDO...');
    await _api.sincronizar(usuarioId, _leerSensores());
    _hw.imprimir('SINCRONIZADO ($_pasos pasos)');
    _hw.escribirLed(Led.verde);
  }

  /// Simula la lectura de los sensores del reloj.
  Map<String, Object> _leerSensores() {
    _pasos += 50 + _azar.nextInt(350);
    // La batería baja despacio: 1 punto cada 10 lecturas.
    _lecturas++;
    if (_lecturas % 10 == 0) _bateria = max(5, _bateria - 1);
    return {
      'pasos': _pasos,
      'calorias': (_pasos * 0.045).round(),
      'sueñoHoras': 6 + (_azar.nextInt(30) / 10),
      'frecuenciaCardiaca': 60 + _azar.nextInt(36),
      'bateria': _bateria,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Actualización por aire (OTA): si el usuario la pidió desde la vista
  /// móvil, descarga (simulado), instala, se reinicia y reporta la versión.
  Future<void> _revisarActualizacion() async {
    final orden = await _api.ordenFirmware(usuarioId);
    if (orden == null || orden.version == version) return;

    _hw.imprimir('ACTUALIZACION DISPONIBLE: $version -> ${orden.version}');
    _hw.escribirLed(Led.amarillo);
    for (var avance = 0; avance <= 100; avance += 20) {
      _hw.imprimir('Instalando firmware ${orden.version}... $avance%');
      await _esperar(pausaActualizacion);
    }
    await _api.reportarFirmware(usuarioId, orden.version);
    version = orden.version;
    _hw.imprimir('REINICIANDO...');
    await setup();
  }

  void _fallar(BackendException e) {
    _iniciado = false;
    _hw.escribirLed(Led.rojo);
    _hw.imprimir('ERROR: ${e.mensaje}. Reintentando...');
  }
}
