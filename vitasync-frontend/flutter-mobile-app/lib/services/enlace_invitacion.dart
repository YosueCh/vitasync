import 'package:flutter/foundation.dart';

/// Práctica 7 (cierre): el enlace de invitación abre la app con el código ya escrito.
///
/// Dos formas del mismo enlace:
///   · Android:  `vitasync://invitacion?codigo=ABCD1234`   (esquema propio registrado en AndroidManifest.xml)
///   · Web/PWA:  `https://<sitio>/movil/#/invitacion?codigo=ABCD1234`
/// En ambos casos Flutter entrega a la app la «ruta» `/invitacion?codigo=ABCD1234`, que este analizador convierte en código.
class EnlaceInvitacion {
  EnlaceInvitacion._();

  static const String esquema = 'vitasync';
  static final RegExp _codigoValido = RegExp(r'^[A-Z0-9]{8}$');

  /// Enlace para Android que se comparte junto con el código.
  static String paraApp(String codigo) => '$esquema://invitacion?codigo=$codigo';

  /// Enlace para el navegador, a partir de la dirección donde se sirve la vista móvil (p. ej. `https://vitasync.mx`).
  static String paraWeb(String sitio, String codigo) =>
      '${sitio.replaceAll(RegExp(r'/+$'), '')}/movil/#/invitacion?codigo=$codigo';

  /// El código de 8 letras o números que lleva una ruta o un enlace completo, en mayúsculas; null si no es un enlace
  /// de invitación o el código no tiene el formato que acepta el servidor.
  static String? codigoDe(String? ruta) {
    if (ruta == null || ruta.trim().isEmpty) return null;
    Uri uri;
    try {
      uri = Uri.parse(ruta.trim());
    } on FormatException {
      return null;
    }
    // «vitasync://invitacion?...» pone «invitacion» como host; «/invitacion?...» como ruta.
    final destino = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
    if (destino != 'invitacion') return null;
    final codigo = uri.queryParameters['codigo']?.trim().toUpperCase();
    return codigo != null && _codigoValido.hasMatch(codigo) ? codigo : null;
  }
}

/// Código de invitación que llegó por un enlace y todavía no se canjea. La puerta de acceso lo recibe (aunque la persona aún
/// no haya entrado) y la pantalla principal lo consume una sola vez.
class InvitacionPendiente extends ValueNotifier<String?> {
  InvitacionPendiente([super.codigo]);

  /// Registra el enlace que llegó (ignora los que no son de invitación).
  void recibir(String? ruta) {
    final c = EnlaceInvitacion.codigoDe(ruta);
    if (c != null) value = c;
  }

  /// Entrega el código una sola vez.
  String? consumir() {
    final c = value;
    value = null;
    return c;
  }
}
