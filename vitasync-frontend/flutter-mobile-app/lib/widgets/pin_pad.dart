import 'package:flutter/material.dart';

/// Teclado numérico con indicadores de avance. Notifica con [onCompleto] al
/// llegar a [longitud] dígitos y se limpia solo después de notificar.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleto,
    this.longitud = 4,
    this.habilitado = true,
  });

  final ValueChanged<String> onCompleto;
  final int longitud;
  final bool habilitado;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digitos = '';

  void _agregar(String digito) {
    if (!widget.habilitado || _digitos.length >= widget.longitud) return;
    setState(() => _digitos += digito);
    if (_digitos.length == widget.longitud) {
      final pin = _digitos;
      setState(() => _digitos = '');
      widget.onCompleto(pin);
    }
  }

  void _borrar() {
    if (_digitos.isEmpty) return;
    setState(() => _digitos = _digitos.substring(0, _digitos.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.longitud, (i) {
            final lleno = i < _digitos.length;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: lleno ? colores.primary : Colors.transparent,
                border: Border.all(color: colores.primary, width: 2),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        for (final fila in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'borrar'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final tecla in fila) _tecla(tecla)],
          ),
      ],
    );
  }

  Widget _tecla(String tecla) {
    const lado = 72.0;
    if (tecla.isEmpty) {
      return const SizedBox(width: lado + 16, height: lado + 16);
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: lado,
        height: lado,
        child: tecla == 'borrar'
            ? IconButton(
                onPressed: widget.habilitado ? _borrar : null,
                icon: const Icon(Icons.backspace_outlined),
                tooltip: 'Borrar',
              )
            : FilledButton.tonal(
                onPressed: widget.habilitado ? () => _agregar(tecla) : null,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: Text(tecla, style: const TextStyle(fontSize: 24)),
              ),
      ),
    );
  }
}
