// ============================================================
// lib/services/auth_service.dart — Auth State Management
// Handles login, register, logout, current user state
// ============================================================

import 'package:flutter/foundation.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  final ApiService _api = ApiService();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _goals;
  List<String> _conditions = [];
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;

  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get profile => _profile;
  Map<String, dynamic>? get goals => _goals;
  List<String> get conditions => _conditions;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;

  String get userName => _user?['name'] ?? 'User';
  String get userEmail => _user?['email'] ?? '';
  bool get hasBP => _conditions.contains('High Blood Pressure');
  bool get hasDiabetes => _conditions.any((c) => c.contains('Diabetes'));

  // ── Check if already logged in (app startup) ──────────────────
  Future<bool> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();

    final hasToken = await _api.hasToken();
    if (!hasToken) {
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final resp = await _api.getMe();
    _isLoading = false;

    if (resp.success) {
      _user = resp.data['user'];
      _profile = resp.data['profile'];
      _goals = resp.data['goals'];
      _conditions = List<String>.from(resp.data['conditions'] ?? []);
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }

    _isAuthenticated = false;
    notifyListeners();
    return false;
  }

  // ── Register ────────────────────────────────────────────────────
  Future<bool> register(String name, String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final resp = await _api.register(name, email, password);
    _isLoading = false;

    if (resp.success) {
      _user = resp.data['user'];
      await _api.saveTokens(resp.data['access_token'], resp.data['refresh_token']);
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }

    _errorMessage = resp.message;
    if (resp.data != null && resp.data['errors'] != null) {
      final errors = resp.data['errors'] as Map;
      _errorMessage = errors.values.first.toString();
    }
    notifyListeners();
    return false;
  }

  // ── Login ────────────────────────────────────────────────────────
  Future<bool> login(String email, String password, {String? fcmToken}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final resp = await _api.login(email, password, fcmToken: fcmToken);
    _isLoading = false;

    if (resp.success) {
      _user = resp.data['user'];
      _profile = resp.data['profile'];
      _goals = resp.data['goals'];
      _conditions = List<String>.from(_user?['conditions'] ?? []);
      await _api.saveTokens(resp.data['access_token'], resp.data['refresh_token']);
      _isAuthenticated = true;
      notifyListeners();
      return true;
    }

    _errorMessage = resp.message;
    notifyListeners();
    return false;
  }

  // ── Update FCM token (call after login + when token refreshes) ──
  Future<void> updateFcmToken(String token) async {
    await _api.updateFcmToken(token);
  }

  // ── Forgot / Reset Password ────────────────────────────────────
  Future<String> forgotPassword(String email) async {
    final resp = await _api.forgotPassword(email);
    return resp.message;
  }

  Future<bool> resetPassword(String email, String token, String password) async {
    final resp = await _api.resetPassword(email, token, password);
    return resp.success;
  }

  Future<bool> changePassword(String currentPw, String newPw) async {
    final resp = await _api.changePassword(currentPw, newPw);
    if (!resp.success) _errorMessage = resp.message;
    notifyListeners();
    return resp.success;
  }

  // ── Refresh user data (after onboarding, profile edits) ────────
  Future<void> refreshUser() async {
    final resp = await _api.getMe();
    if (resp.success) {
      _user = resp.data['user'];
      _profile = resp.data['profile'];
      _goals = resp.data['goals'];
      _conditions = List<String>.from(resp.data['conditions'] ?? []);
      notifyListeners();
    }
  }

  // ── Logout ───────────────────────────────────────────────────────
  Future<void> logout() async {
    await _api.logout();
    await _api.clearTokens();
    _user = null;
    _profile = null;
    _goals = null;
    _conditions = [];
    _isAuthenticated = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}