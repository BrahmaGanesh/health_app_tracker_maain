import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import '../constants/app_theme.dart';

class GoogleAuthService {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;
  GoogleAuthService._internal();

  final _storage = const FlutterSecureStorage();
  final _api = ApiService();

  static const String _webClientId =
      '265872207993-kqll8lric9cuf36jn8q4nn64hc7ml3rh.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _webClientId,
    scopes: ['email'],
  );

  // ── SIGN IN ─────────────────────────────────────────────
  Future<GoogleSignInResult> signIn({String? fcmToken}) async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      if (account == null) {
        return GoogleSignInResult.cancelled();
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null) {
        return GoogleSignInResult.error(
          'Failed to get Google ID token',
        );
      }

      final resp = await _api.post('/auth/google', data: {
        'id_token': idToken,
        'fcm_token': fcmToken ?? '',
      });

      if (!resp.success) {
        return GoogleSignInResult.error(resp.message);
      }

      final data = resp.data;

      await _api.saveTokens(
        data['access_token'],
        data['refresh_token'],
      );

      return GoogleSignInResult.success(
        user: Map<String, dynamic>.from(data['user'] ?? {}),
        profile: Map<String, dynamic>.from(data['profile'] ?? {}),
        isNewUser: data['is_new_user'] == true,
      );
    } catch (e) {
      return GoogleSignInResult.error('Google Sign-In failed: $e');
    }
  }

  // ── SIGN OUT ────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    await _api.clearTokens();
  }

  // ── CHECK LOGIN STATUS (FIXED) ──────────────────────────
  Future<bool> isSignedIn() async {
    final user = _googleSignIn.currentUser;
    return user != null;
  }
}

// ==========================================================
// RESULT MODEL
// ==========================================================

class GoogleSignInResult {
  final bool success;
  final bool cancelled;
  final String? errorMessage;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? profile;
  final bool isNewUser;

  GoogleSignInResult._({
    required this.success,
    required this.cancelled,
    this.errorMessage,
    this.user,
    this.profile,
    this.isNewUser = false,
  });

  factory GoogleSignInResult.success({
    required Map<String, dynamic> user,
    Map<String, dynamic>? profile,
    bool isNewUser = false,
  }) {
    return GoogleSignInResult._(
      success: true,
      cancelled: false,
      user: user,
      profile: profile,
      isNewUser: isNewUser,
    );
  }

  factory GoogleSignInResult.cancelled() {
    return GoogleSignInResult._(
      success: false,
      cancelled: true,
    );
  }

  factory GoogleSignInResult.error(String message) {
    return GoogleSignInResult._(
      success: false,
      cancelled: false,
      errorMessage: message,
    );
  }
}