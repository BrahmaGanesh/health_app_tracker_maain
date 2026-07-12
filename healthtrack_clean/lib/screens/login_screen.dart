// ============================================================
// lib/screens/login_screen.dart — Login & Register
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../constants/app_theme.dart';
import '../services/auth_service.dart';
import '../services/google_auth_service.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isGoogleLoading = false;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _googleSignIn() async {
    setState(() => _isGoogleLoading = true);

    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final result = await GoogleAuthService().signIn(fcmToken: fcmToken);

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    if (result.cancelled) return;

    if (result.success) {
      await context.read<AuthService>().tryAutoLogin();
      await NotificationService().init(onNotificationTap: handleNotificationTap);

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Google Sign-In failed'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    late ApiResponse response;

    if (_isRegisterMode) {
      response = await auth.register(
        _nameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
    } else {
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      response = await auth.login(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        fcmToken: fcmToken,
      );
    }

    if (!mounted) return;

    if (response.success) {
      await NotificationService().init(onNotificationTap: handleNotificationTap);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } else if (auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.errorMessage!),
          backgroundColor: AppColors.danger,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Authentication failed'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // ── Logo ───────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.mint, AppColors.sage],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text('💚', style: TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'HealthTrack',
                    style: TextStyle(
                      fontFamily: 'Fraunces',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // ── Header ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.mint.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _isRegisterMode ? '🎉 GET STARTED' : '👋 WELCOME BACK',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.sage,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _isRegisterMode ? 'Create Your Account' : 'Sign In to HealthTrack',
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isRegisterMode
                    ? 'Start your personalized health recovery journey today.'
                    : 'Enter your credentials to continue your health journey.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // ── Form ───────────────────────────────────────────
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (_isRegisterMode) ...[
                      _buildLabel('Full Name'),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: _inputDecoration('Your full name', '👤'),
                        validator: (v) =>
                            (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                      ),
                      const SizedBox(height: 18),
                    ],

                    _buildLabel('Email Address'),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDecoration('you@example.com', '📧'),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 18),

                    _buildLabel('Password'),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: _inputDecoration('Your password', '🔒').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            size: 20,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'At least 6 characters' : null,
                    ),

                    if (_isRegisterMode) ...[
                      const SizedBox(height: 18),
                      _buildLabel('Confirm Password'),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscureConfirm,
                        decoration: _inputDecoration('Re-enter password', '🔒').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () =>
                                setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) =>
                            (v != _passwordCtrl.text) ? 'Passwords do not match' : null,
                      ),
                    ],

                    if (!_isRegisterMode) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _showForgotPasswordSheet,
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              color: AppColors.sage,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: auth.isLoading ? null : _submit,
                        child: auth.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.navy,
                                ),
                              )
                            : Text(_isRegisterMode ? 'Create Account →' : 'Sign In →'),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted.withOpacity(0.7),
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isGoogleLoading ? null : _googleSignIn,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(
                            color: Color(0xFFE2E8F0),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isGoogleLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const _GoogleLogo(),
                                  const SizedBox(width: 10),
                                  Text(
                                    _isRegisterMode
                                        ? 'Register with Google'
                                        : 'Continue with Google',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '📧 Email reports sent from your own Gmail',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _isRegisterMode = !_isRegisterMode;
                    auth.clearError();
                  }),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                      children: [
                        TextSpan(
                          text: _isRegisterMode
                              ? 'Already have an account? '
                              : "Don't have an account? ",
                        ),
                        TextSpan(
                          text: _isRegisterMode ? 'Sign in' : 'Create one free',
                          style: const TextStyle(
                            color: AppColors.sage,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.textMuted,
          ),
        ),
      );

  InputDecoration _inputDecoration(String hint, String emoji) => InputDecoration(
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(emoji, style: const TextStyle(fontSize: 16)),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      );

  void _showForgotPasswordSheet() {
    final emailCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔑 Reset Password',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your email and we\'ll send a reset link.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtrl,
              decoration: _inputDecoration('you@example.com', '📧'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final msg = await context
                      .read<AuthService>()
                      .forgotPassword(emailCtrl.text.trim());

                  if (ctx.mounted) Navigator.pop(ctx);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(msg.message ?? 'Reset link sent'),
                      ),
                    );
                  }
                },
                child: const Text('Send Reset Link'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google logo SVG widget ─────────────────────────────────────────
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;

    canvas.drawArc(
      Rect.fromLTWH(0, 0, s, s),
      -0.52,
      1.57,
      true,
      Paint()..color = const Color(0xFF4285F4),
    );

    canvas.drawArc(
      Rect.fromLTWH(0, 0, s, s),
      1.05,
      1.57,
      true,
      Paint()..color = const Color(0xFF34A853),
    );

    canvas.drawArc(
      Rect.fromLTWH(0, 0, s, s),
      2.62,
      1.57,
      true,
      Paint()..color = const Color(0xFFFBBC05),
    );

    canvas.drawArc(
      Rect.fromLTWH(0, 0, s, s),
      4.19,
      1.57,
      true,
      Paint()..color = const Color(0xFFEA4335),
    );

    canvas.drawCircle(
      Offset(s / 2, s / 2),
      s * 0.34,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}