import 'package:flutter/material.dart';

/// Tarjeta de una métrica de salud (pasos, calorías, sueño, ritmo cardíaco).
/// Si se indica [progreso] (0 a 1), muestra además una barra de avance.
class MetricaCard extends StatelessWidget {
  const MetricaCard({
    super.key,
    required this.icono,
    required this.titulo,
    required this.valor,
    this.unidad,
    this.progreso,
    this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final String? unidad;
  final double? progreso;

  /// Si se indica, la card es tocable (en el Resumen abre el historial).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icono, size: 20, color: tema.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(titulo, style: tema.textTheme.labelLarge),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: tema.colorScheme.outline,
                    ),
                ],
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(valor, style: tema.textTheme.headlineMedium),
                    if (unidad != null) ...[
                      const SizedBox(width: 4),
                      Text(unidad!, style: tema.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (progreso != null)
                LinearProgressIndicator(
                  value: progreso!.clamp(0.0, 1.0),
                  borderRadius: BorderRadius.circular(4),
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
