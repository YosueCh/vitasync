import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/mensaje_chat.dart';
import '../models/usuario.dart';
import '../services/api_cliente.dart';
import '../services/chat_repository.dart';
import '../services/metas_repository.dart';
import '../services/selector_archivo.dart';
import '../services/usuario_repository.dart';
import 'metas_screen.dart';

/// Máximo de caracteres por mensaje (el backend aplica el mismo límite).
const int maxCaracteresMensaje = 200;

/// Chat médico-paciente (Práctica 6).
///
/// Dos teléfonos con la misma app: uno entra como **Médico (Dispositivo A)** y
/// elige a qué paciente atender; el otro entra como **Paciente
/// (Dispositivo B)** con su propia cuenta. Ambos hablan con el backend (la URL
/// asignada), que guarda la conversación hasta que el paciente cierra el chat.
///
/// Los mensajes nuevos se piden al servidor cada [intervalo] (sondeo); solo
/// llegan los de id mayor al último recibido.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.cuenta,
    required this.chat,
    required this.usuarios,
    this.intervalo,
    this.metasDe,
    this.elegirArchivo = elegirArchivoDelSistema,
  });

  /// Cómo se elige un archivo para adjuntar (Práctica 7). Las pruebas pasan uno falso.
  final Future<ArchivoElegido?> Function() elegirArchivo;

  /// Cuenta con la que se inició sesión. Como paciente, su id es la conversación.
  final Usuario cuenta;
  final ChatRepository chat;
  final UsuarioRepository usuarios;

  /// Cada cuánto se consultan mensajes nuevos. null desactiva el sondeo.
  final Duration? intervalo;

  /// Metas de una cuenta (Práctica 9): el médico puede fijarlas al paciente que atiende.
  final MetasRepository Function(String cuentaId, {bool medico})? metasDe;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controlador = TextEditingController();
  final _scroll = ScrollController();

  RolChat? _rol;
  String? _pacienteId;
  List<Usuario> _pacientes = const [];
  String? _errorPacientes;

  final List<MensajeChat> _mensajes = [];
  int _ultimoId = 0;
  bool _cerrado = false;
  bool _sinConexion = false;
  bool _enviando = false;

  /// Mensajes que no se pudieron enviar por falta de conexión: se muestran como PENDIENTES y se reenvían solos
  /// al volver el servidor (nunca se dan por enviados hasta que el servidor los confirma).
  final List<_Pendiente> _pendientes = [];
  bool _consultando = false;
  String? _errorTexto;
  Timer? _sondeo;

  @override
  void dispose() {
    _sondeo?.cancel();
    _controlador.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- rol

  Future<void> _elegirRol(RolChat rol) async {
    if (_rol == rol) return;
    _sondeo?.cancel();
    setState(() {
      _rol = rol;
      _pacienteId = rol == RolChat.paciente ? widget.cuenta.id : null;
      _reiniciarLocal();
    });
    if (rol == RolChat.medico) {
      await _cargarPacientes();
    } else {
      _iniciarConsulta();
    }
  }

  void _reiniciarLocal() {
    _mensajes.clear();
    _ultimoId = 0;
    _cerrado = false;
    _sinConexion = false;
    _errorTexto = null;
  }

  Future<void> _cargarPacientes() async {
    try {
      final lista = await widget.usuarios.listarHabilitados();
      if (!mounted) return;
      setState(() {
        _pacientes = lista.where((u) => u.id != widget.cuenta.id).toList();
        _errorPacientes = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorPacientes = e.mensaje);
    }
  }

  void _elegirPaciente(String? id) {
    if (id == null) return;
    _sondeo?.cancel();
    setState(() {
      _pacienteId = id;
      _reiniciarLocal();
    });
    _iniciarConsulta();
  }

  // ------------------------------------------------------------ sondeo

  void _iniciarConsulta() {
    _actualizar();
    final intervalo = widget.intervalo;
    if (intervalo != null) {
      _sondeo = Timer.periodic(intervalo, (_) => _actualizar());
    }
  }

  /// Pide al servidor los mensajes posteriores al último recibido.
  Future<void> _actualizar() async {
    final pacienteId = _pacienteId;
    final rol = _rol;
    if (pacienteId == null || rol == null || _consultando) return;
    _consultando = true;
    try {
      await _reenviarPendientes();
      final r = await widget.chat.consultar(pacienteId, desde: _ultimoId);
      // El rol o el paciente pudieron cambiar mientras llegaba la respuesta.
      if (!mounted || pacienteId != _pacienteId || rol != _rol) return;

      final delOtro = r.mensajes.where((m) => m.emisor != rol).toList();
      final habiaCerrado = _cerrado;
      setState(() {
        _sinConexion = false;
        _cerrado = r.cerrado;
        if (r.cerrado) {
          // El paciente cerró el chat: el servidor ya borró el historial.
          _mensajes.clear();
        }
        for (final m in r.mensajes) {
          if (m.id > _ultimoId) {
            _mensajes.add(m);
            _ultimoId = m.id;
          }
        }
      });
      _bajarAlFinal();
      if (delOtro.isNotEmpty) {
        _avisar('Nuevo mensaje de ${delOtro.last.emisor.dispositivo}');
      }
      if (r.cerrado && !habiaCerrado && rol == RolChat.medico) {
        _avisar('El paciente cerró el chat');
      }
    } on ApiException {
      if (mounted) setState(() => _sinConexion = true);
    } finally {
      _consultando = false;
    }
  }

  /// Reintenta, en orden, los mensajes que quedaron pendientes. Si sigue sin conexión se detiene.
  Future<void> _reenviarPendientes() async {
    while (_pendientes.isNotEmpty) {
      final p = _pendientes.first;
      try {
        await widget.chat.enviar(p.pacienteId, p.rol, p.texto);
        if (mounted) setState(() => _pendientes.removeAt(0));
        _avisar('Mensaje pendiente enviado: ya lo confirmó el servidor');
      } on ApiException catch (e) {
        if (e.sinConexion) return;
        // El servidor respondió y lo rechazó (p. ej. el chat ya se cerró): reintentar no sirve.
        if (mounted) setState(() => _pendientes.removeAt(0));
        _avisar('No se pudo enviar un mensaje pendiente: ${e.mensaje}');
      }
    }
  }

  void _bajarAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ---------------------------------------------------------- acciones

  void _avisar(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _enviar() async {
    final rol = _rol;
    final pacienteId = _pacienteId;
    if (rol == null || pacienteId == null || _enviando) return;

    // Validación: no se envían mensajes vacíos ni formados solo por espacios.
    final texto = _controlador.text.trim();
    if (texto.isEmpty) {
      setState(() => _errorTexto = 'El mensaje no puede estar vacío.');
      return;
    }
    if (texto.length > maxCaracteresMensaje) {
      setState(() => _errorTexto = 'Máximo $maxCaracteresMensaje caracteres.');
      return;
    }

    setState(() {
      _errorTexto = null;
      _enviando = true;
    });
    try {
      await widget.chat.enviar(pacienteId, rol, texto);
      if (!mounted) return;
      _controlador.clear();
      _avisar('Mensaje enviado: ${rol.dispositivo} → ${rol.otro.dispositivo}');
      await _actualizar();
    } on ApiException catch (e) {
      if (e.sinConexion) {
        // Sin conexión: el mensaje NO se pierde ni se da por enviado; queda pendiente.
        if (mounted) {
          _controlador.clear();
          setState(() => _pendientes.add(_Pendiente(rol, pacienteId, texto, DateTime.now())));
          _avisar('Sin conexión: el mensaje quedó PENDIENTE y se enviará al reconectar');
          _bajarAlFinal();
        }
      } else {
        _avisar(e.mensaje);
        // Puede que el paciente haya cerrado el chat justo ahora.
        await _actualizar();
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Adjunta un archivo: se revisa tipo y tamaño aquí y el servidor lo vuelve a revisar (incluido el contenido).
  Future<void> _adjuntar() async {
    final rol = _rol;
    final pacienteId = _pacienteId;
    if (rol == null || pacienteId == null || _enviando) return;
    final ArchivoElegido? archivo;
    try {
      archivo = await widget.elegirArchivo();
    } on Exception {
      _avisar('No se pudo abrir el selector de archivos.');
      return;
    }
    if (archivo == null || !mounted) return;
    final error = ReglasArchivo.validar(archivo.nombre, archivo.bytes.length);
    if (error != null) {
      _avisar(error);
      return;
    }
    setState(() => _enviando = true);
    try {
      await widget.chat.enviarArchivo(pacienteId, rol,
          nombre: archivo.nombre, tipo: ReglasArchivo.tipoDe(archivo.nombre)!, bytes: archivo.bytes);
      if (!mounted) return;
      _avisar('Archivo enviado: ${archivo.nombre}');
      await _actualizar();
    } on ApiException catch (e) {
      // Un archivo no se deja «pendiente»: sin conexión se avisa y se vuelve a elegir (es mucho más pesado que un texto).
      _avisar(e.sinConexion ? 'Sin conexión: el archivo no se envió. Inténtalo de nuevo.' : e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Descarga un archivo del chat y lo muestra: imagen y texto dentro de la app; el PDF solo se comprueba.
  Future<void> _abrirArchivo(MensajeChat m) async {
    final pacienteId = _pacienteId;
    final adjunto = m.archivo;
    if (pacienteId == null || adjunto == null) return;
    final Uint8List bytes;
    try {
      bytes = await widget.chat.descargar(pacienteId, m.id);
    } on ApiException catch (e) {
      _avisar(e.mensaje);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        key: const Key('visor-archivo'),
        title: Text(adjunto.nombre),
        content: SingleChildScrollView(
          child: adjunto.esImagen
              ? Image.memory(bytes, errorBuilder: (_, __, ___) => const Text('No se pudo mostrar la imagen.'))
              : adjunto.esTexto
                  ? Text(_comoTexto(bytes))
                  : Text('PDF recibido (${bytes.length} bytes). Esta versión de la app no incluye visor de PDF.'),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  static String _comoTexto(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

  /// Paciente: cierra el chat; el servidor borra todo el historial.
  Future<void> _cerrarChat() async {
    final pacienteId = _pacienteId;
    if (pacienteId == null) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cerrar el chat?'),
        content: const Text(
          'Se borrará todo el historial de la conversación con el médico. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar chat'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await widget.chat.cerrar(pacienteId);
      if (!mounted) return;
      setState(() {
        _mensajes.clear();
        _cerrado = true;
      });
      _avisar('Chat cerrado: historial borrado');
    } on ApiException catch (e) {
      _avisar(e.mensaje);
    }
  }

  /// Paciente: abre una conversación nueva después de haber cerrado la anterior.
  Future<void> _abrirChatNuevo() async {
    final pacienteId = _pacienteId;
    if (pacienteId == null) return;
    try {
      await widget.chat.abrir(pacienteId);
      if (!mounted) return;
      setState(() => _cerrado = false);
      await _actualizar();
    } on ApiException catch (e) {
      _avisar(e.mensaje);
    }
  }

  /// Médico: solo vacía su pantalla (el historial sigue en el servidor).
  void _limpiarPantalla() {
    setState(_mensajes.clear);
  }

  void _abrirMetasDelPaciente() {
    final id = _pacienteId;
    final fabrica = widget.metasDe;
    if (id == null || fabrica == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MetasScreen(repositorio: fabrica(id, medico: true), titulo: 'Metas del paciente'),
    ));
  }

  // --------------------------------------------------------------- vista

  @override
  Widget build(BuildContext context) {
    final rol = _rol;
    return Column(
      children: [
        _SelectorRol(rol: rol, onElegir: _elegirRol),
        if (rol == RolChat.medico) _SelectorPaciente(
          pacientes: _pacientes,
          seleccionado: _pacienteId,
          error: _errorPacientes,
          onElegir: _elegirPaciente,
          onReintentar: _cargarPacientes,
        ),
        if (rol == null)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Elige tu rol para empezar:\n'
                  'Médico (Dispositivo A) o Paciente (Dispositivo B).',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else if (_pacienteId == null)
          const Expanded(
            child: Center(child: Text('Elige al paciente que vas a atender.')),
          )
        else ...[
          if (rol == RolChat.medico && widget.metasDe != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('metas-del-paciente'),
                onPressed: _abrirMetasDelPaciente,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Metas del paciente'),
              ),
            ),
          Expanded(child: _conversacion(rol)),
        ],
      ],
    );
  }

  Widget _conversacion(RolChat rol) {
    final medico = _mensajes.where((m) => m.emisor == RolChat.medico).length;
    final paciente = _mensajes.where((m) => m.emisor == RolChat.paciente).length;
    final pendientes = _pendientes.where((p) => p.pacienteId == _pacienteId).toList();

    return Column(
      children: [
        if (_sinConexion)
          const _Banner(
            texto: 'Sin conexión con el servidor. Reintentando…',
            icono: Icons.cloud_off,
          ),
        if (_cerrado)
          _Banner(
            texto: rol == RolChat.paciente
                ? 'Cerraste el chat. El historial se borró.'
                : 'El paciente cerró el chat. El historial se borró.',
            icono: Icons.lock_outline,
          ),
        if (_cerrado && rol == RolChat.paciente)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('abrir-chat-nuevo'),
                onPressed: _abrirChatNuevo,
                icon: const Icon(Icons.chat),
                label: const Text('ABRIR CHAT NUEVO'),
              ),
            ),
          ),
        // Contador de mensajes enviados por cada dispositivo.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Dispositivo A (Médico): $medico',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  'Dispositivo B (Paciente): $paciente',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _mensajes.isEmpty && pendientes.isEmpty
              ? Center(
                  child: Text(
                    _cerrado ? 'Chat cerrado.' : 'Aún no hay mensajes.',
                    key: const Key('chat-vacio'),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _mensajes.length + pendientes.length,
                  itemBuilder: (_, i) {
                    if (i < _mensajes.length) {
                      return _Burbuja(
                        mensaje: _mensajes[i],
                        propio: _mensajes[i].emisor == rol,
                        onAbrirArchivo: _mensajes[i].archivo == null ? null : () => _abrirArchivo(_mensajes[i]),
                      );
                    }
                    final p = pendientes[i - _mensajes.length];
                    return _Burbuja(
                      mensaje: MensajeChat(id: -1, emisor: p.rol, texto: p.texto, hora: p.hora),
                      propio: true,
                      pendiente: true,
                    );
                  },
                ),
        ),
        _pie(rol),
      ],
    );
  }

  Widget _pie(RolChat rol) {
    // El paciente cerró el chat: solo puede abrir uno nuevo; el médico espera.
    // (el botón «ABRIR CHAT NUEVO» del paciente está arriba, junto al aviso de chat cerrado: así los avisos
    // que aparecen abajo ya no lo tapan)
    if (_cerrado) {
      return rol == RolChat.paciente
          ? const SizedBox.shrink()
          : const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Esperando a que el paciente abra un chat nuevo…'),
            );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controlador,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _enviar(),
                  onChanged: (_) {
                    if (_errorTexto != null) setState(() => _errorTexto = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'Mensaje de ${rol.dispositivo} (${rol.nombre})',
                    errorText: _errorTexto,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IconButton(
                  key: const Key('adjuntar-archivo'),
                  onPressed: _enviando ? null : _adjuntar,
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Adjuntar archivo',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IconButton.filled(
                  onPressed: _enviando ? null : _enviar,
                  icon: const Icon(Icons.send),
                  tooltip: 'Enviar',
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: rol == RolChat.paciente
                ? TextButton.icon(
                    onPressed: _cerrarChat,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('CERRAR CHAT Y BORRAR HISTORIAL'),
                  )
                : TextButton.icon(
                    onPressed: _limpiarPantalla,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('LIMPIAR PANTALLA'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelectorRol extends StatelessWidget {
  const _SelectorRol({required this.rol, required this.onElegir});

  final RolChat? rol;
  final ValueChanged<RolChat> onElegir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      // «Soy:» arriba y las opciones debajo: en pantallas angostas las opciones pasan a una segunda línea,
      // pero siempre alineadas a la izquierda (antes «Soy:» compartía línea y el selector quedaba desalineado).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Soy:'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final r in RolChat.values)
                ChoiceChip(
                  key: Key('rol-${r.name}'),
                  label: Text('${r.nombre} (${r.dispositivo})'),
                  selected: rol == r,
                  onSelected: (_) => onElegir(r),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SelectorPaciente extends StatelessWidget {
  const _SelectorPaciente({
    required this.pacientes,
    required this.seleccionado,
    required this.error,
    required this.onElegir,
    required this.onReintentar,
  });

  final List<Usuario> pacientes;
  final String? seleccionado;
  final String? error;
  final ValueChanged<String?> onElegir;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: Text(error!)),
            TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<String>(
        initialValue: seleccionado,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Paciente a atender',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final p in pacientes)
            DropdownMenuItem(value: p.id, child: Text(p.nombreCompleto)),
        ],
        onChanged: onElegir,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.texto, required this.icono});

  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: esquema.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icono, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

/// Burbuja de un mensaje: los propios a la derecha, los del otro a la izquierda,
/// con el emisor y la hora de envío.
/// Mensaje escrito sin conexión, todavía sin confirmar por el servidor.
class _Pendiente {
  const _Pendiente(this.rol, this.pacienteId, this.texto, this.hora);

  final RolChat rol;
  final String pacienteId;
  final String texto;
  final DateTime hora;
}

class _Burbuja extends StatelessWidget {
  const _Burbuja({required this.mensaje, required this.propio, this.pendiente = false, this.onAbrirArchivo});

  final MensajeChat mensaje;

  /// Solo si el mensaje trae un archivo: lo descarga y lo muestra.
  final VoidCallback? onAbrirArchivo;
  final bool propio;

  /// true = aún no lo confirmó el servidor (se muestra atenuado y con el aviso «Pendiente de enviar»).
  final bool pendiente;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final hora = mensaje.hora;
    final texto = '${_dos(hora.hour)}:${_dos(hora.minute)}:${_dos(hora.second)}';
    return Align(
      alignment: propio ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: pendiente ? 0.6 : 1,
        child: Container(
        key: pendiente ? const Key('burbuja-pendiente') : null,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: propio ? esquema.primaryContainer : esquema.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${mensaje.emisor.dispositivo} · ${mensaje.emisor.nombre}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            if (mensaje.archivo case final a?)
              InkWell(
                key: Key('archivo-${mensaje.id}'),
                onTap: onAbrirArchivo,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(a.esImagen ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 20),
                    const SizedBox(width: 6),
                    Flexible(child: Text('${a.nombre} (${(a.tamano / 1024).ceil()} KB)',
                        style: const TextStyle(decoration: TextDecoration.underline))),
                  ]),
                ),
              )
            else
              Text(mensaje.texto),
            Text(
              pendiente ? '$texto · ⏳ Pendiente de enviar' : '$texto · ✓ enviado',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      ),
    );
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}
