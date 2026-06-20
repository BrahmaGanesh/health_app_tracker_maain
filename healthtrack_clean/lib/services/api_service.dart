// ============================================================
// lib/services/api_service.dart — Central API Client
// All /api/v1/* calls go through here using Dio + JWT
// ============================================================

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_theme.dart';

class ApiResponse {
  final bool success;
  final String message;
  final dynamic data;
  final int statusCode;

  ApiResponse({required this.success, required this.message, this.data, required this.statusCode});

  factory ApiResponse.fromJson(Map<String, dynamic> json, int statusCode) {
    return ApiResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      data: json['data'],
      statusCode: statusCode,
    );
  }

  factory ApiResponse.error(String message) {
    return ApiResponse(success: false, message: message, statusCode: 0);
  }
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiV1,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    // Attach JWT token to every request
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException error, handler) async {
        // Auto-refresh token on 401
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final cloneReq = await _dio.fetch(error.requestOptions);
              return handler.resolve(cloneReq);
            } catch (e) {
              return handler.next(error);
            }
          }
        }
        return handler.next(error);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;

      final dio = Dio(BaseOptions(baseUrl: AppConfig.apiV1));
      final resp = await dio.post('/auth/refresh',
          options: Options(headers: {'Authorization': 'Bearer $refreshToken'}));

      if (resp.statusCode == 200 && resp.data['success'] == true) {
        await _storage.write(key: 'access_token', value: resp.data['data']['access_token']);
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  // ── Generic request handlers ──────────────────────────────────
  Future<ApiResponse> get(String path, {Map<String, dynamic>? query}) async {
    try {
      final resp = await _dio.get(path, queryParameters: query);
      return ApiResponse.fromJson(resp.data, resp.statusCode ?? 200);
    } catch (e) {
      return _handleError(e);
    }
  }

  Future<ApiResponse> post(String path, {dynamic data}) async {
    try {
      final resp = await _dio.post(path, data: data);
      return ApiResponse.fromJson(resp.data, resp.statusCode ?? 200);
    } catch (e) {
      return _handleError(e);
    }
  }

  Future<ApiResponse> put(String path, {dynamic data}) async {
    try {
      final resp = await _dio.put(path, data: data);
      return ApiResponse.fromJson(resp.data, resp.statusCode ?? 200);
    } catch (e) {
      return _handleError(e);
    }
  }

  Future<ApiResponse> delete(String path) async {
    try {
      final resp = await _dio.delete(path);
      return ApiResponse.fromJson(resp.data, resp.statusCode ?? 200);
    } catch (e) {
      return _handleError(e);
    }
  }

   ApiResponse _handleError(dynamic e) {
     print("====================");
     print(e);
     print(e.runtimeType);

     if (e is DioException) {
       print("TYPE: ${e.type}");
       print("MESSAGE: ${e.message}");
       print("STATUS: ${e.response?.statusCode}");
       print("BODY: ${e.response?.data}");

       if (e.response?.data != null) {
         return ApiResponse.error(e.response!.data.toString());
       }

       if (e.type == DioExceptionType.connectionTimeout ||
           e.type == DioExceptionType.connectionError) {
         return ApiResponse.error("No internet connection.");
       }

       return ApiResponse.error(
           "HTTP ${e.response?.statusCode ?? 'Unknown'}");
     }

     return ApiResponse.error(e.toString());
   }


  // ════════════════════════════════════════════════════════════
  // AUTH
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> register(String name, String email, String password) =>
      post('/auth/register', data: {'name': name, 'email': email, 'password': password});

  Future<ApiResponse> login(String email, String password, {String? fcmToken}) {
    print("LOGIN URL: ${AppConfig.apiV1}/auth/login");

    return post(
      '/auth/login',
      data: {
        'email': email,
        'password': password,
        'fcm_token': fcmToken,
      },
    );
  }
  Future<ApiResponse> getMe() => get('/auth/me');

  Future<ApiResponse> updateFcmToken(String token) =>
      post('/auth/fcm-token', data: {'fcm_token': token});

  Future<ApiResponse> forgotPassword(String email) =>
      post('/auth/forgot-password', data: {'email': email});

  Future<ApiResponse> resetPassword(String email, String token, String password) =>
      post('/auth/reset-password', data: {'email': email, 'token': token, 'password': password});

  Future<ApiResponse> changePassword(String currentPw, String newPw) =>
      post('/auth/change-password', data: {'current_password': currentPw, 'new_password': newPw});

  Future<ApiResponse> logout() => post('/auth/logout');

  // ════════════════════════════════════════════════════════════
  // DASHBOARD
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> getDashboard() => get('/dashboard/');

  // ════════════════════════════════════════════════════════════
  // TRACKERS
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> addBP(double systolic, double diastolic, {double? pulse, String? notes}) =>
      post('/tracker/bp', data: {'systolic': systolic, 'diastolic': diastolic, 'pulse': pulse, 'notes': notes});

  Future<ApiResponse> getBP({int days = 7}) => get('/tracker/bp', query: {'days': days});

  Future<ApiResponse> deleteBP(int id) => delete('/tracker/bp/$id');

  Future<ApiResponse> addWeight(double weightKg, {String? notes}) =>
      post('/tracker/weight', data: {'weight_kg': weightKg, 'notes': notes});

  Future<ApiResponse> getWeight({int days = 30}) => get('/tracker/weight', query: {'days': days});

  Future<ApiResponse> addWater(double litres) =>
      post('/tracker/water', data: {'amount_litres': litres});

  Future<ApiResponse> getWaterToday() => get('/tracker/water/today');

  Future<ApiResponse> addSugar({double? fasting, double? postMeal, String? notes}) =>
      post('/tracker/sugar', data: {'fasting': fasting, 'post_meal': postMeal, 'notes': notes});

  Future<ApiResponse> getSugar({int days = 30}) => get('/tracker/sugar', query: {'days': days});

  Future<ApiResponse> addSleep({
    String? sleepTime, String? wakeTime, double? durationHours,
    int? quality, int? interruptions, String? moodOnWake, String? notes,
  }) => post('/tracker/sleep', data: {
        'sleep_time': sleepTime, 'wake_time': wakeTime, 'duration_hours': durationHours,
        'quality': quality, 'interruptions': interruptions,
        'mood_on_wake': moodOnWake, 'notes': notes,
      });

  Future<ApiResponse> getSleep({int days = 14}) => get('/tracker/sleep', query: {'days': days});

  Future<ApiResponse> addSteps(int steps, {String? logDate}) =>
      post('/tracker/steps', data: {'steps': steps, 'log_date': logDate});

  Future<ApiResponse> getSteps({int days = 7}) => get('/tracker/steps', query: {'days': days});

  Future<ApiResponse> addHeartRate(int bpm, {String readingType = 'resting', String? notes}) =>
      post('/tracker/heart-rate', data: {'bpm': bpm, 'reading_type': readingType, 'notes': notes});

  Future<ApiResponse> getHeartRate({int days = 7}) => get('/tracker/heart-rate', query: {'days': days});

  Future<ApiResponse> getTodaySummary() => get('/tracker/summary/today');

  Future<ApiResponse> deleteMetric(String type, int id) => delete('/tracker/$type/$id');

  // ════════════════════════════════════════════════════════════
  // MEALS & RECIPES
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> getRecipes({String? search, String category = 'all', String goal = 'all', String diet = 'all', int page = 1}) =>
      get('/meals/recipes', query: {'search': search ?? '', 'category': category, 'goal': goal, 'diet': diet, 'page': page});

  Future<ApiResponse> getRecipe(int id) => get('/meals/recipes/$id');

  Future<ApiResponse> toggleFavourite(int recipeId) => post('/meals/recipes/$recipeId/favourite');

  Future<ApiResponse> getFavourites() => get('/meals/favourites');

  Future<ApiResponse> getMealPlan() => get('/meals/plan');

  Future<ApiResponse> generateMealPlan() => post('/meals/plan/generate');

  Future<ApiResponse> markMealDone(int itemId) => post('/meals/plan/items/$itemId/done');

  Future<ApiResponse> getGroceryList() => get('/meals/grocery');

  Future<ApiResponse> toggleGroceryItem(int itemId) => post('/meals/grocery/$itemId/toggle');

  // ════════════════════════════════════════════════════════════
  // EXERCISE
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> logExercise({
    required String exerciseName, String exerciseType = 'cardio',
    int? durationMinutes, int? caloriesBurned, int? sets, int? reps,
    double? distanceKm, String intensity = 'moderate', String? notes,
  }) => post('/exercise/log', data: {
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

  Future<ApiResponse> logBreathing(String exerciseId, int rounds, int durationSeconds) =>
      post('/exercise/breathing/log', data: {'exercise_id': exerciseId, 'rounds_completed': rounds, 'duration_seconds': durationSeconds});

  Future<ApiResponse> saveStopwatchSession(int durationSeconds, String exerciseName, String exerciseType) =>
      post('/exercise/stopwatch/save', data: {'duration_seconds': durationSeconds, 'exercise_name': exerciseName, 'exercise_type': exerciseType});

  // ════════════════════════════════════════════════════════════
  // NOTIFICATIONS & REMINDERS
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> getNotifications({bool unreadOnly = false, int page = 1}) =>
      get('/notifications/', query: {'unread_only': unreadOnly, 'page': page});

  Future<ApiResponse> markNotificationRead(int id) => post('/notifications/$id/read');

  Future<ApiResponse> markAllRead() => post('/notifications/read-all');

  Future<ApiResponse> getUnreadCount() => get('/notifications/unread-count');

  Future<ApiResponse> getReminders() => get('/notifications/reminders');

  Future<ApiResponse> createReminder(Map<String, dynamic> data) => post('/notifications/reminders', data: data);

  Future<ApiResponse> updateReminder(int id, Map<String, dynamic> data) => put('/notifications/reminders/$id', data: data);

  Future<ApiResponse> deleteReminder(int id) => delete('/notifications/reminders/$id');

  Future<ApiResponse> markReminderDone(int id) => post('/notifications/reminders/$id/done');

  Future<ApiResponse> snoozeReminder(int id, int minutes) =>
      post('/notifications/reminders/$id/snooze', data: {'minutes': minutes});

  Future<ApiResponse> setupDefaultReminders() => post('/notifications/reminders/setup-defaults');

  Future<ApiResponse> sendTestNotification() => post('/notifications/test');

  // ════════════════════════════════════════════════════════════
  // FAMILY
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> getFamilyMembers() => get('/family/members');

  Future<ApiResponse> getFamilyMember(int id) => get('/family/members/$id');

  Future<ApiResponse> addFamilyMember(Map<String, dynamic> data) => post('/family/members', data: data);

  Future<ApiResponse> updateFamilyMember(int id, Map<String, dynamic> data) => put('/family/members/$id', data: data);

  Future<ApiResponse> deleteFamilyMember(int id) => delete('/family/members/$id');

  Future<ApiResponse> logFamilyMetric(int memberId, Map<String, dynamic> data) =>
      post('/family/members/$memberId/metrics', data: data);

  Future<ApiResponse> getFamilyMetrics(int memberId, {String? type}) =>
      get('/family/members/$memberId/metrics', query: type != null ? {'type': type} : null);

  Future<ApiResponse> addFamilyMedicine(int memberId, Map<String, dynamic> data) =>
      post('/family/members/$memberId/medicines', data: data);

  Future<ApiResponse> getFamilyDashboard() => get('/family/dashboard');

  // ════════════════════════════════════════════════════════════
  // REPORTS
  // ════════════════════════════════════════════════════════════
  Future<ApiResponse> getEmailConfig() => get('/reports/email-config');

  Future<ApiResponse> saveEmailConfig(Map<String, dynamic> data) => post('/reports/email-config', data: data);

  Future<ApiResponse> sendReportNow({int periodDays = 7, List<String>? recipients}) =>
      post('/reports/send-now', data: {'period_days': periodDays, 'recipients': recipients});

  Future<ApiResponse> getReportHistory() => get('/reports/history');

  // ── Token storage helpers ─────────────────────────────────────
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<bool> hasToken() async {
    final token = await _storage.read(key: 'access_token');
    return token != null && token.isNotEmpty;
  }
}