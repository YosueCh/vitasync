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

/// Invitación de un solo uso con el rol ya asignado.
class InvitacionRol {
  const InvitacionRol({required this.codigo, required this.rol, required this.venceEn, this.usada = false});

  final String codigo;
  final String rol;
  final DateTime venceEn;
  final bool usada;

  factory InvitacionRol.fromJson(Map<String, dynamic> json) => InvitacionRol(
        codigo: json['codigo'] as String,
        rol: json['rol'] as String,
        venceEn: DateTime.fromMillisecondsSinceEpoch((json['venceEn'] as num).toInt()),
        usada: json['usadaPor'] != null,
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

  /// El administrador genera un código de un solo uso que concede [rol] (caduca a los 7 días).
  Future<InvitacionRol> crearInvitacion(String rol);

  Future<List<InvitacionRol>> listarInvitaciones();

  /// Cualquier persona con sesión canjea un código y recibe su rol. Devuelve el rol asignado.
  Future<String> canjear(String codigo);
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

  @override
  Future<InvitacionRol> crearInvitacion(String rol) async =>
      InvitacionRol.fromJson(await _api.postJson('/admin/invitaciones', {'rol': rol}) as Map<String, dynamic>);

  @override
  Future<List<InvitacionRol>> listarInvitaciones() async {
    final lista = await _api.get('/admin/invitaciones') as List<dynamic>;
    return lista.cast<Map<String, dynamic>>().map(InvitacionRol.fromJson).toList();
  }

  @override
  Future<String> canjear(String codigo) async {
    final json = await _api.postJson('/invitaciones/canjear', {'codigo': codigo}) as Map<String, dynamic>;
    return json['rol'] as String;
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
  final List<(InvitacionRol, bool)> _invitaciones = [];
  int _n = 0;

  @override
  Future<InvitacionRol> crearInvitacion(String rol) async {
    if (!rolesAsignables.containsKey(rol)) throw const ApiException('Rol no permitido. Solo paciente o medico.');
    final i = InvitacionRol(
        codigo: 'MUESTRA${++_n}', rol: rol, venceEn: DateTime.now().add(const Duration(days: 7)));
    _invitaciones.add((i, false));
    return i;
  }

  @override
  Future<List<InvitacionRol>> listarInvitaciones() async => [
        for (final (i, usada) in _invitaciones)
          InvitacionRol(codigo: i.codigo, rol: i.rol, venceEn: i.venceEn, usada: usada),
      ];

  @override
  Future<String> canjear(String codigo) async {
    final k = _invitaciones.indexWhere((e) => e.$1.codigo == codigo.trim().toUpperCase());
    if (k < 0) throw const ApiException('Ese código no existe.');
    if (_invitaciones[k].$2) throw const ApiException('Ese código ya se usó.');
    _invitaciones[k] = (_invitaciones[k].$1, true);
    return _invitaciones[k].$1.rol;
  }

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
