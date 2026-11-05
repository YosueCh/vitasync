import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../services/chat_repository.dart';
import '../services/contactos_repository.dart';
import '../services/firmware_repository.dart';
import '../services/metas_repository.dart';
import '../services/roles_repository.dart';
import '../services/salud_repository.dart';
import '../services/usuario_repository.dart';
import 'chat_screen.dart';
import 'contactos_screen.dart';
import 'dispositivo_screen.dart';
import 'resumen_screen.dart';
import 'roles_screen.dart';

/// Estructura de la app ya autenticada: barra superior y navegación inferior
/// entre "Resumen", "Dispositivo" y "Chat" (médico-paciente, Práctica 6).
class ShellScreen extends StatefulWidget {
  const ShellScreen({
    super.key,
    required this.cuenta,
    required this.repositorio,
    required this.firmware,
    required this.chat,
    required this.usuarios,
    required this.onCerrarSesion,
    this.intervaloSondeo,
    this.intervaloChat,
    this.contactos,
    this.metasDe,
    this.roles,
  });

  final Usuario cuenta;
  final SaludRepository repositorio;
  final FirmwareRepository firmware;
  final ChatRepository chat;
  final UsuarioRepository usuarios;
  final VoidCallback onCerrarSesion;

  /// Contactos de emergencia (Actividad 1). Si es null no se muestra la pestaña.
  final ContactosRepository? contactos;

  /// Metas de una cuenta (Práctica 9). [medico] = quien guarda es el médico. null = sin metas editables.
  final MetasRepository Function(String cuentaId, {bool medico})? metasDe;

  /// Asignación de roles (Práctica 7, solo con la seguridad activa; el servidor deja pasar solo al administrador).
  final RolesRepository? roles;

  /// Cada cuánto se refrescan las pantallas. null desactiva el sondeo.
  final Duration? intervaloSondeo;

  /// Cada cuánto el chat pide mensajes nuevos. null desactiva el sondeo.
  final Duration? intervaloChat;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _indice = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VitaSync'),
            Text(
              widget.cuenta.nombreCompleto,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: widget.onCerrarSesion,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: IndexedStack(
        index: _indice,
        children: [
          ResumenScreen(
            repositorio: widget.repositorio,
            intervalo: widget.intervaloSondeo,
            metas: widget.metasDe?.call(widget.cuenta.id),
          ),
          DispositivoScreen(
            repositorio: widget.repositorio,
            firmware: widget.firmware,
            intervalo: widget.intervaloSondeo,
          ),
          ChatScreen(
            cuenta: widget.cuenta,
            chat: widget.chat,
            usuarios: widget.usuarios,
            intervalo: widget.intervaloChat,
            metasDe: widget.metasDe,
          ),
          if (widget.contactos != null) ContactosScreen(repositorio: widget.contactos!),
          if (widget.roles != null) RolesScreen(repositorio: widget.roles!),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Resumen'),
          const NavigationDestination(icon: Icon(Icons.watch), label: 'Dispositivo'),
          const NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          if (widget.contactos != null)
            const NavigationDestination(icon: Icon(Icons.contact_phone_outlined), label: 'Contactos'),
          if (widget.roles != null)
            const NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Roles'),
        ],
      ),
    );
  }
}
