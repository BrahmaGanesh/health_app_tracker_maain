import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationTapHandler = void Function(Map<String, dynamic> data);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService().showRemoteMessageAsLocal(message);
}

@pragma('vm:entry-point')
void _onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  NotificationService().handleBackgroundNotificationTap(response);
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _player = AudioPlayer();

  bool _initialized = false;
  NotificationTapHandler? _onTap;

  static const List<String> _sounds = [
    'health_alert',
    'water_drop',
    'medicine',
    'gentle',
    'urgent',
  ];

  Future<void> init({
    NotificationTapHandler? onNotificationTap,
  }) async {
    if (_initialized) {
      _onTap = onNotificationTap ?? _onTap;
      return;
    }

    _onTap = onNotificationTap;

    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        _handleTapPayload(details.payload);
      },
      onDidReceiveBackgroundNotificationResponse:
          _onDidReceiveBackgroundNotificationResponse,
    );

    await _createAndroidChannels();

    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _showLocalNotification(
        title: message.notification?.title ?? 'HealthTrack',
        body: message.notification?.body ?? '',
        data: message.data,
        sound: message.data['sound'] ?? 'health_alert',
      );

      await playSound(message.data['sound'] ?? 'health_alert');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleTapData(message.data);
    });

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleTapData(initialMessage.data);
    }

    _initialized = true;
    debugPrint('[Notifications] Initialised');
  }

  Future<void> showRemoteMessageAsLocal(RemoteMessage message) async {
    await _showLocalNotification(
      title: message.notification?.title ?? 'HealthTrack',
      body: message.notification?.body ?? '',
      data: message.data,
      sound: message.data['sound'] ?? 'health_alert',
    );
  }

  void handleBackgroundNotificationTap(NotificationResponse response) {
    _handleTapPayload(response.payload);
  }

  Future<void> _createAndroidChannels() async {
    if (!Platform.isAndroid) return;

    final plugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (plugin == null) return;

    for (final sound in _sounds) {
      final channel = AndroidNotificationChannel(
        'health_tracker_channel_$sound',
        'HealthTrack ($sound)',
        description: 'Health reminders with $sound sound',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(sound),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
      );

      await plugin.createNotificationChannel(channel);
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String sound = 'health_alert',
  }) async {
    final validSound = _sounds.contains(sound) ? sound : 'health_alert';
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'health_tracker_channel_$validSound',
        'HealthTrack ($validSound)',
        channelDescription: 'Health reminders',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(validSound),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF142D4C),
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: DarwinNotificationDetails(
        sound: '$validSound.aiff',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _local.show(
      id,
      title,
      body,
      details,
      payload: data == null ? null : jsonEncode(data),
    );
  }

  Future<void> playSound(String soundName) async {
    final valid = _sounds.contains(soundName) ? soundName : 'health_alert';

    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$valid.mp3'));
    } catch (e) {
      debugPrint('[Notifications] Sound play error: $e');
    }
  }

  Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('[Notifications] FCM token error: $e');
      return null;
    }
  }

  Future<void> sendTestNotification() async {
    await _showLocalNotification(
      title: '🔔 HealthTrack Test',
      body: 'Notifications are working! Sounds and alerts are active.',
      sound: 'health_alert',
    );
    await playSound('health_alert');
  }

  Future<void> markReminderDone(int reminderId) async {
    await _local.cancel(reminderId);
    await playSound('gentle');
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    String sound = 'health_alert',
  }) async {
    final now = DateTime.now();
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _showLocalNotification(
      title: title,
      body: body,
      sound: sound,
      data: {
        'type': 'reminder',
        'id': id,
        'scheduled_at': scheduled.toIso8601String(),
      },
    );

    debugPrint(
      '[Notifications] Scheduled $title for ${scheduled.toIso8601String()}',
    );
  }

  Future<void> cancelAll() async {
    await _local.cancelAll();
  }

  void _handleTapPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        _handleTapData(decoded);
        return;
      }
      if (decoded is Map) {
        _handleTapData(Map<String, dynamic>.from(decoded));
        return;
      }
    } catch (_) {
      // Fallback if payload is not valid JSON
    }

    final map = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        map[parts[0]] = parts[1];
      }
    }

    if (map.isNotEmpty) {
      _handleTapData(map);
    }
  }

  void _handleTapData(Map<String, dynamic> data) {
    debugPrint('[Notifications] Tapped: $data');
    _onTap?.call(data);
  }
}