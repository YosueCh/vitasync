import 'package:flutter/material.dart';

import 'config/api_config.dart';
import 'data/abrir_dao.dart';
import 'data/metrica_dao.dart';
import 'models/usuario.dart';
import 'screens/login_correo_screen.dart';
import 'screens/login_pin_screen.dart';
import 'screens/seleccionar_cuenta_screen.dart';
import 'screens/shell_screen.dart';
import 'widgets/control_inactividad.dart';
import 'services/api_cliente.dart';
import 'services/auth_service.dart';
import 'services/cache_salud_repository.dart';
import 'services/chat_repository.dart';
import 'services/contactos_repository.dart';
import 'services/metas_repository.dart';
import 'services/roles_repository.dart';
import 'services/cuenta_correo_service.dart';
import 'services/firmware_repository.dart';
import 'services/salud_repository.dart';
import 'services/usuario_repository.dart';
import 'theme/app_theme.dart';

/// Con `--dart-define=MUESTRA=true` la app corre con datos de ejemplo, sin
/// backend (útil para diseñar pantallas y capturas).
const _modoMuestra = bool.fromEnvironment('MUESTRA');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_modoMuestra) {
    runApp(VitaSyncMobileApp.muestra());
  } else {
    runApp(VitaSyncMobileApp.real(dao: await abrirDaoLocal()));
  }
}

class VitaSyncMobileApp extends StatelessWidget {
  const VitaSyncMobileApp({
    super.key,
    required this.usuarios,
    required this.saludPara,
    required this.firmwarePara,
    this.intervaloSondeo,
    this.auth,
    this.tiempoInactividad,
    this.chat,
    this.intervaloChat,
    this.cuentaCorreo,
    this.contactosPara,
    this.metasDe,
    this.roles,
  });

  /// Conectada al backend: HTTP real, caché local y sondeo cada 3 s.
  factory VitaSyncMobileApp.real({
    Key? key,
    required MetricaDao dao,
    ApiCliente? api,
    CuentaCorreoService? cuentaCorreo,
  }) {
    // Con --dart-define=SEGURIDAD=true (Práctica 10) se pide correo y contraseña y el token viaja en cada petición.
    final correo = cuentaCorreo ?? (ApiConfig.seguridadActiva ? HttpCuentaCorreoService() : null);
    final cliente = api ?? ApiCliente(token: correo?.token);
    return VitaSyncMobileApp(
      key: key,
      usuarios: HttpUsuarioRepository(api: cliente),
      saludPara: (u) => CacheSaludRepository(
        usuarioId: u.id,
        remoto: HttpSaludRepository(usuarioId: u.id, api: cliente),
        dao: dao,
      ),
      firmwarePara: (u) => HttpFirmwareRepository(usuarioId: u.id, api: cliente, puedeVincular: correo != null),
      intervaloSondeo: ApiConfig.intervaloSondeo,
      auth: HttpAuthService(api: cliente),
      tiempoInactividad: ApiConfig.tiempoInactividad,
      chat: HttpChatRepository(api: cliente),
      intervaloChat: ApiConfig.intervaloChat,
      cuentaCorreo: correo,
      contactosPara: (u) => HttpContactosRepository(usuarioId: u.id, api: cliente),
      metasDe: (cuentaId, {bool medico = false}) => HttpMetasRepository(usuarioId: cuentaId, api: cliente),
      // La pestaña de roles solo existe con la seguridad activa: sin sesiones no hay roles que repartir.
      roles: correo != null ? HttpRolesRepository(api: cliente) : null,
    );
  }

  /// Datos de ejemplo, sin red ni sondeo.
  factory VitaSyncMobileApp.muestra({Key? key}) {
    final metas = AlmacenMetasMuestra();
    return VitaSyncMobileApp(
      metasDe: (cuentaId, {bool medico = false}) =>
          MuestraMetasRepository(metas, quien: medico ? 'Médico' : 'Paciente'),
      key: key,
      usuarios: const MuestraUsuarioRepository(),
      saludPara: (_) => const MuestraSaludRepository(),
      firmwarePara: (_) => MuestraFirmwareRepository(),
      contactosPara: (_) => MuestraContactosRepository(),
    );
  }

  final UsuarioRepository usuarios;
  final SaludRepository Function(Usuario cuenta) saludPara;
  final FirmwareRepository Function(Usuario cuenta) firmwarePara;
  final Duration? intervaloSondeo;

