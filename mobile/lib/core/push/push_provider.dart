import 'dart:async';

final class const PushMessagePayload({
  required final String title,
  required final String body,
  final String? deepLinkUri,
  final Map<String, Object?> data = const <String, Object?>{},
});

abstract interface class const PushProvider() {
  Future<void> initialize();

  Future<String?> getDevicePushToken();

  Stream<String> get onTokenRefresh;

  Stream<PushMessagePayload> get onForegroundMessage;

  Stream<String> get onNotificationTapDeepLink;

  Future<void> registerCurrentToken({
    required String deviceId,
    String platform = 'fcm_android',
  });

  Future<void> unregisterCurrentToken();

  Future<void> dispose();
}
