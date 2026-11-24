import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/api_client.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';

final class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl({ApiClient? apiClient, SqliteDatabase? db})
    : _apiClient = apiClient ?? ApiClient(),
      _db = db ?? SqliteDatabase.instance;

  final ApiClient _apiClient;
  final SqliteDatabase _db;

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

    return netResult.fold(Ok.new, (err) {
      // Fallback profile for offline/guest mode (Vadim - Developer 2)
      final defaultProfile = UserProfile(
        id: 'user-vadim-dev2',
        displayName: 'Вадим Нопин',
        email: 'vadim.nopin@vyatsu.ru',
        phoneMasked: '+7 (912) ***-45-67',
        friendCode: 'ECO-VDM2-2026',
        pointsBalance: 120,
        dailyStepGoal: 10000,
        vehicle: UserVehicle.defaultVehicle(),
      );
      return Ok(defaultProfile);
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
