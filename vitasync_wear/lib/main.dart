import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'auth/usuario_activo.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/seleccionar_usuario_screen.dart';

void main() {
  runApp(const SmartwatchAuthApp());
}

class SmartwatchAuthApp extends StatelessWidget {
  const SmartwatchAuthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salud Segura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      // Cualquier toque en la app cuenta como actividad y pospone el
      // auto-cierre de sesión por inactividad.
      home: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => AuthService.instance.registerActivity(),
        child: const _AuthGate(),
      ),
    );
  }
}

/// Único punto de entrada a la pantalla protegida: sin sesión válida en
/// AuthService, es imposible construir HomeScreen. No se usa Navigator.push
/// para llegar a ella, así que tampoco existe un "atrás" que la exponga
/// después de cerrar sesión.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    AuthService.instance.onSessionExpired.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _onAuthenticated() => setState(() {});

  void _onUsuarioElegido() => setState(() {});

  void _onLogout() {
    AuthService.instance.logout();
    UsuarioActivo.limpiar();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isAuthenticated) {
      return LoginScreen(onAuthenticated: _onAuthenticated);
    }
    if (UsuarioActivo.id == null) {
      return SeleccionarUsuarioScreen(onSeleccionado: _onUsuarioElegido);
    }
    return HomeScreen(onLogout: _onLogout);
  }
}
