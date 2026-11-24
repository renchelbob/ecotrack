import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';

final class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.displayName,
    required this.email,
    required this.phoneMasked,
    required this.hasFz152Consent,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String displayName;
  final String? email;
  final String? phoneMasked;
  final bool hasFz152Consent;

  static Result<AuthSession, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'access_token': final String access,
      'refresh_token': final String refresh,
      'user_id': final String uid,
      'display_name': final String name,
    }) {
      return Ok(
        AuthSession(
          accessToken: access,
          refreshToken: refresh,
          userId: uid,
          displayName: name,
          email: json['email'] as String?,
          phoneMasked: json['phone_masked'] as String?,
          hasFz152Consent: json['has_fz152_consent'] as bool? ?? false,
        ),
      );
    }
    return Err(
      AppError.fromCode(
        'VALIDATION_ERROR',
        'Неверный формат ответа авторизации',
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'display_name': displayName,
    if (email != null) 'email': email,
    if (phoneMasked != null) 'phone_masked': phoneMasked,
    'has_fz152_consent': hasFz152Consent,
  };
}

abstract interface class AuthRepository {
  Future<Result<AuthSession, AppError>> login({
    required String email,
    required String password,
  });

  Future<Result<AuthSession, AppError>> loginWithGoogle({
    required String googleAuthCode,
    String? phone,
  });

  Future<Result<void, AppError>> submitFz152Consent({
    required bool allowPdnProcessing,
    required bool allowTelemetry,
  });

  Future<AuthSession?> getCurrentSession();
  Future<void> logout();
}
