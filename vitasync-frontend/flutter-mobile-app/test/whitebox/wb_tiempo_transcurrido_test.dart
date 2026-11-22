// PRÁCTICA 11 · Fase 2 · Método 2 (PROCESAMIENTO/CÁLCULO): tiempoTranscurrido(fecha, {ahora})
//
// Código (lib/screens/resumen_screen.dart):
//   L1  if (fecha == null) return 'sin datos';                                ← D1
//   L2  final diferencia = (ahora ?? DateTime.now()).difference(fecha);       ← D2 (operador ??)
//   L3  if (diferencia.inMinutes < 1) return 'hace un momento';               ← D3
//   L4  if (diferencia.inHours   < 1) return 'hace ${diferencia.inMinutes} min'; ← D4
//   L5  if (diferencia.inDays    < 1) return 'hace ${diferencia.inHours} h';     ← D5
//   L6  return 'hace ${diferencia.inDays} d';
//
// V(G) = 5 decisiones + 1 = 6. Caminos independientes:
//   P1 fecha==null | P2 ahora==null (usa el reloj) | P3 <1 min | P4 <1 h | P5 <1 día | P6 ≥1 día
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/screens/resumen_screen.dart';

void main() {
  final ahora = DateTime(2026, 11, 22, 12, 0, 0);
  String hace(Duration d) => tiempoTranscurrido(ahora.subtract(d), ahora: ahora);

  group('Caminos independientes (V(G)=6)', () {
    test('P1: fecha nula → «sin datos» (D1=T)', () {
      expect(tiempoTranscurrido(null, ahora: ahora), 'sin datos');
    });
    test('P2: sin «ahora» usa el reloj del sistema (D2: rama «??» tomada)', () {
      expect(tiempoTranscurrido(DateTime.now()), 'hace un momento');
    });
    test('P3: menos de un minuto', () => expect(hace(const Duration(seconds: 5)), 'hace un momento'));
    test('P4: menos de una hora', () => expect(hace(const Duration(minutes: 5)), 'hace 5 min'));
    test('P5: menos de un día', () => expect(hace(const Duration(hours: 2)), 'hace 2 h'));
    test('P6: un día o más', () => expect(hace(const Duration(days: 3)), 'hace 3 d'));
  });

  group('Valores límite (en cada frontera: justo antes, justo en, justo después)', () {
    final casos = <Duration, String>{
      Duration.zero: 'hace un momento',
      const Duration(seconds: 59): 'hace un momento',
      const Duration(seconds: 60): 'hace 1 min',
      const Duration(minutes: 59, seconds: 59): 'hace 59 min',
      const Duration(minutes: 60): 'hace 1 h',
      const Duration(hours: 23, minutes: 59): 'hace 23 h',
      const Duration(hours: 24): 'hace 1 d',
      const Duration(days: 365): 'hace 365 d',
    };
    for (final e in casos.entries) {
      test('${e.key} → «${e.value}»', () => expect(hace(e.key), e.value));
    }
  });

  group('Entradas fuera de lo normal', () {
    test('una fecha FUTURA (reloj del teléfono adelantado) se muestra como «hace un momento»', () {
      // Hallazgo de la auditoría: no se distingue de una lectura recién llegada (ver informe, WB-HALLAZGO-3).
      expect(tiempoTranscurrido(ahora.add(const Duration(hours: 5)), ahora: ahora), 'hace un momento');
    });
    test('la misma fecha y hora exactas → «hace un momento»', () {
      expect(tiempoTranscurrido(ahora, ahora: ahora), 'hace un momento');
    });
    test('un salto de horario (diferencia de 25 h) se redondea hacia abajo a 1 día', () {
      expect(hace(const Duration(hours: 25)), 'hace 1 d');
    });
    test('no lanza con fechas extremas', () {
      expect(() => tiempoTranscurrido(DateTime(1970), ahora: ahora), returnsNormally);
    });
  });
}
