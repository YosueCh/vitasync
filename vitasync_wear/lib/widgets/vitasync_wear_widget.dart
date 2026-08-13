import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget de la Práctica 5-6: representa, sobre una esfera de reloj, las
/// métricas de salud más relevantes (pasos hacia la meta, calorías, sueño
/// y estado de sincronización). Diseño y arquitectura completos en
/// `docs/practica-05-06/Practica_5_6_VitaSync.docx`.
///
/// A diferencia del ejemplo standalone del documento (pensado para correr
/// a pantalla completa con `flutter run`), aquí el widget recibe un
/// [diametro] configurable para integrarse dentro de la pantalla protegida
/// de `vitasync_wear` (HomeScreen), que usa una escala tipográfica muy
/// compacta.
class VitaSyncWearWidget extends StatelessWidget {
  final int pasos;
  final int metaPasos;
  final int calorias;
  final double suenoHoras;
  final bool sincronizado;
  final double diametro;

  const VitaSyncWearWidget({
    super.key,
    required this.pasos,
    required this.metaPasos,
    required this.calorias,
    required this.suenoHoras,
    required this.sincronizado,
    this.diametro = 150,
  });

  @override
  Widget build(BuildContext context) {
    final double progreso = (pasos / metaPasos).clamp(0.0, 1.0);
    final double anillo = diametro * 0.72;

    return ClipOval(
      child: Container(
        width: diametro,
        height: diametro,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0xFF0F2027), Color(0xFF000000)],
            radius: 0.9,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: anillo,
              height: anillo,
              child: CustomPaint(painter: _AnilloProgreso(progreso)),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_walk, color: Color(0xFF34D399), size: 13),
                const SizedBox(height: 2),
                Text(
                  '$pasos',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  '/ $metaPasos',
                  style: const TextStyle(fontSize: 7, color: Colors.white54),
                ),
                const SizedBox(height: 3),
                _ChipSync(sincronizado: sincronizado),
              ],
            ),
            Positioned(
              top: diametro * 0.02,
              child: _TarjetaMetrica(
                icono: Icons.local_fire_department,
                valor: '$calorias',
                unidad: 'kcal',
                color: const Color(0xFFFB923C),
              ),
            ),
            Positioned(
              bottom: diametro * 0.02,
              child: _TarjetaMetrica(
                icono: Icons.bedtime,
                valor: suenoHoras.toStringAsFixed(1),
                unidad: 'h',
                color: const Color(0xFF818CF8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaMetrica extends StatelessWidget {
  final IconData icono;
  final String valor;
  final String unidad;
  final Color color;

  const _TarjetaMetrica({
    required this.icono,
    required this.valor,
    required this.unidad,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: color, size: 9),
          const SizedBox(width: 2),
          Text(valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 8)),
          const SizedBox(width: 1),
          Text(unidad, style: const TextStyle(color: Colors.white54, fontSize: 7)),
        ],
      ),
    );
  }
}

class _ChipSync extends StatelessWidget {
  final bool sincronizado;

  const _ChipSync({required this.sincronizado});

  @override
  Widget build(BuildContext context) {
    final Color c = sincronizado ? const Color(0xFF34D399) : const Color(0xFFF87171);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(sincronizado ? Icons.cloud_done : Icons.cloud_off, color: c, size: 8),
        const SizedBox(width: 2),
        Text(
          sincronizado ? 'Sincronizado' : 'Sin sincronizar',
          style: TextStyle(color: c, fontSize: 6.5),
        ),
      ],
    );
  }
}

/// Pinta el anillo de progreso circular alrededor del núcleo (pasos/meta).
class _AnilloProgreso extends CustomPainter {
  final double progreso; // 0.0 – 1.0

  _AnilloProgreso(this.progreso);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radio = size.width / 2 - 5;

    final fondo = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawCircle(center, radio, fondo);

    final arco = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF34D399), Color(0xFF10B981)],
      ).createShader(Rect.fromCircle(center: center, radius: radio))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radio),
      -math.pi / 2,
      2 * math.pi * progreso,
      false,
      arco,
    );
  }

  @override
  bool shouldRepaint(covariant _AnilloProgreso old) => old.progreso != progreso;
}
