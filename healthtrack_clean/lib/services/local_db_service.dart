// lib/services/local_db_service.dart
// Offline-first local SQLite database
// Stores all health data locally → syncs to server when online

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDb {
  static final LocalDb _i = LocalDb._();
  factory LocalDb() => _i;
  LocalDb._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'healthtrack.db');
    return openDatabase(path, version: 1, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    // ── Metrics (BP, weight, water, sugar, steps, sleep, heart rate) ──
    await db.execute('''
      CREATE TABLE metrics (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id   INTEGER,
        type        TEXT NOT NULL,
        value1      REAL,
        value2      REAL,
        value3      REAL,
        notes       TEXT,
        log_date    TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        synced      INTEGER DEFAULT 0,
        deleted     INTEGER DEFAULT 0
      )
    ''');

    // ── Step daily log (one row per day, cumulative) ───────────────
    await db.execute('''
      CREATE TABLE step_days (
        date          TEXT PRIMARY KEY,
        steps         INTEGER DEFAULT 0,
        distance_km   REAL DEFAULT 0,
        calories      INTEGER DEFAULT 0,
        goal          INTEGER DEFAULT 8000,
        synced        INTEGER DEFAULT 0
      )
    ''');

    // ── Sync queue (pending API calls) ─────────────────────────────
    await db.execute('''
      CREATE TABLE sync_queue (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        method      TEXT NOT NULL,
        endpoint    TEXT NOT NULL,
        body        TEXT,
        created_at  TEXT NOT NULL,
        retries     INTEGER DEFAULT 0
      )
    ''');

    // ── Reminders (cached locally) ──────────────────────────────────
    await db.execute('''
      CREATE TABLE reminders (
        id                  INTEGER PRIMARY KEY,
        title               TEXT,
        message             TEXT,
        category            TEXT,
        remind_time         TEXT,
        repeat_interval_mins INTEGER DEFAULT 5,
        sound_name          TEXT DEFAULT 'health_alert',
        is_active           INTEGER DEFAULT 1,
        is_done_today       INTEGER DEFAULT 0,
        last_done_date      TEXT,
        synced              INTEGER DEFAULT 0
      )
    ''');

    // ── Meals cache ─────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE meal_cache (
        key   TEXT PRIMARY KEY,
        value TEXT,
        cached_at TEXT
      )
    ''');

    // ── Cached dashboard ────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE app_cache (
        key       TEXT PRIMARY KEY,
        value     TEXT,
        cached_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {}

  // ════════════════════════════════════════════════════════════════
  // METRICS
  // ════════════════════════════════════════════════════════════════

  Future<int> saveMetric({
    required String type,
    double? value1, double? value2, double? value3,
    String? notes,
  }) async {
    final d = await db;
    final now = DateTime.now();
    return d.insert('metrics', {
      'type':        type,
      'value1':      value1,
      'value2':      value2,
      'value3':      value3,
      'notes':       notes,
      'log_date':    now.toIso8601String().substring(0, 10),
      'recorded_at': now.toIso8601String(),
      'synced':      0,
    });
  }

  Future<List<Map<String, dynamic>>> getMetrics(String type, {int days = 30}) async {
    final d = await db;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String().substring(0, 10);
    return d.query('metrics',
        where: 'type=? AND log_date>=? AND deleted=0',
        whereArgs: [type, since],
        orderBy: 'recorded_at DESC');
  }

  Future<Map<String, dynamic>?> getLatestMetric(String type) async {
    final d = await db;
    final rows = await d.query('metrics', where: 'type=? AND deleted=0', whereArgs: [type], orderBy: 'recorded_at DESC', limit: 1);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> deleteMetricLocal(int id) async {
    final d = await db;
    return d.update('metrics', {'deleted': 1}, where: 'id=?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedMetrics() async {
    final d = await db;
    return d.query('metrics', where: 'synced=0 AND deleted=0');
  }

  Future<void> markMetricSynced(int localId, int serverId) async {
    final d = await db;
    await d.update('metrics', {'synced': 1, 'server_id': serverId}, where: 'id=?', whereArgs: [localId]);
  }

  // ════════════════════════════════════════════════════════════════
  // STEP DAILY LOG — with daily reset
  // ════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getTodaySteps() async {
    final d = await db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await d.query('step_days', where: 'date=?', whereArgs: [today]);
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<void> upsertTodaySteps(int steps, int goal) async {
    final d = await db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final h = goal > 0 ? steps / goal : 0;
    final strideM = 0.00076; // avg stride 76cm
    final distKm  = double.parse((steps * strideM).toStringAsFixed(2));
    final calories = (steps * 0.04).toInt();
    await d.insert('step_days', {
      'date': today, 'steps': steps, 'distance_km': distKm,
      'calories': calories, 'goal': goal, 'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Returns last N days of step data
  Future<List<Map<String, dynamic>>> getWeekSteps({int days = 7}) async {
    final d = await db;
    final since = DateTime.now().subtract(Duration(days: days - 1)).toIso8601String().substring(0, 10);
    return d.query('step_days', where: 'date>=?', whereArgs: [since], orderBy: 'date ASC');
  }

  Future<List<Map<String, dynamic>>> getUnsyncedSteps() async {
    final d = await db;
    return d.query('step_days', where: 'synced=0');
  }

  Future<void> markStepSynced(String date) async {
    final d = await db;
    await d.update('step_days', {'synced': 1}, where: 'date=?', whereArgs: [date]);
  }

  // ════════════════════════════════════════════════════════════════
  // SYNC QUEUE
  // ════════════════════════════════════════════════════════════════

  Future<void> enqueue(String method, String endpoint, {String? body}) async {
    final d = await db;
    await d.insert('sync_queue', {
      'method': method, 'endpoint': endpoint,
      'body': body, 'created_at': DateTime.now().toIso8601String(), 'retries': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingQueue() async {
    final d = await db;
    return d.query('sync_queue', where: 'retries < 5', orderBy: 'created_at ASC');
  }

  Future<void> removeFromQueue(int id) async {
    final d = await db;
    await d.delete('sync_queue', where: 'id=?', whereArgs: [id]);
  }

  Future<void> incrementRetry(int id) async {
    final d = await db;
    await d.rawUpdate('UPDATE sync_queue SET retries = retries + 1 WHERE id = ?', [id]);
  }

  // ════════════════════════════════════════════════════════════════
  // REMINDERS (local cache)
  // ════════════════════════════════════════════════════════════════

  Future<void> saveReminders(List<Map<String, dynamic>> reminders) async {
    final d = await db;
    final batch = d.batch();
    for (final r in reminders) {
      batch.insert('reminders', r, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getCachedReminders() async {
    final d = await db;
    return d.query('reminders', where: 'is_active=1', orderBy: 'remind_time ASC');
  }

  Future<void> markReminderDoneLocal(int id) async {
    final d = await db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await d.update('reminders', {'is_done_today': 1, 'last_done_date': today}, where: 'id=?', whereArgs: [id]);
  }

  /// Reset done status at midnight
  Future<void> resetDailyReminders() async {
    final d = await db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await d.rawUpdate(
        'UPDATE reminders SET is_done_today=0 WHERE last_done_date != ? OR last_done_date IS NULL', [today]);
  }

  // ════════════════════════════════════════════════════════════════
  // APP CACHE (dashboard, recipes etc.)
  // ════════════════════════════════════════════════════════════════

  Future<void> setCache(String key, String value) async {
    final d = await db;
    await d.insert('app_cache', {
      'key': key, 'value': value, 'cached_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getCache(String key, {int maxAgeMinutes = 60}) async {
    final d = await db;
    final rows = await d.query('app_cache', where: 'key=?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final cached = DateTime.parse(rows.first['cached_at'] as String);
    if (DateTime.now().difference(cached).inMinutes > maxAgeMinutes) return null;
    return rows.first['value'] as String;
  }

  Future<void> clearCache() async {
    final d = await db;
    await d.delete('app_cache');
  }
}