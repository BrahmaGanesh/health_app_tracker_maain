import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

class StepTrackingService extends ChangeNotifier {
  static final StepTrackingService _instance = StepTrackingService._internal();
  factory StepTrackingService() => _instance;
  StepTrackingService._internal();

  final ApiService _api = ApiService();

  int _todaySteps = 0;
  int _sessionSteps = 0;
  int _lastRawCount = 0;

  int _dailyGoal = 8000;
  bool _isTracking = false;
  bool _hasPermission = false;
  String _status = 'stopped';

  Timer? _syncTimer;
  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;

  // ── GETTERS ─────────────────────
  int get todaySteps => _todaySteps;
  int get sessionSteps => _sessionSteps;
  int get dailyGoal => _dailyGoal;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  String get status => _status;

  bool get goalAchieved => _todaySteps >= _dailyGoal;

  double get progressPct =>
      _dailyGoal == 0 ? 0 : (_todaySteps / _dailyGoal).clamp(0.0, 1.0);

  int get estimatedCalories => (_todaySteps * 0.04).toInt();

  double get estimatedDistanceKm =>
      double.parse((_todaySteps * 0.00076).toStringAsFixed(2));

  // ── INIT ─────────────────────
  Future<void> init({int dailyGoal = 8000}) async {
    _dailyGoal = dailyGoal;

    await _loadSteps();

    _hasPermission = await Permission.activityRecognition.isGranted;

    if (!_hasPermission) {
      _status = 'no_permission';
      notifyListeners();
      return;
    }

    await startTracking();
  }

  // ── PERMISSION ─────────────────────
  Future<bool> requestPermission() async {
    final res = await Permission.activityRecognition.request();
    _hasPermission = res.isGranted;
    notifyListeners();
    return _hasPermission;
  }

  // ── LOAD ─────────────────────
  Future<void> _loadSteps() async {
    try {
      final res = await _api.getSteps(days: 1);
      if (res.success) {
        _todaySteps = (res.data['today_steps'] ?? 0) as int;
      }
    } catch (_) {}
    notifyListeners();
  }

  // ── START ─────────────────────
  Future<void> startTracking() async {
    if (_isTracking) return;

    final granted = await Permission.activityRecognition.isGranted;

    if (!granted) {
      _status = 'no_permission';
      notifyListeners();
      return;
    }

    _stepSub = Pedometer.stepCountStream.listen(_onStep);
    _statusSub = Pedometer.pedestrianStatusStream.listen(_onStatus, onError: _onError);

    _isTracking = true;
    _status = 'tracking';

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => syncNow(),
    );

    notifyListeners();
  }

  // ── STOP ─────────────────────
  Future<void> stopTracking() async {
    _isTracking = false;
    _status = 'stopped';

    _syncTimer?.cancel();
    await _stepSub?.cancel();
    await _statusSub?.cancel();

    await syncNow();
    notifyListeners();
  }

  // ── STEP HANDLER ─────────────────────
  void _onStep(StepCount event) {
    if (_lastRawCount == 0) {
      _lastRawCount = event.steps;
      return;
    }

    final diff = event.steps - _lastRawCount;

    if (diff > 0 && diff < 500) {
      _todaySteps += diff;
      _sessionSteps += diff;
    }

    _lastRawCount = event.steps;
    notifyListeners();
  }

  void _onStatus(PedestrianStatus event) {
    debugPrint('Status: ${event.status}');
  }

  void _onError(error) {
    _status = 'unavailable';
    notifyListeners();
  }

  // ── SYNC ─────────────────────
  Future<void> syncNow() async {
    try {
      await _api.addSteps(_todaySteps);
    } catch (_) {}
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _stepSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}