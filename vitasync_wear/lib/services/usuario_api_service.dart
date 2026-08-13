import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/usuario.dart';

/// Cliente HTTP hacia `vitasync-backend` (`GET /api/usuarios`) — el
/// mismo listado de cuentas que administra "Gestión de Usuarios" en el
/// sitio web (Práctica 13). Se usa para que, al entrar al reloj, se
/// elija de cuál cuenta son los datos de salud que va a mostrar/
/// sincronizar, en vez de compartir un solo dispositivo global.
class UsuarioApiService {
  static const _timeout = Duration(seconds: 4);
  static const _puerto = 8081;

  String get _host {
    if (kIsWeb) return 'localhost';
    return Platform.isAndroid ? '10.0.2.2' : 'localhost';
  }

  Future<List<Usuario>> listar() async {
    try {
      final resp = await http
          .get(Uri.parse('http://$_host:$_puerto/api/usuarios'))
          .timeout(_timeout);
      if (resp.statusCode == 200) {
        final lista = jsonDecode(resp.body) as List<dynamic>;
        return lista
            .map((e) => Usuario.fromJson(e as Map<String, dynamic>))
            .where((u) => u.habilitado)
            .toList();
      }
    } catch (_) {
      // Backend no disponible: la pantalla que llama esto muestra el error.
    }
    return [];
  }
}
