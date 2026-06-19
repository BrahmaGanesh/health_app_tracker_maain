class NotificationService {
  NotificationService();

  Future<void> init({
    void Function(Map<String, dynamic>)? onNotificationTap,
  }) async {}

  Future<void> playSound(String sound) async {}

  Future<void> sendTestNotification() async {}

  Future<void> markReminderDone(int id) async {}

  Future<void> snoozeReminder(int id, {int minutes = 10}) async {}

  Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required DateTime dateTime,
  }) async {}

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {}

  Future<void> cancel(int id) async {}

  Future<void> cancelAll() async {}
}