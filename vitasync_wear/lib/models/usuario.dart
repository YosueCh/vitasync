/// Cuenta de VitaSync, en el mismo formato que expone
/// `vitasync-backend` en `GET /api/usuarios` (mismo listado que
/// administra la pantalla "Gestión de Usuarios" del sitio web).
class Usuario {
  final String id;
  final String nombreCompleto;
  final String username;
  final bool habilitado;

  const Usuario({
    required this.id,
    required this.nombreCompleto,
    required this.username,
    required this.habilitado,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as String,
      nombreCompleto: json['nombreCompleto'] as String,
      username: json['username'] as String,
      habilitado: json['habilitado'] as bool? ?? true,
    );
  }
}
