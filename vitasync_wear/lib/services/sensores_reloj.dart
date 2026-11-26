import 'dart:math';

import 'package:flutter/services.dart';

import '../models/metricas.dart';

/// Qué puede medir este reloj y si la persona ya dio permiso (rúbrica D2 y D4).
class EstadoSensores {
  const EstadoSensores({
    this.frecuenciaDisponible = false,
    this.pasosDisponible = false,
    this.permisoCardiaco = false,
    this.permisoActividad = false,
    this.bateria = -1,
  });

  factory EstadoSensores.deMapa(Map<Object?, Object?> m) => EstadoSensores(
        frecuenciaDisponible: m['frecuenciaDisponible'] == true,
        pasosDisponible: m['pasosDisponible'] == true,
        permisoCardiaco: m['permisoCardiaco'] == true,
        permisoActividad: m['permisoActividad'] == true,
        bateria: (m['bateria'] as num?)?.toInt() ?? -1,
      );

  final bool frecuenciaDisponible;
  final bool pasosDisponible;
  final bool permisoCardiaco;
  final bool permisoActividad;
  final int bateria;

  /// El reloj tiene al menos un sensor de los que usa la app.
  bool get hayAlgunSensor => frecuenciaDisponible || pasosDisponible;

  /// Hay sensores que se podrían usar pero falta un permiso.
  bool get faltaPermiso =>
      (frecuenciaDisponible && !permisoCardiaco) || (pasosDisponible && !permisoActividad);

  bool get frecuenciaUsable => frecuenciaDisponible && permisoCardiaco;
  bool get pasosUsable => pasosDisponible && permisoActividad;
}

/// Una lectura cruda: null en lo que no se pudo medir.
class LecturaSensores {
  const LecturaSensores({this.frecuenciaCardiaca, this.pasos, this.bateria = -1});

  final int? frecuenciaCardiaca;
  final int? pasos;
  final int bateria;
}

abstract interface class SensoresReloj {
  Future<EstadoSensores> estado();

  /// Muestra el diálogo de permisos del sistema y devuelve el estado resultante.
  Future<EstadoSensores> pedirPermisos();

  Future<LecturaSensores> leer();
}

/// Sensores reales de Android por el canal nativo de MainActivity.kt (reloj físico o emulador con Virtual sensors).
class SensoresRelojAndroid implements SensoresReloj {
  SensoresRelojAndroid([MethodChannel? canal]) : _canal = canal ?? const MethodChannel('vitasync/sensores');
  final MethodChannel _canal;

  @override
  Future<EstadoSensores> estado() async {
    try {
      return EstadoSensores.deMapa(await _canal.invokeMapMethod<Object?, Object?>('estado') ?? {});
    } on MissingPluginException {
      return const EstadoSensores(); // plataforma sin sensores (pruebas, escritorio): todo simulado
    } on PlatformException {
      return const EstadoSensores();
    }
  }

  @override
  Future<EstadoSensores> pedirPermisos() async {
    try {
      return EstadoSensores.deMapa(await _canal.invokeMapMethod<Object?, Object?>('pedirPermisos') ?? {});
    } on MissingPluginException {
      return const EstadoSensores();
    } on PlatformException {
      return estado();
    }
  }

  @override
  Future<LecturaSensores> leer() async {
    try {
      final m = await _canal.invokeMapMethod<Object?, Object?>('leer') ?? {};
      return LecturaSensores(
        frecuenciaCardiaca: (m['frecuenciaCardiaca'] as num?)?.toInt(),
        pasos: (m['pasos'] as num?)?.toInt(),
        bateria: (m['bateria'] as num?)?.toInt() ?? -1,
      );
    } on MissingPluginException {
      return const LecturaSensores();
    } on PlatformException {
      return const LecturaSensores();
    }
  }
}

/// Qué parte de la lectura enviada es medida y cuál no.
class ResultadoLectura {
  const ResultadoLectura(this.metricas, {required this.reales, required this.estimadas, required this.simuladas});

  final Metricas metricas;

  /// Medidas por un sensor del reloj (p. ej. «frecuencia cardíaca»).
  final List<String> reales;

  /// Calculadas a partir de otra medida (las calorías, desde los pasos).
  final List<String> estimadas;

  /// Inventadas porque el reloj no tiene el sensor o no se dio el permiso.
  final List<String> simuladas;

  bool get todoSimulado => reales.isEmpty;
  bool get hayReales => reales.isNotEmpty;
}

/// Arma la lectura que se envía al backend con lo que el reloj SÍ pudo medir, y marca el resto.
///  · frecuencia cardíaca, pasos y batería: del sensor si hay y se permitió; si no, simulados.
///  · calorías: estimadas de los pasos reales (≈0,04 kcal por paso); simuladas si los pasos lo son.
///  · sueño: el reloj no lo mide aquí; se conserva el último valor conocido del servidor (o 7 h si no hay) y se marca como simulado.
ResultadoLectura construirLectura({
  required EstadoSensores estado,
  required LecturaSensores sensor,
  double? ultimoSueno,
  Random? azar,
}) {
  final r = azar ?? Random();
  final reales = <String>[], estimadas = <String>[], simuladas = <String>[];

  final fcReal = estado.frecuenciaUsable ? sensor.frecuenciaCardiaca : null;
  final int fc;
  if (fcReal != null && fcReal > 0) {
    fc = fcReal;
    reales.add('frecuencia cardíaca');
  } else {
    fc = 62 + r.nextInt(33);
    simuladas.add('frecuencia cardíaca');
  }

  final pasosReales = estado.pasosUsable ? sensor.pasos : null;
  final int pasos;
  if (pasosReales != null && pasosReales >= 0) {
    pasos = pasosReales;
    reales.add('pasos');
  } else {
    pasos = 4000 + r.nextInt(8000);
    simuladas.add('pasos');
  }

  final int calorias;
  if (reales.contains('pasos')) {
    calorias = max(0, (pasos * 0.04).round());
    estimadas.add('calorías');
  } else {
    calorias = 250 + r.nextInt(550);
    simuladas.add('calorías');
  }

  final bateria = sensor.bateria >= 0 && sensor.bateria <= 100 ? sensor.bateria : (estado.bateria >= 0 ? estado.bateria : 40 + r.nextInt(55));
  if (sensor.bateria >= 0 || estado.bateria >= 0) {
    reales.add('batería');
  } else {
    simuladas.add('batería');
  }

  final sueno = ultimoSueno ?? 7.0;
  simuladas.add('sueño');

  return ResultadoLectura(
    Metricas(pasos: pasos, calorias: calorias, suenoHoras: sueno, frecuenciaCardiaca: fc, bateria: bateria),
    reales: reales, estimadas: estimadas, simuladas: simuladas,
  );
}
