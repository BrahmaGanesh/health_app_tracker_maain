// ============================================================
// lib/screens/splash_screen.dart — App Launch / Auto-Login
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/step_tracking_service.dart';
import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final auth = context.read<AuthService>();
    final loggedIn = await auth.tryAutoLogin();

    if (!mounted) return;

    if (loggedIn) {
      // Initialize push notifications now that we have a session
      await NotificationService().init(onNotificationTap: handleNotificationTap);
      // Start live step tracking
      if (mounted) {
        final stepSvc = context.read<StepTrackingService>();
        await stepSvc.init();
      }
      Navigator.of(context).pushReplacementNamed('/dashboard');
    } else {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.navy, Color(0xFF1E3F6E), AppColors.violet],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _controller,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.mint, AppColors.sage]),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: AppColors.mint.withOpacity(0.4), blurRadius: 30, spreadRadius: 4)],
                  ),
                  child: const Center(child: Text('💚', style: TextStyle(fontSize: 42))),
                ),
                const SizedBox(height: 24),
                const Text(
                  'HealthTrack',
                  style: TextStyle(
                    fontFamily: 'Fraunces', fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your Adaptive Health Recovery Platform',
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7)),
                ),
                const SizedBox(height: 40),
                const SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.mint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}