// lib/services/auth_service.dart — Login, register, auto-login, refresh with Firebase Auth
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  User? _firebaseUser;
  Map<String, dynamic>? _userProfile;
  bool _loading = false;
  String? _errorMessage;

  User? get firebaseUser => _firebaseUser;
  Map<String, dynamic>? get user => _userProfile;
  bool get loading => _loading;
  bool get isLoading => _loading;
  bool get isLoggedIn => _firebaseUser != null;
  String? get errorMessage => _errorMessage;
  String get userName => _userProfile?['name'] ?? _firebaseUser?.displayName ?? 'User';
  List<String> get conditions => List<String>.from(_userProfile?['conditions'] ?? []);

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
    _firebaseUser = FirebaseAuth.instance.currentUser;
    if (_firebaseUser == null) return false;

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

  Future<bool> _fetchUserProfile() async {
    try {
      final resp = await ApiService().get('/auth/me');
      if (resp.success) {
        _userProfile = resp.data['user'];
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<ApiResponse> login(
    String email,
    String password, {
    String? fcmToken,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      // Sign in with Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      _firebaseUser = userCredential.user;

      // Get ID token for API calls
      String? idToken = await _firebaseUser?.getIdToken();

      // Update FCM token if provided
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await ApiService().post('/auth/fcm-token', data: {'fcm_token': fcmToken});
      }

      // Fetch user profile from backend
      await _fetchUserProfile();

      _errorMessage = null;
      notifyListeners();

      return ApiResponse(
        success: true,
        message: 'Login successful',
        data: {'user': _userProfile},
        statusCode: 200,
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email';
          break;
        case 'wrong-password':
          message = 'Invalid email or password';
          break;
        case 'invalid-email':
          message = 'Invalid email address';
          break;
        case 'user-disabled':
          message = 'This account has been disabled';
          break;
        case 'too-many-requests':
          message = 'Too many attempts. Please try again later';
          break;
        default:
          message = 'Login failed: ${e.message}';
      }
      _errorMessage = message;
      notifyListeners();
      return ApiResponse(
        success: false,
        message: message,
        data: {},
        statusCode: 401,
      );
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
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      _firebaseUser = userCredential.user;

      // Update display name
      await _firebaseUser?.updateDisplayName(name.trim());

      // Get ID token for API calls
      String? idToken = await _firebaseUser?.getIdToken();

      // Create user profile in backend
      final resp = await ApiService().post(
        '/auth/register',
        data: {
          'name': name.trim(),
          'email': email.trim(),
          'password': password,
        },
      );

      if (resp.success) {
        _user = resp.data['user'];
        _errorMessage = null;
      } else {
        _errorMessage = resp.message ?? 'Registration failed';
      }

      notifyListeners();
      return resp;
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Email already registered';
          break;
        case 'weak-password':
          message = 'Password should be at least 6 characters';
          break;
        case 'invalid-email':
          message = 'Invalid email address';
          break;
        default:
          message = 'Registration failed: ${e.message}';
      }
      _errorMessage = message;
      notifyListeners();
      return ApiResponse(
        success: false,
        message: message,
        data: {},
        statusCode: 400,
      );
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
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    await ApiService().post('/auth/logout');

    _firebaseUser = null;
    _userProfile = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    try {
      _firebaseUser = FirebaseAuth.instance.currentUser;
      if (_firebaseUser != null) {
        await _fetchUserProfile();
      } else {
        _userProfile = null;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      final resp = await ApiService().get('/auth/me');
      if (resp.success) {
        _userProfile = resp.data['user'];
        _errorMessage = null;
        notifyListeners();
      } else {
        _userProfile = null;
      }
    } catch (e) {
      _userProfile = null;
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

  Future<void> reauthenticate(String password) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      final credential = EmailAuthProvider.credential(email: user.email!, password: password);
      await user.reauthenticateWithCredential(credential);
    }
  }
}