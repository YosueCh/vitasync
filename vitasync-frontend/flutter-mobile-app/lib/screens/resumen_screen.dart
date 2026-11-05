import 'dart:async';

import 'package:flutter/material.dart';

import '../models/estado_vista.dart';
import '../models/lectura_metricas.dart';
import '../models/tipo_metrica.dart';
import '../services/api_cliente.dart';
import '../services/salud_repository.dart';
import '../widgets/metrica_card.dart';
import '../widgets/vista_estado.dart';
import 'historial_screen.dart';

const _metaPasos = 10000;

class ResumenScreen extends StatefulWidget {
  const ResumenScreen({super.key, required this.repositorio, this.intervalo});

  final SaludRepository repositorio;

  /// Cada cuánto se consulta de nuevo. null desactiva el sondeo.
  final Duration? intervalo;

  @override
  State<ResumenScreen> createState() => _ResumenScreenState();
}

class _ResumenScreenState extends State<ResumenScreen> {
  EstadoVista<LecturaMetricas> _estado = const Cargando();
  Timer? _sondeo;

  /// true = el servidor respondió que la cuenta aún no tiene lecturas (D-05: no se muestran valores inventados).
  bool _sinLecturas = false;

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

  /// Carga con indicador de "cargando" (primera vez o al reintentar).
  Future<void> _cargar() async {
    setState(() => _estado = const Cargando());
    await _actualizar();
  }

  /// Consulta sin parpadeo: si ya hay datos en pantalla, los reemplaza en
  /// silencio; si falla, conserva los que ya se veían marcados sin conexión.
  Future<void> _actualizar() async {
    try {
      final lectura = await widget.repositorio.obtenerMetricas();
      if (!mounted) return;
      setState(() {
        _sinLecturas = lectura == null;
        if (lectura != null) _estado = Exito(lectura);
      });
    } on ApiException catch (e) {
      _fallar(e.mensaje);
    } on Exception {
      _fallar('No se pudo conectar al servidor');
    }
  }

  void _fallar(String mensaje) {
    if (!mounted) return;
    final actual = _estado;
    setState(() {
      _estado = actual is Exito<LecturaMetricas>
          ? Exito(actual.datos.comoSinConexion())
          : Fallo(mensaje);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sinLecturas) return const _SinLecturas();
    return VistaEstado<LecturaMetricas>(
      estado: _estado,
      onReintentar: _cargar,
      builder: (context, lectura) => _Contenido(
        lectura: lectura,
        onAbrirHistorial: _abrirHistorial,
      ),
    );
  }

  /// Al tocar una card se abre el historial de esa métrica.
  void _abrirHistorial(TipoMetrica tipo) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HistorialScreen(tipo: tipo, repositorio: widget.repositorio),
    ));
  }
}

/// La cuenta aún no tiene ninguna lectura: se dice tal cual, sin mostrar números de ejemplo.
class _SinLecturas extends StatelessWidget {
  const _SinLecturas();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      key: const Key('sin-lecturas'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.watch_off_outlined, size: 48, color: tema.colorScheme.outline),
            const SizedBox(height: 12),
            Text('Aún no hay lecturas', style: tema.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Vincula tu reloj y sincronízalo para ver tus datos de salud aquí.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.lectura, required this.onAbrirHistorial});

  final LecturaMetricas lectura;
  final ValueChanged<TipoMetrica> onAbrirHistorial;

  @override
  Widget build(BuildContext context) {
    final metricas = lectura.metricas;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Mis datos de salud', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Toca una tarjeta para ver su historial',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _Procedencia(lectura: lectura),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
          children: [
            MetricaCard(
              icono: Icons.directions_walk,
              titulo: 'Pasos',
              valor: '${metricas.pasos}',
              unidad: '/ $_metaPasos',
              progreso: metricas.pasos / _metaPasos,
              onTap: () => onAbrirHistorial(TipoMetrica.pasos),
            ),
            MetricaCard(
              icono: Icons.local_fire_department,
              titulo: 'Calorías',
              valor: '${metricas.calorias}',
              unidad: 'kcal',
              onTap: () => onAbrirHistorial(TipoMetrica.calorias),
            ),
            MetricaCard(
              icono: Icons.bedtime,
              titulo: 'Sueño',
              valor: metricas.suenoHoras.toStringAsFixed(1),
              unidad: 'h',
              onTap: () => onAbrirHistorial(TipoMetrica.sueno),
            ),
            MetricaCard(
              icono: Icons.monitor_heart,
              titulo: 'Ritmo cardíaco',
              valor: '${metricas.frecuenciaCardiaca}',
              unidad: 'lpm',
              onTap: () => onAbrirHistorial(TipoMetrica.ritmo),
            ),
          ],
        ),
      ],
    );
  }
}

/// Indica de dónde vienen los datos: en vivo del servidor o la última
/// lectura guardada en el teléfono cuando no hay conexión.
class _Procedencia extends StatelessWidget {
  const _Procedencia({required this.lectura});

  final LecturaMetricas lectura;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final hace = tiempoTranscurrido(lectura.capturadaEn);
    if (lectura.sinConexion) {
      return Container(
        key: const Key('procedencia-cache'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: esquema.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: esquema.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sin conexión. Datos de la caché del teléfono (sin confirmar con el servidor). Última lectura: $hace',
                style: TextStyle(color: esquema.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }
    return Row(
      key: const Key('procedencia-servidor'),
      children: [
        Icon(Icons.cloud_done_outlined, size: 16, color: esquema.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Confirmado por el servidor · actualizado: $hace',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// "hace un momento", "hace 5 min", "hace 2 h"; "sin datos" si no hay fecha.
String tiempoTranscurrido(DateTime? fecha, {DateTime? ahora}) {
  if (fecha == null) return 'sin datos';
  final diferencia = (ahora ?? DateTime.now()).difference(fecha);
  if (diferencia.inMinutes < 1) return 'hace un momento';
  if (diferencia.inHours < 1) return 'hace ${diferencia.inMinutes} min';
  if (diferencia.inDays < 1) return 'hace ${diferencia.inHours} h';
  return 'hace ${diferencia.inDays} d';
}
