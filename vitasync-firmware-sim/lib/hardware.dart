/// Estados del LED (Práctica 1): en la placa real era un LED en el GPIO 22;
/// aquí se dibuja en la consola.
enum Led {
  apagado('⚫', 'apagado'),
  verde('🟢', 'conectado'),
  amarillo('🟡', 'sincronizando'),
  rojo('🔴', 'error');

  const Led(this.icono, this.significado);

  final String icono;
  final String significado;
}

/// Lo que el firmware "toca" del dispositivo. En la Práctica 1/2 eran los
/// pines del ESP32 (`digitalRead`, `digitalWrite`, `Serial.println`); aquí
/// se abstrae para poder simularlo en consola o probarlo sin teclado.
abstract interface class Hardware {
  /// Botón de sincronizar. true mientras está presionado (como `digitalRead(BOTON) == LOW`).
  bool leerBoton();

  /// Sensor de presencia: true si el reloj está puesto (el sensor IR de la Práctica 2).
  bool leerRelojPuesto();

  /// Enciende el LED en ese estado (`digitalWrite(LED, ...)`).
  void escribirLed(Led estado);

  /// Monitor serial (`Serial.println`).
  void imprimir(String mensaje);
}
