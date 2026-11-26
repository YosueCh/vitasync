import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dónde está el backend y con qué clave se identifica ESTE reloj (rúbrica D: compatibilidad con un reloj físico).
///
/// Antes la dirección estaba fija en `10.0.2.2`, que solo existe dentro del emulador de Android. Un reloj real, en la misma red
/// Wi-Fi que la PC, necesita la IP de la PC (p. ej. 192.168.1.50); la clave de dispositivo la entrega la app del celular al
/// vincular el reloj (con la seguridad encendida el backend responde 401 sin ella).
///
/// Orden de valores: lo guardado en el reloj → `--dart-define` de la compilación → valores del emulador.
class ConfiguracionServidor {
  ConfiguracionServidor({required this.host, required this.puerto, required this.clave});

  static const String hostPorOmision = String.fromEnvironment('API_HOST', defaultValue: '10.0.2.2');
  static const int puertoPorOmision = int.fromEnvironment('API_PORT', defaultValue: 8081);
  static const String clavePorOmision = String.fromEnvironment('CLAVE_DISPOSITIVO');

  final String host;
  final int puerto;
  final String clave;

  /// Base de las rutas del reloj.
  String get base => 'http://$host:$puerto/api/smartwatch';
  bool get tieneClave => clave.isNotEmpty;

  ConfiguracionServidor copiar({String? host, int? puerto, String? clave}) =>
      ConfiguracionServidor(host: host ?? this.host, puerto: puerto ?? this.puerto, clave: clave ?? this.clave);

  static ConfiguracionServidor predeterminada() =>
      ConfiguracionServidor(host: hostPorOmision, puerto: puertoPorOmision, clave: clavePorOmision);

  /// Un host válido es un nombre o una IP sin esquema, sin ruta y sin espacios; el puerto, de 1 a 65535.
  static String? validar(String host, String puerto) {
    final h = host.trim();
    if (h.isEmpty) return 'Escribe la dirección del servidor.';
    if (RegExp(r'[\s/:@]').hasMatch(h)) return 'Solo la IP o el nombre, sin http:// ni puerto.';
    final p = int.tryParse(puerto.trim());
    if (p == null || p < 1 || p > 65535) return 'El puerto va de 1 a 65535.';
    return null;
  }
}

/// Dónde se guarda la configuración. En el reloj es el almacén seguro del sistema (la clave de dispositivo es un secreto).
abstract interface class AlmacenConfiguracion {
  Future<ConfiguracionServidor> cargar();
  Future<void> guardar(ConfiguracionServidor c);
}

class AlmacenSeguro implements AlmacenConfiguracion {
  AlmacenSeguro([FlutterSecureStorage? almacen]) : _a = almacen ?? const FlutterSecureStorage();
  final FlutterSecureStorage _a;

  @override
  Future<ConfiguracionServidor> cargar() async {
    final base = ConfiguracionServidor.predeterminada();
    try {
      final h = await _a.read(key: 'srv_host');
      final p = int.tryParse(await _a.read(key: 'srv_puerto') ?? '');
      final c = await _a.read(key: 'srv_clave');
      return base.copiar(host: (h == null || h.isEmpty) ? null : h, puerto: p, clave: c);
    } on Object {
      return base; // sin almacén (pruebas, web): valores por omisión
    }
  }

  @override
  Future<void> guardar(ConfiguracionServidor c) async {
    await _a.write(key: 'srv_host', value: c.host);
    await _a.write(key: 'srv_puerto', value: '${c.puerto}');
    await _a.write(key: 'srv_clave', value: c.clave);
  }
}

/// En memoria, para pruebas.
class AlmacenEnMemoria implements AlmacenConfiguracion {
  AlmacenEnMemoria([ConfiguracionServidor? inicial]) : _c = inicial ?? ConfiguracionServidor.predeterminada();
  ConfiguracionServidor _c;
  @override
  Future<ConfiguracionServidor> cargar() async => _c;
  @override
  Future<void> guardar(ConfiguracionServidor c) async => _c = c;
}
