import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/api_client.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl({
    ApiClient? apiClient,
    SqliteDatabase? db,
    FlutterSecureStorage? secureStorage,
  }) : _apiClient = apiClient ?? ApiClient(),
       _db = db ?? SqliteDatabase.instance,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final ApiClient _apiClient;
  final SqliteDatabase _db;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<Result<UserProfile, AppError>> getProfile() async {
    final netResult = await _apiClient.get<UserProfile>(
      path: '/v1/users/me',
      fromJson: (data) {
        if (data case final Map<String, Object?> map) {
          final res = UserProfile.fromJson(map);
          return res.fold((p) => p, (e) => throw e);
        }
        throw AppError.fromCode('VALIDATION_ERROR');
      },
    );

    return netResult.fold(Ok.new, (err) async {
      // If server unreachable, check if user is logged in
      final userId = await _secureStorage.read(key: 'auth_user_id');
      final name = await _secureStorage.read(key: 'auth_user_name');
      if (userId != null && name != null) {
        final email = await _secureStorage.read(key: 'auth_user_email');
        final phone = await _secureStorage.read(key: 'auth_user_phone');
        final cleanCode = userId
            .toUpperCase()
            .replaceAll(RegExp('[^A-Z0-9]'), '')
            .padRight(4, '0')
            .substring(0, 4);
        return Ok(
          UserProfile(
            id: userId,
            displayName: name,
            email: email ?? '',
            phoneMasked: phone ?? '',
            friendCode: 'ECO-$cleanCode',
            pointsBalance: 0,
            dailyStepGoal: 10000,
            vehicle: UserVehicle.defaultVehicle(),
          ),
        );
      }
      return Err(err);
    });
  }

  @override
  Future<Result<void, AppError>> exportPersonalData152Fz() =>
      _apiClient.post<void>(path: '/v1/users/me/export', fromJson: (_) {});

  @override
  Future<Result<void, AppError>> deleteAccount152Fz() async {
    // 152-FZ Right to be forgotten (cascades deletion across server & local SQLite)
    try {
      await _db.database.delete('local_user_profile');
      await _db.database.delete('local_daily_step_summaries');
      await _db.database.delete('offline_mutation_outbox');
    } catch (_) {}

    return _apiClient.post<void>(
      path: '/v1/users/me/anonymize',
      fromJson: (_) {},
    );
  }
}
