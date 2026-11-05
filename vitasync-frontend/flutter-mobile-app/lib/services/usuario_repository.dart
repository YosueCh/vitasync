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
    return lista
        .cast<Map<String, dynamic>>()
        .map(Usuario.fromJson)
        .where((u) => u.habilitado)
        .toList();
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
