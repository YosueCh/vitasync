import 'package:flutter/material.dart';

import '../config/configuracion_servidor.dart';
import '../services/smartwatch_api_service.dart';

/// Dirección del servidor y clave de dispositivo de ESTE reloj (rúbrica D: compatibilidad con un reloj físico).
/// Pensada para pantalla redonda y pequeña: campos grandes, un solo botón y desplazamiento vertical.
class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key, required this.api});

  final SmartwatchApiService api;

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _host = TextEditingController();
  final _puerto = TextEditingController();
  final _clave = TextEditingController();
  String? _error;
  bool _cargado = false;

  @override
  void initState() {
    super.initState();
    widget.api.configuracion().then((c) {
      if (!mounted) return;
      setState(() {
        _host.text = c.host;
        _puerto.text = '${c.puerto}';
        _clave.text = c.clave;
        _cargado = true;
      });
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _puerto.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final error = ConfiguracionServidor.validar(_host.text, _puerto.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await widget.api.guardarConfiguracion(ConfiguracionServidor(
      host: _host.text.trim(),
      puerto: int.parse(_puerto.text.trim()),
      clave: _clave.text.trim(),
    ));
    if (mounted) Navigator.pop(context, true);
  }

  Widget _campo(String clave, TextEditingController c, String etiqueta, {TextInputType? tipo, bool oculto = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: TextField(
          key: Key(clave),
          controller: c,
          keyboardType: tipo,
          obscureText: oculto,
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(labelText: etiqueta, isDense: true, labelStyle: const TextStyle(fontSize: 9)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          child: !_cargado
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Servidor', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _campo('campo-host', _host, 'IP o nombre (p. ej. 192.168.1.50)', tipo: TextInputType.url),
                    _campo('campo-puerto', _puerto, 'Puerto', tipo: TextInputType.number),
                    _campo('campo-clave', _clave, 'Clave de dispositivo', oculto: true),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_error!, key: const Key('error-config'), style: const TextStyle(fontSize: 8, color: Colors.redAccent), textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 26,
                      child: ElevatedButton(key: const Key('guardar-config'), onPressed: _guardar, child: const Text('Guardar', style: TextStyle(fontSize: 10))),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
