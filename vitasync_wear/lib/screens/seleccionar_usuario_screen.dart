import 'package:flutter/material.dart';

import '../auth/usuario_activo.dart';
import '../models/usuario.dart';
import '../services/usuario_api_service.dart';

/// Se muestra una sola vez por sesión, justo después de entrar con el
/// PIN: elige de cuál cuenta de VitaSync son los datos de salud que va
/// a mostrar/sincronizar este reloj. Usa el mismo listado de cuentas
/// (`GET /api/usuarios`) que administra "Gestión de Usuarios" en el
/// sitio web — así el reloj y la web quedan ligados a una cuenta real,
/// en vez de compartir un dispositivo global sin dueño.
class SeleccionarUsuarioScreen extends StatefulWidget {
  const SeleccionarUsuarioScreen({super.key, required this.onSeleccionado});

  final VoidCallback onSeleccionado;

  @override
  State<SeleccionarUsuarioScreen> createState() => _SeleccionarUsuarioScreenState();
}

class _SeleccionarUsuarioScreenState extends State<SeleccionarUsuarioScreen> {
  final _api = UsuarioApiService();
  List<Usuario> _usuarios = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await _api.listar();
    if (!mounted) return;
    setState(() {
      _usuarios = lista;
      _cargando = false;
    });
  }

  void _reintentar() {
    setState(() => _cargando = true);
    _cargar();
  }

  void _elegir(Usuario u) {
    UsuarioActivo.establecer(u.id, u.nombreCompleto);
    widget.onSeleccionado();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: _cargando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _usuarios.isEmpty
                    ? _SinConexion(onReintentar: _reintentar)
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_outline, size: 16, color: Colors.tealAccent),
                            const SizedBox(height: 4),
                            const Text(
                              '¿Quién eres?',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            for (final u in _usuarios)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: SizedBox(
                                  width: 140,
                                  height: 26,
                                  child: OutlinedButton(
                                    onPressed: () => _elegir(u),
                                    child: Text(
                                      u.nombreCompleto,
                                      style: const TextStyle(fontSize: 9),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}

class _SinConexion extends StatelessWidget {
  const _SinConexion({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off, size: 18, color: Colors.white38),
        const SizedBox(height: 6),
        const Text(
          'No se pudo conectar al servidor',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, color: Colors.white38),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 22,
          child: OutlinedButton(
            onPressed: onReintentar,
            child: const Text('Reintentar', style: TextStyle(fontSize: 9)),
          ),
        ),
      ],
    );
  }
}
