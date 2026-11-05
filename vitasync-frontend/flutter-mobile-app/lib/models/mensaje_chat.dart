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

/// Archivo adjunto de un mensaje (Práctica 7). El contenido se descarga aparte.
class ArchivoAdjunto {
  const ArchivoAdjunto({required this.nombre, required this.tipo, required this.tamano});

  final String nombre;
  final String tipo;
  final int tamano;

  factory ArchivoAdjunto.fromJson(Map<String, dynamic> json) => ArchivoAdjunto(
        nombre: json['nombre'] as String,
        tipo: json['tipo'] as String,
        tamano: (json['tamano'] as num).toInt(),
      );

  bool get esImagen => tipo.startsWith('image/');
  bool get esTexto => tipo == 'text/plain';
}

/// Reglas de los archivos del chat (el servidor las repite).
class ReglasArchivo {
  static const maxBytes = 300 * 1024;
  static const tipos = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
  };

  /// El tipo según la extensión, o null si no se permite.
  static String? tipoDe(String nombre) {
    final punto = nombre.lastIndexOf('.');
    if (punto < 0) return null;
    return tipos[nombre.substring(punto + 1).toLowerCase()];
  }

  /// Mensaje de error si el archivo no se puede enviar, o null si está bien.
  static String? validar(String nombre, int bytes) {
    if (tipoDe(nombre) == null) return 'Solo se pueden enviar PNG, JPG, PDF o TXT.';
    if (bytes == 0) return 'El archivo está vacío.';
    if (bytes > maxBytes) return 'El archivo no puede pasar de ${maxBytes ~/ 1024} KB.';
    return null;
  }
}

/// Mensaje de la conversación, en el formato de `MensajeChatDTO.java`.
class MensajeChat {
  const MensajeChat({
    required this.id,
    required this.emisor,
    required this.texto,
    required this.hora,
    this.archivo,
  });

  final int id;
  final RolChat emisor;
  final String texto;

  /// Hora de envío, la pone el servidor (se muestra en hora local).
  final DateTime hora;

  /// Archivo adjunto, o null si es un mensaje de texto.
  final ArchivoAdjunto? archivo;

  factory MensajeChat.fromJson(Map<String, dynamic> json) {
    return MensajeChat(
      id: json['id'] as int,
      emisor: RolChat.desdeApi(json['emisor'] as String),
      texto: json['texto'] as String,
      hora: DateTime.parse(json['hora'] as String).toLocal(),
      archivo: json['archivo'] is Map<String, dynamic>
          ? ArchivoAdjunto.fromJson(json['archivo'] as Map<String, dynamic>)
          : null,
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
