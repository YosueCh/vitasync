import 'dart:async';

import 'package:flutter/material.dart';

import '../models/dispositivo.dart';
import '../models/estado_dispositivo.dart';
import '../models/estado_firmware.dart';
import '../models/estado_vista.dart';
import '../services/api_cliente.dart';
import '../services/firmware_repository.dart';
import '../services/salud_repository.dart';
import '../widgets/vista_estado.dart';
import 'resumen_screen.dart' show tiempoTranscurrido;

/// Lo que muestra la pantalla: el dispositivo y su firmware.
class _Vista {
  const _Vista(this.estado, this.firmware);

  final EstadoDispositivo estado;

  /// null si no se pudo consultar el firmware (no debe tirar toda la pantalla).
  final EstadoFirmware? firmware;
}

class DispositivoScreen extends StatefulWidget {
  const DispositivoScreen({
    super.key,
    required this.repositorio,
    required this.firmware,
    this.intervalo,
  });

  final SaludRepository repositorio;
  final FirmwareRepository firmware;

  /// Cada cuánto se consulta de nuevo. null desactiva el sondeo.
  final Duration? intervalo;

  @override
  State<DispositivoScreen> createState() => _DispositivoScreenState();
}

class _DispositivoScreenState extends State<DispositivoScreen> {
  EstadoVista<_Vista> _estado = const Cargando();
  Timer? _sondeo;
  bool _solicitando = false;
  bool _vinculando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    final intervalo = widget.intervalo;
    if (intervalo != null) {
      _sondeo = Timer.periodic(intervalo, (_) => _actualizar());
    }
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _estado = const Cargando());
    await _actualizar();
  }

  Future<void> _actualizar() async {
    try {
      final estado = await widget.repositorio.obtenerEstado();
      EstadoFirmware? firmware;
      try {
        firmware = await widget.firmware.obtenerEstado();
      } on Exception {
        firmware = null;
      }
      if (mounted) setState(() => _estado = Exito(_Vista(estado, firmware)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _estado = Fallo(e.mensaje));
    } on Exception {
      if (mounted) {
        setState(() => _estado = const Fallo('No se pudo conectar al servidor'));
      }
    }
  }

  Future<void> _actualizarFirmware() async {
    setState(() => _solicitando = true);
    try {
      await widget.firmware.solicitarActualizacion();
      await _actualizar();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo pedir la actualización')),
        );
      }
    } finally {
      if (mounted) setState(() => _solicitando = false);
    }
  }

  bool get _puedeVincular {
    final f = widget.firmware;
    return f is VinculaRelojes && (f as VinculaRelojes).puedeVincular;
  }

  Future<void> _vincular() async {
    final vinculador = widget.firmware;
    if (vinculador is! VinculaRelojes) return;
    setState(() => _vinculando = true);
    try {
      final reloj = await (vinculador as VinculaRelojes).vincularReloj();
      if (!mounted) return;
      if (reloj != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reloj vinculado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Esta clave se muestra UNA sola vez. Guárdala: el reloj la necesita para enviar datos.'),
                const SizedBox(height: 12),
                SelectableText(reloj.clave, key: const Key('clave-dispositivo')),
                const SizedBox(height: 12),
                SelectableText(
                  'dart run bin/vitasync_firmware.dart --usuario ${reloj.usuarioId} --clave ${reloj.clave}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
          ),
        );
      }
      await _actualizar();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo vincular el reloj')));
      }
    } finally {
      if (mounted) setState(() => _vinculando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VistaEstado<_Vista>(
      estado: _estado,
      onReintentar: _cargar,
      builder: (context, vista) => _Contenido(
        vista: vista,
        solicitando: _solicitando,
        onActualizarFirmware: _actualizarFirmware,
        onVincular: _puedeVincular && !_vinculando ? _vincular : null,
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.vista,
    required this.solicitando,
    required this.onActualizarFirmware,
    this.onVincular,
  });

  final _Vista vista;
  final bool solicitando;
  final VoidCallback onActualizarFirmware;

  /// null si no se puede vincular desde aquí (modo muestra) o ya hay una vinculación en curso.
  final VoidCallback? onVincular;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final dispositivo = vista.estado.dispositivo;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (onVincular != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              key: const Key('btn-vincular-reloj'),
              onPressed: onVincular,
              icon: const Icon(Icons.watch),
              label: const Text('Vincular reloj'),
            ),
          ),
        Text('Mi smartwatch', style: tema.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (dispositivo == null)
          _SinDispositivo(mensaje: vista.estado.mensaje)
        else ...[
          _TarjetaDispositivo(estado: vista.estado, dispositivo: dispositivo),
          const SizedBox(height: 12),
          if (vista.firmware != null)
            _TarjetaFirmware(
              firmware: vista.firmware!,
              solicitando: solicitando,
              onActualizar: onActualizarFirmware,
            ),
        ],
      ],
    );
  }
}

class _SinDispositivo extends StatelessWidget {
  const _SinDispositivo({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.watch_off),
        title: const Text('Sin dispositivo conectado'),
        subtitle: Text(
          mensaje.isEmpty ? 'Enciende el reloj o el firmware para vincularlo.' : mensaje,
        ),
      ),
    );
  }
}

class _TarjetaDispositivo extends StatelessWidget {
  const _TarjetaDispositivo({required this.estado, required this.dispositivo});

  final EstadoDispositivo estado;
  final Dispositivo dispositivo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.watch),
            title: Text(dispositivo.nombre),
            subtitle: Text(dispositivo.modelo),
            trailing: Chip(label: Text(_etiqueta(estado.estado))),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.battery_full),
            title: const Text('Batería'),
            trailing: Text('${dispositivo.bateria}%'),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Última sincronización'),
            trailing: Text(_sync(dispositivo.ultimaSync)),
          ),
        ],
      ),
    );
  }

  static String _etiqueta(String estado) => switch (estado) {
        'CONECTADO' => 'Conectado',
        'CONECTANDO' => 'Conectando',
        'SINCRONIZANDO' => 'Sincronizando',
        'ERROR' => 'Error',
        _ => 'Desconectado',
      };

  static String _sync(DateTime? fecha) {
    if (fecha == null) return 'Sin datos';
    final texto = tiempoTranscurrido(fecha);
    return texto[0].toUpperCase() + texto.substring(1);
  }
}

class _TarjetaFirmware extends StatelessWidget {
  const _TarjetaFirmware({
    required this.firmware,
    required this.solicitando,
    required this.onActualizar,
  });

  final EstadoFirmware firmware;
  final bool solicitando;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory),
                const SizedBox(width: 12),
                const Expanded(child: Text('Versión de firmware')),
                Text(firmware.versionActual ?? '—'),
              ],
            ),
            const SizedBox(height: 12),
            if (firmware.ordenPendiente) ...[
              const Text('Actualizando el reloj…'),
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ] else if (firmware.hayActualizacion) ...[
              Text(
                'Disponible: ${firmware.ultimaVersion}',
                style: tema.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(firmware.notas, style: tema.textTheme.bodySmall),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: solicitando ? null : onActualizar,
                icon: const Icon(Icons.system_update),
                label: const Text('Actualizar firmware'),
              ),
            ] else
              Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: tema.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('El firmware está al día'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
