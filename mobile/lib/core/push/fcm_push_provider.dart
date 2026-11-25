import 'dart:async';

import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/push/push_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final class FcmPushProvider({
  final DioClient? dioClient,
  final FirebaseMessaging? messaging,
  final FlutterLocalNotificationsPlugin? localNotifications,
}) implements PushProvider {
  static const String _channelId = 'ecotrack_social_nudges';
  static const String _channelName = 'Эко-уведомления и друзья';
  static const String _channelDescription =
      'Уведомления о прогрессе, зверьке, друзьях и челленджах EcoTrack';

  final StreamController<String> _tokenRefreshController =
      StreamController<String>.broadcast();
  final StreamController<PushMessagePayload> _foregroundController =
      StreamController<PushMessagePayload>.broadcast();
  final StreamController<String> _deepLinkController =
      StreamController<String>.broadcast();

  StreamSubscription<String>? _fcmTokenSub;
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  StreamSubscription<RemoteMessage>? _fcmTapSub;
  String? _lastRegisteredToken;
  bool _initialized = false;
  bool _fcmAvailable = false;

  FlutterLocalNotificationsPlugin get _notifications =>
      localNotifications ?? FlutterLocalNotificationsPlugin();

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<PushMessagePayload> get onForegroundMessage =>
      _foregroundController.stream;

  @override
  Stream<String> get onNotificationTapDeepLink => _deepLinkController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _initLocalNotifications();
    await _initFirebaseMessaging();
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    try {
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null &&
              payload.isNotEmpty &&
              !_deepLinkController.isClosed) {
            _deepLinkController.add(payload);
          }
        },
      );
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _initFirebaseMessaging() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final fcm = messaging ?? FirebaseMessaging.instance;
      await fcm.requestPermission();
      _fcmAvailable = true;

      _fcmTokenSub = fcm.onTokenRefresh.listen((token) {
        if (!_tokenRefreshController.isClosed) {
          _tokenRefreshController.add(token);
        }
      });

      _fcmForegroundSub = FirebaseMessaging.onMessage.listen((message) {
        unawaited(_handleForegroundRemoteMessage(message));
      });

      _fcmTapSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final deepLink = message.data['deep_link'];
        if (deepLink is String &&
            deepLink.isNotEmpty &&
            !_deepLinkController.isClosed) {
          _deepLinkController.add(deepLink);
        }
      });

      final initialMessage = await fcm.getInitialMessage();
      final initialLink = initialMessage?.data['deep_link'];
      if (initialLink is String &&
          initialLink.isNotEmpty &&
          !_deepLinkController.isClosed) {
        _deepLinkController.add(initialLink);
      }
    } on FirebaseException {
      _fcmAvailable = false;
    } on MissingPluginException {
      _fcmAvailable = false;
    } on PlatformException {
      _fcmAvailable = false;
    }
  }

  Future<void> _handleForegroundRemoteMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? 'EcoTrack';
    final body = message.notification?.body ?? '';
    final deepLink = message.data['deep_link'] as String?;
    final dataMap = <String, Object?>{};
    for (final entry in message.data.entries) {
      dataMap[entry.key] = entry.value;
    }
    if (!_foregroundController.isClosed) {
      _foregroundController.add(
        PushMessagePayload(
          title: title,
          body: body,
          deepLinkUri: deepLink,
          data: dataMap,
        ),
      );
    }
    if (body.isNotEmpty) {
      await _showLocalBannerNotification(
        title: title,
        body: body,
        deepLink: deepLink,
      );
    }
  }

  Future<void> _showLocalBannerNotification({
    required String title,
    required String body,
    String? deepLink,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        title,
        body,
        details,
        payload: deepLink,
      );
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  @override
  Future<String?> getDevicePushToken() async {
    if (!_fcmAvailable) {
      return null;
    }
    try {
      final fcm = messaging ?? FirebaseMessaging.instance;
      return await fcm.getToken();
    } on FirebaseException {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> registerCurrentToken({
    required String deviceId,
    String platform = 'fcm_android',
  }) async {
    final client = dioClient;
    if (client == null) {
      return;
    }
    final token = await getDevicePushToken();
    if (token == null || token.length < 8) {
      return;
    }
    _lastRegisteredToken = token;
    await client.post<void>(
      '/api/v1/push/tokens',
      data: <String, Object?>{
        'platform': platform,
        'token': token,
        'device_id': deviceId,
      },
      parser: (_) {},
    );
  }

  @override
  Future<void> unregisterCurrentToken() async {
    final client = dioClient;
    if (client == null) {
      return;
    }
    final token = _lastRegisteredToken ?? await getDevicePushToken();
    if (token == null || token.length < 8) {
      return;
    }
    await client.delete<void>(
      '/api/v1/push/tokens/${Uri.encodeComponent(token)}',
      parser: (_) {},
    );
    _lastRegisteredToken = null;
  }

  @override
  Future<void> dispose() async {
    await _fcmTokenSub?.cancel();
    await _fcmForegroundSub?.cancel();
    await _fcmTapSub?.cancel();
    await _tokenRefreshController.close();
    await _foregroundController.close();
    await _deepLinkController.close();
  }
}
