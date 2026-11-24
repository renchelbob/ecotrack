import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';

final class TransportShare {
  const TransportShare({
    required this.mode,
    required this.distanceKm,
    required this.co2SavedKg,
    required this.percentage,
  });

  factory TransportShare.fromJson(Map<String, Object?> json) => TransportShare(
    mode: json['mode'] as String? ?? 'walking',
    distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
    co2SavedKg: (json['co2_saved_kg'] as num?)?.toDouble() ?? 0.0,
    percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
  );

  final String mode;
  final double distanceKm;
  final double co2SavedKg;
  final double percentage;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'distance_km': distanceKm,
    'co2_saved_kg': co2SavedKg,
    'percentage': percentage,
  };
}

final class EmissionsStats {
  const EmissionsStats({
    required this.totalCo2SavedKg,
    required this.treesEquivalent,
    required this.gasolineSavedLiters,
    required this.totalWalkedKm,
    required this.shares,
  });

  final double totalCo2SavedKg;
  final double treesEquivalent;
  final double gasolineSavedLiters;
  final double totalWalkedKm;
  final List<TransportShare> shares;

  static Result<EmissionsStats, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'total_co2_saved_kg': final num totalCo2,
      'trees_equivalent': final num trees,
      'gasoline_saved_liters': final num gas,
      'total_walked_km': final num walked,
    }) {
      final rawShares = json['shares'] as List<dynamic>? ?? [];
      final shares = rawShares
          .whereType<Map<String, Object?>>()
          .map(TransportShare.fromJson)
          .toList();

      return Ok(
        EmissionsStats(
          totalCo2SavedKg: totalCo2.toDouble(),
          treesEquivalent: trees.toDouble(),
          gasolineSavedLiters: gas.toDouble(),
          totalWalkedKm: walked.toDouble(),
          shares: shares,
        ),
      );
    }
    return Err(
      AppError.fromCode('VALIDATION_ERROR', 'Неверный формат статистики'),
    );
  }

  Map<String, Object?> toJson() => {
    'total_co2_saved_kg': totalCo2SavedKg,
    'trees_equivalent': treesEquivalent,
    'gasoline_saved_liters': gasolineSavedLiters,
    'total_walked_km': totalWalkedKm,
    'shares': shares.map((s) => s.toJson()).toList(),
  };
}

final class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.totalCo2SavedGrams,
    required this.streakDays,
    this.isCurrentUser = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, Object?> json) =>
      LeaderboardEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 1,
        userId: json['user_id'] as String? ?? '',
        displayName: json['display_name'] as String? ?? 'Эко-друг',
        totalCo2SavedGrams:
            (json['total_co2_saved_grams'] as num?)?.toInt() ?? 0,
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 1,
        isCurrentUser: json['is_current_user'] as bool? ?? false,
      );

  final int rank;
  final String userId;
  final String displayName;
  final int totalCo2SavedGrams;
  final int streakDays;
  final bool isCurrentUser;
}

abstract interface class StatsRepository {
  Future<Result<EmissionsStats, AppError>> getEmissionsStats();
  Future<Result<List<LeaderboardEntry>, AppError>> getLeaderboard();
}
