import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'hardware.dart';

/// Hardware simulado en la terminal:
///
/// - tecla `s`: presiona el botón de sincronizar
/// - tecla `p`: pone o retira el reloj (el sensor de presencia)
/// - tecla `q`: apaga el dispositivo
///
/// La salida es el "monitor serial" y el LED se dibuja con un emoji.
class HardwareConsola implements Hardware {
  HardwareConsola({bool relojPuesto = true}) : _relojPuesto = relojPuesto;

  bool _relojPuesto;
  bool _botonPendiente = false;
  StreamSubscription<List<int>>? _teclas;
  final _apagado = Completer<void>();

  /// Se completa cuando el usuario presiona `q`.
  Future<void> get apagado => _apagado.future;

  /// Empieza a escuchar el teclado. Si no hay terminal interactiva (por
  /// ejemplo al redirigir la salida), no hay teclas y solo corre en automático.
  void escucharTeclado() {
    if (!stdin.hasTerminal) return;
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    } on StdinException {
      // Algunas terminales (p. ej. Git Bash sin winpty) dicen ser terminal
      // pero no dejan cambiar el modo: se corre solo en automático.
      imprimir('Sin teclado interactivo: usa --auto <seg> para sincronizar.');
      return;
    }
    _teclas = stdin.listen((bytes) {
      for (final tecla in utf8.decode(bytes, allowMalformed: true).toLowerCase().split('')) {
        switch (tecla) {
          case 's':
            _botonPendiente = true;
          case 'p':
            _relojPuesto = !_relojPuesto;
          case 'q':
            if (!_apagado.isCompleted) _apagado.complete();
        }
      }
    });
  }

  Future<void> cerrar() async {
    final habiaTeclado = _teclas != null;
    await _teclas?.cancel();
    if (habiaTeclado) {
      stdin.echoMode = true;
      stdin.lineMode = true;
    }
  }

  @override
  bool leerBoton() {
    // Un toque de tecla equivale a un botón presionado durante una vuelta.
    final presionado = _botonPendiente;
    _botonPendiente = false;
    return presionado;
  }

  @override
  bool leerRelojPuesto() => _relojPuesto;

  @override
  void escribirLed(Led estado) =>
      stdout.writeln('  LED ${estado.icono} ${estado.significado}');

  @override
  void imprimir(String mensaje) {
    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    stdout.writeln('[${dos(ahora.hour)}:${dos(ahora.minute)}:${dos(ahora.second)}] $mensaje');
  }
}
