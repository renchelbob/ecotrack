import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/api_client.dart';
import 'package:ecotrack_mobile/features/auth_fz152/domain/auth_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    ApiClient? apiClient,
    FlutterSecureStorage? secureStorage,
  }) : _apiClient = apiClient ?? ApiClient(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<Result<AuthSession, AppError>> login({
    required String email,
    required String password,
  }) async {
    final result = await _apiClient.post<AuthSession>(
      path: '/v1/auth/login',
      data: {'email': email, 'password': password},
      fromJson: (data) {
        if (data case final Map<String, Object?> map) {
          final parsed = AuthSession.fromJson(map);
          return parsed.fold((s) => s, (e) => throw e);
        }
        throw AppError.fromCode('VALIDATION_ERROR');
      },
    );

    return result.fold((session) async {
      await _persistSession(session);
      return Ok(session);
    }, Err.new);
  }

  @override
  Future<Result<AuthSession, AppError>> loginWithGoogle({
    required String googleAuthCode,
    String? phone,
  }) async {
    // 152-FZ verification: Google Auth requires RU phone number (+7...)
    if (phone == null || !phone.startsWith('+7')) {
      return Err(AppError.fromCode('FZ152_GOOGLE_PHONE_REQUIRED'));
    }

    final result = await _apiClient.post<AuthSession>(
      path: '/v1/auth/google',
      data: {'auth_code': googleAuthCode, 'phone': phone},
      fromJson: (data) {
        if (data case final Map<String, Object?> map) {
          final parsed = AuthSession.fromJson(map);
          return parsed.fold((s) => s, (e) => throw e);
        }
        throw AppError.fromCode('VALIDATION_ERROR');
      },
    );

    return result.fold((session) async {
      await _persistSession(session);
      return Ok(session);
    }, Err.new);
  }

  @override
  Future<Result<void, AppError>> submitFz152Consent({
    required bool allowPdnProcessing,
    required bool allowTelemetry,
  }) async {
    if (!allowPdnProcessing) {
      return Err(AppError.fromCode('FZ152_CONSENT_REQUIRED'));
    }

    return _apiClient.post<void>(
      path: '/v1/users/me/consents',
      data: {
        'allow_pdn_processing': allowPdnProcessing,
        'allow_telemetry': allowTelemetry,
        'consent_timestamp': DateTime.now().toIso8601String(),
      },
      fromJson: (_) {},
    );
  }

  @override
  Future<AuthSession?> getCurrentSession() async {
    final token = await _secureStorage.read(key: 'jwt_access_token');
    final userId = await _secureStorage.read(key: 'auth_user_id');
    final name = await _secureStorage.read(key: 'auth_user_name');

    if (token != null && userId != null && name != null) {
      return AuthSession(
        accessToken: token,
        refreshToken: await _secureStorage.read(key: 'jwt_refresh_token') ?? '',
        userId: userId,
        displayName: name,
        email: await _secureStorage.read(key: 'auth_user_email'),
        phoneMasked: await _secureStorage.read(key: 'auth_user_phone'),
        hasFz152Consent: true,
      );
    }
    return null;
  }

  @override
  Future<void> logout() async {
    await _secureStorage.deleteAll();
  }

  Future<void> _persistSession(AuthSession session) async {
    await _secureStorage.write(
      key: 'jwt_access_token',
      value: session.accessToken,
    );
    await _secureStorage.write(
      key: 'jwt_refresh_token',
      value: session.refreshToken,
    );
    await _secureStorage.write(key: 'auth_user_id', value: session.userId);
    await _secureStorage.write(
      key: 'auth_user_name',
      value: session.displayName,
    );
    if (session.email != null) {
      await _secureStorage.write(key: 'auth_user_email', value: session.email);
    }
    if (session.phoneMasked != null) {
      await _secureStorage.write(
        key: 'auth_user_phone',
        value: session.phoneMasked,
      );
    }
  }
}
