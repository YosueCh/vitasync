import '../models/mensaje_chat.dart';
import 'api_cliente.dart';

/// Contrato del chat médico-paciente (Práctica 6). Los dos teléfonos no se
/// conectan entre sí: ambos hablan con el backend, que guarda la conversación
/// hasta que el paciente cierra el chat.
abstract interface class ChatRepository {
  /// Mensajes con id mayor a [desde] (0 = todos) y si el chat está cerrado.
  Future<ConversacionChat> consultar(String pacienteId, {int desde = 0});

  Future<void> enviar(String pacienteId, RolChat emisor, String texto);

  /// El paciente cierra el chat: el servidor borra el historial.
  Future<void> cerrar(String pacienteId);

  /// Abre un chat nuevo después de haberlo cerrado.
  Future<void> abrir(String pacienteId);
}

/// Implementación real: `/api/chat/{pacienteId}/...` del backend.
class HttpChatRepository implements ChatRepository {
  HttpChatRepository({ApiCliente? api}) : _api = api ?? ApiCliente();

  final ApiCliente _api;

  String _ruta(String pacienteId, String accion) =>
      '/chat/${Uri.encodeComponent(pacienteId)}/$accion';

  @override
  Future<ConversacionChat> consultar(String pacienteId, {int desde = 0}) async {
    final json = await _api.get(_ruta(pacienteId, 'mensajes'), {'desde': '$desde'})
        as Map<String, dynamic>;
    return ConversacionChat.fromJson(json);
  }

  @override
  Future<void> enviar(String pacienteId, RolChat emisor, String texto) async {
    await _api.postJson(
      _ruta(pacienteId, 'mensajes'),
      {'emisor': emisor.api, 'texto': texto},
    );
  }

  @override
  Future<void> cerrar(String pacienteId) async {
    await _api.post(_ruta(pacienteId, 'cerrar'));
  }

  @override
  Future<void> abrir(String pacienteId) async {
    await _api.post(_ruta(pacienteId, 'abrir'));
  }
}

/// Servidor de chat en memoria, para el modo de muestra y las pruebas. Imita
/// las reglas del backend (ids consecutivos, chat cerrado, historial borrado).
class MuestraChatRepository implements ChatRepository {
  final Map<String, List<MensajeChat>> _mensajes = {};
  final Map<String, bool> _cerrado = {};
  int _siguienteId = 1;

  @override
  Future<ConversacionChat> consultar(String pacienteId, {int desde = 0}) async {
    final nuevos =
        (_mensajes[pacienteId] ?? const []).where((m) => m.id > desde).toList();
    return ConversacionChat(cerrado: _cerrado[pacienteId] ?? false, mensajes: nuevos);
  }

  @override
  Future<void> enviar(String pacienteId, RolChat emisor, String texto) async {
    if (_cerrado[pacienteId] ?? false) {
      throw const ApiException('El paciente cerró el chat.');
    }
    (_mensajes[pacienteId] ??= []).add(MensajeChat(
      id: _siguienteId++,
      emisor: emisor,
      texto: texto,
      hora: DateTime.now(),
    ));
  }

  @override
  Future<void> cerrar(String pacienteId) async {
    _mensajes[pacienteId]?.clear();
    _cerrado[pacienteId] = true;
  }

  @override
  Future<void> abrir(String pacienteId) async {
    _mensajes[pacienteId]?.clear();
    _cerrado[pacienteId] = false;
  }
}
