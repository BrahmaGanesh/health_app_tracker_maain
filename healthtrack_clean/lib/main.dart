// lib/main.dart — HealthTrack v2.0 — Complete with Security + All Routes
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants/app_theme.dart';
import 'services/auth_service.dart';
import 'services/step_tracking_service.dart';
import 'services/sync_service.dart';
import 'services/local_db_service.dart';
import 'services/security_service.dart';

// ── Screens ───────────────────────────────────────────────────────
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/ai_camera_screen.dart';
import 'screens/onboarding_screen.dart';
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
import 'screens/medicine_screen.dart';
import 'screens/lab_test_screen.dart';
import 'screens/appointments_screen.dart';
import 'screens/emergency_card_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/subscription_screen.dart';
// import 'screens/pin_setup_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ════════════════════════════════════════════════════════════════
// THEME SERVICE (Light / Auto / Dark) — persists in SharedPreferences
// ════════════════════════════════════════════════════════════════
class ThemeService extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  ThemeService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('theme_mode') ?? 'system';
    _mode = v == 'dark'
        ? ThemeMode.dark
        : v == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      mode == ThemeMode.dark
          ? 'dark'
          : mode == ThemeMode.light
              ? 'light'
              : 'system',
    );
  }

  void toggle() =>
      setMode(_mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

// ════════════════════════════════════════════════════════════════
// ENTRY POINT
// ════════════════════════════════════════════════════════════════
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Open local SQLite DB (creates tables on first run)
  await LocalDb().db;

  // 2. Load security settings (biometric/PIN state)
  await SecurityService().init();

  // 3. Firebase — for FCM push notifications
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Firebase] init skipped: $e');
  }

  // 4. Background sync service (auto-syncs when internet returns)
  await SyncService().init();

  runApp(const HealthTrackApp());
}

// ══════════════════════════════���═════════════════════════════════
// ROOT APP WIDGET — with lifecycle observer for auto-lock
// ════════════════════════════════════════════════════════════════
class HealthTrackApp extends StatefulWidget {
  const HealthTrackApp({super.key});

  @override
  State<HealthTrackApp> createState() => _HealthTrackAppState();
}

class _HealthTrackAppState extends State<HealthTrackApp>
    with WidgetsBindingObserver {
  final _security = SecurityService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Block screenshots and screen recording (FLAG_SECURE)
    SecurityService.enableScreenProtection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _security.onAppBackground();
        break;
      case AppLifecycleState.resumed:
        _security.onAppForeground(); // triggers lock if timeout exceeded
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => StepTrackingService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider.value(value: _security),
      ],
      child: Consumer<ThemeService>(
        builder: (_, theme, __) => MaterialApp(
          title: 'HealthTrack',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,

          // ── Global lock-screen overlay ─────────────────────────
          // Sits above ALL routes — activates when app locked
          builder: (context, child) {
            return Consumer<SecurityService>(
              builder: (_, sec, __) => Stack(
                children: [
                  child!,
                  if (sec.isLocked && sec.hasAnyLock)
                    LockScreen(
                      onUnlocked: () => sec.unlock(),
                    ),
                ],
              ),
            );
          },

          // ── All routes ─────────────────────────────────────────
          routes: {
            // Core
            '/': (_) => const SplashScreen(),
            '/login': (_) => const LoginScreen(),

            // Main screens
            '/dashboard': (_) => const DashboardScreen(),
            '/profile': (_) => const ProfileScreen(),

            // Health trackers
            '/bp': (_) => const BPTrackerScreen(),
            '/water': (_) => const WaterTrackerScreen(),
            '/weight': (_) => const WeightTrackerScreen(),
            '/sleep': (_) => const SleepTrackerScreen(),
            '/sugar': (_) => const SugarTrackerScreen(),

            // Exercise & meals
            '/exercise': (_) => const ExerciseScreen(),
            '/meals': (_) => const MealScreen(),

            // Analytics
            '/analytics': (_) => const AnalyticsScreen(),

            // Family
            '/family': (_) => const FamilyScreen(),

            // Reminders & notifications
            '/reminders': (_) => const RemindersScreen(),

            // Documents & reports
            '/documents': (_) => const DocumentsScreen(),
            '/reports': (_) => const ReportsScreen(),

            // ── NEW MODULES ──────────────────────────────────────

            // Module 4: Medicine management
            '/medicines': (_) => const MedicineScreen(),

            // Module 8: Lab test tracker
            '/lab-tests': (_) => const LabTestScreen(),

            // Module 10: Appointment manager
            '/appointments': (_) => const AppointmentsScreen(),

            // Module 14: Emergency card (no auth needed when standalone)
            '/emergency': (_) => const EmergencyCardScreen(),

            // Module 20: Health timeline
            '/timeline': (_) => const TimelineScreen(),

            // Module 19: AI assistant
            '/ai': (_) => const AiAssistantScreen(),

            // AI Camera with on/off toggle
            '/ai-camera': (_) => const AiCameraScreen(),

            // Subscription / plans
            '/plans': (_) => const SubscriptionScreen(),

            // Onboarding (first-time setup)
            '/onboarding': (_) => const OnboardingScreen(),

            // Security settings (accessed from profile)
            '/pin-setup': (ctx) => PinSetupScreen(
                  onDone: () => Navigator.of(ctx).pop(),
                ),
          },
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// NOTIFICATION TAP → NAVIGATE
// ════════════════════════════════════════════════════════════════
void handleNotificationTap(Map<String, dynamic> data) {
  final state = navigatorKey.currentState;
  if (state == null) return;

  switch (data['type']) {
    case 'reminder':
      state.pushNamed('/reminders');
      break;
    case 'bp_alert':
      state.pushNamed('/bp');
      break;
    case 'water':
      state.pushNamed('/water');
      break;
    case 'medicine':
      state.pushNamed('/medicines');
      break;
    case 'appointment':
      state.pushNamed('/appointments');
      break;
    case 'lab':
      state.pushNamed('/lab-tests');
      break;
    default:
      state.pushNamed('/dashboard');
  }
}