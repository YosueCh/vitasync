/// Rol de quien usa el chat (Práctica 6): el médico es el Dispositivo A y el
/// paciente, el Dispositivo B.
enum RolChat {
  medico('MEDICO', 'Médico', 'Dispositivo A'),
  paciente('PACIENTE', 'Paciente', 'Dispositivo B');

  const RolChat(this.api, this.nombre, this.dispositivo);

  /// Valor que viaja al backend (`ChatService.java`).
  final String api;
  final String nombre;
  final String dispositivo;

  RolChat get otro => this == medico ? paciente : medico;

  static RolChat desdeApi(String valor) =>
      RolChat.values.firstWhere((r) => r.api == valor);
}

/// Mensaje de la conversación, en el formato de `MensajeChatDTO.java`.
class MensajeChat {
  const MensajeChat({
    required this.id,
    required this.emisor,
    required this.texto,
    required this.hora,
  });

  final int id;
  final RolChat emisor;
  final String texto;

  /// Hora de envío, la pone el servidor (se muestra en hora local).
  final DateTime hora;

  factory MensajeChat.fromJson(Map<String, dynamic> json) {
    return MensajeChat(
      id: json['id'] as int,
      emisor: RolChat.desdeApi(json['emisor'] as String),
      texto: json['texto'] as String,
      hora: DateTime.parse(json['hora'] as String).toLocal(),
    );
  }
}

/// Respuesta de consultar la conversación (`ConversacionDTO.java`).
class ConversacionChat {
  const ConversacionChat({required this.cerrado, required this.mensajes});

  /// true si el paciente cerró el chat (el historial ya se borró).
  final bool cerrado;
  final List<MensajeChat> mensajes;

  factory ConversacionChat.fromJson(Map<String, dynamic> json) {
    return ConversacionChat(
      cerrado: json['cerrado'] as bool? ?? false,
      mensajes: (json['mensajes'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MensajeChat.fromJson)
          .toList(),
    );
  }
}
