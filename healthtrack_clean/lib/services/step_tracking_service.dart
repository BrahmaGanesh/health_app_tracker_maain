// lib/services/step_tracking_service.dart
// Live pedometer + daily reset at midnight + offline-first storage

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db_service.dart';
import 'sync_service.dart';

class StepTrackingService extends ChangeNotifier {
  static final StepTrackingService _i = StepTrackingService._();
  factory StepTrackingService() => _i;
  StepTrackingService._();

  final _db = LocalDb();
  final _sync = SyncService();

  // ── State ──────────────────────────────────────────────────────
  int _todaySteps = 0;
  int _dailyGoal = 8000;
  double _distanceKm = 0;
  int _calories = 0;
  bool _isTracking = false;
  bool _hasPermission = false;
  String _status = 'stopped';
  String _today = '';

  // Pedometer sensor base (resets on app start, tracks delta)
  int _sensorBase = 0;
  int _baseSteps = 0; // steps at start of today from stored value
  int _lastRaw = 0;

  // Weekly history for graph
  List<StepDayData> _weekHistory = [];

  // Timers
  Timer? _midnightTimer;
  Timer? _saveTimer;
  Timer? _syncTimer;

  // Streams
  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;

  // ── Getters ────────────────────────────────────────────────────
  int get todaySteps => _todaySteps;
  int get dailyGoal => _dailyGoal;
  double get distanceKm => _distanceKm;
  double get estimatedDistanceKm => _distanceKm;
  int get calories => _calories;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  String get status => _status;
  bool get goalAchieved => _todaySteps >= _dailyGoal;
  double get progressPct =>
      _dailyGoal > 0 ? (_todaySteps / _dailyGoal).clamp(0.0, 1.0) : 0.0;
  List<StepDayData> get weekHistory => _weekHistory;

