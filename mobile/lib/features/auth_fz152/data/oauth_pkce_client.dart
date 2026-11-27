import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

final class const OAuthPkcePayload({
  required final AuthProviderType provider,
  required final String authorizationCode,
  required final String codeVerifier,
  required final String redirectUri,
});

final class const OAuthProviderConfig({
  required final String clientId,
  required final AuthorizationServiceConfiguration serviceConfig,
  required final List<String> scopes,
});

final class OAuthPkceClient({
  final FlutterAppAuth? appAuth,
  final Future<Result<OAuthPkcePayload, AppError>> Function(
    AuthProviderType provider,
  )?
  overrideAuthorizer,
}) {
  static const String redirectUri = 'ecotrack://auth/callback';

  static const String _googleRedirectUri = String.fromEnvironment(
    'GOOGLE_OAUTH_REDIRECT_URI',
    defaultValue: redirectUri,
  );
  static const String _yandexClientId = String.fromEnvironment(
    'YANDEX_OAUTH_CLIENT_ID',
    defaultValue: 'ecotrack-yandex-client',
  );
  static const String _vkClientId = String.fromEnvironment(
    'VK_OAUTH_CLIENT_ID',
    defaultValue: 'ecotrack-vk-client',
  );
  static const String _googleClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
    defaultValue: 'ecotrack-google-client',
  );

  FlutterAppAuth get _effectiveAppAuth => appAuth ?? const FlutterAppAuth();

  static String redirectUriFor(AuthProviderType provider) => switch (provider) {
    .google => _googleRedirectUri,
    .yandex || .vk => redirectUri,
  };

  static bool isClientConfiguredFor(AuthProviderType provider) {
    final clientId = configFor(provider).clientId.trim();
    if (clientId.isEmpty || clientId.startsWith('mock_')) {
      return false;
    }
    return clientId != 'ecotrack-yandex-client' &&
        clientId != 'ecotrack-vk-client' &&
        clientId != 'ecotrack-google-client';
  }

  static String _envKeyFor(AuthProviderType provider) => switch (provider) {
    .yandex => 'YANDEX_OAUTH_CLIENT_ID',
    .vk => 'VK_OAUTH_CLIENT_ID',
    .google => 'GOOGLE_OAUTH_CLIENT_ID',
  };

  static OAuthProviderConfig configFor(AuthProviderType provider) =>
      switch (provider) {
        .yandex => const OAuthProviderConfig(
          clientId: _yandexClientId,
          serviceConfig: AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://oauth.yandex.ru/authorize',
            tokenEndpoint: 'https://oauth.yandex.ru/token',
          ),
          scopes: ['login:email', 'login:info'],
        ),
        .vk => const OAuthProviderConfig(
          clientId: _vkClientId,
          serviceConfig: AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://id.vk.com/authorize',
            tokenEndpoint: 'https://id.vk.com/oauth2/auth',
          ),
          scopes: ['vkid.personal_info', 'email'],
        ),
        .google => const OAuthProviderConfig(
          clientId: _googleClientId,
          serviceConfig: AuthorizationServiceConfiguration(
            authorizationEndpoint:
                'https://accounts.google.com/o/oauth2/v2/auth',
            tokenEndpoint: 'https://oauth2.googleapis.com/token',
          ),
          scopes: ['openid', 'email', 'profile'],
        ),
      };

  Future<Result<OAuthPkcePayload, AppError>> authorize(
    AuthProviderType provider,
  ) async {
    final override = overrideAuthorizer;
    if (override != null) {
      return await override(provider);
    }

    if (!isClientConfiguredFor(provider)) {
      return Err(
        AppError(
          code: 'OAUTH_CODE_EXCHANGE_FAILED',
          httpStatus: 400,
          domain: 'auth',
          retryable: false,
          clientAction: .showBanner,
          uiMessageRu:
              'OAuth для ${provider.displayNameRu} не настроен в этой сборке: передайте --dart-define=${_envKeyFor(provider)}=...',
        ),
      );
    }

    final cfg = configFor(provider);
    final effectiveRedirect = redirectUriFor(provider);
    try {
      final response = await _effectiveAppAuth.authorize(
        AuthorizationRequest(
          cfg.clientId,
          effectiveRedirect,
          serviceConfiguration: cfg.serviceConfig,
          scopes: cfg.scopes,
        ),
      );
      final code = response.authorizationCode;
      final verifier = response.codeVerifier;
      if (code == null ||
          code.isEmpty ||
          verifier == null ||
          verifier.isEmpty) {
        return Err(AppError.fromCode('OAUTH_PKCE_VERIFICATION_FAILED'));
      }
      return Ok(
        OAuthPkcePayload(
          provider: provider,
          authorizationCode: code,
          codeVerifier: verifier,
          redirectUri: effectiveRedirect,
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      return Err(AppError.fromCode('OAUTH_CODE_EXCHANGE_FAILED'));
    } on PlatformException {
      return Err(AppError.fromCode('OAUTH_CODE_EXCHANGE_FAILED'));
    }
  }
}
