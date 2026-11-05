import 'package:flutter/material.dart';

import '../services/api_cliente.dart' show ApiException;
import '../services/cuenta_correo_service.dart';

/// Primer paso con la seguridad activa (Práctica 10): iniciar sesión con correo y contraseña. De aquí sale
/// el token que el backend exige; sin él no se puede pedir ninguna cuenta.
class LoginCorreoScreen extends StatefulWidget {
  const LoginCorreoScreen({super.key, required this.servicio, required this.onAutenticado});

  final CuentaCorreoService servicio;
  final VoidCallback onAutenticado;

  @override
  State<LoginCorreoScreen> createState() => _LoginCorreoScreenState();
}

class _LoginCorreoScreenState extends State<LoginCorreoScreen> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  final _repetir = TextEditingController();
  String? _error;
  bool _ocupado = false;

  /// false = «Entrar» (ya tengo cuenta); true = «Soy nuevo» (crear cuenta, con la contraseña repetida).
  bool _crear = false;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    _repetir.dispose();
    super.dispose();
  }

  void _cambiarModo(bool crear) {
    setState(() {
      _crear = crear;
      _error = null;
      _repetir.clear();
    });
  }

  Future<void> _enviar({required bool crear}) async {
    if (crear && _clave.text != _repetir.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      if (crear) {
        await widget.servicio.registrarse(_correo.text, _clave.text);
      } else {
        await widget.servicio.iniciarSesion(_correo.text, _clave.text);
      }
      if (mounted) widget.onAutenticado();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(Icons.lock_outline, size: 48, color: tema.colorScheme.primary),
              const SizedBox(height: 8),
              Text('VitaSync', textAlign: TextAlign.center, style: tema.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                _crear ? 'Crea tu cuenta' : 'Inicia sesión con tu correo',
                key: const Key('titulo-acceso'),
                textAlign: TextAlign.center,
                style: tema.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              // Dos modos bien distintos: entrar con una cuenta que ya existe, o crear una nueva.
              SegmentedButton<bool>(
                key: const Key('modo-acceso'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Ya tengo cuenta'), icon: Icon(Icons.login)),
                  ButtonSegment(value: true, label: Text('Soy nuevo'), icon: Icon(Icons.person_add_alt)),
                ],
                selected: {_crear},
                onSelectionChanged: _ocupado ? null : (s) => _cambiarModo(s.first),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('campo-correo'),
                controller: _correo,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('campo-clave'),
                controller: _clave,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: _crear ? 'Mínimo 6 caracteres' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_crear) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('campo-clave-repetir'),
                  controller: _repetir,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Repite la contraseña', border: OutlineInputBorder()),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, key: const Key('error-acceso'), style: TextStyle(color: tema.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              // Un solo botón principal, con el nombre de lo que va a pasar según el modo.
              if (_crear)
                FilledButton(
                  key: const Key('btn-crear-cuenta'),
                  onPressed: _ocupado ? null : () => _enviar(crear: true),
                  child: Text(_ocupado ? 'Creando…' : 'Crear mi cuenta'),
                )
              else
                FilledButton(
                  key: const Key('btn-entrar'),
                  onPressed: _ocupado ? null : () => _enviar(crear: false),
                  child: Text(_ocupado ? 'Entrando…' : 'Entrar'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
