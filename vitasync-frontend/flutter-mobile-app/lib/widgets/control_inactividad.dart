import 'dart:async';

import 'package:flutter/widgets.dart';

/// Cierra la sesión si el usuario no toca la pantalla durante [limite].
///
/// Cada toque reinicia la cuenta. Las consultas automáticas (el sondeo cada
/// 3 s) no cuentan como actividad: solo la cuenta el usuario. Es el mismo
/// criterio del `sessionTimeout` de `AuthService` en el reloj. Con [limite]
/// en null no hace nada (vista de diseño y capturas).
class ControlInactividad extends StatefulWidget {
  const ControlInactividad({
    super.key,
    required this.limite,
    required this.onInactivo,
    required this.child,
  });

  final Duration? limite;
  final VoidCallback onInactivo;
  final Widget child;

  @override
  State<ControlInactividad> createState() => _ControlInactividadState();
}

class _ControlInactividadState extends State<ControlInactividad> {
  Timer? _temporizador;

  @override
  void initState() {
    super.initState();
    _reiniciar();
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  void _reiniciar() {
    _temporizador?.cancel();
    final limite = widget.limite;
    if (limite == null) return;
    _temporizador = Timer(limite, () {
      if (mounted) widget.onInactivo();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reiniciar(),
      onPointerSignal: (_) => _reiniciar(),
      child: widget.child,
    );
  }
}
