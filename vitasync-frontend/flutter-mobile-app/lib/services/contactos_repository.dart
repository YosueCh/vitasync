import '../models/contacto.dart';
import 'api_cliente.dart';

/// Contrato de los contactos de emergencia de la cuenta con sesión abierta (Actividad 1 dentro de VitaSync).
abstract interface class ContactosRepository {
  Future<List<ContactoEmergencia>> listar();

  Future<ContactoEmergencia> crear({required String nombre, required String telefono, required String relacion});

  Future<void> eliminar(String id);
}

/// Implementación real: `GET/POST /api/contactos?usuarioId=` y `DELETE /api/contactos/{id}?usuarioId=`.
/// Los datos viven en Firestore (los guarda el servidor); aquí no se guarda copia.
class HttpContactosRepository implements ContactosRepository {
  HttpContactosRepository({required this.usuarioId, ApiCliente? api}) : _api = api ?? ApiCliente();

  final String usuarioId;
  final ApiCliente _api;

  @override
  Future<List<ContactoEmergencia>> listar() async {
    final lista = await _api.get('/contactos', {'usuarioId': usuarioId}) as List<dynamic>;
    return lista.cast<Map<String, dynamic>>().map(ContactoEmergencia.fromJson).toList();
  }

  @override
  Future<ContactoEmergencia> crear({required String nombre, required String telefono, required String relacion}) async {
    final json = await _api.postJson('/contactos?usuarioId=${Uri.encodeQueryComponent(usuarioId)}', {
      'nombre': nombre,
      'telefono': telefono,
      'relacion': relacion,
    });
    return ContactoEmergencia.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<void> eliminar(String id) async {
    await _api.delete('/contactos/${Uri.encodeComponent(id)}', {'usuarioId': usuarioId});
  }
}

/// Datos de ejemplo en memoria (modo `MUESTRA`), con las mismas reglas del servidor.
class MuestraContactosRepository implements ContactosRepository {
  MuestraContactosRepository([List<ContactoEmergencia>? iniciales])
      : _contactos = [
          ...(iniciales ??
              const [ContactoEmergencia(id: 'c1', nombre: 'Mamá', telefono: '4421234567', relacion: 'Familiar')]),
        ];

  final List<ContactoEmergencia> _contactos;
  int _siguiente = 2;

  @override
  Future<List<ContactoEmergencia>> listar() async => List.of(_contactos);

  @override
  Future<ContactoEmergencia> crear({required String nombre, required String telefono, required String relacion}) async {
    final tel = ReglasContacto.normalizarTelefono(telefono);
    if (_contactos.length >= ReglasContacto.maxPorCuenta) {
      throw const ApiException('Solo se pueden guardar 5 contactos de emergencia. Elimina uno para agregar otro.');
    }
    if (_contactos.any((c) => c.telefono == tel)) throw const ApiException('Ya hay un contacto con ese teléfono.');
    final nuevo = ContactoEmergencia(id: 'c${_siguiente++}', nombre: nombre.trim(), telefono: tel, relacion: relacion);
    _contactos.add(nuevo);
    return nuevo;
  }

  @override
  Future<void> eliminar(String id) async {
    _contactos.removeWhere((c) => c.id == id);
  }
}
