// lib/services/step_tracking_service.dart
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

  int _todaySteps = 0;
  int _dailyGoal = 8000;
  double _distanceKm = 0;
  int _calories = 0;
  bool _isTracking = false;
  bool _hasPermission = false;
  bool _isInitialized = false;
  bool _isSyncing = false;
  String _status = 'stopped';
  String _today = '';

  String _selectedDate = '';
  int _selectedSteps = 0;
  double _selectedDistanceKm = 0;
  int _selectedCalories = 0;

  int _sensorBase = 0;
  int _baseSteps = 0;
  int _lastRaw = 0;

  List<StepDayData> _weekHistory = [];

  Timer? _midnightTimer;
  Timer? _saveTimer;
  Timer? _syncTimer;

  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;

  int get todaySteps => _todaySteps;
  int get dailyGoal => _dailyGoal;
  double get distanceKm => _distanceKm;
  double get estimatedDistanceKm => _distanceKm;
  int get calories => _calories;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing;
  String get status => _status;
  bool get goalAchieved => _todaySteps >= _dailyGoal;
  double get progressPct =>
      _dailyGoal > 0 ? (_todaySteps / _dailyGoal).clamp(0.0, 1.0) : 0.0;
  List<StepDayData> get weekHistory => _weekHistory;

  String get selectedDate => _selectedDate;
  int get selectedSteps => _selectedSteps;
  double get selectedDistanceKm => _selectedDistanceKm;
  int get selectedCalories => _selectedCalories;

  bool get isOnline => _sync.isOnline;

  Future<void> init({int dailyGoal = 8000, bool autoStart = true}) async {
    if (_isInitialized) return;

    _dailyGoal = dailyGoal;
    _today = _dateStr(DateTime.now());
    _selectedDate = _today;

    await _restoreState();
    await _loadTodayFromDb();
    await _loadWeekHistory();
    await loadSelectedDate(_selectedDate);

    _hasPermission = await _checkPermission();
    if (!_hasPermission) {
      _status = 'no_permission';
      _isInitialized = true;
      notifyListeners();
      return;
    }

    if (autoStart) {
      await startTracking();
    }

    _scheduleMidnightReset();

    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _saveToDb(),
    );

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _syncNow(),
    );

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _loadTodayFromDb() async {
    final row = await _db.getTodaySteps();

    if (row != null) {
      _todaySteps = _asInt(row['steps']);
      _distanceKm = _asDouble(row['distance_km']);
      _calories = _asInt(row['calories']);
      _dailyGoal = _asInt(row['goal'], fallback: _dailyGoal);
      _baseSteps = _todaySteps;
    } else {
      _todaySteps = 0;
      _distanceKm = 0;
      _calories = 0;
      _baseSteps = 0;
    }

    await _persistState();
    notifyListeners();
  }

  Future<void> _loadWeekHistory() async {
    final rows = await _db.getWeekSteps(days: 7);
    final now = DateTime.now();

    final map = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final date = (r['date'] ?? '').toString();
      if (date.isNotEmpty) {
        map[date] = r;
      }
    }

    _weekHistory = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final dStr = _dateStr(d);
      final row = map[dStr];

      return StepDayData(
        date: dStr,
        dayLabel: _dayLabel(d),
        steps: row != null ? _asInt(row['steps']) : 0,
        goal: row != null ? _asInt(row['goal'], fallback: _dailyGoal) : _dailyGoal,
        distanceKm: row != null ? _asDouble(row['distance_km']) : 0,
        calories: row != null ? _asInt(row['calories']) : 0,
      );
    });

    final todayIdx = _weekHistory.indexWhere((d) => d.date == _today);
    if (todayIdx >= 0) {
      _weekHistory[todayIdx] = _weekHistory[todayIdx].copyWith(
        steps: _todaySteps,
        goal: _dailyGoal,
        distanceKm: _distanceKm,
        calories: _calories,
      );
    }

    notifyListeners();
  }

  Future<void> loadSelectedDate(String date) async {
    _selectedDate = date;

    if (date == _today) {
      _selectedSteps = _todaySteps;
      _selectedDistanceKm = _distanceKm;
      _selectedCalories = _calories;
      notifyListeners();
      return;
    }

    final row = await _db.getStepsByDate(date);
    if (row != null) {
      _selectedSteps = _asInt(row['steps']);
      _selectedDistanceKm = _asDouble(row['distance_km']);
      _selectedCalories = _asInt(row['calories']);
    } else {
      _selectedSteps = 0;
      _selectedDistanceKm = 0;
      _selectedCalories = 0;
    }

    notifyListeners();
  }

  Future<void> startTracking() async {
    if (_isTracking) return;
    _hasPermission = await _checkPermission();
    if (!_hasPermission) {
      _status = 'no_permission';
      notifyListeners();
      return;
    }

    try {
      await _stepSub?.cancel();
      await _statusSub?.cancel();

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
      await _persistState();
      notifyListeners();
    } catch (e) {
      _status = 'unavailable';
      debugPrint('[Steps] Pedometer unavailable: $e');
      notifyListeners();
    }
  }

  Future<void> stopTracking() async {
    await _saveToDb();
    await _syncNow();

    _saveTimer?.cancel();
    _syncTimer?.cancel();
    _midnightTimer?.cancel();

    await _stepSub?.cancel();
    await _statusSub?.cancel();

    _isTracking = false;
    _status = 'stopped';
    await _persistState();
    notifyListeners();
  }

  void _onStep(StepCount event) {
    final raw = event.steps;

    if (_sensorBase == 0 && raw > 0) {
      _sensorBase = raw;
      _lastRaw = raw;
      return;
    }

    final delta = raw - _lastRaw;
    if (delta > 0 && delta < 300) {
      _todaySteps += delta;
      _recalculate();

      if (_selectedDate == _today) {
        _selectedSteps = _todaySteps;
        _selectedDistanceKm = _distanceKm;
        _selectedCalories = _calories;
      }

      _updateTodayInWeekHistory();
      _persistState();
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
  }

  void _updateTodayInWeekHistory() {
    final idx = _weekHistory.indexWhere((d) => d.date == _today);
    if (idx >= 0) {
      _weekHistory[idx] = _weekHistory[idx].copyWith(
        steps: _todaySteps,
        goal: _dailyGoal,
        distanceKm: _distanceKm,
        calories: _calories,
      );
    }
  }

  void _scheduleMidnightReset() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final delay = midnight.difference(now);

    _midnightTimer = Timer(delay, () async {
      await _saveToDb();
      await _syncNow();

      _today = _dateStr(DateTime.now());
      _todaySteps = 0;
      _distanceKm = 0;
      _calories = 0;
      _baseSteps = 0;
      _sensorBase = 0;
      _lastRaw = 0;

      await _db.upsertTodaySteps(
        steps: _todaySteps,
        goal: _dailyGoal,
        distanceKm: _distanceKm,
      );

      await _loadWeekHistory();
      await loadSelectedDate(_today);
      await _persistState();
      notifyListeners();
      _scheduleMidnightReset();
    });
  }

  Future<void> setManualSteps(int steps) async {
    _todaySteps = steps.clamp(0, 1000000);
    _recalculate();
    _updateTodayInWeekHistory();

    if (_selectedDate == _today) {
      _selectedSteps = _todaySteps;
      _selectedDistanceKm = _distanceKm;
      _selectedCalories = _calories;
    }

    await _saveToDb();
    await _syncNow();
    await _persistState();
    notifyListeners();
  }

  Future<void> _saveToDb() async {
    await _db.upsertTodaySteps(
      steps: _todaySteps,
      goal: _dailyGoal,
      distanceKm: _distanceKm,
    );
  }

  Future<void> _syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final unsynced = await _db.getUnsyncedSteps();
      if (unsynced.isNotEmpty) {
        await _sync.syncAll();
      }
    } catch (e) {
      debugPrint('[Steps] Sync failed: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> syncNow() async {
    await _saveToDb();
    await _syncNow();
    await _loadTodayFromDb();
    await _loadWeekHistory();
    await loadSelectedDate(_selectedDate);
    notifyListeners();
  }

  Future<bool> _checkPermission() async =>
      (await Permission.activityRecognition.status).isGranted;

  Future<bool> requestPermission() async {
    final s = await Permission.activityRecognition.request();
    _hasPermission = s.isGranted;
    notifyListeners();
    return _hasPermission;
  }

  Future<void> _persistState() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('steps_today_date', _today);
    await p.setInt('steps_today_count', _todaySteps);
    await p.setDouble('steps_today_distance', _distanceKm);
    await p.setInt('steps_today_calories', _calories);
    await p.setInt('steps_daily_goal', _dailyGoal);
    await p.setBool('steps_tracking_enabled', _isTracking);
    await p.setInt('steps_sensor_base', _sensorBase);
    await p.setInt('steps_last_raw', _lastRaw);
  }

  Future<void> _restoreState() async {
    final p = await SharedPreferences.getInstance();
    final savedDate = p.getString('steps_today_date') ?? '';
    final currentDate = _dateStr(DateTime.now());

    _dailyGoal = p.getInt('steps_daily_goal') ?? _dailyGoal;

    if (savedDate == currentDate) {
      _today = savedDate;
      _todaySteps = p.getInt('steps_today_count') ?? 0;
      _distanceKm = p.getDouble('steps_today_distance') ?? 0;
      _calories = p.getInt('steps_today_calories') ?? 0;
      _sensorBase = p.getInt('steps_sensor_base') ?? 0;
      _lastRaw = p.getInt('steps_last_raw') ?? 0;
    } else {
      _today = currentDate;
      _todaySteps = 0;
      _distanceKm = 0;
      _calories = 0;
      _sensorBase = 0;
      _lastRaw = 0;
    }
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse('$v') ?? fallback;
  }

  double _asDouble(dynamic v, {double fallback = 0}) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse('$v') ?? fallback;
  }

  String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);

  String _dayLabel(DateTime d) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

class StepDayData {
  final String date;
  final String dayLabel;
  final int steps;
  final int goal;
  final double distanceKm;
  final int calories;

  bool get achieved => steps >= goal;

  const StepDayData({
    required this.date,
    required this.dayLabel,
    required this.steps,
    required this.goal,
    this.distanceKm = 0,
    this.calories = 0,
  });

  StepDayData copyWith({
    int? steps,
    int? goal,
    double? distanceKm,
    int? calories,
  }) {
    return StepDayData(
      date: date,
      dayLabel: dayLabel,
      steps: steps ?? this.steps,
      goal: goal ?? this.goal,
      distanceKm: distanceKm ?? this.distanceKm,
      calories: calories ?? this.calories,
    );
  }
}