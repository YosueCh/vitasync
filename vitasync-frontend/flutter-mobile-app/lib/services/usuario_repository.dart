import '../models/usuario.dart';
import 'api_cliente.dart';

/// Contrato para obtener las cuentas entre las que se elige al entrar.
abstract interface class UsuarioRepository {
  Future<List<Usuario>> listarHabilitados();
}

/// Capacidad opcional (Práctica 10): crear una cuenta VitaSync. Con la seguridad activa cada persona ve solo
/// SUS cuentas, así que una persona nueva empieza sin ninguna y necesita crear la suya.
abstract interface class CreadorDeCuentas {
  Future<Usuario> crearCuenta({required String nombreCompleto, required String username});
}

/// Implementación real: `GET /api/usuarios`, dejando solo las cuentas
/// habilitadas (las deshabilitadas no pueden entrar).
class HttpUsuarioRepository implements UsuarioRepository, CreadorDeCuentas {
  HttpUsuarioRepository({ApiCliente? api}) : _api = api ?? ApiCliente();

  final ApiCliente _api;

  @override
  Future<Usuario> crearCuenta({required String nombreCompleto, required String username}) async {
    final json = await _api.postJson('/usuarios', {
      'nombreCompleto': nombreCompleto,
      'username': username,
      'grupos': <String>[],
    });
    return Usuario.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<List<Usuario>> listarHabilitados() async {
    final lista = await _api.get('/usuarios') as List<dynamic>;
    final cuentas = lista
        .cast<Map<String, dynamic>>()
        .map(Usuario.fromJson)
        .where((u) => u.habilitado)
        .toList();
    // Orden estable y predecible (D-06): por nombre y, si empatan, por usuario. Antes salían en el orden en que
    // el servidor las devolvía, que podía cambiar entre una consulta y otra.
    cuentas.sort((a, b) {
      final porNombre = a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase());
      return porNombre != 0 ? porNombre : a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });
    return cuentas;
  }
}

class MuestraUsuarioRepository implements UsuarioRepository {
  const MuestraUsuarioRepository();

  @override
  Future<List<Usuario>> listarHabilitados() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [
      Usuario(id: 'u1', nombreCompleto: 'Ana Torres', username: 'ana', habilitado: true),
      Usuario(id: 'u2', nombreCompleto: 'Luis Pérez', username: 'luis', habilitado: true),
    ];
  }
}
