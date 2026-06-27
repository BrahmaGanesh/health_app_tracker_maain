import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants/app_theme.dart';
import 'services/auth_service.dart';
import 'services/step_tracking_service.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/bp_tracker_screen.dart';
import 'screens/water_tracker_screen.dart';
import 'screens/weight_tracker_screen.dart';
import 'screens/sleep_tracker_screen.dart';
import 'screens/exercise_screen.dart';
import 'screens/meal_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/family_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/sugar_tracker_screen.dart';
import 'screens/documents_screen.dart';
import 'screens/reports_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── Theme notifier ────────────────────────────────────────────────
class ThemeService extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeService() { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('theme_mode') ?? 'system';
    _mode = v == 'dark' ? ThemeMode.dark : v == 'light' ? ThemeMode.light : ThemeMode.system;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode',
        mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
  }

  void toggle() => setMode(_mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  bool get isDark => _mode == ThemeMode.dark;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(); } catch (e) { debugPrint('Firebase: $e'); }
  runApp(const HealthTrackApp());
}

class HealthTrackApp extends StatelessWidget {
  const HealthTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => StepTrackingService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: Consumer<ThemeService>(
        builder: (_, theme, __) => MaterialApp(
          title: 'HealthTrack',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme:      AppTheme.light(),
          darkTheme:  AppTheme.dark(),
          themeMode:  theme.mode,
          routes: {
            '/':           (_) => const SplashScreen(),
            '/login':      (_) => const LoginScreen(),
            '/dashboard':  (_) => const DashboardScreen(),
            '/bp':         (_) => const BPTrackerScreen(),
            '/water':      (_) => const WaterTrackerScreen(),
            '/weight':     (_) => const WeightTrackerScreen(),
            '/sleep':      (_) => const SleepTrackerScreen(),
            '/exercise':   (_) => const ExerciseScreen(),
            '/meals':      (_) => const MealScreen(),
            '/analytics':  (_) => const AnalyticsScreen(),
            '/family':     (_) => const FamilyScreen(),
            '/profile':    (_) => const ProfileScreen(),
            '/reminders':  (_) => const RemindersScreen(),
            '/sugar':      (_) => const SugarTrackerScreen(),
            '/documents':  (_) => const DocumentsScreen(),
            '/reports':    (_) => const ReportsScreen(),
          },
        ),
      ),
    );
  }
}

void handleNotificationTap(Map<String, dynamic> data) {
  final state = navigatorKey.currentState;
  if (state == null) return;
  switch (data['type']) {
    case 'reminder': state.pushNamed('/reminders'); break;
    case 'bp_alert': state.pushNamed('/bp');        break;
    default:         state.pushNamed('/dashboard');
  }
}