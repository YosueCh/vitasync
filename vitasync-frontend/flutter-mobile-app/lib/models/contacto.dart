/// Contacto de emergencia de una cuenta, en el formato de `ContactoDTO.java` (`GET /api/contactos`).
class ContactoEmergencia {
  const ContactoEmergencia({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.relacion,
  });

  final String id;
  final String nombre;

  /// Solo dígitos, con «+» al inicio si lo llevaba (el servidor quita espacios, guiones y paréntesis).
  final String telefono;
  final String relacion;

  factory ContactoEmergencia.fromJson(Map<String, dynamic> json) {
    return ContactoEmergencia(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      telefono: json['telefono'] as String,
      relacion: json['relacion'] as String? ?? 'Otro',
    );
  }
}

/// Reglas de los contactos. Son las MISMAS que valida el servidor (ContactoService): la app las revisa primero
/// para avisar sin esperar la red, pero la autoridad es el servidor.
class ReglasContacto {
  ReglasContacto._();

  static const int maxPorCuenta = 5;
  static const List<String> relaciones = ['Familiar', 'Médico', 'Amigo', 'Otro'];
  static final RegExp _separadores = RegExp(r'[\s().-]');
  static final RegExp _telefono = RegExp(r'^\+?[0-9]{7,15}$');

  static String normalizarTelefono(String texto) => texto.replaceAll(_separadores, '');

  /// Un mensaje por campo con error; vacío si todo está bien.
  static Map<String, String> validar(String nombre, String telefono) {
    final errores = <String, String>{};
    final n = nombre.trim();
    if (n.length < 2 || n.length > 60) errores['nombre'] = 'El nombre es obligatorio (2 a 60 caracteres).';
    if (!_telefono.hasMatch(normalizarTelefono(telefono))) {
      errores['telefono'] = 'El teléfono debe tener de 7 a 15 dígitos (puede empezar con +).';
    }
    return errores;
  }
}
