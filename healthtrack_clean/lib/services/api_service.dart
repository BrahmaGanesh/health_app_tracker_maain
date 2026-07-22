// ============================================================
// lib/services/api_service.dart — HTTP API Client
// Uses: http (no dio), shared_preferences (no flutter_secure_storage)
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_theme.dart';

class ApiResponse {
  final bool success;
  final String message;
  final dynamic data;
  final int statusCode;

  ApiResponse({required this.success, required this.message, this.data, required this.statusCode});

  factory ApiResponse.fromJson(Map<String, dynamic> json, int statusCode) {
    return ApiResponse(
      success:    json['success'] ?? false,
      message:    json['message'] ?? '',
      data:       json['data'],
      statusCode: statusCode,
    );
  }

  factory ApiResponse.error(String message) =>
      ApiResponse(success: false, message: message, statusCode: 0);
}

class ApiService {
  static final ApiService _i = ApiService._();
  factory ApiService() => _i;
  ApiService._();

  // ── Token helpers ─────────────────────────────────────────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  Future<void> saveTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }

  Future<bool> hasToken() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString('access_token');
    return t != null && t.isNotEmpty;
  }

  Map<String, String> _headers(String? token) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('${AppConfig.apiV1}$path');
    if (query == null) return base;
    return base.replace(queryParameters: query.map((k, v) => MapEntry(k, '$v')));
  }

  ApiResponse _parse(http.Response resp) {
    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      return ApiResponse.fromJson(json, resp.statusCode);
    } catch (_) {
      return ApiResponse.error('Invalid server response (${resp.statusCode})');
    }
  }

  // ── Auto-refresh on 401 ───────────────────────────────────────
  Future<bool> _refresh() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final rToken = prefs.getString('refresh_token');
      if (rToken == null) return false;
      final resp = await http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $rToken'},
      );
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        if (json['success'] == true) {
          await prefs.setString('access_token', json['data']['access_token']);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<ApiResponse> _request(Future<http.Response> Function(String? token) call) async {
    try {
      String? token = await _getToken();
      http.Response resp = await call(token);

      // Auto-refresh on 401
      if (resp.statusCode == 401) {
        final ok = await _refresh();
        if (ok) {
          token = await _getToken();
          resp = await call(token);
        }
      }

      return _parse(resp);
    } on http.ClientException catch (e) {
      return ApiResponse.error('No internet connection: ${e.message}');
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // ── Core HTTP methods ─────────────────────────────────────────
  Future<ApiResponse> get(String path, {Map<String, dynamic>? query}) =>
      _request((token) => http.get(_uri(path, query), headers: _headers(token)));

  Future<ApiResponse> post(String path, {dynamic data}) =>
      _request((token) => http.post(_uri(path), headers: _headers(token), body: jsonEncode(data ?? {})));

  Future<ApiResponse> put(String path, {dynamic data}) =>
      _request((token) => http.put(_uri(path), headers: _headers(token), body: jsonEncode(data ?? {})));

  Future<ApiResponse> delete(String path) =>
      _request((token) => http.delete(_uri(path), headers: _headers(token)));

  // ═══════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> register(String name, String email, String password) =>
      post('/auth/register', data: {'name': name, 'email': email, 'password': password});

  Future<ApiResponse> login(String email, String password, {String? fcmToken}) =>
      post('/auth/login', data: {'email': email, 'password': password, 'fcm_token': fcmToken ?? ''});

  Future<ApiResponse> getMe() => get('/auth/me');

  Future<ApiResponse> updateFcmToken(String token) =>
      post('/auth/fcm-token', data: {'fcm_token': token});

  Future<ApiResponse> forgotPassword(String email) =>
      post('/auth/forgot-password', data: {'email': email});

  Future<ApiResponse> resetPassword(String email, String token, String password) =>
      post('/auth/reset-password', data: {'email': email, 'token': token, 'password': password});

  Future<ApiResponse> changePassword(String cur, String nw) =>
      post('/auth/change-password', data: {'current_password': cur, 'new_password': nw});

  Future<ApiResponse> logout() => post('/auth/logout');

  // ═══════════════════════════════════════════════════════════
  // DASHBOARD
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getDashboard() => get('/dashboard/');

  // ═══════════════════════════════════════════════════════════
  // TRACKERS
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> addBP(double sys, double dia, {double? pulse, String? notes}) =>
      post('/tracker/bp', data: {'systolic': sys, 'diastolic': dia, 'pulse': pulse, 'notes': notes});

  Future<ApiResponse> getBP({int days = 7}) => get('/tracker/bp', query: {'days': days});
  Future<ApiResponse> deleteBP(int id) => delete('/tracker/bp/$id');

  Future<ApiResponse> addWeight(double kg, {String? notes}) =>
      post('/tracker/weight', data: {'weight_kg': kg, 'notes': notes});

  Future<ApiResponse> getWeight({int days = 30}) => get('/tracker/weight', query: {'days': days});

  Future<ApiResponse> addWater(double litres) =>
      post('/tracker/water', data: {'amount_litres': litres});

  Future<ApiResponse> getWaterToday() => get('/tracker/water/today');

  Future<ApiResponse> addSugar({double? fasting, double? postMeal, String? notes}) =>
      post('/tracker/sugar', data: {'fasting': fasting, 'post_meal': postMeal, 'notes': notes});

  Future<ApiResponse> getSugar({int days = 30}) => get('/tracker/sugar', query: {'days': days});

  Future<ApiResponse> addSleep({String? sleepTime, String? wakeTime, double? durationHours,
      int? quality, int? interruptions, String? moodOnWake, String? notes}) =>
      post('/tracker/sleep', data: {
        'sleep_time': sleepTime, 'wake_time': wakeTime,
        'duration_hours': durationHours, 'quality': quality,
        'interruptions': interruptions, 'mood_on_wake': moodOnWake, 'notes': notes,
      });

  Future<ApiResponse> getSleep({int days = 14}) => get('/tracker/sleep', query: {'days': days});

  Future<ApiResponse> addSteps(int steps, {String? logDate}) =>
      post('/tracker/steps', data: {'steps': steps, 'log_date': logDate});

  Future<ApiResponse> getSteps({int days = 7}) => get('/tracker/steps', query: {'days': days});

  Future<ApiResponse> addHeartRate(int bpm, {String type = 'resting', String? notes}) =>
      post('/tracker/heart-rate', data: {'bpm': bpm, 'reading_type': type, 'notes': notes});

  Future<ApiResponse> getHeartRate({int days = 7}) => get('/tracker/heart-rate', query: {'days': days});

  Future<ApiResponse> getTodaySummary() => get('/tracker/summary/today');

  Future<ApiResponse> deleteMetric(String type, int id) => delete('/tracker/$type/$id');

  // ═══════════════════════════════════════════════════════════
  // MEALS
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getRecipes({String? search, String category = 'all', String goal = 'all', String diet = 'all', int page = 1}) =>
      get('/meals/recipes', query: {'search': search ?? '', 'category': category, 'goal': goal, 'diet': diet, 'page': page});

  Future<ApiResponse> getRecipe(int id) => get('/meals/recipes/$id');

  Future<ApiResponse> toggleFavourite(int id) => post('/meals/recipes/$id/favourite');

  Future<ApiResponse> getFavourites() => get('/meals/favourites');

  Future<ApiResponse> getMealPlan() => get('/meals/plan');

  Future<ApiResponse> generateMealPlan() => post('/meals/plan/generate');

  Future<ApiResponse> markMealDone(int itemId) => post('/meals/plan/items/$itemId/done');

  Future<ApiResponse> getGroceryList() => get('/meals/grocery');

  Future<ApiResponse> toggleGroceryItem(int id) => post('/meals/grocery/$id/toggle');

  // ═══════════════════════════════════════════════════════════
  // EXERCISE
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> logExercise({required String exerciseName, String exerciseType = 'cardio',
      int? durationMinutes, int? caloriesBurned, int? sets, int? reps, double? distanceKm,
      String intensity = 'moderate', String? notes}) =>
      post('/exercise/log', data: {
        'exercise_name': exerciseName, 'exercise_type': exerciseType,
        'duration_minutes': durationMinutes, 'calories_burned': caloriesBurned,
        'sets': sets, 'reps': reps, 'distance_km': distanceKm,
        'intensity': intensity, 'notes': notes,
      });

  Future<ApiResponse> getExerciseHistory({int days = 7}) => get('/exercise/history', query: {'days': days});

  Future<ApiResponse> deleteExerciseLog(int id) => delete('/exercise/log/$id');

  Future<ApiResponse> getExerciseLibrary({String category = 'all', String difficulty = 'all', bool bpSafe = false}) =>
      get('/exercise/library', query: {'category': category, 'difficulty': difficulty, 'bp_safe': bpSafe});

  Future<ApiResponse> getBreathingConfig() => get('/exercise/breathing/config');

  Future<ApiResponse> logBreathing(String id, int rounds, int durationSecs) =>
      post('/exercise/breathing/log', data: {'exercise_id': id, 'rounds_completed': rounds, 'duration_seconds': durationSecs});

  Future<ApiResponse> saveStopwatchSession(int durationSecs, String name, String type) =>
      post('/exercise/stopwatch/save', data: {'duration_seconds': durationSecs, 'exercise_name': name, 'exercise_type': type});

  // ═══════════════════════════════════════════════════════════
  // NOTIFICATIONS & REMINDERS
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getNotifications({bool unreadOnly = false, int page = 1}) =>
      get('/notifications/', query: {'unread_only': unreadOnly, 'page': page});

  Future<ApiResponse> markNotificationRead(int id) => post('/notifications/$id/read');

  Future<ApiResponse> markAllRead() => post('/notifications/read-all');

  Future<ApiResponse> getUnreadCount() => get('/notifications/unread-count');

  Future<ApiResponse> getReminders() => get('/notifications/reminders');

  Future<ApiResponse> createReminder(Map<String, dynamic> data) =>
      post('/notifications/reminders', data: data);

  Future<ApiResponse> updateReminder(int id, Map<String, dynamic> data) =>
      put('/notifications/reminders/$id', data: data);

  Future<ApiResponse> deleteReminder(int id) => delete('/notifications/reminders/$id');

  Future<ApiResponse> markReminderDone(int id) => post('/notifications/reminders/$id/done');

  Future<ApiResponse> snoozeReminder(int id, int mins) =>
      post('/notifications/reminders/$id/snooze', data: {'minutes': mins});

  Future<ApiResponse> setupDefaultReminders() => post('/notifications/reminders/setup-defaults');

  Future<ApiResponse> sendTestNotification() => post('/notifications/test');

  // ═══════════════════════════════════════════════════════════
  // FAMILY
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getFamilyMembers() => get('/family/members');

  Future<ApiResponse> getFamilyMember(int id) => get('/family/members/$id');

  Future<ApiResponse> addFamilyMember(Map<String, dynamic> data) =>
      post('/family/members', data: data);

  Future<ApiResponse> updateFamilyMember(int id, Map<String, dynamic> data) =>
      put('/family/members/$id', data: data);

  Future<ApiResponse> deleteFamilyMember(int id) => delete('/family/members/$id');

  Future<ApiResponse> logFamilyMetric(int memberId, Map<String, dynamic> data) =>
      post('/family/members/$memberId/metrics', data: data);

  Future<ApiResponse> getFamilyMetrics(int memberId, {String? type}) =>
      get('/family/members/$memberId/metrics', query: type != null ? {'type': type} : null);

  Future<ApiResponse> addFamilyMedicine(int memberId, Map<String, dynamic> data) =>
      post('/family/members/$memberId/medicines', data: data);

  Future<ApiResponse> getFamilyDashboard() => get('/family/dashboard');

  // ═══════════════════════════════════════════════════════════
  // REPORTS
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getEmailConfig() => get('/reports/email-config');

  Future<ApiResponse> saveEmailConfig(Map<String, dynamic> data) =>
      post('/reports/email-config', data: data);

  Future<ApiResponse> sendReportNow({int periodDays = 7, List<String>? recipients}) =>
      post('/reports/send-now', data: {'period_days': periodDays, 'recipients': recipients});

  Future<ApiResponse> getReportHistory() => get('/reports/history');

  // ═══════════════════════════════════════════════════════════
  // MEDICINES (Module 4)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getMedicines({int? memberId}) =>
      get('/medicines/', query: memberId != null ? {'member_id': memberId} : null);

  Future<ApiResponse> addMedicine(Map<String, dynamic> data) => post('/medicines/', data: data);

  Future<ApiResponse> updateMedicine(int id, Map<String, dynamic> data) => put('/medicines/$id', data: data);

  Future<ApiResponse> deleteMedicine(int id) => delete('/medicines/$id');

  Future<ApiResponse> logMedicineTaken(int id, bool taken) =>
      post('/medicines/$id/log', data: {'taken': taken});

  Future<ApiResponse> getMedicineAdherence(int id, {int days = 30}) =>
      get('/medicines/$id/adherence', query: {'days': days});

  Future<ApiResponse> updateMedicineStock(int id, int count) =>
      post('/medicines/$id/stock', data: {'stock_count': count});

  // ═══════════════════════════════════════════════════════════
  // LAB TESTS (Module 8)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getLabTests(String testType, {int? memberId}) =>
      get('/lab-tests/', query: {'test_type': testType, if (memberId != null) 'member_id': memberId});

  Future<ApiResponse> addLabTest(Map<String, dynamic> data) => post('/lab-tests/', data: data);

  Future<ApiResponse> deleteLabTest(int id) => delete('/lab-tests/$id');

  Future<ApiResponse> getLabTestTypes() => get('/lab-tests/types');

  // ═══════════════════════════════════════════════════════════
  // DOCTOR VISITS (Module 9)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getDoctorVisits({int? memberId}) =>
      get('/doctor-visits/', query: memberId != null ? {'member_id': memberId} : null);

  Future<ApiResponse> addDoctorVisit(Map<String, dynamic> data) => post('/doctor-visits/', data: data);

  Future<ApiResponse> deleteDoctorVisit(int id) => delete('/doctor-visits/$id');

  // ═══════════════════════════════════════════════════════════
  // APPOINTMENTS (Module 10)
  // ═══════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════
  // APPOINTMENTS (Module 10 — Complete)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getAppointmentDashboard({int? memberId}) =>
      get('/appointments/dashboard', query: memberId != null ? {'member_id': memberId} : null);

  Future<ApiResponse> getAppointments({String? status, String? apptType, String? search, String? section, int? memberId}) =>
      get('/appointments/', query: {
        if (status != null)    'status':    status,
        if (apptType != null)  'appt_type': apptType,
        if (search != null)    'search':    search,
        if (section != null)   'section':   section,
        if (memberId != null)  'member_id': memberId,
      });

  Future<ApiResponse> addAppointment(Map<String, dynamic> data) => post('/appointments/', data: data);

  Future<ApiResponse> updateAppointment(int id, Map<String, dynamic> data) => put('/appointments/$id', data: data);

  Future<ApiResponse> deleteAppointment(int id) => delete('/appointments/$id');

  Future<ApiResponse> markAppointmentDone(int id) => post('/appointments/$id/status', data: {'action': 'complete'});

  Future<ApiResponse> cancelAppointment(int id) => post('/appointments/$id/status', data: {'action': 'cancel'});

  Future<ApiResponse> markAppointmentMissed(int id) => post('/appointments/$id/status', data: {'action': 'missed'});

  Future<ApiResponse> getAppointmentSettings() => get('/appointments/settings');

  Future<ApiResponse> saveAppointmentSettings(Map<String, dynamic> data) => post('/appointments/settings', data: data);

  // ═══════════════════════════════════════════════════════════
  // DOCUMENTS (Module 11)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getDocuments({String? docType, int? memberId}) =>
      get('/documents/list', query: {if (docType != null) 'type': docType, if (memberId != null) 'member_id': memberId});

  Future<ApiResponse> deleteDocument(int id) => delete('/documents/$id');

  Future<ApiResponse> toggleDocumentImportant(int id) => post('/documents/$id/toggle-important');

  // ═══════════════════════════════════════════════════════════
  // HEALTH SCORE (Module 13)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getHealthScore({String? date}) =>
      get('/health-score/', query: date != null ? {'date': date} : null);

  Future<ApiResponse> getHealthScoreHistory({int days = 30}) =>
      get('/health-score/history', query: {'days': days});

  // ═══════════════════════════════════════════════════════════
  // EMERGENCY CARD (Module 14)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getEmergencyCard({int? memberId}) =>
      get('/emergency-card/', query: memberId != null ? {'member_id': memberId} : null);

  Future<ApiResponse> updateEmergencyCard(Map<String, dynamic> data) =>
      post('/emergency-card/', data: data);

  // ═══════════════════════════════════════════════════════════
  // HABITS (Module 3)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getHabits({int? memberId}) =>
      get('/habits/', query: memberId != null ? {'member_id': memberId} : null);

  Future<ApiResponse> addHabit(Map<String, dynamic> data) => post('/habits/', data: data);

  Future<ApiResponse> logHabit(int id, bool completed, {double? value}) =>
      post('/habits/$id/log', data: {'completed': completed, 'actual_value': value});

  Future<ApiResponse> deleteHabit(int id) => delete('/habits/$id');

  // ═══════════════════════════════════════════════════════════
  // HEALTH TIMELINE (Module 20)
  // ═══════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════
  // HEALTH TIMELINE (Module 20 — Complete)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getTimelineSummary({int? memberId}) =>
      get('/timeline/summary', query: memberId != null ? {'member_id': memberId} : null);

  Future<ApiResponse> getTimeline({int? memberId, String? category, String? search, String sort = 'newest', int page = 1}) =>
      get('/timeline/', query: {
        if (memberId != null)   'member_id': memberId,
        if (category != null)   'category':  category,
        if (search != null)     'search':    search,
        'sort': sort, 'page': page,
      });

  Future<ApiResponse> getTimelineCalendar({required int year, required int month, int? memberId}) =>
      get('/timeline/calendar', query: {'year': year, 'month': month, if (memberId != null) 'member_id': memberId});

  Future<ApiResponse> getTimelineDay({required String date, int? memberId}) =>
      get('/timeline/day', query: {'date': date, if (memberId != null) 'member_id': memberId});

  Future<ApiResponse> getFamilyTimeline({int page = 1}) =>
      get('/timeline/family', query: {'page': page});

  Future<ApiResponse> deleteTimelineEvent(int id) =>
      delete('/timeline/$id');

  // ═══════════════════════════════════════════════════════════
  // AI ASSISTANT (Module 19)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> sendAiMessage(String message, {List<Map<String, String>>? history}) =>
      post('/ai-assistant/chat', data: {'message': message, 'history': history ?? []});

  // ═══════════════════════════════════════════════════════════
  // AI CAMERA (Module 6)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> analyzeFoodPhoto(String base64Image) =>
      post('/ai-camera/food', data: {'image': base64Image});

  Future<ApiResponse> analyzeMedicinePhoto(String base64Image) =>
      post('/ai-camera/medicine', data: {'image': base64Image});

  // ═══════════════════════════════════════════════════════════
  // SUBSCRIPTION (Premium / Family plans)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getSubscriptionStatus() => get('/subscription/status');

  Future<ApiResponse> verifyPurchase(String purchaseToken, String productId) =>
      post('/subscription/verify', data: {'purchase_token': purchaseToken, 'product_id': productId});

  Future<ApiResponse> cancelSubscription() => post('/subscription/cancel');

  // ═══════════════════════════════════════════════════════════
  // EMERGENCY ALERTS (Module 15)
  // ═══════════════════════════════════════════════════════════
  Future<ApiResponse> getTrustedContacts() => get('/emergency-alerts/contacts');

  Future<ApiResponse> addTrustedContact(Map<String, dynamic> data) =>
      post('/emergency-alerts/contacts', data: data);

  Future<ApiResponse> deleteTrustedContact(int id) => delete('/emergency-alerts/contacts/$id');
}