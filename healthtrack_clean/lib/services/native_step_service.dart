import 'package:flutter/services.dart';

class NativeStepService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.healthtrack/steps');

  static const EventChannel _eventChannel =
      EventChannel('com.healthtrack/steps_stream');

  Stream<Map<String, dynamic>> get stepStream {
    return _eventChannel.receiveBroadcastStream().map((dynamic event) {
      final map = Map<dynamic, dynamic>.from(event as Map);
      return {
        'steps': (map['steps'] ?? 0) as int,
        'isTracking': (map['isTracking'] ?? false) as bool,
      };
    });
  }

  Future<bool> startTracking() async {
    final result = await _methodChannel.invokeMethod<bool>('startTracking');
    return result ?? false;
  }

  Future<bool> stopTracking() async {
    final result = await _methodChannel.invokeMethod<bool>('stopTracking');
    return result ?? false;
  }

  Future<int> getCurrentSteps() async {
    final result = await _methodChannel.invokeMethod<int>('getCurrentSteps');
    return result ?? 0;
  }

  Future<bool> isTracking() async {
    final result = await _methodChannel.invokeMethod<bool>('isTracking');
    return result ?? false;
  }
}