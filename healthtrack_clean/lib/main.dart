import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'constants/app_theme.dart';
import 'services/auth_service.dart';
import 'services/step_tracking_service.dart';

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
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb) {
      debugPrint("Skipping Firebase on Web");
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }

  runApp(const HealthTrackApp());
}

class HealthTrackApp extends StatelessWidget {
  const HealthTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(
          create: (_) => StepTrackingService()..init(),
        ),
      ],
      child: MaterialApp(
        title: 'HealthTrack',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        navigatorKey: navigatorKey,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/dashboard': (context) => const DashboardScreen(),
          '/bp': (context) => const BPTrackerScreen(),
          '/water': (context) => const WaterTrackerScreen(),
          '/weight': (context) => const WeightTrackerScreen(),
          '/sleep': (context) => const SleepTrackerScreen(),
          '/exercise': (context) => const ExerciseScreen(),
          '/meals': (context) => const MealScreen(),
          '/analytics': (context) => const AnalyticsScreen(),
          '/family': (context) => const FamilyScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/reminders': (context) => const RemindersScreen(),
        },
      ),
    );
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void handleNotificationTap(Map<String, dynamic> data) {
  final state = navigatorKey.currentState;
  if (state == null) return;

  switch (data['type']) {
    case 'reminder':
      state.pushNamed('/reminders');
      break;
    case 'alert':
      state.pushNamed('/dashboard');
      break;
    default:
      state.pushNamed('/dashboard');
  }
}