// lib/services/security_service.dart
// MODULE: Security First
// Biometric/PIN lock, screenshot blocking, auto-lock, root detection

import 'dart:async';
import 'package:flutter/material.dart';
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

  static const _pinKey         = 'app_pin_hash';
  static const _biometricKey   = 'biometric_enabled';
  static const _autoLockKey    = 'auto_lock_enabled';
  static const _autoLockSecsKey= 'auto_lock_seconds';

  bool _isLocked        = true;
  bool _biometricEnabled= false;
  bool _hasPinSet       = false;
  bool _autoLockEnabled = true;
  int  _autoLockSeconds = 30;
  DateTime? _lastBackgroundTime;
  Timer? _autoLockTimer;

  bool get isLocked         => _isLocked;
  bool get biometricEnabled => _biometricEnabled;
  bool get hasPinSet        => _hasPinSet;
  bool get autoLockEnabled  => _autoLockEnabled;
  int  get autoLockSeconds  => _autoLockSeconds;
  bool get hasAnyLock       => _biometricEnabled || _hasPinSet;

  // ── INIT ──────────────────────────────────────────────────────
  Future<void> init() async {
    final pin = await _storage.read(key: _pinKey);
    _hasPinSet = pin != null && pin.isNotEmpty;

    final bio = await _storage.read(key: _biometricKey);
    _biometricEnabled = bio == 'true';

    final autoLock = await _storage.read(key: _autoLockKey);
    _autoLockEnabled = autoLock != 'false'; // default true

    final secs = await _storage.read(key: _autoLockSecsKey);
    _autoLockSeconds = int.tryParse(secs ?? '30') ?? 30;

    _isLocked = hasAnyLock; // locked on launch if security enabled
    notifyListeners();
  }

  // ── BIOMETRIC CHECK ───────────────────────────────────────────
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> authenticateWithBiometric({String reason = 'Authenticate to access HealthTrack'}) async {
    try {
      final result = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN fallback too
          stickyAuth: true,
        ),
      );
      if (result) {
        _isLocked = false;
        notifyListeners();
      }
      return result;
    } catch (e) {
      debugPrint('[Security] Biometric auth error: $e');
      return false;
    }
  }

  // ── ENABLE / DISABLE BIOMETRIC ──────────────────────────────
  Future<bool> enableBiometric() async {
    final available = await isBiometricAvailable();
    if (!available) return false;

    final ok = await authenticateWithBiometric(reason: 'Confirm to enable biometric lock');
    if (ok) {
      await _storage.write(key: _biometricKey, value: 'true');
      _biometricEnabled = true;
      notifyListeners();
    }
    return ok;
  }

  Future<void> disableBiometric() async {
    await _storage.write(key: _biometricKey, value: 'false');
    _biometricEnabled = false;
    notifyListeners();
  }

  // ── PIN MANAGEMENT ────────────────────────────────────────────
  String _hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<void> setPin(String pin) async {
    await _storage.write(key: _pinKey, value: _hashPin(pin));
    _hasPinSet = true;
    notifyListeners();
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinKey);
    if (stored == null) return false;
    final ok = stored == _hashPin(pin);
    if (ok) {
      _isLocked = false;
      notifyListeners();
    }
    return ok;
  }

  Future<void> removePin() async {
    await _storage.delete(key: _pinKey);
    _hasPinSet = false;
    notifyListeners();
  }

  // ── AUTO-LOCK SETTINGS ─────────────────────────────────────────
  Future<void> setAutoLock(bool enabled, {int seconds = 30}) async {
    _autoLockEnabled = enabled;
    _autoLockSeconds = seconds;
    await _storage.write(key: _autoLockKey, value: enabled.toString());
    await _storage.write(key: _autoLockSecsKey, value: seconds.toString());
    notifyListeners();
  }

  // ── APP LIFECYCLE HOOKS ─────────────────────────────────────────
  void onAppBackground() {
    _lastBackgroundTime = DateTime.now();
  }

  void onAppForeground() {
    if (!hasAnyLock || !_autoLockEnabled) return;
    if (_lastBackgroundTime == null) return;

    final elapsed = DateTime.now().difference(_lastBackgroundTime!).inSeconds;
    if (elapsed >= _autoLockSeconds) {
      _isLocked = true;
      notifyListeners();
    }
  }

  void lockNow() {
    if (hasAnyLock) {
      _isLocked = true;
      notifyListeners();
    }
  }

  void unlock() {
    _isLocked = false;
    notifyListeners();
  }

  // ── SCREENSHOT / SCREEN RECORDING BLOCK ─────────────────────────
  /// Call once at app startup — sets FLAG_SECURE on Android
  /// Blocks screenshots, screen recording, and app-switcher thumbnail
  static Future<void> enableScreenProtection() async {
    try {
      const channel = MethodChannel('com.healthtrack.app/security');
      await channel.invokeMethod('enableSecureFlag');
    } catch (e) {
      debugPrint('[Security] Screen protection error: $e');
    }
  }

  static Future<void> disableScreenProtection() async {
    try {
      const channel = MethodChannel('com.healthtrack.app/security');
      await channel.invokeMethod('disableSecureFlag');
    } catch (e) {
      debugPrint('[Security] Screen protection disable error: $e');
    }
  }

  // ── ROOT / TAMPER DETECTION (basic checks) ───────────────────
  static Future<bool> isDeviceRooted() async {
    try {
      const channel = MethodChannel('com.healthtrack.app/security');
      final result = await channel.invokeMethod<bool>('isDeviceRooted');
      return result ?? false;
    } catch (_) {
      return false; // fail-safe: don't block user if check fails
    }
  }
}