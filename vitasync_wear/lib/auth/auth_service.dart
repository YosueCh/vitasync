import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Maneja autenticación por PIN, biometría y ciclo de vida de la sesión.
///
/// El PIN nunca se guarda en texto plano: se guarda un salt aleatorio y el
/// hash SHA-256 de `salt:pin` en flutter_secure_storage (respaldado por
/// Android Keystore / EncryptedSharedPreferences).
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  static const _kPinHashKey = 'pin_hash';
  static const _kPinSaltKey = 'pin_salt';

  // Cierra la sesión automáticamente tras este tiempo sin actividad.
  static const Duration sessionTimeout = Duration(seconds: 45);

  bool _isAuthenticated = false;
  Timer? _inactivityTimer;

  final _sessionExpiredController = StreamController<void>.broadcast();
  Stream<void> get onSessionExpired => _sessionExpiredController.stream;

  bool get isAuthenticated => _isAuthenticated;

  Future<bool> hasPinConfigured() async {
    final hash = await _storage.read(key: _kPinHashKey);
    return hash != null;
  }

  String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  String _generateSalt() {
    final rand = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => rand.nextInt(256)));
  }

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    await _storage.write(key: _kPinSaltKey, value: salt);
    await _storage.write(key: _kPinHashKey, value: _hashPin(pin, salt));
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _kPinSaltKey);
    final storedHash = await _storage.read(key: _kPinHashKey);
    if (salt == null || storedHash == null) return false;

    final valid = _hashPin(pin, salt) == storedHash;
    if (valid) _startSession();
    return valid;
  }

  Future<bool> canUseBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Confirma tu identidad para acceder a tus datos',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (didAuth) _startSession();
      return didAuth;
    } catch (_) {
      return false;
    }
  }

  void _startSession() {
    _isAuthenticated = true;
    _resetInactivityTimer();
  }

  /// Debe llamarse ante cualquier interacción del usuario para mantener
  /// la sesión viva mientras esté activo.
  void registerActivity() {
    if (_isAuthenticated) _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(sessionTimeout, _expireSession);
  }

  void _expireSession() {
    _isAuthenticated = false;
    _sessionExpiredController.add(null);
  }

  void logout() {
    _isAuthenticated = false;
    _inactivityTimer?.cancel();
  }

  /// Utilidad para pruebas de seguridad: borra el PIN guardado.
  Future<void> resetPin() async {
    await _storage.delete(key: _kPinHashKey);
    await _storage.delete(key: _kPinSaltKey);
    logout();
  }
}
