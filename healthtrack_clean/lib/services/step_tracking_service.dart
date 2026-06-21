import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';
import 'native_step_service.dart';

class StepTrackingService extends ChangeNotifier {
  static final StepTrackingService _instance = StepTrackingService._internal();
  factory StepTrackingService() => _instance;
  StepTrackingService._internal();

  final ApiService _api = ApiService();
  final NativeStepService _native = NativeStepService();

  int _todaySteps = 0;
  int _sessionSteps = 0;
  int _baselineSteps = 0;
  int _dailyGoal = 8000;

  bool _isTracking = false;
  bool _hasPermission = false;
  bool _initialized = false;
  String _status = 'stopped';

  Timer? _syncTimer;
  StreamSubscription<Map<String, dynamic>>? _nativeStepSub;

  int get todaySteps => _todaySteps;
  int get sessionSteps => _sessionSteps;
  int get dailyGoal => _dailyGoal;
  bool get isTracking => _isTracking;
  bool get hasPermission => _hasPermission;
  String get status => _status;
  bool get initialized => _initialized;

  bool get goalAchieved => _todaySteps >= _dailyGoal;

  double get progressPct =>
      _dailyGoal == 0 ? 0 : (_todaySteps / _dailyGoal).clamp(0.0, 1.0);

  int get estimatedCalories => (_todaySteps * 0.04).toInt();

  double get estimatedDistanceKm =>
      double.parse((_todaySteps * 0.00076).toStringAsFixed(2));

  Future<void> init({int dailyGoal = 8000}) async {
    if (_initialized) return;

    _dailyGoal = dailyGoal;

    await _loadStepsFromApi();
    await _checkAndPreparePermissions();
    await _attachNativeListener();
    await _restoreNativeState();

    _initialized = true;
    notifyListeners();
  }

  Future<void> _checkAndPreparePermissions() async {
    final activityGranted =
        await Permission.activityRecognition.status.isGranted;

    bool notificationGranted = true;
    if (!kIsWeb) {
      notificationGranted = await Permission.notification.status.isGranted ||
          await Permission.notification.status.isLimited ||
          await Permission.notification.status.isProvisional;
    }

    _hasPermission = activityGranted && notificationGranted;

    if (!_hasPermission) {
      _status = 'no_permission';
    }
  }

  Future<bool> requestPermission() async {
    final activityStatus = await Permission.activityRecognition.request();

    PermissionStatus? notificationStatus;
    if (!kIsWeb) {
      notificationStatus = await Permission.notification.request();
    }

    final activityGranted = activityStatus.isGranted;
    final notificationGranted = notificationStatus == null
        ? true
        : notificationStatus.isGranted ||
            notificationStatus.isLimited ||
            notificationStatus.isProvisional;

    _hasPermission = activityGranted && notificationGranted;

    if (!_hasPermission) {
      _status = 'no_permission';
      notifyListeners();
      return false;
    }

    notifyListeners();
    return true;
  }

  Future<void> _loadStepsFromApi() async {
    try {
      final res = await _api.getSteps(days: 1);
      if (res.success) {
        final dynamic raw = res.data['today_steps'];
        if (raw is int) {
          _todaySteps = raw;
        } else if (raw is num) {
          _todaySteps = raw.toInt();
        }
      }
    } catch (_) {}
  }

  Future<void> _attachNativeListener() async {
    await _nativeStepSub?.cancel();

    _nativeStepSub = _native.stepStream.listen(
      (event) {
        final nativeSteps = (event['steps'] ?? 0) as int;
        final tracking = (event['isTracking'] ?? false) as bool;

        _isTracking = tracking;
        _status = tracking ? 'tracking' : 'stopped';

        if (_baselineSteps == 0) {
          _baselineSteps = _todaySteps;
        }

        _todaySteps = nativeSteps;
        _sessionSteps = (_todaySteps - _baselineSteps).clamp(0, 1 << 30);

        notifyListeners();
      },
      onError: (_) {
        _status = 'unavailable';
        notifyListeners();
      },
    );
  }

  Future<void> _restoreNativeState() async {
    try {
      final currentSteps = await _native.getCurrentSteps();
      final tracking = await _native.isTracking();

      _baselineSteps = currentSteps;
      _todaySteps = currentSteps;
      _isTracking = tracking;
      _status = tracking ? 'tracking' : 'stopped';

      if (tracking) {
        _startSyncTimer();
      }
    } catch (_) {
      _status = 'unavailable';
    }
  }

  Future<void> startTracking() async {
    if (_isTracking) return;

    final granted = await requestPermission();
    if (!granted) {
      return;
    }

    try {
      final ok = await _native.startTracking();
      if (!ok) {
        _status = 'unavailable';
        notifyListeners();
        return;
      }

      _baselineSteps = await _native.getCurrentSteps();
      _isTracking = true;
      _status = 'tracking';
      _startSyncTimer();
      notifyListeners();
    } catch (_) {
      _status = 'unavailable';
      notifyListeners();
    }
  }

  Future<void> stopTracking() async {
    try {
      await _native.stopTracking();
    } catch (_) {}

    _isTracking = false;
    _status = 'stopped';
    _syncTimer?.cancel();

    await syncNow();
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      _todaySteps = await _native.getCurrentSteps();
      _isTracking = await _native.isTracking();
      _status = _isTracking ? 'tracking' : 'stopped';
      _sessionSteps = (_todaySteps - _baselineSteps).clamp(0, 1 << 30);
    } catch (_) {
      _status = 'unavailable';
    }
    notifyListeners();
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => syncNow(),
    );
  }

  Future<void> syncNow() async {
    try {
      await _api.addSteps(_todaySteps);
    } catch (_) {}
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _nativeStepSub?.cancel();
    super.dispose();
  }
}