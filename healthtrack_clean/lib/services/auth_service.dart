// lib/services/auth_service.dart — Login, register, auto-login, refresh
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  Map<String, dynamic>? _user;
  bool _loading = false;
  String? _errorMessage;

  Map<String, dynamic>? get user => _user;
  bool get loading => _loading;
  bool get isLoading => _loading;
  bool get isLoggedIn => _user != null;
  String? get errorMessage => _errorMessage;
  String get userName => _user?['name'] ?? 'User';
  List<String> get conditions => List<String>.from(_user?['conditions'] ?? []);

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null || token.isEmpty) return false;

    try {
      _setError(null);
      final resp = await ApiService().get('/auth/me');
      if (resp.success) {
        _user = resp.data['user'];
        notifyListeners();
        return true;
      } else {
        _errorMessage = resp.message ?? 'Auto-login failed';
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
    return false;
  }

  Future<ApiResponse> login(
    String email,
    String password, {
    String? fcmToken,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final resp = await ApiService().post(
        '/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
          'fcm_token': fcmToken ?? '',
        },
      );

      if (resp.success) {
        await ApiService().saveTokens(
          resp.data['access_token'],
          resp.data['refresh_token'],
        );
        _user = resp.data['user'];
        _errorMessage = null;
      } else {
        _errorMessage = resp.message ?? 'Login failed';
      }

      notifyListeners();
      return resp;
    } catch (e) {
      final error = ApiResponse(
        success: false,
        message: 'Login error: $e',
        data: {},
        statusCode: 500,
      );
      _errorMessage = error.message;
      notifyListeners();
      return error;
    } finally {
      _setLoading(false);
    }
  }

  Future<ApiResponse> register(
    String name,
    String email,
    String password,
  ) async {
    _setLoading(true);
    _setError(null);

    try {
      final resp = await ApiService().post(
        '/auth/register',
        data: {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
        },
      );

      if (resp.success) {
        await ApiService().saveTokens(
          resp.data['access_token'],
          resp.data['refresh_token'],
        );
        _user = resp.data['user'];
        _errorMessage = null;
      } else {
        _errorMessage = resp.message ?? 'Registration failed';
      }

      notifyListeners();
      return resp;
    } catch (e) {
      final error = ApiResponse(
        success: false,
        message: 'Registration error: $e',
        data: {},
        statusCode: 500,
      );
      _errorMessage = error.message;
      notifyListeners();
      return error;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    try {
      await ApiService().post('/auth/logout');
    } catch (_) {}

    await ApiService().clearTokens();
    _user = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    try {
      final resp = await ApiService().get('/auth/me');
      if (resp.success) {
        _user = resp.data['user'];
        _errorMessage = null;
        notifyListeners();
      } else {
        _errorMessage = resp.message ?? 'Failed to refresh user';
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateFcmToken(String token) async {
    try {
      await ApiService().post('/auth/fcm-token', data: {'fcm_token': token});
    } catch (_) {}
  }

  Future<ApiResponse> forgotPassword(String email) async {
    _setError(null);
    try {
      final resp = await ApiService().post(
        '/auth/forgot-password',
        data: {'email': email.trim()},
      );
      if (!resp.success) {
        _errorMessage = resp.message ?? 'Forgot password failed';
        notifyListeners();
      }
      return resp;
    } catch (e) {
      final error = ApiResponse(
        success: false,
        message: 'Forgot password error: $e',
        data: {},
        statusCode: 500,
      );
      _errorMessage = error.message;
      notifyListeners();
      return error;
    }
  }

  Future<ApiResponse> resetPassword(String token, String password) async {
    _setError(null);
    try {
      final resp = await ApiService().post(
        '/auth/reset-password',
        data: {'token': token, 'password': password},
      );
      if (!resp.success) {
        _errorMessage = resp.message ?? 'Reset password failed';
        notifyListeners();
      }
      return resp;
    } catch (e) {
      final error = ApiResponse(
        success: false,
        message: 'Reset password error: $e',
        data: {},
        statusCode: 500,
      );
      _errorMessage = error.message;
      notifyListeners();
      return error;
    }
  }

  Future<ApiResponse> changePassword(String current, String newPass) async {
    _setError(null);
    try {
      final resp = await ApiService().post(
        '/auth/change-password',
        data: {
          'current_password': current,
          'new_password': newPass,
        },
      );
      if (!resp.success) {
        _errorMessage = resp.message ?? 'Change password failed';
        notifyListeners();
      }
      return resp;
    } catch (e) {
      final error = ApiResponse(
        success: false,
        message: 'Change password error: $e',
        data: {},
        statusCode: 500,
      );
      _errorMessage = error.message;
      notifyListeners();
      return error;
    }
  }
}