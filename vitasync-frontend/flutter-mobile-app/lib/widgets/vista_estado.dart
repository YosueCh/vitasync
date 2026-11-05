import 'package:flutter/material.dart';

import '../models/estado_vista.dart';

/// Dibuja el estado de una pantalla: cargando, con datos o con error.
class VistaEstado<T> extends StatelessWidget {
  const VistaEstado({
    super.key,
    required this.estado,
    required this.builder,
    required this.onReintentar,
  });

  final EstadoVista<T> estado;
  final Widget Function(BuildContext context, T datos) builder;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return switch (estado) {
      Cargando<T>() => const Center(child: CircularProgressIndicator()),
      Exito<T>(:final datos) => builder(context, datos),
      Fallo<T>(:final mensaje) => _Error(
          mensaje: mensaje,
          onReintentar: onReintentar,
        ),
    };
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: colores.outline),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
