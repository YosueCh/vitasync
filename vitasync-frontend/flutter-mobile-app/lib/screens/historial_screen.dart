import 'package:flutter/material.dart';

import '../models/estado_vista.dart';
import '../models/lectura_metricas.dart';
import '../models/tipo_metrica.dart';
import '../services/api_cliente.dart';
import '../services/salud_repository.dart';
import '../widgets/vista_estado.dart';

/// Historial de una métrica: se abre al tocar su card en el Resumen.
///
/// Muestra las lecturas guardadas en la base de datos (de la más reciente a la
/// más antigua), un resumen (mínimo, promedio y máximo) y una gráfica de cómo
/// ha cambiado. Sin conexión, muestra el historial guardado en el teléfono.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key, required this.tipo, required this.repositorio});

  final TipoMetrica tipo;
  final SaludRepository repositorio;

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  EstadoVista<List<LecturaMetricas>> _estado = const Cargando();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _estado = const Cargando());
    try {
      final lecturas = await widget.repositorio.obtenerHistorial();
      if (mounted) setState(() => _estado = Exito(lecturas));
    } on ApiException catch (e) {
      if (mounted) setState(() => _estado = Fallo(e.mensaje));
    } on Exception {
      if (mounted) setState(() => _estado = const Fallo('No se pudo conectar al servidor'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipo = widget.tipo;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(tipo.icono, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Historial de ${tipo.titulo}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: VistaEstado<List<LecturaMetricas>>(
        estado: _estado,
        onReintentar: _cargar,
        builder: (context, lecturas) => RefreshIndicator(
          onRefresh: _cargar,
          child: _Contenido(tipo: tipo, lecturas: lecturas),
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.tipo, required this.lecturas});

  final TipoMetrica tipo;

  /// De la más reciente a la más antigua.
  final List<LecturaMetricas> lecturas;

  @override
  Widget build(BuildContext context) {
    if (lecturas.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'Aún no hay historial. Aparecerá cuando el reloj sincronice.',
                key: Key('historial-vacio'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    final valores = [for (final l in lecturas) tipo.valor(l.metricas)];
    final minimo = valores.reduce((a, b) => a < b ? a : b);
    final maximo = valores.reduce((a, b) => a > b ? a : b);
    final promedio = valores.reduce((a, b) => a + b) / valores.length;
    final sinConexion = lecturas.any((l) => l.sinConexion);
    final esquema = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sinConexion)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                    'Sin conexión. Se muestra el historial guardado en el teléfono.',
                    style: TextStyle(color: esquema.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            _Dato(etiqueta: 'Mínimo', valor: '${tipo.formato(minimo)} ${tipo.unidad}'.trim()),
            _Dato(etiqueta: 'Promedio', valor: '${tipo.formato(promedio)} ${tipo.unidad}'.trim()),
            _Dato(etiqueta: 'Máximo', valor: '${tipo.formato(maximo)} ${tipo.unidad}'.trim()),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: lecturas.length < 2
              ? const Center(child: Text('Se necesitan al menos 2 lecturas para la gráfica.'))
              : CustomPaint(
                  key: const Key('grafica-historial'),
                  size: Size.infinite,
                  // La gráfica va de la lectura más antigua (izquierda) a la más reciente.
                  painter: _GraficaPainter(
                    valores: valores.reversed.toList(),
                    color: esquema.primary,
                    colorEje: esquema.outlineVariant,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text('${lecturas.length} lecturas', style: Theme.of(context).textTheme.labelLarge),
        const Divider(),
        for (final l in lecturas)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(tipo.icono, color: esquema.primary),
            title: Text(
              '${tipo.formato(tipo.valor(l.metricas))} ${tipo.unidad}'.trim(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Text(_fechaHora(l.capturadaEn)),
          ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(etiqueta, style: tema.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(valor, style: tema.textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// Línea con puntos de los valores, escalada entre su mínimo y su máximo.
class _GraficaPainter extends CustomPainter {
  _GraficaPainter({required this.valores, required this.color, required this.colorEje});

  final List<double> valores;
  final Color color;
  final Color colorEje;

  @override
  void paint(Canvas canvas, Size size) {
    const margen = 10.0;
    final ancho = size.width - margen * 2;
    final alto = size.height - margen * 2;
    final minimo = valores.reduce((a, b) => a < b ? a : b);
    final maximo = valores.reduce((a, b) => a > b ? a : b);
    final rango = (maximo - minimo) == 0 ? 1.0 : (maximo - minimo);

    canvas.drawLine(
      Offset(margen, size.height - margen),
      Offset(size.width - margen, size.height - margen),
      Paint()
        ..color = colorEje
        ..strokeWidth = 1,
    );

    final puntos = <Offset>[
      for (var i = 0; i < valores.length; i++)
        Offset(
          margen + ancho * i / (valores.length - 1),
          margen + alto * (1 - (valores[i] - minimo) / rango),
        ),
    ];
    final linea = Path()..moveTo(puntos.first.dx, puntos.first.dy);
    for (final p in puntos.skip(1)) {
      linea.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      linea,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    final relleno = Paint()..color = color;
    for (final p in puntos) {
      canvas.drawCircle(p, 3.5, relleno);
    }
  }

  @override
  bool shouldRepaint(_GraficaPainter anterior) =>
      anterior.valores != valores || anterior.color != color;
}

/// "22/10 18:05:12"; "sin fecha" si la lectura no la trae.
String _fechaHora(DateTime? f) {
  if (f == null) return 'sin fecha';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)} ${dos(f.hour)}:${dos(f.minute)}:${dos(f.second)}';
}
