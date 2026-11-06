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

      final now = DateTime.now();

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'rentledger_pickup_channel',
        'Equipment Pick-up Reminders',
        channelDescription: 'Notifications sent before and at equipment pickup time',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );

      // 1. Schedule 30-minute advance notification
      final notificationTime30m = pickupTime.subtract(const Duration(minutes: 30));
      final int notificationId1 = leaseId.hashCode.abs() % 2147483647;

      if (notificationTime30m.isAfter(now)) {
        final tz.TZDateTime scheduledTZDate30m = tz.TZDateTime.from(notificationTime30m, tz.local);
        await _notificationsPlugin.zonedSchedule(
          id: notificationId1,
          title: title,
          body: body,
          scheduledDate: scheduledTZDate30m,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('--> Scheduled 30-min pickup notification for lease $leaseId at $scheduledTZDate30m');
      } else {
        debugPrint('30-min notification time ($notificationTime30m) is past; skipped.');
      }

      // 2. Schedule exact pickup time notification
      final int notificationId2 = (leaseId.hashCode.abs() + 1) % 2147483647;
      if (pickupTime.isAfter(now)) {
        final tz.TZDateTime scheduledTZDatePickup = tz.TZDateTime.from(pickupTime, tz.local);
        await _notificationsPlugin.zonedSchedule(
          id: notificationId2,
          title: '🚨 Equipment Pick-up Time Now!',
          body: title.replaceAll('⏰ Equipment Pick-up Reminder', '').trim().isNotEmpty
              ? title
              : body,
          scheduledDate: scheduledTZDatePickup,
          notificationDetails: notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('--> Scheduled exact pickup time notification for lease $leaseId at $scheduledTZDatePickup');
      } else {
        debugPrint('Exact pickup time ($pickupTime) is past; skipped.');
      }
    } catch (e) {
      debugPrint('NotificationService.schedulePickupNotification error: $e');
    }
  }

  Future<void> cancelNotification(String leaseId) async {
    try {
      final int notificationId1 = leaseId.hashCode.abs() % 2147483647;
      final int notificationId2 = (leaseId.hashCode.abs() + 1) % 2147483647;
      await _notificationsPlugin.cancel(id: notificationId1);
      await _notificationsPlugin.cancel(id: notificationId2);
      debugPrint('--> Cancelled pickup notifications for lease $leaseId');
    } catch (e) {
      debugPrint('NotificationService.cancelNotification error: $e');
    }
  }
}
