import 'package:flutter/material.dart';

import '../services/api_cliente.dart';
import '../services/roles_repository.dart';

/// Asignación masiva de roles por el administrador (Práctica 7 dentro de VitaSync). Los cambios se marcan como
/// «sin aplicar» y se envían juntos al pulsar «Aplicar»; el servidor los valida todos antes de cambiar alguno.
/// Quien no sea administrador recibe 403 del servidor y aquí solo ve el aviso.
class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key, required this.repositorio});

  final RolesRepository repositorio;

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  List<PersonaRol>? _personas;
  List<InvitacionRol> _invitaciones = const [];
  String _rolInvitacion = 'medico';
  String? _error;
  String? _aviso;
  bool _aplicando = false;

  /// uid → rol elegido que todavía no se envía.
  final Map<String, String> _sinAplicar = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final lista = await widget.repositorio.listar();
      final invitaciones = await widget.repositorio.listarInvitaciones();
      if (mounted) {
        setState(() {
          _personas = lista;
          _invitaciones = invitaciones;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudo conectar al servidor');
    }
  }

  void _elegir(PersonaRol p, String? rol) {
    if (rol == null) return;
    setState(() {
      if (rol == p.rol) {
        _sinAplicar.remove(p.uid);
      } else {
        _sinAplicar[p.uid] = rol;
      }
      _aviso = null;
    });
  }

  Future<void> _crearInvitacion() async {
    try {
      final i = await widget.repositorio.crearInvitacion(_rolInvitacion);
      final todas = await widget.repositorio.listarInvitaciones();
      if (mounted) {
        setState(() {
          _invitaciones = todas;
          _aviso = 'Código para ${rolesAsignables[i.rol]}: ${i.codigo} (un solo uso, caduca en 7 días). Entrégaselo a la persona.';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _aviso = e.mensaje);
    }
  }

  Future<void> _aplicar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('confirmar-roles'),
        title: Text('Aplicar ${_sinAplicar.length} cambio(s) de rol'),
        content: Text([
          for (final e in _sinAplicar.entries)
            '${_personas!.firstWhere((p) => p.uid == e.key).correo} → ${rolesAsignables[e.value]}',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirmar-roles-si'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _aplicando = true);
    try {
      final aplicados = await widget.repositorio.asignar(Map.of(_sinAplicar));
      if (!mounted) return;
      _sinAplicar.clear();
      await _cargar();
      if (mounted) {
        setState(() => _aviso = '${aplicados.length} rol(es) asignado(s). Cada persona lo adopta al renovar su sesión.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _aviso = e.mensaje);
    } on Exception {
      if (mounted) setState(() => _aviso = 'No se pudo conectar al servidor');
    } finally {
      if (mounted) setState(() => _aplicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final personas = _personas;
    if (_error != null) {
      return Center(
        key: const Key('roles-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );
    }
    if (personas == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Roles de las personas', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Elige el rol de cada persona y aplica todos los cambios juntos.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Card(
                key: const Key('invitaciones'),
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Invitaciones de un solo uso', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Row(children: [
                        DropdownButton<String>(
                          key: const Key('rol-invitacion'),
                          value: _rolInvitacion,
                          items: [
                            for (final e in rolesAsignables.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
                          onChanged: (r) => setState(() => _rolInvitacion = r ?? _rolInvitacion),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonal(
                          key: const Key('crear-invitacion'),
                          onPressed: _crearInvitacion,
                          child: const Text('Generar código'),
                        ),
                      ]),
                      for (final i in _invitaciones)
                        Text('${i.codigo} · ${rolesAsignables[i.rol] ?? i.rol} · ${i.usada ? 'usado' : 'libre'}',
                            key: Key('invitacion-${i.codigo}')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final p in personas)
                ListTile(
                  key: Key('persona-${p.uid}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.correo),
                  subtitle: _sinAplicar.containsKey(p.uid) ? const Text('sin aplicar') : null,
                  trailing: p.esAdmin
                      ? const Text('Administrador')
                      : DropdownButton<String>(
                          key: Key('rol-${p.uid}'),
                          value: _sinAplicar[p.uid] ?? p.rol,
                          items: [
                            for (final e in rolesAsignables.entries)
                              DropdownMenuItem(value: e.key, child: Text(e.value)),
                          ],
                          onChanged: (r) => _elegir(p, r),
                        ),
                ),
            ],
          ),
        ),
        if (_aviso != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_aviso!, key: const Key('roles-aviso')),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('aplicar-roles'),
            onPressed: _sinAplicar.isEmpty || _aplicando ? null : _aplicar,
            child: Text(_sinAplicar.isEmpty ? 'Aplicar cambios' : 'Aplicar ${_sinAplicar.length} cambio(s)'),
          ),
        ),
      ],
    );
  }
}
