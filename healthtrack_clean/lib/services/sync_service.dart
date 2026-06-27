// lib/services/sync_service.dart
// Offline-first background sync
// Watches connectivity → syncs queued data when online

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'local_db_service.dart';

enum SyncStatus { idle, syncing, online, offline }

class SyncService extends ChangeNotifier {
  static final SyncService _i = SyncService._();
  factory SyncService() => _i;
  SyncService._();

  final _api     = ApiService();
  final _localDb = LocalDb();

  SyncStatus _status   = SyncStatus.idle;
  bool       _isOnline = true;
  int        _pending  = 0;
  DateTime?  _lastSync;
  Timer?     _periodicTimer;
  StreamSubscription? _connectSub;

  SyncStatus get status   => _status;
  bool       get isOnline => _isOnline;
  int        get pending  => _pending;
  DateTime?  get lastSync => _lastSync;

  String get statusLabel {
    if (!_isOnline) return '📵 Offline — changes saved locally';
    if (_status == SyncStatus.syncing) return '🔄 Syncing...';
    if (_pending > 0) return '⏳ $_pending pending sync';
    return '✅ All synced';
  }

  // ── INIT ──────────────────────────────────────────────────────
  Future<void> init() async {
    // Watch connectivity
    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      notifyListeners();
      // Just came online → sync immediately
      if (!wasOnline && _isOnline) {
        debugPrint('[Sync] Back online — triggering sync');
        syncAll();
      }
    });

    // Check current state
    final results = await Connectivity().checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);

    // Periodic sync every 3 minutes
    _periodicTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (_isOnline) syncAll();
    });

    // Initial sync
    if (_isOnline) syncAll();
    notifyListeners();
  }

  void dispose() {
    _connectSub?.cancel();
    _periodicTimer?.cancel();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════
  // MAIN SYNC — pushes all local data to server
  // ════════════════════════════════════════════════════════════════
  Future<void> syncAll() async {
    if (!_isOnline || _status == SyncStatus.syncing) return;
    _status = SyncStatus.syncing;
    notifyListeners();

    try {
      await Future.wait([
        _syncMetrics(),
        _syncSteps(),
        _syncQueue(),
        _refreshReminders(),
      ]);
      _lastSync = DateTime.now();
      _pending = (await _localDb.getPendingQueue()).length
          + (await _localDb.getUnsyncedMetrics()).length;
    } catch (e) {
      debugPrint('[Sync] Error: $e');
    }

    _status = SyncStatus.idle;
    notifyListeners();
  }

  // ── Push unsynced metrics ──────────────────────────────────────
  Future<void> _syncMetrics() async {
    final metrics = await _localDb.getUnsyncedMetrics();
    for (final m in metrics) {
      try {
        final type = m['type'] as String;
        final endpoint = _endpointForType(type);
        final body = _bodyForMetric(m);
        final resp = await _api.post(endpoint, data: body);
        if (resp.success) {
          final serverId = resp.data?['id'] ?? 0;
          await _localDb.markMetricSynced(m['id'] as int, serverId);
          debugPrint('[Sync] Metric $type synced (serverId=$serverId)');
        }
      } catch (e) {
        debugPrint('[Sync] Metric sync failed: $e');
      }
    }
  }

  // ── Push step daily counts ─────────────────────────────────────
  Future<void> _syncSteps() async {
    final stepDays = await _localDb.getUnsyncedSteps();
    for (final day in stepDays) {
      try {
        final resp = await _api.addSteps(day['steps'] as int, logDate: day['date'] as String);
        if (resp.success) {
          await _localDb.markStepSynced(day['date'] as String);
          debugPrint('[Sync] Steps synced for ${day['date']}');
        }
      } catch (e) {
        debugPrint('[Sync] Steps sync failed: $e');
      }
    }
  }

  // ── Process generic queue ──────────────────────────────────────
  Future<void> _syncQueue() async {
    final queue = await _localDb.getPendingQueue();
    for (final item in queue) {
      final id       = item['id'] as int;
      final method   = item['method'] as String;
      final endpoint = item['endpoint'] as String;
      final body     = item['body'] != null ? jsonDecode(item['body'] as String) : null;

      try {
        ApiResponse resp;
        if (method == 'POST')  resp = await _api.post(endpoint, data: body);
        else if (method == 'PUT') resp = await _api.put(endpoint, data: body);
        else if (method == 'DELETE') resp = await _api.delete(endpoint);
        else continue;

        if (resp.success || (resp.statusCode >= 200 && resp.statusCode < 300)) {
          await _localDb.removeFromQueue(id);
          debugPrint('[Sync] Queue item $id synced ($method $endpoint)');
        } else {
          await _localDb.incrementRetry(id);
        }
      } catch (e) {
        await _localDb.incrementRetry(id);
        debugPrint('[Sync] Queue item $id failed: $e');
      }
    }
  }

  // ── Pull reminders from server ─────────────────────────────────
  Future<void> _refreshReminders() async {
    try {
      final resp = await _api.getReminders();
      if (resp.success) {
        final reminders = (resp.data['reminders'] as List).map((r) => {
          'id':                    r['id'],
          'title':                 r['title'],
          'message':               r['message'],
          'category':              r['category'],
          'remind_time':           r['remind_time'],
          'repeat_interval_mins':  r['repeat_interval_mins'] ?? 5,
          'sound_name':            r['sound_name'] ?? 'health_alert',
          'is_active':             r['is_active'] == true ? 1 : 0,
          'is_done_today':         r['is_done_today'] == true ? 1 : 0,
          'last_done_date':        r['last_done_date'],
          'synced':                1,
        }).toList();
        await _localDb.saveReminders(reminders);
        await _localDb.resetDailyReminders();
        debugPrint('[Sync] ${reminders.length} reminders refreshed');
      }
    } catch (e) {
      debugPrint('[Sync] Reminders refresh failed: $e');
    }
  }

  // ── Offline-first save: local first, queue for sync ────────────
  Future<int> saveMetricOffline({
    required String type,
    double? value1, double? value2, double? value3, String? notes,
  }) async {
    // 1. Save locally immediately
    final localId = await _localDb.saveMetric(
        type: type, value1: value1, value2: value2, value3: value3, notes: notes);

    // 2. If online → sync now; else stays in unsynced table
    if (_isOnline) {
      final endpoint = _endpointForType(type);
      final body = _bodyForMetric({
        'type': type, 'value1': value1, 'value2': value2, 'value3': value3, 'notes': notes
      });
      try {
        final resp = await _api.post(endpoint, data: body);
        if (resp.success) {
          await _localDb.markMetricSynced(localId, resp.data?['id'] ?? 0);
        }
      } catch (_) {}
    }

    notifyListeners();
    return localId;
  }

  // ── Helpers ────────────────────────────────────────────────────
  String _endpointForType(String type) {
    switch (type) {
      case 'bp':         return '/tracker/bp';
      case 'weight':     return '/tracker/weight';
      case 'water':      return '/tracker/water';
      case 'sugar':      return '/tracker/sugar';
      case 'sleep':      return '/tracker/sleep';
      case 'heart_rate': return '/tracker/heart-rate';
      default:           return '/tracker/$type';
    }
  }

  Map<String, dynamic> _bodyForMetric(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'bp':
        return {'systolic': m['value1'], 'diastolic': m['value2'], 'pulse': m['value3'], 'notes': m['notes']};
      case 'weight':
        return {'weight_kg': m['value1'], 'notes': m['notes']};
      case 'water':
        return {'amount_litres': m['value1']};
      case 'sugar':
        return {'fasting': m['value1'], 'post_meal': m['value2'], 'notes': m['notes']};
      case 'sleep':
        return {'duration_hours': m['value1'], 'quality': m['value2']?.toInt(), 'notes': m['notes']};
      case 'heart_rate':
        return {'bpm': m['value1']?.toInt(), 'notes': m['notes']};
      default:
        return {'value': m['value1']};
    }
  }

  /// Enqueue any API call for offline retry
  Future<void> enqueue(String method, String endpoint, {Map<String, dynamic>? body}) async {
    await _localDb.enqueue(method, endpoint, body: body != null ? jsonEncode(body) : null);
    _pending++;
    notifyListeners();
    if (_isOnline) syncAll();
  }
}