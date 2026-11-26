// Práctica 7 (cierre): el enlace de invitación abre la app con el código ya escrito.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitasync_mobile/models/usuario.dart';
import 'package:vitasync_mobile/screens/roles_screen.dart';
import 'package:vitasync_mobile/screens/shell_screen.dart';
import 'package:vitasync_mobile/services/enlace_invitacion.dart';
import 'package:vitasync_mobile/services/firmware_repository.dart';
import 'package:vitasync_mobile/services/chat_repository.dart';
import 'package:vitasync_mobile/services/roles_repository.dart';
import 'package:vitasync_mobile/services/salud_repository.dart';
import 'package:vitasync_mobile/services/usuario_repository.dart';

const _ana = Usuario(id: 'ana1', nombreCompleto: 'Ana Torres', username: 'ana', habilitado: true);

class _Usuarios implements UsuarioRepository {
  @override
  Future<List<Usuario>> listarHabilitados() async => const [_ana];
}

Widget _shell(RolesRepository? roles, InvitacionPendiente? inv) => MaterialApp(
      home: ShellScreen(
        cuenta: _ana,
        repositorio: const MuestraSaludRepository(),
        firmware: MuestraFirmwareRepository(),
        chat: MuestraChatRepository(),
        usuarios: _Usuarios(),
        roles: roles,
        invitacion: inv,
        onCerrarSesion: () {},
      ),
    );

void main() {
  group('EnlaceInvitacion.codigoDe', () {
    test('ruta de la vista web: /invitacion?codigo=ABCD1234', () {
      expect(EnlaceInvitacion.codigoDe('/invitacion?codigo=ABCD1234'), 'ABCD1234');
    });

    test('enlace de Android: vitasync://invitacion?codigo=ABCD1234', () {
      expect(EnlaceInvitacion.codigoDe('vitasync://invitacion?codigo=ABCD1234'), 'ABCD1234');
    });

    test('enlace completo de la web con # : https://sitio/movil/#/invitacion?codigo=ABCD1234 (la ruta va en el fragmento)', () {
      final uri = Uri.parse('https://sitio.mx/movil/#/invitacion?codigo=ABCD1234');
      expect(EnlaceInvitacion.codigoDe(uri.fragment), 'ABCD1234');
    });

    test('el código se normaliza a mayúsculas y se recortan espacios', () {
      expect(EnlaceInvitacion.codigoDe('/invitacion?codigo=abcd1234'), 'ABCD1234');
    });

    test('no son enlaces de invitación: nulo, vacío, otra ruta, sin código, código inválido o con caracteres peligrosos', () {
      for (final r in [null, '', '   ', '/', '/chat?codigo=ABCD1234', '/invitacion', '/invitacion?codigo=', '/invitacion?codigo=ABC', '/invitacion?codigo=ABCD12345', '/invitacion?codigo=AB<script>', '/invitacion?codigo=ABCD 234', 'http://[::bad']) {
        expect(EnlaceInvitacion.codigoDe(r), isNull, reason: '«$r»');
      }
    });

    test('paraApp y paraWeb arman enlaces que codigoDe entiende (ida y vuelta)', () {
      expect(EnlaceInvitacion.paraApp('ABCD1234'), 'vitasync://invitacion?codigo=ABCD1234');
      expect(EnlaceInvitacion.paraWeb('https://vitasync.mx/', 'ABCD1234'), 'https://vitasync.mx/movil/#/invitacion?codigo=ABCD1234');
      expect(EnlaceInvitacion.codigoDe(EnlaceInvitacion.paraApp('ABCD1234')), 'ABCD1234');
      expect(EnlaceInvitacion.codigoDe(Uri.parse(EnlaceInvitacion.paraWeb('https://vitasync.mx', 'ABCD1234')).fragment), 'ABCD1234');
    });
  });

  group('InvitacionPendiente', () {
    test('recibir guarda el código; ignorar lo que no es invitación; consumir lo entrega una sola vez', () {
      final p = InvitacionPendiente();
      p.recibir('/chat');
      expect(p.value, isNull);
      p.recibir('/invitacion?codigo=ABCD1234');
      expect(p.consumir(), 'ABCD1234');
      expect(p.consumir(), isNull);
    });
  });

  group('Pantalla principal con enlace de invitación', () {
    testWidgets('el enlace llegó ANTES de entrar: al abrirse la pantalla, el canje aparece con el código ya escrito y canjear funciona', (t) async {
      final roles = MuestraRolesRepository();
      final i = await roles.crearInvitacion('medico');
      final pendiente = InvitacionPendiente(i.codigo);
      await t.pumpWidget(_shell(roles, pendiente));
      await t.pumpAndSettle();

      expect(find.text('Código de invitación'), findsOneWidget);
      expect(find.widgetWithText(TextField, i.codigo), findsOneWidget, reason: 'el campo ya trae el código');
      await t.tap(find.byKey(const Key('canjear-codigo')));
      await t.pumpAndSettle();
      expect(find.textContaining('ahora eres Médico'), findsOneWidget);
      expect(pendiente.value, isNull, reason: 'el código se consumió una sola vez');
    });

    testWidgets('el enlace llega con la pantalla YA abierta (arranque en caliente): también abre el canje', (t) async {
      final roles = MuestraRolesRepository();
      final i = await roles.crearInvitacion('paciente');
      final pendiente = InvitacionPendiente();
      await t.pumpWidget(_shell(roles, pendiente));
      await t.pumpAndSettle();
      expect(find.text('Código de invitación'), findsNothing);

      pendiente.recibir('vitasync://invitacion?codigo=${i.codigo}');
      await t.pumpAndSettle();
      expect(find.text('Código de invitación'), findsOneWidget);
    });

    testWidgets('sin repositorio de roles (sin sesión) el enlace no abre nada', (t) async {
      await t.pumpWidget(_shell(null, InvitacionPendiente('ABCD1234')));
      await t.pumpAndSettle();
      expect(find.text('Código de invitación'), findsNothing);
    });

    testWidgets('un código que no existe se rechaza con el mensaje del servidor, sin romper', (t) async {
      final roles = MuestraRolesRepository();
      await t.pumpWidget(_shell(roles, InvitacionPendiente('NOEXISTE')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('canjear-codigo')));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('ahora eres'), findsNothing);
    });
  });

  group('Pantalla de roles: copiar el enlace', () {
    testWidgets('cada invitación libre tiene un botón que copia el enlace al portapapeles', (t) async {
      final roles = MuestraRolesRepository();
      final i = await roles.crearInvitacion('medico');
      String? copiado;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copiado = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: RolesScreen(repositorio: roles))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('copiar-enlace-${i.codigo}')));
      await t.pumpAndSettle();

      expect(copiado, EnlaceInvitacion.paraApp(i.codigo));
      expect(find.textContaining('Enlace copiado'), findsOneWidget);
    });
  });
}
