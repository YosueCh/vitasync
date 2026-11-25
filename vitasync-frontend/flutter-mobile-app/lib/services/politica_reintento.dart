import 'dart:math';

/// PRÁCTICA 12 · Fase 5 (reto) · Reintento controlado con espera progresiva (exponential backoff).
///
/// Cuando una solicitud falla porque no se alcanzó el servidor (red, tiempo agotado) o porque este contestó 502/504,
/// se vuelve a intentar esperando cada vez más: [esperaBase] · [factor]^intento, con un tope ([esperaMaxima]) y un poco
/// de azar ([jitter]) para que muchos móviles que se reconectan a la vez no golpeen al servidor en el mismo instante.
///
/// Solo se reintentan operaciones SEGURAS de repetir: lecturas (GET) y escrituras marcadas como idempotentes
/// (llevan un identificador que el servidor usa para no guardar dos veces lo mismo).
class PoliticaReintento {
  const PoliticaReintento({
    this.maxReintentos = 0,
    this.esperaBase = const Duration(milliseconds: 300),
    this.factor = 2.0,
    this.esperaMaxima = const Duration(seconds: 3),
    this.jitter = 0.2,
  })  : assert(maxReintentos >= 0),
        assert(factor >= 1),
        assert(jitter >= 0 && jitter <= 1);

  /// Sin reintentos: comportamiento anterior a la Práctica 12 (y el que usan las pruebas que no lo necesitan).
  static const PoliticaReintento ninguna = PoliticaReintento();

  /// La que usa la app: hasta 2 reintentos (esperas ≈ 0,3 s y 0,6 s). Con el tiempo límite de 4 s por intento, un
  /// servidor que no contesta bloquea como máximo 3 × 4 s + 0,9 s ≈ 13 s antes de mostrar el error.
  static const PoliticaReintento estandar = PoliticaReintento(maxReintentos: 2);

  final int maxReintentos;
  final Duration esperaBase;
  final double factor;
  final Duration esperaMaxima;

  /// Fracción de la espera que se varía al azar (0,2 = ±20 %).
  final double jitter;

  /// Espera antes del reintento número [intento] (0 = antes del primer reintento).
  Duration espera(int intento, [Random? azar]) {
    final bruta = esperaBase.inMilliseconds * pow(factor, intento);
    final tope = min(bruta, esperaMaxima.inMilliseconds.toDouble());
    if (jitter == 0) return Duration(milliseconds: tope.round());
    final variacion = ((azar ?? _azar).nextDouble() * 2 - 1) * jitter; // -jitter … +jitter
    return Duration(milliseconds: max(0, (tope * (1 + variacion)).round()));
  }

  static final Random _azar = Random();
}