  // ── INIT ──────────────────────────────────────────────────────
  Future<void> init({int dailyGoal = 8000}) async {
    _dailyGoal = dailyGoal;
    _today = _dateStr(DateTime.now());

    await _loadTodayFromDb();
    await _loadWeekHistory();

    _hasPermission = await _checkPermission();
    if (!_hasPermission) {
      _status = 'no_permission';
      notifyListeners();
      return;
    }

    await startTracking();
    _scheduleMidnightReset();

    _saveTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _saveToDb());
    _syncTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _syncNow());
  }

  // ── LOAD FROM LOCAL DB ────────────────────────────────────────
  Future<void> _loadTodayFromDb() async {
    final row = await _db.getTodaySteps();
    if (row != null) {
      _todaySteps = (row['steps'] as int?) ?? 0;
      _distanceKm = (row['distance_km'] as double?) ?? 0;
      _calories = (row['calories'] as int?) ?? 0;
      _dailyGoal = (row['goal'] as int?) ?? _dailyGoal;
      _baseSteps = _todaySteps;
    }
    notifyListeners();
  }

  Future<void> _loadWeekHistory() async {
    final rows = await _db.getWeekSteps(days: 7);
    final now = DateTime.now();

    final map = <String, int>{};
    for (final r in rows) {
      map[r['date'] as String] = (r['steps'] as int?) ?? 0;
    }

    _weekHistory = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final dStr = _dateStr(d);
      return StepDayData(
        date: dStr,
        dayLabel: _dayLabel(d),
        steps: map[dStr] ?? 0,
        goal: _dailyGoal,
      );
    });

    final todayIdx = _weekHistory.indexWhere((d) => d.date == _today);
    if (todayIdx >= 0) {
      _weekHistory[todayIdx] =
          _weekHistory[todayIdx].copyWith(steps: _todaySteps);
    }
    notifyListeners();
  }

  // ── START TRACKING ────────────────────────────────────────────
  Future<void> startTracking() async {
    if (_isTracking) return;
    _hasPermission = await _checkPermission();
    if (!_hasPermission) {
      _status = 'no_permission';
      notifyListeners();
      return;
    }

    try {
      _stepSub = Pedometer.stepCountStream.listen(
        _onStep,
        onError: _onStepError,
        cancelOnError: false,
      );
      _statusSub = Pedometer.pedestrianStatusStream.listen(
        (s) => debugPrint('[Steps] Status: ${s.status}'),
        onError: (_) {},
        cancelOnError: false,
      );

      _isTracking = true;
      _status = 'tracking';
      _sensorBase = 0;
      notifyListeners();
      debugPrint('[Steps] Tracking started. Base=$_baseSteps');
    } catch (e) {
      _status = 'unavailable';
      debugPrint('[Steps] Pedometer unavailable: $e');
      notifyListeners();
    }
  }

  Future<void> stopTracking() async {
    _saveTimer?.cancel();
    _syncTimer?.cancel();
    _midnightTimer?.cancel();
    await _stepSub?.cancel();
    await _statusSub?.cancel();
    await _saveToDb();
    await _syncNow();
    _isTracking = false;
    _status = 'stopped';
    notifyListeners();
  }

  // ── STEP CALLBACK ─────────────────────────────────────────────
  void _onStep(StepCount event) {
    final raw = event.steps;

    if (_sensorBase == 0 && raw > 0) {
      _sensorBase = raw;
      _lastRaw = raw;
      debugPrint('[Steps] Sensor base set: $_sensorBase');
      return;
    }

    final delta = raw - _lastRaw;
    if (delta > 0 && delta < 300) {
      _todaySteps += delta;
      _recalculate();
    }
    _lastRaw = raw;
    notifyListeners();
  }

  void _onStepError(dynamic e) {
    debugPrint('[Steps] Error: $e');
    _status = 'unavailable';
    notifyListeners();
  }

  void _recalculate() {
    final strideM = 0.00076;
    _distanceKm = double.parse((_todaySteps * strideM).toStringAsFixed(2));
    _calories = (_todaySteps * 0.04).toInt();

    final idx = _weekHistory.indexWhere((d) => d.date == _today);
    if (idx >= 0) {
      _weekHistory[idx] = _weekHistory[idx].copyWith(steps: _todaySteps);
    }
  }

  // ── MIDNIGHT RESET ────────────────────────────────────────────
  void _scheduleMidnightReset() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final delay = midnight.difference(now);

    _midnightTimer = Timer(delay, () {
      debugPrint('[Steps] 🌙 Midnight reset! Saving $_todaySteps steps for $_today');
      _saveToDb().then((_) => _syncNow()).then((_) {
        _today = _dateStr(DateTime.now());
        _todaySteps = 0;
        _distanceKm = 0;
        _calories = 0;
        _baseSteps = 0;
        _sensorBase = 0;
        _lastRaw = 0;
        _loadWeekHistory();
        notifyListeners();
        debugPrint('[Steps] New day started: $_today');
        _scheduleMidnightReset();
      });
    });

    debugPrint('[Steps] Next reset in ${delay.inHours}h ${delay.inMinutes % 60}m');
  }

  // ── MANUAL ENTRY ──────────────────────────────────────────────
  Future<void> setManualSteps(int steps) async {
    _todaySteps = steps;
    _recalculate();
    await _saveToDb();
    await _syncNow();
    notifyListeners();
  }

  // ── SAVE TO LOCAL DB ─────────────────────────────────────────
  Future<void> _saveToDb() async {
    if (_todaySteps <= 0) return;
    await _db.upsertTodaySteps(_todaySteps, _dailyGoal);
    debugPrint('[Steps] Saved $_todaySteps steps locally for $_today');
  }

  // ── SYNC TO SERVER ────────────────────────────────────────────
  Future<void> _syncNow() async {
    if (_todaySteps <= 0) return;
    try {
      final unsynced = await _db.getUnsyncedSteps();
      if (unsynced.isNotEmpty) await _sync.syncAll();
    } catch (e) {
      debugPrint('[Steps] Sync failed: $e');
    }
  }

  Future<void> syncNow() async {
    await _saveToDb();
    await _syncNow();
    await _loadTodayFromDb();
    await _loadWeekHistory();
    notifyListeners();
  }

  // ── PERMISSIONS ───────────────────────────────────────────────
  Future<bool> _checkPermission() async =>
      (await Permission.activityRecognition.status).isGranted;

  Future<bool> requestPermission() async {
    final s = await Permission.activityRecognition.request();
    _hasPermission = s.isGranted;
    notifyListeners();
    return _hasPermission;
  }

  // ── HELPERS ───────────────────────────────────────────────────
  String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);
  String _dayLabel(DateTime d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

class StepDayData {
  final String date, dayLabel;
  final int steps, goal;

  bool get achieved => steps >= goal;

  const StepDayData({
    required this.date,
    required this.dayLabel,
    required this.steps,
    required this.goal,
  });

  StepDayData copyWith({int? steps}) {
    return StepDayData(
      date: date,
      dayLabel: dayLabel,
      steps: steps ?? this.steps,
      goal: goal,
    );
  }
}