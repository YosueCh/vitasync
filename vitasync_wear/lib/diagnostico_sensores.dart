// Pantalla de DIAGNÓSTICO de sensores: dice qué sensores tiene el reloj, si hay permiso, y muestra una lectura real. Sirve para
// comprobar un reloj nuevo (físico o emulador) antes de usar la app completa:
//   flutter run -t lib/diagnostico_sensores.dart -d <id del reloj>
import 'package:flutter/material.dart';

import 'auth/usuario_activo.dart';
import 'services/sensores_reloj.dart';
import 'services/smartwatch_api_service.dart';

/// --dart-define=CUENTA_ID=ID_DE_LA_CUENTA: habilita el botón «Enviar al servidor» (mide y manda UNA lectura con el servicio real).
const _cuentaId = String.fromEnvironment('CUENTA_ID');

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: DiagnosticoSensores()));

class DiagnosticoSensores extends StatefulWidget {
  const DiagnosticoSensores({super.key});

  @override
  State<DiagnosticoSensores> createState() => _DiagnosticoSensoresState();
}

class _DiagnosticoSensoresState extends State<DiagnosticoSensores> {
  final _s = SensoresRelojAndroid();
  EstadoSensores? _estado;
  LecturaSensores? _lectura;
  bool _leyendo = false;
  String? _envio;
  final _api = SmartwatchApiService();

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  Future<void> _refrescar() async {
    final e = await _s.estado();
    debugPrint('DIAG estado frecuencia=${e.frecuenciaDisponible} pasos=${e.pasosDisponible} permisoCardiaco=${e.permisoCardiaco} permisoActividad=${e.permisoActividad} bateria=${e.bateria}');
    if (mounted) setState(() => _estado = e);
  }

  Future<void> _permisos() async {
    final e = await _s.pedirPermisos();
    debugPrint('DIAG tras permisos: cardiaco=${e.permisoCardiaco} actividad=${e.permisoActividad}');
    if (mounted) setState(() => _estado = e);
  }

  Future<void> _leer() async {
    setState(() => _leyendo = true);
    final l = await _s.leer();
    debugPrint('DIAG lectura fc=${l.frecuenciaCardiaca} pasos=${l.pasos} bateria=${l.bateria}');
    if (mounted) {
      setState(() {
        _lectura = l;
        _leyendo = false;
      });
    }
  }

  Future<void> _enviar() async {
    setState(() => _envio = 'Enviando…');
    UsuarioActivo.establecer(_cuentaId, 'diagnóstico');
    final m = await _api.sincronizar();
    final l = _api.ultimaLectura;
    final texto = m == null ? 'FALLÓ: ${_api.ultimoError}' : 'ENVIADO FC ${m.frecuenciaCardiaca} · medido: ${l?.reales.join(", ")} · simulado: ${l?.simuladas.join(", ")}';
    debugPrint('DIAG envio $texto');
    if (mounted) setState(() => _envio = texto);
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    final l = _lectura;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 11, color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Diagnóstico de sensores', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (e != null) ...[
                  Text('Ritmo cardíaco: ${e.frecuenciaDisponible ? "sí hay" : "no hay"} · permiso ${e.permisoCardiaco ? "sí" : "no"}'),
                  Text('Pasos: ${e.pasosDisponible ? "sí hay" : "no hay"} · permiso ${e.permisoActividad ? "sí" : "no"}'),
                  Text('Batería: ${e.bateria >= 0 ? "${e.bateria} %" : "n/d"}'),
                ],
                if (l != null) Text('LECTURA: FC ${l.frecuenciaCardiaca ?? "—"} · pasos ${l.pasos ?? "—"}', key: const Key('lectura')),
                const SizedBox(height: 6),
                if (e?.faltaPermiso ?? false)
                  ElevatedButton(key: const Key('permisos'), onPressed: _permisos, child: const Text('Permitir sensores', style: TextStyle(fontSize: 10))),
                if (_cuentaId.isNotEmpty)
                  ElevatedButton(key: const Key('enviar'), onPressed: _enviar, child: const Text('Enviar al servidor', style: TextStyle(fontSize: 10))),
                if (_envio != null) Text(_envio!, key: const Key('envio'), style: const TextStyle(fontSize: 9)),
                ElevatedButton(key: const Key('leer'), onPressed: _leyendo ? null : _leer, child: Text(_leyendo ? 'Midiendo…' : 'Leer ahora', style: const TextStyle(fontSize: 10))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
