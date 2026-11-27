import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStore() {
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<String?> getAuthProvider();
  Future<bool?> getIsForeignLabMode();
  Future<int?> getExpiresInSeconds();
  Future<String> getOrCreateDeviceFingerprint();
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    int? expiresInSeconds,
    String? authProvider,
    bool? isForeignProviderLabMode,
  });
  Future<void> clearTokens();
  Future<void> clearAll();
}

final class SecureTokenStore({final FlutterSecureStorage? storage})
    implements TokenStore {
  static const String _accessTokenKey = 'ecotrack_access_token';
  static const String _refreshTokenKey = 'ecotrack_refresh_token';
  static const String _deviceFingerprintKey = 'ecotrack_device_fingerprint';
  static const String _authProviderKey = 'ecotrack_auth_provider';
  static const String _foreignLabModeKey = 'ecotrack_is_foreign_lab_mode';
  static const String _expiresInSecondsKey = 'ecotrack_expires_in_seconds';

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
  Future<String?> getAuthProvider() =>
      _effectiveStorage.read(key: _authProviderKey);

  @override
  Future<bool?> getIsForeignLabMode() async {
    final raw = await _effectiveStorage.read(key: _foreignLabModeKey);
    return switch (raw) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  @override
  Future<int?> getExpiresInSeconds() async {
    final raw = await _effectiveStorage.read(key: _expiresInSecondsKey);
    return raw == null ? null : int.tryParse(raw);
  }

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
    int? expiresInSeconds,
    String? authProvider,
    bool? isForeignProviderLabMode,
  }) async {
    await _effectiveStorage.write(key: _accessTokenKey, value: accessToken);
    await _effectiveStorage.write(key: _refreshTokenKey, value: refreshToken);
    if (expiresInSeconds != null) {
      await _effectiveStorage.write(
        key: _expiresInSecondsKey,
        value: expiresInSeconds.toString(),
      );
    }
    if (authProvider != null && authProvider.isNotEmpty) {
      await _effectiveStorage.write(key: _authProviderKey, value: authProvider);
    }
    if (isForeignProviderLabMode != null) {
      await _effectiveStorage.write(
        key: _foreignLabModeKey,
        value: isForeignProviderLabMode ? 'true' : 'false',
      );
    }
  }

  @override
  Future<void> clearTokens() async {
    await _effectiveStorage.delete(key: _accessTokenKey);
    await _effectiveStorage.delete(key: _refreshTokenKey);
    await _effectiveStorage.delete(key: _authProviderKey);
    await _effectiveStorage.delete(key: _foreignLabModeKey);
    await _effectiveStorage.delete(key: _expiresInSecondsKey);
  }

  @override
  Future<void> clearAll() => _effectiveStorage.deleteAll();
}

final class InMemoryTokenStore() implements TokenStore {
  String? _accessToken;
  String? _refreshToken;
  String? _deviceFingerprint;
  String? _authProvider;
  bool? _isForeignLabMode;
  int? _expiresInSeconds;

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;

  @override
  Future<String?> getAuthProvider() async => _authProvider;

  @override
  Future<bool?> getIsForeignLabMode() async => _isForeignLabMode;

  @override
  Future<int?> getExpiresInSeconds() async => _expiresInSeconds;

  @override
  Future<String> getOrCreateDeviceFingerprint() async =>
      _deviceFingerprint ??= UuidV7.generate();

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    int? expiresInSeconds,
    String? authProvider,
    bool? isForeignProviderLabMode,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (expiresInSeconds != null) {
      _expiresInSeconds = expiresInSeconds;
    }
    if (authProvider != null && authProvider.isNotEmpty) {
      _authProvider = authProvider;
    }
    if (isForeignProviderLabMode != null) {
      _isForeignLabMode = isForeignProviderLabMode;
    }
  }

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _authProvider = null;
    _isForeignLabMode = null;
    _expiresInSeconds = null;
  }

  @override
  Future<void> clearAll() async {
    _accessToken = null;
    _refreshToken = null;
    _deviceFingerprint = null;
    _authProvider = null;
    _isForeignLabMode = null;
    _expiresInSeconds = null;
  }
}
