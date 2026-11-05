import 'package:flutter/material.dart';

import 'metricas.dart';

/// Las cuatro métricas que muestran las cards del Resumen. Cada una sabe
/// sacar su valor de una lectura y cómo mostrarlo, para que la card y su
/// historial hablen siempre igual.
enum TipoMetrica {
  pasos('Pasos', Icons.directions_walk, ''),
  calorias('Calorías', Icons.local_fire_department, 'kcal'),
  sueno('Sueño', Icons.bedtime, 'h'),
  ritmo('Ritmo cardíaco', Icons.monitor_heart, 'lpm');

  const TipoMetrica(this.titulo, this.icono, this.unidad);

  final String titulo;
  final IconData icono;
  final String unidad;

  double valor(Metricas m) => switch (this) {
        TipoMetrica.pasos => m.pasos.toDouble(),
        TipoMetrica.calorias => m.calorias.toDouble(),
        TipoMetrica.sueno => m.suenoHoras,
        TipoMetrica.ritmo => m.frecuenciaCardiaca.toDouble(),
      };

  /// Valor listo para mostrar: enteros sin decimales y el sueño con uno.
  String formato(double valor) =>
      this == TipoMetrica.sueno ? valor.toStringAsFixed(1) : valor.round().toString();
}
