import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/usuario_activo.dart';
import '../models/metricas.dart';
import '../services/smartwatch_api_service.dart';
import '../widgets/vitasync_wear_widget.dart';

const _intervaloSondeo = Duration(seconds: 3);

/// Datos de ejemplo usados SOLO si el backend no responde (sin red, sin
/// `vitasync-backend` corriendo, o sin `serviceAccountKey.json`
/// configurado). Mismos valores que antes de conectar la API real.
const _metricasEjemplo = Metricas(
  pasos: 6320,
  calorias: 412,
  suenoHoras: 7.2,
  frecuenciaCardiaca: 78,
  bateria: 87,
);
const _metaPasos = 10000;

/// Pantalla principal protegida. Solo se construye cuando AuthService
/// reporta una sesión válida (ver _AuthGate en main.dart).
///
/// El núcleo de la pantalla es [VitaSyncWearWidget] (Práctica 5-6): el
/// widget circular que muestra pasos/meta, calorías, sueño y estado de
/// sincronización. A diferencia de la primera versión (datos fijos en
/// el código), ahora se conecta de verdad a `vitasync-backend`
/// (`GET /api/smartwatch/metrics`) — el mismo backend que usa la
/// pantalla "Configuración de Dispositivo" del sitio web, así que
/// sincronizar desde el reloj o desde la web actualiza el mismo dato.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = SmartwatchApiService();

  Metricas _metricas = _metricasEjemplo;
  bool _conectado = false;
  bool _sincronizando = false;
  Timer? _sondeo;

  @override
  void initState() {
    super.initState();
    _cargarMetricas();
    // Si se sincroniza desde la web mientras esta pantalla está abierta,
    // el dato nuevo aparece solo en unos segundos, sin reabrir la app.
    _sondeo = Timer.periodic(_intervaloSondeo, (_) => _sondear());
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  Future<void> _cargarMetricas() async {
    final m = await _api.obtenerMetricas();
    if (!mounted) return;
    setState(() {
      if (m != null) {
        _metricas = m;
        _conectado = true;
      } else {
        _conectado = false;
      }
    });
  }

  Future<void> _sondear() async {
    if (_sincronizando) return;
    final m = await _api.obtenerMetricas();
    if (!mounted || m == null) return;
    setState(() {
      _metricas = m;
      _conectado = true;
    });
  }

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    final m = await _api.sincronizar();
    if (!mounted) return;
    setState(() {
      _sincronizando = false;
      if (m != null) {
        _metricas = m;
        _conectado = true;
      } else {
        _conectado = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // SingleChildScrollView en vez de solo Center+Column: en pantallas
        // redondas reales (probado en emulador Wear OS) el área útil
        // vertical es menor que el alto lógico del dispositivo, y el
        // contenido (icono + widget circular + recordatorio + botón)
        // puede no caber. Sin esto, Flutter lanza un
        // "RenderFlex overflowed" en vez de simplemente permitir scroll.
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.verified_user,
                    color: Colors.tealAccent,
                    size: 16,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Mis datos de salud',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  if (UsuarioActivo.nombreCompleto != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        UsuarioActivo.nombreCompleto!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 8, color: Colors.white38),
                      ),
                    ),
                  const SizedBox(height: 8),
                  VitaSyncWearWidget(
                    pasos: _metricas.pasos,
                    metaPasos: _metaPasos,
                    calorias: _metricas.calorias,
                    suenoHoras: _metricas.suenoHoras,
                    sincronizado: _conectado,
                    diametro: 150,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _conectado ? 'Backend conectado' : 'Sin conexión (datos de ejemplo)',
                    style: TextStyle(
                      fontSize: 8,
                      color: _conectado ? Colors.tealAccent : Colors.white38,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 24,
                    child: OutlinedButton.icon(
                      onPressed: _sincronizando ? null : _sincronizar,
                      icon: Icon(
                        _sincronizando ? Icons.hourglass_top : Icons.sync,
                        size: 11,
                      ),
                      label: Text(
                        _sincronizando ? 'Sincronizando…' : 'Sincronizar',
                        style: const TextStyle(fontSize: 9),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _InfoRow(
                    icon: Icons.medication,
                    label: 'Medicamento 14:00',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 26,
                    child: ElevatedButton.icon(
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout, size: 12),
                      label: const Text(
                        'Cerrar sesión',
                        style: TextStyle(fontSize: 9),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
