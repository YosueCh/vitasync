/// Cuenta de VitaSync, en el formato de `UsuarioDTO.java`
/// (`GET /api/usuarios`, el mismo listado de "Gestión de Usuarios" en la web).
class Usuario {
  const Usuario({
    required this.id,
    required this.nombreCompleto,
    required this.username,
    required this.habilitado,
    this.tienePin = true,
  });

  final String id;
  final String nombreCompleto;
  final String username;
  final bool habilitado;

  /// false si la cuenta aún no registró su PIN: la app le pide crearlo en
  /// lugar de pedírselo. Si el servidor no lo informa, se asume que sí tiene.
  final bool tienePin;

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as String,
      nombreCompleto: json['nombreCompleto'] as String,
      username: json['username'] as String,
      habilitado: json['habilitado'] as bool? ?? true,
      tienePin: json['tienePin'] as bool? ?? true,
    );
  }
}