  /// Autenticación por PIN. null usa la de muestra (acepta cualquier PIN de 4 dígitos).
  final AuthService? auth;

  /// Tiempo sin tocar la pantalla antes de cerrar la sesión. null lo desactiva.
  final Duration? tiempoInactividad;

  /// Chat médico-paciente (Práctica 6). null usa uno de muestra en memoria.
  final ChatRepository? chat;

  /// Cada cuánto el chat consulta mensajes nuevos. null desactiva el sondeo.
  final Duration? intervaloChat;

  /// Inicio de sesión con correo y contraseña (Práctica 10). null = la app no lo pide (backend sin seguridad).
  final CuentaCorreoService? cuentaCorreo;

  /// Contactos de emergencia de la cuenta (Actividad 1). null = la app no muestra esa pestaña.
  final ContactosRepository Function(Usuario cuenta)? contactosPara;

  /// Metas compartidas de una cuenta (Práctica 9). null = la app no las muestra.
  final MetasRepository Function(String cuentaId, {bool medico})? metasDe;

  /// Asignación de roles por el administrador (Práctica 7). null = la app no muestra esa pestaña.
  final RolesRepository? roles;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitaSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro,
      darkTheme: AppTheme.oscuro,
      builder: (context, child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: child,
        ),
      ),
      home: _PuertaDeAcceso(app: this),
    );
  }
}

/// Único punto de entrada a la app. Orden obligatorio: elegir cuenta, PIN y
/// solo entonces el contenido; no existe una ruta que lo salte.
class _PuertaDeAcceso extends StatefulWidget {
  const _PuertaDeAcceso({required this.app});

  final VitaSyncMobileApp app;

  @override
  State<_PuertaDeAcceso> createState() => _PuertaDeAccesoState();
}

class _PuertaDeAccesoState extends State<_PuertaDeAcceso> {
  late final AuthService _auth = widget.app.auth ?? MuestraAuthService();
  Usuario? _cuenta;
  // Se crean una vez al elegir la cuenta, no en cada build.
  late SaludRepository _salud;
  late FirmwareRepository _firmware;
  ContactosRepository? _contactos;
  // Una sola instancia: en muestra, médico y paciente comparten la misma memoria.
  late final ChatRepository _chat = widget.app.chat ?? MuestraChatRepository();

  void _elegir(Usuario u) {
    _salud = widget.app.saludPara(u);
    _firmware = widget.app.firmwarePara(u);
    _contactos = widget.app.contactosPara?.call(u);
    setState(() => _cuenta = u);
  }

  void _salir() {
    _auth.cerrarSesion();
    _cuenta = null;
  }

  void _cerrarPorInactividad() {
    setState(_salir);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tu sesión se cerró por inactividad')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final correo = app.cuentaCorreo;
    // Con la seguridad activa, antes que nada: iniciar sesión con correo y contraseña.
    if (correo != null && correo.sesion == null) {
      return LoginCorreoScreen(servicio: correo, onAutenticado: () => setState(() {}));
    }
    final cuenta = _cuenta;
    if (cuenta == null) {
      return SeleccionarCuentaScreen(
        // La clave por sesión recarga las cuentas al cambiar de persona (cada una ve solo las suyas).
        key: ValueKey(correo?.sesion?.uid),
        repositorio: app.usuarios,
        onSeleccionada: _elegir,
        sesion: correo?.sesion,
        onCerrarSesionCorreo: correo == null
            ? null
            : () => setState(() {
                  _auth.cerrarSesion();
                  correo.cerrarSesion();
                }),
      );
    }
    if (!_auth.autenticado) {
      return LoginPinScreen(
        cuenta: cuenta,
        auth: _auth,
        onAutenticado: () => setState(() {}),
        onCambiarCuenta: () => setState(() => _cuenta = null),
      );
    }
    return ControlInactividad(
      limite: app.tiempoInactividad,
      onInactivo: _cerrarPorInactividad,
      child: ShellScreen(
        // La clave por cuenta evita reutilizar el estado de otra sesión.
        key: ValueKey(cuenta.id),
        cuenta: cuenta,
        repositorio: _salud,
        firmware: _firmware,
        chat: _chat,
        contactos: _contactos,
        metasDe: app.metasDe,
        roles: app.roles,
        usuarios: app.usuarios,
        intervaloSondeo: app.intervaloSondeo,
        intervaloChat: app.intervaloChat,
        onCerrarSesion: () => setState(_salir),
      ),
    );
  }
}
