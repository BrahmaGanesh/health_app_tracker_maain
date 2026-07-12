// lib/screens/splash_screen.dart — Auto-login + onboarding check
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../services/auth_service.dart';
import '../services/step_tracking_service.dart';
import '../services/notification_service.dart';
import '../services/security_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _init();
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    // Init notifications
    await NotificationService().init();

    // Small delay for splash animation
    await Future.delayed(const Duration(milliseconds: 1800));

    if (!mounted) return;

    final auth = context.read<AuthService>();

    // Try auto-login from saved tokens
    final loggedIn = await auth.tryAutoLogin();

    if (!mounted) return;

    if (!loggedIn) {
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    // Check if onboarding is complete
    final user = auth.user;
    final onboardingDone = user?['onboarding_done'] == true;

    if (!onboardingDone) {
      Navigator.of(context).pushReplacementNamed('/onboarding');
      return;
    }

    // Init step tracking now that user is logged in
    final goal = user?['goals']?['target_steps'] ?? 8000;
    await context.read<StepTrackingService>().init(dailyGoal: goal);

    // Root detection warning
    final rooted = await SecurityService.isDeviceRooted();
    if (rooted && mounted) {
      await showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
        title: const Text('⚠️ Security Warning'),
        content: const Text('Your device appears to be rooted. HealthTrack works best on non-rooted devices. Some security features may not work correctly.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('I Understand'))],
      ));
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : AppColors.navy,
      body: Center(child: FadeTransition(opacity: _fade, child: ScaleTransition(scale: _scale,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.mint, AppColors.sage], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: AppColors.mint.withOpacity(0.4), blurRadius: 32, spreadRadius: 4)],
            ),
            child: const Center(child: Text('💚', style: TextStyle(fontSize: 44))),
          ),
          const SizedBox(height: 22),
          const Text('HealthTrack', style: TextStyle(fontFamily: 'Fraunces', fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 6),
          Text('Your health companion', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 50),
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white.withOpacity(0.4))),
        ]),
      ))),
    );
  }
}