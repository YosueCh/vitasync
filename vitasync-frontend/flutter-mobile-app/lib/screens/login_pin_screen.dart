import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../services/api_cliente.dart';
import '../services/auth_service.dart';
import '../widgets/pin_pad.dart';

/// Pide el PIN de la cuenta elegida. Si la cuenta todavía no tiene PIN, lo
/// crea: lo pide dos veces y recién entonces lo registra en el servidor.
class LoginPinScreen extends StatefulWidget {
  const LoginPinScreen({
    super.key,
    required this.cuenta,
    required this.auth,
    required this.onAutenticado,
    required this.onCambiarCuenta,
  });

  final Usuario cuenta;
  final AuthService auth;
  final VoidCallback onAutenticado;
  final VoidCallback onCambiarCuenta;

  @override
  State<LoginPinScreen> createState() => _LoginPinScreenState();
}

class _LoginPinScreenState extends State<LoginPinScreen> {
  bool _ocupado = false;
  String? _error;

  /// Primer PIN escrito al crear uno; null mientras se escribe el primero.
  String? _primerPin;

  bool get _creando => !widget.cuenta.tienePin;

  String get _indicacion {
    if (!_creando) return 'Ingresa tu PIN';
    return _primerPin == null ? 'Crea tu PIN de 4 dígitos' : 'Confirma tu PIN';
  }

  Future<void> _alCompletar(String pin) async {
    if (_creando && _primerPin == null) {
      setState(() {
        _primerPin = pin;
        _error = null;
      });
      return;
    }
    if (_creando && pin != _primerPin) {
      setState(() {
        _primerPin = null;
        _error = 'Los PIN no coinciden, intenta de nuevo';
      });
      return;
    }
    await _enviar(pin);
  }

  Future<void> _enviar(String pin) async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    String? error;
    var entro = false;
    try {
      final resultado = _creando
          ? await widget.auth.registrarPin(widget.cuenta.id, pin)
          : await widget.auth.verificarPin(widget.cuenta.id, pin);
      entro = resultado.exito;
      if (!entro) error = resultado.mensaje;
    } on ApiException catch (e) {
      error = e.mensaje;
    } on Exception {
      error = 'No se pudo conectar al servidor';
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _error = error;
      if (!entro) _primerPin = null;
    });
    if (entro) widget.onAutenticado();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite, size: 48, color: tema.colorScheme.primary),
                const SizedBox(height: 8),
                Text('VitaSync', style: tema.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('Hola, ${widget.cuenta.nombreCompleto}', style: tema.textTheme.bodyLarge),
                Text(_indicacion, style: tema.textTheme.bodyMedium),
                const SizedBox(height: 32),
                PinPad(onCompleto: _alCompletar, habilitado: !_ocupado),
                SizedBox(
                  height: 48,
                  child: Center(
                    child: Text(
                      _error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tema.colorScheme.error),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onCambiarCuenta,
                  child: const Text('Cambiar de cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
