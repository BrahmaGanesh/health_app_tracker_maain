// lib/services/security_service.dart — Fixed biometric + PIN (fully toggleable)
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class SecurityService extends ChangeNotifier {
  static final SecurityService _i = SecurityService._();
  factory SecurityService() => _i;
  SecurityService._();

  final _auth    = LocalAuthentication();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kPin      = 'ht_pin_hash';
  static const _kBio      = 'ht_biometric';
  static const _kAutoLock = 'ht_auto_lock';
  static const _kAutoSecs = 'ht_auto_secs';

  bool     _isLocked        = false;
  bool     _biometricEnabled= false;
  bool     _hasPinSet       = false;
  bool     _autoLockEnabled = true;
  int      _autoLockSeconds = 30;
  DateTime? _lastBackground;

  bool get isLocked         => _isLocked;
  bool get biometricEnabled => _biometricEnabled;
  bool get hasPinSet        => _hasPinSet;
  bool get autoLockEnabled  => _autoLockEnabled;
  int  get autoLockSeconds  => _autoLockSeconds;
  bool get hasAnyLock       => _hasPinSet || _biometricEnabled;

  // ── INIT (called once at app start) ───────────────────────────
  Future<void> init() async {
    final pin  = await _storage.read(key: _kPin);
    final bio  = await _storage.read(key: _kBio);
    final al   = await _storage.read(key: _kAutoLock);
    final secs = await _storage.read(key: _kAutoSecs);

    _hasPinSet        = (pin != null && pin.isNotEmpty);
    _biometricEnabled = bio == 'true';
    _autoLockEnabled  = al != 'false';
    _autoLockSeconds  = int.tryParse(secs ?? '30') ?? 30;

    // Only lock at startup if security is configured
    _isLocked = hasAnyLock;
    notifyListeners();
  }

  // ── BIOMETRIC AVAILABILITY ────────────────────────────────────
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck   = await _auth.canCheckBiometrics;
      final isSupported= await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) { return false; }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try { return await _auth.getAvailableBiometrics(); }
    catch (_) { return []; }
  }

  // ── AUTHENTICATE WITH BIOMETRIC ───────────────────────────────
  Future<bool> authenticateWithBiometric({String? reason}) async {
    if (!_biometricEnabled) return false;
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason ?? 'Authenticate to access HealthTrack',
        options: const AuthenticationOptions(
          biometricOnly: false, // allows device PIN/pattern as fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) { _isLocked = false; notifyListeners(); }
      return ok;
    } catch (e) {
      debugPrint('[Security] Biometric error: $e');
      return false;
    }
  }

  // ── ENABLE BIOMETRIC (user turns ON in settings) ──────────────
  Future<bool> enableBiometric() async {
    final available = await isBiometricAvailable();
    if (!available) return false;

    // Verify first before enabling
    final ok = await _auth.authenticate(
      localizedReason: 'Confirm fingerprint/face to enable biometric lock',
      options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
    );
    if (ok) {
      await _storage.write(key: _kBio, value: 'true');
      _biometricEnabled = true;
      notifyListeners();
    }
    return ok;
  }

  // ── DISABLE BIOMETRIC (user turns OFF in settings) ────────────
  Future<void> disableBiometric() async {
    await _storage.write(key: _kBio, value: 'false');
    _biometricEnabled = false;
    // If PIN also not set, unlock the app
    if (!_hasPinSet) _isLocked = false;
    notifyListeners();
  }

  // ── PIN MANAGEMENT ────────────────────────────────────────────
  String _hash(String pin) => sha256.convert(utf8.encode(pin + 'ht_salt_2026')).toString();

  Future<void> setPin(String pin) async {
    await _storage.write(key: _kPin, value: _hash(pin));
    _hasPinSet = true;
    _isLocked  = false; // don't lock right after setting PIN
    notifyListeners();
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _kPin);
    if (stored == null) return false;
    final ok = stored == _hash(pin);
    if (ok) { _isLocked = false; notifyListeners(); }
    return ok;
  }

  Future<void> removePin() async {
    await _storage.delete(key: _kPin);
    _hasPinSet = false;
    if (!_biometricEnabled) _isLocked = false;
    notifyListeners();
  }

  // ── AUTO-LOCK SETTINGS ────────────────────────────────────────
  Future<void> setAutoLock(bool enabled, {int seconds = 30}) async {
    _autoLockEnabled = enabled;
    _autoLockSeconds = seconds;
    await _storage.write(key: _kAutoLock, value: enabled.toString());
    await _storage.write(key: _kAutoSecs, value: seconds.toString());
    notifyListeners();
  }

  // ── APP LIFECYCLE ─────────────────────────────────────────────
  void onAppBackground() {
    _lastBackground = DateTime.now();
  }

  void onAppForeground() {
    if (!hasAnyLock || !_autoLockEnabled) return;
    if (_lastBackground == null) return;
    final elapsed = DateTime.now().difference(_lastBackground!).inSeconds;
    if (elapsed >= _autoLockSeconds) {
      _isLocked = true;
      notifyListeners();
      debugPrint('[Security] Auto-locked after ${elapsed}s');
    }
  }

  void lockNow() {
    if (hasAnyLock) { _isLocked = true; notifyListeners(); }
  }

  void unlock() {
    _isLocked = false;
    notifyListeners();
  }

  // ── SCREENSHOT PROTECTION (FLAG_SECURE) ───────────────────────
  static Future<void> enableScreenProtection() async {
    try {
      const ch = MethodChannel('com.healthtrack.app/security');
      await ch.invokeMethod('enableSecureFlag');
      debugPrint('[Security] Screenshot protection enabled');
    } catch (e) { debugPrint('[Security] FLAG_SECURE error: $e'); }
  }

  static Future<void> disableScreenProtection() async {
    try {
      const ch = MethodChannel('com.healthtrack.app/security');
      await ch.invokeMethod('disableSecureFlag');
    } catch (_) {}
  }

  // ── ROOT DETECTION ────────────────────────────────────────────
  static Future<bool> isDeviceRooted() async {
    try {
      const ch = MethodChannel('com.healthtrack.app/security');
      return await ch.invokeMethod<bool>('isDeviceRooted') ?? false;
    } catch (_) { return false; }
  }
}