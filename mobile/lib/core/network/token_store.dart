import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore() {
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<String> getOrCreateDeviceFingerprint();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clearTokens();
  Future<void> clearAll();
}

final class SecureTokenStore({final FlutterSecureStorage? storage})
    implements TokenStore {
  static const String _accessTokenKey = 'ecotrack_access_token';
  static const String _refreshTokenKey = 'ecotrack_refresh_token';
  static const String _deviceFingerprintKey = 'ecotrack_device_fingerprint';

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  FlutterSecureStorage get _effectiveStorage => storage ?? _defaultStorage;

  @override
  Future<String?> getAccessToken() =>
      _effectiveStorage.read(key: _accessTokenKey);

  @override
  Future<String?> getRefreshToken() =>
      _effectiveStorage.read(key: _refreshTokenKey);

  @override
  Future<String> getOrCreateDeviceFingerprint() async {
    final existing = await _effectiveStorage.read(key: _deviceFingerprintKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = UuidV7.generate();
    await _effectiveStorage.write(key: _deviceFingerprintKey, value: created);
    return created;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _effectiveStorage.write(key: _accessTokenKey, value: accessToken);
    await _effectiveStorage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<void> clearTokens() async {
    await _effectiveStorage.delete(key: _accessTokenKey);
    await _effectiveStorage.delete(key: _refreshTokenKey);
  }

  @override
  Future<void> clearAll() => _effectiveStorage.deleteAll();
}

final class InMemoryTokenStore() implements TokenStore {
  String? _accessToken;
  String? _refreshToken;
  String? _deviceFingerprint;

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;

  @override
  Future<String> getOrCreateDeviceFingerprint() async =>
      _deviceFingerprint ??= UuidV7.generate();

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<void> clearAll() async {
    _accessToken = null;
    _refreshToken = null;
    _deviceFingerprint = null;
  }
}
