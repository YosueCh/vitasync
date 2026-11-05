import 'package:flutter/material.dart';

import '../models/contacto.dart';
import '../models/estado_vista.dart';
import '../services/api_cliente.dart';
import '../services/contactos_repository.dart';
import '../widgets/vista_estado.dart';

/// Contactos de emergencia de la cuenta (Actividad 1 dentro de VitaSync): capturar los datos, enviarlos a la nube
/// (los guarda el servidor en Firestore) y consultarlos. Máximo 5 por cuenta y sin teléfonos repetidos; el
/// servidor repite todas las validaciones.
class ContactosScreen extends StatefulWidget {
  const ContactosScreen({super.key, required this.repositorio});

  final ContactosRepository repositorio;

  @override
  State<ContactosScreen> createState() => _ContactosScreenState();
}

class _ContactosScreenState extends State<ContactosScreen> {
  EstadoVista<List<ContactoEmergencia>> _estado = const Cargando();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _estado = const Cargando());
    try {
      final lista = await widget.repositorio.listar();
      if (mounted) setState(() => _estado = Exito(lista));
    } on ApiException catch (e) {
      if (mounted) setState(() => _estado = Fallo(e.mensaje));
    } on Exception {
      if (mounted) setState(() => _estado = const Fallo('No se pudo conectar al servidor'));
    }
  }

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _agregar() async {
    final datos = await showDialog<_Datos>(context: context, builder: (_) => const _FormularioContacto());
    if (datos == null) return;
    try {
      await widget.repositorio.crear(nombre: datos.nombre, telefono: datos.telefono, relacion: datos.relacion);
      _avisar('Contacto guardado');
      await _cargar();
    } on ApiException catch (e) {
      // 400 y 409 traen un mensaje listo para mostrar (dato inválido, teléfono repetido, límite de 5).
      _avisar(e.mensaje);
    }
  }

  Future<void> _eliminar(ContactoEmergencia c) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar a ${c.nombre}?'),
        content: const Text('El contacto se borra de la nube.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirmar-eliminar-contacto'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await widget.repositorio.eliminar(c.id);
      _avisar('Contacto eliminado');
      await _cargar();
    } on ApiException catch (e) {
      _avisar(e.mensaje);
      await _cargar(); // por si ya no existía (otro teléfono lo borró)
    }
  }

  @override
  Widget build(BuildContext context) {
    return VistaEstado<List<ContactoEmergencia>>(
      estado: _estado,
      onReintentar: _cargar,
      builder: (context, contactos) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Contactos de emergencia', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${contactos.length} de ${ReglasContacto.maxPorCuenta} · se guardan en la nube',
            key: const Key('contador-contactos'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (contactos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aún no tienes contactos de emergencia. Agrega a alguien a quien avisar.',
                key: Key('sin-contactos'),
                textAlign: TextAlign.center,
              ),
            ),
          for (final c in contactos)
            Card(
              key: Key('contacto-${c.id}'),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.contact_phone)),
                title: Text(c.nombre),
                subtitle: Text('${c.relacion} · ${c.telefono}'),
                trailing: IconButton(
                  key: Key('eliminar-contacto-${c.id}'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Eliminar',
                  onPressed: () => _eliminar(c),
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('btn-agregar-contacto'),
            onPressed: contactos.length >= ReglasContacto.maxPorCuenta ? null : _agregar,
            icon: const Icon(Icons.person_add_alt),
            label: Text(contactos.length >= ReglasContacto.maxPorCuenta ? 'Límite de contactos alcanzado' : 'Agregar contacto'),
          ),
        ],
      ),
    );
  }
}

class _Datos {
  const _Datos(this.nombre, this.telefono, this.relacion);

  final String nombre;
  final String telefono;
  final String relacion;
}

class _FormularioContacto extends StatefulWidget {
  const _FormularioContacto();

  @override
  State<_FormularioContacto> createState() => _FormularioContactoState();
}

class _FormularioContactoState extends State<_FormularioContacto> {
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  String _relacion = ReglasContacto.relaciones.first;
  Map<String, String> _errores = {};

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  void _guardar() {
    final errores = ReglasContacto.validar(_nombre.text, _telefono.text);
    if (errores.isNotEmpty) {
      setState(() => _errores = errores);
      return;
    }
    Navigator.pop(context, _Datos(_nombre.text.trim(), _telefono.text.trim(), _relacion));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo contacto de emergencia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('campo-contacto-nombre'),
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Nombre', errorText: _errores['nombre'], errorMaxLines: 2),
            ),
            TextField(
              key: const Key('campo-contacto-telefono'),
              controller: _telefono,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Teléfono', errorText: _errores['telefono'], errorMaxLines: 2),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final r in ReglasContacto.relaciones)
                  ChoiceChip(
                    key: Key('relacion-$r'),
                    label: Text(r),
                    selected: _relacion == r,
                    onSelected: (_) => setState(() => _relacion = r),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const Key('btn-guardar-contacto'), onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
