import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      tz.initializeTimeZones();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
      );

      await _notificationsPlugin.initialize(
        settings: initializationSettings,
      );

      // Request Android 13+ Notification Permission
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      _initialized = true;
      debugPrint('NotificationService initialized successfully.');
    } catch (e) {
      debugPrint('NotificationService initialize error: $e');
    }
  }

  Future<void> schedulePickupNotification({
    required String leaseId,
    required String title,
    required String body,
    required DateTime pickupTime,
  }) async {
    try {
      await initialize();

      final notificationTime = pickupTime.subtract(const Duration(minutes: 30));
      final now = DateTime.now();

      // Only schedule if notification time is in the future
      if (notificationTime.isBefore(now)) {
        debugPrint('Pickup notification time ($notificationTime) is in the past; skipping schedule.');
        return;
      }

      final tz.TZDateTime scheduledTZDate = tz.TZDateTime.from(notificationTime, tz.local);
      final int notificationId = leaseId.hashCode.abs() % 2147483647;

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'rentledger_pickup_channel',
        'Equipment Pick-up Reminders',
        channelDescription: 'Notifications sent 30 minutes before equipment pickup time',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: scheduledTZDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      debugPrint('--> Scheduled 30-min pickup notification for lease $leaseId at $scheduledTZDate');
    } catch (e) {
      debugPrint('NotificationService.schedulePickupNotification error: $e');
    }
  }

  Future<void> cancelNotification(String leaseId) async {
    try {
      final int notificationId = leaseId.hashCode.abs() % 2147483647;
      await _notificationsPlugin.cancel(id: notificationId);
      debugPrint('--> Cancelled pickup notification for lease $leaseId');
    } catch (e) {
      debugPrint('NotificationService.cancelNotification error: $e');
    }
  }
}
