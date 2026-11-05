/// Metas de salud de una cuenta, que pueden cambiar la paciente y su médico (Práctica 9 dentro de VitaSync).
/// [version] sube con cada cambio guardado: así el servidor detecta que alguien se adelantó.
class MetasCuenta {
  const MetasCuenta({
    required this.metaPasos,
    required this.metaCalorias,
    required this.metaSueno,
    required this.version,
    required this.actualizadaPor,
  });

  static const predeterminadas =
      MetasCuenta(metaPasos: 10000, metaCalorias: 600, metaSueno: 8.0, version: 0, actualizadaPor: '—');

  final int metaPasos;
  final int metaCalorias;
  final double metaSueno;
  final int version;
  final String actualizadaPor;

  factory MetasCuenta.fromJson(Map<String, dynamic> json) => MetasCuenta(
        metaPasos: (json['metaPasos'] as num).toInt(),
        metaCalorias: (json['metaCalorias'] as num).toInt(),
        metaSueno: (json['metaSueno'] as num).toDouble(),
        version: (json['version'] as num).toInt(),
        actualizadaPor: json['actualizadaPor'] as String? ?? '—',
      );
}

/// Rangos que acepta el servidor (la app los revisa antes para avisar sin ir a la red).
class ReglasMetas {
  static const pasos = (min: 1000, max: 50000);
  static const calorias = (min: 100, max: 5000);
  static const sueno = (min: 4.0, max: 12.0);

  static String? validarPasos(int? v) =>
      v == null || v < pasos.min || v > pasos.max ? 'Pasos: de ${pasos.min} a ${pasos.max}.' : null;

  static String? validarCalorias(int? v) =>
      v == null || v < calorias.min || v > calorias.max ? 'Calorías: de ${calorias.min} a ${calorias.max}.' : null;

  static String? validarSueno(double? v) => v == null || v < sueno.min || v > sueno.max
      ? 'Sueño: de ${sueno.min.toInt()} a ${sueno.max.toInt()} horas.'
      : null;
}
