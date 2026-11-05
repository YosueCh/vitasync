import 'package:flutter/material.dart';

import '../models/estado_vista.dart';
import '../models/usuario.dart';
import '../services/api_cliente.dart';
import '../services/cuenta_correo_service.dart';
import '../services/usuario_repository.dart';
import '../widgets/vista_estado.dart';

/// Primer paso al entrar: elegir de cuál cuenta son los datos. Todos los
/// endpoints del backend trabajan por `usuarioId`, así que hay que saberlo
/// antes de pedir el PIN.
class SeleccionarCuentaScreen extends StatefulWidget {
  const SeleccionarCuentaScreen({
    super.key,
    required this.repositorio,
    required this.onSeleccionada,
    this.sesion,
    this.onCerrarSesionCorreo,
  });

  final UsuarioRepository repositorio;
  final ValueChanged<Usuario> onSeleccionada;

  /// Sesión de correo activa (Práctica 10). Si existe, se muestra quién es y su UID.
  final SesionCorreo? sesion;
  final VoidCallback? onCerrarSesionCorreo;

  @override
  State<SeleccionarCuentaScreen> createState() => _SeleccionarCuentaScreenState();
}

class _SeleccionarCuentaScreenState extends State<SeleccionarCuentaScreen> {
  EstadoVista<List<Usuario>> _estado = const Cargando();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _estado = const Cargando());
    try {
      final cuentas = await widget.repositorio.listarHabilitados();
      if (mounted) setState(() => _estado = Exito(cuentas));
    } on ApiException catch (e) {
      if (mounted) setState(() => _estado = Fallo(e.mensaje));
    } on Exception {
      if (mounted) {
        setState(() => _estado = const Fallo('No se pudo conectar al servidor'));
      }
    }
  }

  Future<void> _crearCuenta() async {
    final nombre = TextEditingController();
    final usuario = TextEditingController();
    final datos = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear mi cuenta VitaSync'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('campo-nombre'),
              controller: nombre,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
            ),
            TextField(
              key: const Key('campo-usuario'),
              controller: usuario,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Usuario (letras, números . _ -)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('btn-guardar-cuenta'),
            onPressed: () => Navigator.pop(context, (nombre.text, usuario.text)),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    final creador = widget.repositorio;
    if (datos == null || creador is! CreadorDeCuentas || !mounted) return;
    try {
      await (creador as CreadorDeCuentas).crearCuenta(nombreCompleto: datos.$1, username: datos.$2);
      await _cargar();
    } on ApiException catch (e) {
      // 400 (datos inválidos) y 409 (usuario repetido) traen un mensaje listo para mostrar.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sesion = widget.sesion;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Icon(Icons.favorite, size: 48, color: tema.colorScheme.primary),
            const SizedBox(height: 8),
            Text('VitaSync', style: tema.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('¿Quién eres?', style: tema.textTheme.bodyLarge),
            if (sesion != null) ...[
              const SizedBox(height: 8),
              Text('Sesión: ${sesion.correo}', key: const Key('sesion-correo'), style: tema.textTheme.bodyMedium),
              Text('UID: ${sesion.uid}', key: const Key('sesion-uid'), style: tema.textTheme.bodySmall),
              if (widget.onCerrarSesionCorreo != null)
                TextButton(
                  key: const Key('btn-cerrar-sesion-correo'),
                  onPressed: widget.onCerrarSesionCorreo,
                  child: const Text('Cerrar sesión de correo'),
                ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: VistaEstado<List<Usuario>>(
                estado: _estado,
                onReintentar: _cargar,
                builder: (context, cuentas) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final cuenta in cuentas)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(cuenta.nombreCompleto),
                          subtitle: Text('@${cuenta.username}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => widget.onSeleccionada(cuenta),
                        ),
                      ),
                    if (cuentas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aún no tienes ninguna cuenta VitaSync.', textAlign: TextAlign.center),
                      ),
                    if (widget.repositorio is CreadorDeCuentas)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: OutlinedButton.icon(
                          key: const Key('btn-crear-cuenta-vitasync'),
                          onPressed: _crearCuenta,
                          icon: const Icon(Icons.person_add_alt),
                          label: const Text('Crear mi cuenta VitaSync'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
