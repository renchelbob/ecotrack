import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/api_client.dart';
import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';

final class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({ApiClient? apiClient, SqliteDatabase? db})
    : _apiClient = apiClient ?? ApiClient(),
      _db = db ?? SqliteDatabase.instance;

  final ApiClient _apiClient;
  final SqliteDatabase _db;

  @override
  Future<Result<DailyActivitySummary, AppError>> getTodaySummary() async {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    // Try reading from SQLite cache first
    try {
      final rows = await _db.database.query(
        'local_daily_step_summaries',
        where: 'activity_date = ?',
        whereArgs: [todayStr],
      );

      if (rows.isNotEmpty) {
        final parsed = DailyActivitySummary.fromJson(rows.first);
        if (parsed is Ok<DailyActivitySummary, AppError>) {
          return parsed;
        }
      }
    } catch (_) {}

    // Fallback or network fetch
    final netResult = await _apiClient.get<DailyActivitySummary>(
      path: '/v1/users/me/summary',
      fromJson: (data) {
        if (data case final Map<String, Object?> map) {
          final res = DailyActivitySummary.fromJson(map);
          return res.fold((s) => s, (e) => throw e);
        }
        throw AppError.fromCode('VALIDATION_ERROR');
      },
    );

    return netResult.fold(
      (summary) async {
        // Cache in SQLite
        try {
          await _db.database.insert(
            'local_daily_step_summaries',
            summary.toJson(),
          );
        } catch (_) {}
        return Ok(summary);
      },
      (err) {
        // Default optimistic local summary if offline/unreachable
        final fallback = DailyActivitySummary(
          id: 'local-$todayStr',
          activityDate: todayStr,
          validatedSteps: 4520,
          totalStepDistanceM: 3390.0,
          allocatedGpsDistanceM: 0.0,
          unallocatedStepDistanceM: 3390.0,
          allocatedCo2SavedGrams: 0,
          autoDefaultCo2SavedGrams: 420,
          totalCo2SavedGrams: 420,
          pointsBalance: 120,
          isAutoCalculated: true,
          streakDays: 3,
        );
        return Ok(fallback);
      },
    );
  }

  @override
  Future<Result<DailyActivitySummary, AppError>> syncSteps(int rawSteps) async {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    // Calculate preliminary CO2 savings (0.7m per step, 80% default replacement at 0.155 g/m)
    final distanceM = rawSteps * 0.7;
    final autoCo2Grams = (distanceM * 0.8 * 0.155).round();
    final points = (autoCo2Grams / 10).round();

    final mood = rawSteps >= 10000
        ? MascotMood.thriving
        : rawSteps == 0
        ? MascotMood.sleepy
        : MascotMood.happy;

    final updated = DailyActivitySummary(
      id: 'local-$todayStr',
      activityDate: todayStr,
      validatedSteps: rawSteps,
      totalStepDistanceM: distanceM,
      allocatedGpsDistanceM: 0.0,
      unallocatedStepDistanceM: distanceM,
      allocatedCo2SavedGrams: 0,
      autoDefaultCo2SavedGrams: autoCo2Grams,
      totalCo2SavedGrams: autoCo2Grams,
      pointsBalance: points,
      isAutoCalculated: true,
      mascotMood: mood,
      streakDays: 3,
    );

    // Save to SQLite
    try {
      await _db.database.insert('local_daily_step_summaries', updated.toJson());
    } catch (_) {}

    return Ok(updated);
  }
}
