import 'package:flutter/foundation.dart' show kIsWeb;

/// Configuración de acceso al backend de VitaSync.
///
/// La vista móvil se abre desde el teléfono, donde "localhost" es el propio
/// teléfono y no la PC que corre el backend. Por eso el host de la API:
///
/// - En la web (PWA) se toma de la dirección con la que se cargó la página
///   (`Uri.base.host`).
/// - Como app Android no hay página de la que tomarlo: se usa `10.0.2.2`, el
///   alias con el que el emulador ve a la PC. En un teléfono físico se indica
///   la IP de la PC con `--dart-define=API_HOST=192.168.x.x`.
class ApiConfig {
  ApiConfig._();

  /// Puerto del backend. Por omisión 8081; se cambia con --dart-define=API_PORT=8082 (p. ej. para probar otra copia).
  static const int puertoBackend = int.fromEnvironment('API_PORT', defaultValue: 8081);
  static const Duration intervaloSondeo = Duration(seconds: 3);

  /// Cada cuánto el chat pide mensajes nuevos al backend (Práctica 6).
  static const Duration intervaloChat = Duration(seconds: 2);
  static const Duration tiempoLimite = Duration(seconds: 4);

  /// Sin tocar la pantalla este tiempo, la sesión se cierra (igual que el reloj).
  static const Duration tiempoInactividad = Duration(seconds: 45);

  /// Host del backend cuando la app no corre en un navegador.
  static const String hostApp = String.fromEnvironment(
    'API_HOST',
    defaultValue: '10.0.2.2',
  );

  /// Práctica 10: con `--dart-define=SEGURIDAD=true` la app pide correo y contraseña (Firebase Authentication)
  /// y manda el token al backend. Debe coincidir con vitasync.seguridad.activa del servidor.
  static const bool seguridadActiva = bool.fromEnvironment('SEGURIDAD');

  /// Clave web de Firebase (solo para la nube real; el emulador acepta cualquiera).
  static const String firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'clave-local');

  /// Servicio de Authentication. Por omisión, el emulador local (puerto 9099) de la misma máquina que el
  /// backend. Con la nube real: --dart-define=AUTH_BASE=https://identitytoolkit.googleapis.com
  static String get authBase => const String.fromEnvironment('AUTH_BASE').isNotEmpty
      ? const String.fromEnvironment('AUTH_BASE')
      : 'http://${kIsWeb ? Uri.base.host : hostApp}:9099/identitytoolkit.googleapis.com';

  static String baseUrlPara(String host) => 'http://$host:$puertoBackend/api';

  static String get baseUrl => baseUrlPara(kIsWeb ? Uri.base.host : hostApp);
}
