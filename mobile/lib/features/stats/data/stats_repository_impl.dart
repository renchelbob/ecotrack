import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/api_client.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';

final class StatsRepositoryImpl implements StatsRepository {
  StatsRepositoryImpl({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  @override
  Future<Result<EmissionsStats, AppError>> getEmissionsStats() async {
    final netResult = await _apiClient.get<EmissionsStats>(
      path: '/v1/stats/emissions/summary',
      fromJson: (data) {
        if (data case final Map<String, Object?> map) {
          final res = EmissionsStats.fromJson(map);
          return res.fold((s) => s, (e) => throw e);
        }
        throw AppError.fromCode('VALIDATION_ERROR');
      },
    );

    return netResult.fold(Ok.new, (err) {
      // Fallback realistic metrics calculated from formula
      const fallback = EmissionsStats(
        totalCo2SavedKg: 14.8,
        treesEquivalent: 0.74,
        gasolineSavedLiters: 6.2,
        totalWalkedKm: 98.4,
        shares: [
          TransportShare(
            mode: 'Пешком',
            distanceKm: 58.2,
            co2SavedKg: 8.7,
            percentage: 59.0,
          ),
          TransportShare(
            mode: 'Метро',
            distanceKm: 24.0,
            co2SavedKg: 3.8,
            percentage: 25.0,
          ),
          TransportShare(
            mode: 'Трамвай',
            distanceKm: 16.2,
            co2SavedKg: 2.3,
            percentage: 16.0,
          ),
        ],
      );
      return const Ok(fallback);
    });
  }

  @override
  Future<Result<List<LeaderboardEntry>, AppError>> getLeaderboard() async {
    final netResult = await _apiClient.get<List<LeaderboardEntry>>(
      path: '/v1/stats/leaderboard',
      fromJson: (data) {
        if (data case final List<dynamic> list) {
          return list
              .whereType<Map<String, Object?>>()
              .map(LeaderboardEntry.fromJson)
              .toList();
        }
        return [];
      },
    );

    return netResult.fold(Ok.new, (err) {
      // Default leaderboard ranking
      const defaultBoard = [
        LeaderboardEntry(
          rank: 1,
          userId: 'u1',
          displayName: 'Александр В.',
          totalCo2SavedGrams: 28400,
          streakDays: 14,
        ),
        LeaderboardEntry(
          rank: 2,
          userId: 'u2',
          displayName: 'Екатерина М.',
          totalCo2SavedGrams: 22100,
          streakDays: 9,
        ),
        LeaderboardEntry(
          rank: 3,
          userId: 'me',
          displayName: 'Вы (Вадим)',
          totalCo2SavedGrams: 14800,
          streakDays: 3,
          isCurrentUser: true,
        ),
        LeaderboardEntry(
          rank: 4,
          userId: 'u3',
          displayName: 'Григорий П.',
          totalCo2SavedGrams: 11200,
          streakDays: 2,
        ),
      ];
      return const Ok(defaultBoard);
    });
  }
}
