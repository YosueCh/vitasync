import 'api_cliente.dart';

/// Una persona con sesión en la app y su rol (Práctica 7 dentro de VitaSync).
class PersonaRol {
  const PersonaRol({required this.uid, required this.correo, required this.rol});

  final String uid;
  final String correo;

  /// «paciente», «medico» o «admin».
  final String rol;

  bool get esAdmin => rol == 'admin';

  factory PersonaRol.fromJson(Map<String, dynamic> json) => PersonaRol(
        uid: json['uid'] as String,
        correo: json['correo'] as String? ?? '(sin correo)',
        rol: json['rol'] as String,
      );
}

/// Roles que el administrador puede repartir.
const rolesAsignables = {'paciente': 'Paciente', 'medico': 'Médico'};

/// Contrato de la gestión de roles, solo para el administrador. El servidor es quien decide: si quien pregunta no
/// es administrador responde 403 y la app muestra el mensaje.
abstract interface class RolesRepository {
  Future<List<PersonaRol>> listar();

  /// Aplica varios cambios de un solo envío (uid → rol). Si uno no cumple las reglas no se aplica ninguno.
  Future<List<PersonaRol>> asignar(Map<String, String> cambios);
}

/// Implementación real: `GET /api/admin/personas` y `PUT /api/admin/roles`.
class HttpRolesRepository implements RolesRepository {
  HttpRolesRepository({ApiCliente? api}) : _api = api ?? ApiCliente();

  final ApiCliente _api;

  @override
  Future<List<PersonaRol>> listar() async {
    final lista = await _api.get('/admin/personas') as List<dynamic>;
    return lista.cast<Map<String, dynamic>>().map(PersonaRol.fromJson).toList();
  }

  @override
  Future<List<PersonaRol>> asignar(Map<String, String> cambios) async {
    final lista = await _api.putJson('/admin/roles', {
      'cambios': [for (final e in cambios.entries) {'uid': e.key, 'rol': e.value}],
    }) as List<dynamic>;
    return lista.cast<Map<String, dynamic>>().map(PersonaRol.fromJson).toList();
  }
}

/// Datos de ejemplo con las mismas reglas del servidor.
class MuestraRolesRepository implements RolesRepository {
  MuestraRolesRepository([List<PersonaRol>? iniciales])
      : _personas = [
          ...(iniciales ??
              const [
                PersonaRol(uid: 'u0', correo: 'admin@vitasync.mx', rol: 'admin'),
                PersonaRol(uid: 'u1', correo: 'ana@vitasync.mx', rol: 'paciente'),
                PersonaRol(uid: 'u2', correo: 'luis@vitasync.mx', rol: 'paciente'),
              ]),
        ];

  final List<PersonaRol> _personas;

  @override
  Future<List<PersonaRol>> listar() async => List.of(_personas);

  @override
  Future<List<PersonaRol>> asignar(Map<String, String> cambios) async {
    if (cambios.isEmpty) throw const ApiException('Indica al menos un cambio de rol.');
    for (final e in cambios.entries) {
      if (!rolesAsignables.containsKey(e.value)) throw ApiException('Rol no permitido: «${e.value}».');
      final i = _personas.indexWhere((p) => p.uid == e.key);
      if (i < 0) throw ApiException('No existe la persona ${e.key}.');
      if (_personas[i].esAdmin) throw const ApiException('No se puede cambiar el rol de un administrador.');
    }
    final nuevas = <PersonaRol>[];
    for (final e in cambios.entries) {
      final i = _personas.indexWhere((p) => p.uid == e.key);
      _personas[i] = PersonaRol(uid: e.key, correo: _personas[i].correo, rol: e.value);
      nuevas.add(_personas[i]);
    }
    return nuevas;
  }
}
