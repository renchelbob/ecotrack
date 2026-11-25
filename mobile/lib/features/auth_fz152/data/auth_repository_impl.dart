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
  static const String localPreviewAccessToken = 'local-preview-access-token';
  static const String localPreviewRefreshToken =
      'local-preview-refresh-token-ecotrack';

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

    if (accessToken == localPreviewAccessToken && cachedProfile != null) {
      return Ok(
        AuthSession(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresInSeconds: 86400,
          isForeignProviderLabMode: false,
          user: cachedProfile,
        ),
      );
    }

    final profileRes = await _dioClient.get<UserProfile>(
      '/api/v1/users/me',
      parser: (data) => _parseOrThrow(
        data,
        (map) => UserProfile.fromJson(
          map,
          authProviderOverride: cachedProfile?.authProvider,
          isForeignLabModeOverride: cachedProfile?.isForeignProviderLabMode,
        ),
      ),
    );

    switch (profileRes) {
      case Ok(:final value):
        await _profileRepo.cacheProfile(
          value,
          authProvider: cachedProfile?.authProvider,
          isForeignLabMode: cachedProfile?.isForeignProviderLabMode,
        );
        return Ok(
          AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresInSeconds: 900,
            isForeignProviderLabMode: value.isForeignProviderLabMode,
            labModeWarningBanner: value.isForeignProviderLabMode
                ? _defaultGoogleLabBanner
                : null,
            user: value,
          ),
        );
      case Err(:final error):
        if (_isOfflineError(error) && cachedProfile != null) {
          return Ok(
            AuthSession(
              accessToken: accessToken,
              refreshToken: refreshToken,
              expiresInSeconds: 900,
              isForeignProviderLabMode: cachedProfile.isForeignProviderLabMode,
              labModeWarningBanner: cachedProfile.isForeignProviderLabMode
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
  Future<Result<AuthSession, AppError>> signInLocally({
    required ConsentScopeObject consentScope,
  }) async {
    if (!consentScope.personalData152fz) {
      return Err(AppError.fromCode('FZ152_CONSENT_REQUIRED'));
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final localProfile = UserProfile(
      id: 'usr-local-preview',
      email: 'preview@ecotrack.local',
      displayName: 'Артём Волков',
      friendCode: 'ECO-4219-DEMO',
      requiresFormalPhone: false,
      pointsBalance: 450,
      lifetimePointsEarned: 1280,
      lifetimeCo2SavedGrams: 18450,
      currentStreakDays: 6,
      longestStreakDays: 14,
      streakFreezeCount: 2,
      dailyCo2GoalGrams: 1500,
      isGpsTrackingEnabled: consentScope.backgroundGeolocation,
      isStatsVisibleToFriends: true,
      is152fzConsentActive: true,
      mascot: const MascotVisualState(
        mood: .happy,
        dailyGoalProgressRatio: 0.72,
      ),
      personalVehicle: UserVehicle(
        id: 'veh-local-1',
        vehicleName: 'Lada Vesta',
        fuel: .petrol95,
        consumptionPer100km: 7.8,
        fuelEmissionFactorGPerUnit: 2330.0,
        computedCo2GPerKm: 181.74,
        computedCo2GPerMeter: 0.18174,
        updatedAt: nowIso,
      ),
      createdAt: nowIso,
    );

    await _tokenStore.saveTokens(
      accessToken: localPreviewAccessToken,
      refreshToken: localPreviewRefreshToken,
    );
    await _profileRepo.cacheProfile(
      localProfile,
      authProvider: .yandex,
      isForeignLabMode: false,
    );
    await markOnboardingStepSeen();

    return Ok(
      AuthSession(
        accessToken: localPreviewAccessToken,
        refreshToken: localPreviewRefreshToken,
        expiresInSeconds: 86400,
        isForeignProviderLabMode: false,
        user: localProfile,
      ),
    );
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
    if (accessToken != localPreviewAccessToken) {
      await _pushProvider.unregisterCurrentToken();
      if (refreshToken != null && refreshToken.length >= 32) {
        await _dioClient.post<void>(
          '/api/v1/auth/logout',
          data: {'refresh_token': refreshToken},
          parser: (_) {},
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
    await _tokenStore.clearAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _profileRepo.clearAllLocalUserData();
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
