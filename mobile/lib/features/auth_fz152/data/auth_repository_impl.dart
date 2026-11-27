import 'dart:async';

import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';
import 'package:ecotrack_mobile/core/push/push_provider.dart';
import 'package:ecotrack_mobile/features/auth_fz152/data/oauth_pkce_client.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class AuthRepositoryImpl(
  final DioClient _dioClient,
  final TokenStore _tokenStore,
  final ProfileRepository _profileRepo,
  final OAuthPkceClient _pkceClient,
  final PushProvider _pushProvider,
) implements AuthRepository, AuthSessionNotifier {
  static const String _onboardingSeenKey = 'ecotrack_onboarding_seen';
  static const String _policyVersion = '1.0.0-2026';

  final StreamController<void> _sessionEndedController =
      StreamController<void>.broadcast();

  @override
  Stream<void> get onSessionEnded => _sessionEndedController.stream;

  Future<void> dispose() => _sessionEndedController.close();

  @override
  Future<Result<AuthSession?, AppError>> restoreSession() async {
    final accessToken = await _tokenStore.getAccessToken();
    final refreshToken = await _tokenStore.getRefreshToken();
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      return const Ok(null);
    }

    final cachedProfile = await _profileRepo.getCachedProfileSnapshot();
    final storedProviderRaw = await _tokenStore.getAuthProvider();
    final storedProvider = storedProviderRaw != null
        ? AuthProviderType.fromWire(storedProviderRaw)
        : null;
    final storedLabMode = await _tokenStore.getIsForeignLabMode();
    final storedExpiresIn = await _tokenStore.getExpiresInSeconds();
    var resolvedExpiresIn = storedExpiresIn ?? 900;

    final profileRes = await _dioClient.get<UserProfile>(
      '/api/v1/users/me',
      parser: (data) => _parseOrThrow(data, (map) {
        if (map['expires_in_seconds'] case final num rawExpires) {
          resolvedExpiresIn = rawExpires.toInt();
        }
        final hasServerProvider = map['auth_provider'] is String;
        final hasServerLabMode = map['is_foreign_provider_lab_mode'] is bool;
        return UserProfile.fromJson(
          map,
          authProviderOverride: hasServerProvider
              ? null
              : (cachedProfile?.authProvider ?? storedProvider),
          isForeignLabModeOverride: hasServerLabMode
              ? null
              : (cachedProfile?.isForeignProviderLabMode ?? storedLabMode),
        );
      }),
    );

    switch (profileRes) {
      case Ok(:final value):
        await _tokenStore.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresInSeconds: resolvedExpiresIn,
          authProvider: value.authProvider.wireName,
          isForeignProviderLabMode: value.isForeignProviderLabMode,
        );
        await _profileRepo.cacheProfile(
          value,
          authProvider: value.authProvider,
          isForeignLabMode: value.isForeignProviderLabMode,
        );
        return Ok(
          AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresInSeconds: resolvedExpiresIn,
            isForeignProviderLabMode: value.isForeignProviderLabMode,
            labModeWarningBanner: value.isForeignProviderLabMode
                ? _defaultGoogleLabBanner
                : null,
            user: value,
          ),
        );
      case Err(:final error):
        if (_isOfflineError(error) && cachedProfile != null) {
          final offlineLabMode =
              cachedProfile.isForeignProviderLabMode ||
              (storedLabMode ?? false);
          return Ok(
            AuthSession(
              accessToken: accessToken,
              refreshToken: refreshToken,
              expiresInSeconds: resolvedExpiresIn,
              isForeignProviderLabMode: offlineLabMode,
              labModeWarningBanner: offlineLabMode
                  ? _defaultGoogleLabBanner
                  : null,
              user: cachedProfile,
            ),
          );
        }
        if (error.clientAction == ClientErrorAction.forceLogout) {
          await _clearLocalSession();
          return const Ok(null);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<AuthSession, AppError>> signInWithOAuth({
    required AuthProviderType provider,
    required ConsentScopeObject consentScope,
  }) async {
    if (!consentScope.personalData152fz) {
      return Err(AppError.fromCode('FZ152_CONSENT_REQUIRED'));
    }

    final pkceResult = await _pkceClient.authorize(provider);
    final OAuthPkcePayload pkcePayload;
    switch (pkceResult) {
      case Ok(:final value):
        pkcePayload = value;
      case Err(:final error):
        return Err(error);
    }

    final fingerprint = await _tokenStore.getOrCreateDeviceFingerprint();
    final exchangeRes = await _dioClient.post<AuthSession>(
      '/api/v1/auth/oauth/exchange',
      data: {
        'provider': provider.wireName,
        'authorization_code': pkcePayload.authorizationCode,
        'code_verifier': pkcePayload.codeVerifier,
        'redirect_uri': pkcePayload.redirectUri,
        'device_fingerprint': fingerprint,
        'policy_version': _policyVersion,
        'consent_scope': consentScope.toJson(),
      },
      parser: (data) => _parseOrThrow(
        data,
        (map) => AuthSession.fromJson(map, authProviderOverride: provider),
      ),
    );

    if (exchangeRes case Ok(:final value)) {
      await _tokenStore.saveTokens(
        accessToken: value.accessToken,
        refreshToken: value.refreshToken,
        expiresInSeconds: value.expiresInSeconds,
        authProvider: provider.wireName,
        isForeignProviderLabMode: value.isForeignProviderLabMode,
      );
      await _profileRepo.cacheProfile(
        value.user,
        authProvider: provider,
        isForeignLabMode: value.isForeignProviderLabMode,
      );
      await markOnboardingStepSeen();
      unawaited(_registerPushTokenBestEffort(fingerprint));
      return Ok(value);
    }
    return exchangeRes;
  }

  @override
  Future<Result<UserProfile, AppError>> submitGoogleFormalPhone(
    String phoneE164,
  ) async {
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phoneE164)) {
      return Err(AppError.fromCode('INVALID_FORMAL_PHONE_E164'));
    }
    final cached = await _profileRepo.getCachedProfileSnapshot();
    final result = await _dioClient.post<UserProfile>(
      '/api/v1/auth/google-phone',
      data: {'formal_phone_e164': phoneE164},
      parser: (data) => _parseOrThrow(
        data,
        (map) => UserProfile.fromJson(
          map,
          authProviderOverride: .google,
          isForeignLabModeOverride: true,
        ),
      ),
    );

    if (result case Ok(:final value)) {
      await _profileRepo.cacheProfile(
        value,
        authProvider: cached?.authProvider ?? .google,
        isForeignLabMode: true,
      );
    }
    return result;
  }

  @override
  Future<Result<ConsentHistoryListResponse, AppError>> getConsentHistory() =>
      _dioClient.get<ConsentHistoryListResponse>(
        '/api/v1/users/me/consents',
        parser: (data) =>
            _parseOrThrow(data, ConsentHistoryListResponse.fromJson),
      );

  @override
  Future<Result<ConsentJournalEntry, AppError>> recordConsent({
    required String policyVersion,
    required String action,
    required ConsentScopeObject scope,
  }) async {
    final result = await _dioClient.post<ConsentJournalEntry>(
      '/api/v1/users/me/consents',
      data: {
        'policy_version': policyVersion,
        'action': action,
        'consent_scope': scope.toJson(),
      },
      parser: (data) => _parseOrThrow(data, ConsentJournalEntry.fromJson),
    );
    if (result case Ok()) {
      await _profileRepo.updateLocalConsentActive(
        isActive: action != 'revoked' && scope.personalData152fz,
      );
    }
    return result;
  }

  @override
  Future<Result<void, AppError>> logout() async {
    final accessToken = await _tokenStore.getAccessToken();
    final refreshToken = await _tokenStore.getRefreshToken();
    final hasValidAccess = accessToken != null && accessToken.isNotEmpty;
    if (hasValidAccess) {
      await _pushProvider.unregisterCurrentToken();
      if (refreshToken != null && refreshToken.length >= 32) {
        await _dioClient.post<void>(
          '/api/v1/auth/logout',
          data: {'refresh_token': refreshToken},
          parser: _ignoreResponse,
        );
      }
    }
    await _clearLocalSession();
    if (!_sessionEndedController.isClosed) {
      _sessionEndedController.add(null);
    }
    return const Ok(null);
  }

  @override
  Future<void> clearLocalSessionOnly() => _clearLocalSession();

  @override
  Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingSeenKey) ?? false;
  }

  @override
  Future<void> markOnboardingStepSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
  }

  Future<void> _clearLocalSession() async {
    await _tokenStore.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    final onboardingSeen = prefs.getBool(_onboardingSeenKey) ?? false;
    await prefs.clear();
    if (onboardingSeen) {
      await prefs.setBool(_onboardingSeenKey, true);
    }
    await _profileRepo.clearAllLocalUserData();
  }

  static void _ignoreResponse(Object? _) {
    return;
  }

  Future<void> _registerPushTokenBestEffort(String deviceId) async {
    try {
      await _pushProvider.registerCurrentToken(deviceId: deviceId);
    } on Exception {
      return;
    }
  }

  bool _isOfflineError(AppError error) =>
      error.clientAction == ClientErrorAction.queueRetry ||
      error.httpStatus == 0 ||
      error.httpStatus == 503;

  T _parseOrThrow<T>(
    Object? data,
    Result<T, AppError> Function(Map<String, Object?>) parser,
  ) {
    if (data is Map<String, Object?>) {
      return switch (parser(data)) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };
    }
    throw AppError.fromCode('VALIDATION_ERROR');
  }

  static const String _defaultGoogleLabBanner =
      'Внимание: регистрация и вход через иностранный провайдер (Google OAuth) не соответствуют требованиям 406-ФЗ РФ. Данный способ входа включён исключительно для академического / лабораторного тестирования.';
}
