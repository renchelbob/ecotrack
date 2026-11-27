import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';

enum ConsentActionType(final String wireName, final String displayNameRu) {
  granted('granted', 'Согласие предоставлено'),
  revoked('revoked', 'Согласие отозвано'),
  updated('updated', 'Согласие обновлено');

  static ConsentActionType fromWire(String? raw) => switch (raw) {
    'revoked' => .revoked,
    'updated' => .updated,
    _ => .granted,
  };
}

final class const ConsentScopeObject({
  required final bool personalData152fz,
  required final bool healthStepsSensor,
  required final bool backgroundGeolocation,
}) {
  static Result<ConsentScopeObject, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'personal_data_152fz': final bool personalData152fz,
      'health_steps_sensor': final bool healthStepsSensor,
      'background_geolocation': final bool backgroundGeolocation,
    }) {
      return Ok(
        ConsentScopeObject(
          personalData152fz: personalData152fz,
          healthStepsSensor: healthStepsSensor,
          backgroundGeolocation: backgroundGeolocation,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'personal_data_152fz': personalData152fz,
    'health_steps_sensor': healthStepsSensor,
    'background_geolocation': backgroundGeolocation,
  };
}

final class const ConsentJournalEntry({
  required final String id,
  required final String policyVersion,
  required final ConsentActionType action,
  required final ConsentScopeObject consentScope,
  required final String recordedAt,
}) {
  static Result<ConsentJournalEntry, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'id': final String id,
      'policy_version': final String policyVersion,
      'action': final String actionRaw,
      'consent_scope': final Map<String, Object?> scopeRaw,
      'recorded_at': final String recordedAt,
    }) {
      return switch (ConsentScopeObject.fromJson(scopeRaw)) {
        Ok(:final value) => Ok(
          ConsentJournalEntry(
            id: id,
            policyVersion: policyVersion,
            action: .fromWire(actionRaw),
            consentScope: value,
            recordedAt: recordedAt,
          ),
        ),
        Err(:final error) => Err(error),
      };
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'policy_version': policyVersion,
    'action': action.wireName,
    'consent_scope': consentScope.toJson(),
    'recorded_at': recordedAt,
  };
}

final class const ConsentHistoryListResponse({
  required final bool is152fzConsentActive,
  required final List<ConsentJournalEntry> entries,
}) {
  static Result<ConsentHistoryListResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'is_152fz_consent_active': final bool isActive,
      'entries': final List<Object?> entriesRaw,
    }) {
      final parsed = <ConsentJournalEntry>[];
      for (final item in entriesRaw) {
        if (item is Map<String, Object?>) {
          if (ConsentJournalEntry.fromJson(item) case Ok(:final value)) {
            parsed.add(value);
          }
        }
      }
      return Ok(
        ConsentHistoryListResponse(
          is152fzConsentActive: isActive,
          entries: parsed,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'is_152fz_consent_active': is152fzConsentActive,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
}

final class const AuthSession({
  required final String accessToken,
  required final String refreshToken,
  required final int expiresInSeconds,
  required final bool isForeignProviderLabMode,
  required final UserProfile user,
  final String tokenType = 'Bearer',
  final String? labModeWarningBanner,
}) {
  static Result<AuthSession, AppError> fromJson(
    Map<String, Object?> json, {
    AuthProviderType? authProviderOverride,
  }) {
    if (json case {
      'access_token': final String accessToken,
      'refresh_token': final String refreshToken,
      'token_type': final String tokenType,
      'expires_in_seconds': final int expiresInSeconds,
      'is_foreign_provider_lab_mode': final bool isForeignLabMode,
      'user': final Map<String, Object?> userMap,
    }) {
      return switch (UserProfile.fromJson(
        userMap,
        authProviderOverride: authProviderOverride,
        isForeignLabModeOverride: isForeignLabMode,
      )) {
        Ok(:final value) => Ok(
          AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresInSeconds: expiresInSeconds,
            isForeignProviderLabMode: isForeignLabMode,
            labModeWarningBanner: json['lab_mode_warning_banner'] as String?,
            user: value,
          ),
        ),
        Err(:final error) => Err(error),
      };
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': tokenType,
    'expires_in_seconds': expiresInSeconds,
    'is_foreign_provider_lab_mode': isForeignProviderLabMode,
    'lab_mode_warning_banner': labModeWarningBanner,
    'user': user.toJson(),
  };
}

abstract interface class const AuthSessionNotifier() {
  Stream<void> get onSessionEnded;

  /// Clears local session tokens and user data without performing remote
  /// logout or push-token unregistration calls (used on forced 401 logout).
  Future<void> clearLocalSessionOnly();
}

abstract interface class const AuthRepository() {
  Future<Result<AuthSession?, AppError>> restoreSession();

  Future<Result<AuthSession, AppError>> signInWithOAuth({
    required AuthProviderType provider,
    required ConsentScopeObject consentScope,
  });

  Future<Result<UserProfile, AppError>> submitGoogleFormalPhone(
    String phoneE164,
  );

  Future<Result<ConsentHistoryListResponse, AppError>> getConsentHistory();

  Future<Result<ConsentJournalEntry, AppError>> recordConsent({
    required String policyVersion,
    required String action,
    required ConsentScopeObject scope,
  });

  Future<Result<void, AppError>> logout();

  Future<bool> hasCompletedOnboarding();

  Future<void> markOnboardingStepSeen();
}
