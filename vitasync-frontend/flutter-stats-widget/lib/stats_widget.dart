import 'package:flutter/material.dart';

/// Widget especializado que consume los datos provistos por la aplicacion
/// web host (Angular) y genera una vista estadistica interactiva con
/// indicadores de progreso circulares. Documentado en la Practica 7-8
/// como "Implementacion de Statswidget.dart".
class StatsWidget extends StatelessWidget {
  final int tareasCompletadas;
  final int tareasPendientes;
  final int tareasEnProgreso;

  const StatsWidget({
    super.key,
    required this.tareasCompletadas,
    required this.tareasPendientes,
    required this.tareasEnProgreso,
  });

  @override
  Widget build(BuildContext context) {
    final int total = tareasCompletadas + tareasPendientes + tareasEnProgreso;
    final double porcentaje = total > 0 ? (tareasCompletadas / total) : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Métricas de Productividad',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Pendientes', tareasPendientes, Colors.orange),
              _buildStatItem('En Progreso', tareasEnProgreso, Colors.blue),
              _buildStatItem('Completadas', tareasCompletadas, Colors.green),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: porcentaje,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  Text(
                    '${(porcentaje * 100).round()}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
