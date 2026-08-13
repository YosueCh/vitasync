import 'package:flutter/material.dart';

import '../auth/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService.instance;

  bool _loading = true;
  bool _hasPin = false;
  bool _biometricsAvailable = false;

  int _pinLength = 4;
  String _entered = '';
  String? _firstEntry; // primer PIN capturado durante la configuración
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final hasPin = await _auth.hasPinConfigured();
    final bio = hasPin ? await _auth.canUseBiometrics() : false;
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _biometricsAvailable = bio;
      _loading = false;
    });
  }

  Future<void> _tryBiometric() async {
    setState(() => _busy = true);
    final ok = await _auth.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onAuthenticated();
    } else {
      setState(() => _error = 'Biometría no reconocida');
    }
  }

  void _onDigit(String d) {
    if (_busy || _entered.length >= _pinLength) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == _pinLength) _submit();
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _submit() async {
    if (!_hasPin) {
      // Flujo de configuración: primero se captura, luego se confirma.
      if (_firstEntry == null) {
        setState(() {
          _firstEntry = _entered;
          _entered = '';
        });
        return;
      }
      if (_firstEntry != _entered) {
        setState(() {
          _error = 'Los PIN no coinciden, intenta de nuevo';
          _entered = '';
          _firstEntry = null;
        });
        return;
      }

      final pin = _entered;
      await _auth.setPin(pin);
      final ok = await _auth.verifyPin(pin);
      if (!mounted) return;
      setState(() {
        _hasPin = true;
        _entered = '';
        _firstEntry = null;
      });
      if (ok) widget.onAuthenticated();
      return;
    }

    setState(() => _busy = true);
    final ok = await _auth.verifyPin(_entered);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onAuthenticated();
    } else {
      setState(() {
        _error = 'PIN incorrecto';
        _entered = '';
      });
    }
  }

  String get _title {
    if (_loading) return '';
    if (!_hasPin) {
      return _firstEntry == null ? 'Crea tu PIN' : 'Confirma tu PIN';
    }
    return 'Ingresa tu PIN';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 18),
                const SizedBox(height: 2),
                Text(_title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (!_hasPin && _firstEntry == null) _PinLengthSelector(
                  value: _pinLength,
                  onChanged: (v) => setState(() => _pinLength = v),
                ),
                const SizedBox(height: 4),
                _PinDots(length: _pinLength, filled: _entered.length),
                const SizedBox(height: 2),
                SizedBox(
                  height: 12,
                  child: Text(
                    _error ?? '',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 9),
                  ),
                ),
                const SizedBox(height: 2),
                _Keypad(onDigit: _onDigit, onBackspace: _onBackspace, enabled: !_busy),
                if (_hasPin && _biometricsAvailable) ...[
                  const SizedBox(height: 2),
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    onPressed: _busy ? null : _tryBiometric,
                    icon: const Icon(Icons.fingerprint),
                    tooltip: 'Usar biometría',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinLengthSelector extends StatelessWidget {
  const _PinLengthSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [4, 6].map((n) {
        final selected = value == n;
        return ChoiceChip(
          label: Text('$n dígitos', style: const TextStyle(fontSize: 9)),
          selected: selected,
          onSelected: (_) => onChanged(n),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.filled});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? Colors.tealAccent : Colors.transparent,
            border: Border.all(color: Colors.tealAccent, width: 1),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace, required this.enabled});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  static const _layout = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', 'back'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _layout.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            if (key.isEmpty) return const SizedBox(width: 24, height: 24);
            if (key == 'back') {
              return _KeypadButton(
                enabled: enabled,
                onTap: onBackspace,
                child: const Icon(Icons.backspace_outlined, size: 10),
              );
            }
            return _KeypadButton(
              enabled: enabled,
              onTap: () => onDigit(key),
              child: Text(key, style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.child, required this.onTap, required this.enabled});

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: SizedBox(
        width: 24,
        height: 24,
        child: ElevatedButton(
          onPressed: enabled ? onTap : null,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
          ),
          child: child,
        ),
      ),
    );
  }
}
