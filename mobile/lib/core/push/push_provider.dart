import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract interface class PushProvider {
  Future<void> initialize();
  Future<String?> getDeviceToken();
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  });
}

final class LocalPushProvider implements PushProvider {
  LocalPushProvider({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
  }

  @override
  Future<String?> getDeviceToken() async => 'mock-device-token-ecotrack';

  @override
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'ecotrack_general',
      'ЭкоТрек Уведомления',
      channelDescription:
          'Напоминания о шагах, целях и экологических челленджах',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details, payload: payload);
  }
}
