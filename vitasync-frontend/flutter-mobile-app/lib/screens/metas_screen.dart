import 'package:flutter/material.dart';

import '../models/metas_cuenta.dart';
import '../services/api_cliente.dart';
import '../services/metas_repository.dart';

/// Metas de salud de una cuenta, editables por la paciente y por su médico (Práctica 9 dentro de VitaSync).
///
/// Al abrir se lee la versión vigente. Al guardar se manda esa versión: si la otra persona guardó antes, el servidor
/// responde 409 y aquí se ofrece elegir entre «usar las del otro» o «sobrescribir con las mías» (nunca se pisa en
/// silencio).
class MetasScreen extends StatefulWidget {
  const MetasScreen({super.key, required this.repositorio, this.titulo = 'Mis metas'});

  final MetasRepository repositorio;
  final String titulo;

  @override
  State<MetasScreen> createState() => _MetasScreenState();
}

class _MetasScreenState extends State<MetasScreen> {
  final _pasos = TextEditingController();
  final _calorias = TextEditingController();
  final _sueno = TextEditingController();

  MetasCuenta? _vigente;
  String? _error;
  bool _guardando = false;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _pasos.dispose();
    _calorias.dispose();
    _sueno.dispose();
    super.dispose();
  }

  void _mostrar(MetasCuenta m) {
    _vigente = m;
    _pasos.text = '${m.metaPasos}';
    _calorias.text = '${m.metaCalorias}';
    _sueno.text = '${m.metaSueno}';
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final m = await widget.repositorio.obtener();
      if (mounted) setState(() => _mostrar(m));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } on Exception {
      if (mounted) setState(() => _error = 'No se pudo conectar al servidor');
    }
  }

  Future<void> _guardar({int? versionForzada}) async {
    final vigente = _vigente;
    if (vigente == null) return;
    final pasos = int.tryParse(_pasos.text.trim());
    final calorias = int.tryParse(_calorias.text.trim());
    final sueno = double.tryParse(_sueno.text.trim().replaceAll(',', '.'));
    final invalido =
        ReglasMetas.validarPasos(pasos) ?? ReglasMetas.validarCalorias(calorias) ?? ReglasMetas.validarSueno(sueno);
    if (invalido != null) {
      setState(() => _aviso = invalido);
      return;
    }
    setState(() {
      _guardando = true;
      _aviso = null;
    });
    try {
      final nuevo = await widget.repositorio
          .guardar(pasos: pasos, calorias: calorias, sueno: sueno, version: versionForzada ?? vigente.version);
      if (!mounted) return;
      setState(() {
        _mostrar(nuevo);
        _aviso = 'Metas guardadas (versión ${nuevo.version}).';
      });
    } on ConflictoDeMetas catch (c) {
      if (mounted) await _resolverConflicto(c.actual);
    } on ApiException catch (e) {
      if (mounted) setState(() => _aviso = e.mensaje);
    } on Exception {
      if (mounted) setState(() => _aviso = 'No se pudo conectar al servidor');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _resolverConflicto(MetasCuenta actual) async {
    final sobrescribir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        key: const Key('dialogo-conflicto'),
        title: const Text('Alguien cambió las metas'),
        content: Text(
          '${actual.actualizadaPor} guardó otras metas mientras editabas (versión ${actual.version}):\n\n'
          'Pasos: ${actual.metaPasos}\nCalorías: ${actual.metaCalorias}\nSueño: ${actual.metaSueno} h\n\n'
          'Tus cambios no se guardaron.',
        ),
        actions: [
          TextButton(
            key: const Key('conflicto-usar-otras'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Usar las del otro'),
          ),
          FilledButton(
            key: const Key('conflicto-sobrescribir'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sobrescribir con las mías'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (sobrescribir == true) {
      // Se reintenta sobre la versión nueva: ahora sí es una decisión consciente.
      await _guardar(versionForzada: actual.version);
    } else {
      setState(() {
        _mostrar(actual);
        _aviso = 'Se cargaron las metas de ${actual.actualizadaPor}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vigente = _vigente;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!),
                const SizedBox(height: 8),
                FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
              ]),
            )
          : vigente == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Versión ${vigente.version} · última edición: ${vigente.actualizadaPor}',
                      key: const Key('metas-version'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('meta-pasos'),
                      controller: _pasos,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Meta diaria de pasos', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('meta-calorias'),
                      controller: _calorias,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Meta de calorías (kcal)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('meta-sueno'),
                      controller: _sueno,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Meta de sueño (horas)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('guardar-metas'),
                      onPressed: _guardando ? null : () => _guardar(),
                      child: Text(_guardando ? 'Guardando…' : 'Guardar metas'),
                    ),
                    if (_aviso != null) ...[
                      const SizedBox(height: 12),
                      Text(_aviso!, key: const Key('metas-aviso')),
                    ],
                  ],
                ),
    );
  }
}
