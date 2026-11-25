import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';

Result<List<T>, AppError> _parseList<T>(
  Object? raw,
  Result<T, AppError> Function(Map<String, Object?>) itemParser,
) {
  if (raw is! List<Object?>) {
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }
  final parsed = <T>[];
  for (final element in raw) {
    if (element is! Map<String, Object?>) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    switch (itemParser(element)) {
      case Ok(:final value):
        parsed.add(value);
      case Err(:final error):
        return Err(error);
    }
  }
  return Ok(parsed);
}

final class const EmissionsBucketItem({
  required final String bucketLabel,
  required final String startDate,
  required final String endDate,
  required final int validatedSteps,
  required final double totalStepDistanceM,
  required final int allocatedCo2SavedGrams,
  required final int autoDefaultCo2SavedGrams,
  required final int totalCo2SavedGrams,
}) {
  static Result<EmissionsBucketItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'bucket_label': final String bucketLabel,
      'start_date': final String startDate,
      'end_date': final String endDate,
      'validated_steps': final int validatedSteps,
      'total_step_distance_m': final num totalStepDistanceM,
      'allocated_co2_saved_grams': final int allocatedCo2SavedGrams,
      'auto_default_co2_saved_grams': final int autoDefaultCo2SavedGrams,
      'total_co2_saved_grams': final int totalCo2SavedGrams,
    }) {
      return Ok(
        EmissionsBucketItem(
          bucketLabel: bucketLabel,
          startDate: startDate,
          endDate: endDate,
          validatedSteps: validatedSteps,
          totalStepDistanceM: totalStepDistanceM.toDouble(),
          allocatedCo2SavedGrams: allocatedCo2SavedGrams,
          autoDefaultCo2SavedGrams: autoDefaultCo2SavedGrams,
          totalCo2SavedGrams: totalCo2SavedGrams,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'bucket_label': bucketLabel,
    'start_date': startDate,
    'end_date': endDate,
    'validated_steps': validatedSteps,
    'total_step_distance_m': totalStepDistanceM,
    'allocated_co2_saved_grams': allocatedCo2SavedGrams,
    'auto_default_co2_saved_grams': autoDefaultCo2SavedGrams,
    'total_co2_saved_grams': totalCo2SavedGrams,
  };
}

final class const EcoEquivalentsMetrics({
  required final int totalCo2SavedGrams,
  required final double treesPlantedEquivalent,
  required final double carKmAvoided,
  required final int smartphoneChargesEquivalent,
  required final int plasticBottlesRecycledEquivalent,
  required final int ledBulbHoursEquivalent,
}) {
  static const EcoEquivalentsMetrics empty = EcoEquivalentsMetrics(
    totalCo2SavedGrams: 0,
    treesPlantedEquivalent: 0,
    carKmAvoided: 0,
    smartphoneChargesEquivalent: 0,
    plasticBottlesRecycledEquivalent: 0,
    ledBulbHoursEquivalent: 0,
  );

  double get forestAreaSqm => ((totalCo2SavedGrams / 500.0) * 10).round() / 10;

  double get gasolineLitersSaved =>
      ((totalCo2SavedGrams / 2330.0) * 100).round() / 100;

  int get fuelRubSaved => ((totalCo2SavedGrams / 2330.0) * 62.50).round();

  double get cleanAirCubicMeters =>
      ((totalCo2SavedGrams / 1.96) * 10).round() / 10;

  static Result<EcoEquivalentsMetrics, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'total_co2_saved_grams': final int totalCo2SavedGrams,
      'trees_planted_equivalent': final num treesPlantedEquivalent,
      'car_km_avoided': final num carKmAvoided,
      'smartphone_charges_equivalent': final int smartphoneChargesEquivalent,
      'plastic_bottles_recycled_equivalent':
          final int plasticBottlesRecycledEquivalent,
      'led_bulb_hours_equivalent': final int ledBulbHoursEquivalent,
    }) {
      return Ok(
        EcoEquivalentsMetrics(
          totalCo2SavedGrams: totalCo2SavedGrams,
          treesPlantedEquivalent: treesPlantedEquivalent.toDouble(),
          carKmAvoided: carKmAvoided.toDouble(),
          smartphoneChargesEquivalent: smartphoneChargesEquivalent,
          plasticBottlesRecycledEquivalent: plasticBottlesRecycledEquivalent,
          ledBulbHoursEquivalent: ledBulbHoursEquivalent,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'total_co2_saved_grams': totalCo2SavedGrams,
    'trees_planted_equivalent': treesPlantedEquivalent,
    'car_km_avoided': carKmAvoided,
    'smartphone_charges_equivalent': smartphoneChargesEquivalent,
    'plastic_bottles_recycled_equivalent': plasticBottlesRecycledEquivalent,
    'led_bulb_hours_equivalent': ledBulbHoursEquivalent,
  };
}

final class const EcoEquivalentsResponse({
  required final EcoEquivalentsMetrics lifetime,
  required final EcoEquivalentsMetrics currentWeek,
}) {
  static Result<EcoEquivalentsResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'lifetime': final Map<String, Object?> lifetimeMap,
      'current_week': final Map<String, Object?> weekMap,
    }) {
      final lifetimeRes = EcoEquivalentsMetrics.fromJson(lifetimeMap);
      final weekRes = EcoEquivalentsMetrics.fromJson(weekMap);
      return switch ((lifetimeRes, weekRes)) {
        (Ok(value: final l), Ok(value: final w)) => Ok(
          EcoEquivalentsResponse(lifetime: l, currentWeek: w),
        ),
        (Err(:final error), _) => Err(error),
        (_, Err(:final error)) => Err(error),
      };
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'lifetime': lifetime.toJson(),
    'current_week': currentWeek.toJson(),
  };
}

final class const TransportBreakdownShare({
  required final String modeCode,
  required final String labelRu,
  required final int co2SavedGrams,
  required final double percentage,
}) {
  static Result<TransportBreakdownShare, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'mode_code': final String modeCode,
      'label_ru': final String labelRu,
      'co2_saved_grams': final int co2SavedGrams,
      'percentage': final num percentage,
    }) {
      return Ok(
        TransportBreakdownShare(
          modeCode: modeCode,
          labelRu: labelRu,
          co2SavedGrams: co2SavedGrams,
          percentage: percentage.toDouble(),
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'mode_code': modeCode,
    'label_ru': labelRu,
    'co2_saved_grams': co2SavedGrams,
    'percentage': percentage,
  };
}

final class const EmissionsStatisticsResponse({
  required final String period,
  required final int periodTotalCo2SavedGrams,
  required final int periodTotalSteps,
  required final double periodTotalDistanceM,
  required final List<EmissionsBucketItem> buckets,
  required final EcoEquivalentsMetrics equivalents,
  final List<TransportBreakdownShare> transportShares = const [],
}) {
  EmissionsStatisticsResponse copyWith({
    List<TransportBreakdownShare>? transportShares,
  }) => EmissionsStatisticsResponse(
    period: period,
    periodTotalCo2SavedGrams: periodTotalCo2SavedGrams,
    periodTotalSteps: periodTotalSteps,
    periodTotalDistanceM: periodTotalDistanceM,
    buckets: buckets,
    equivalents: equivalents,
    transportShares: transportShares ?? this.transportShares,
  );

  static Result<EmissionsStatisticsResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'period': final String period,
      'period_total_co2_saved_grams': final int periodTotalCo2SavedGrams,
      'period_total_steps': final int periodTotalSteps,
      'period_total_distance_m': final num periodTotalDistanceM,
      'buckets': final Object? rawBuckets,
      'equivalents': final Map<String, Object?> eqMap,
    }) {
      final bucketsRes = _parseList(rawBuckets, EmissionsBucketItem.fromJson);
      final eqRes = EcoEquivalentsMetrics.fromJson(eqMap);
      final rawShares = json['transport_shares'];
      final shares = switch (rawShares) {
        final List<Object?> _ => switch (_parseList(
          rawShares,
          TransportBreakdownShare.fromJson,
        )) {
          Ok(:final value) => value,
          Err() => const <TransportBreakdownShare>[],
        },
        _ => const <TransportBreakdownShare>[],
      };
      return switch ((bucketsRes, eqRes)) {
        (Ok(value: final buckets), Ok(value: final eq)) => Ok(
          EmissionsStatisticsResponse(
            period: period,
            periodTotalCo2SavedGrams: periodTotalCo2SavedGrams,
            periodTotalSteps: periodTotalSteps,
            periodTotalDistanceM: periodTotalDistanceM.toDouble(),
            buckets: buckets,
            equivalents: eq,
            transportShares: shares,
          ),
        ),
        (Err(:final error), _) => Err(error),
        (_, Err(:final error)) => Err(error),
      };
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'period': period,
    'period_total_co2_saved_grams': periodTotalCo2SavedGrams,
    'period_total_steps': periodTotalSteps,
    'period_total_distance_m': periodTotalDistanceM,
    'buckets': buckets.map((b) => b.toJson()).toList(),
    'equivalents': equivalents.toJson(),
    if (transportShares.isNotEmpty)
      'transport_shares': transportShares.map((s) => s.toJson()).toList(),
  };
}

final class const PaginatedActivityHistoryResponse({
  required final int totalCount,
  required final int limit,
  required final int offset,
  required final List<DailyActivitySummary> items,
}) {
  static Result<PaginatedActivityHistoryResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'total_count': final int totalCount,
      'limit': final int limit,
      'offset': final int offset,
      'items': final Object? rawItems,
    }) {
      final itemsRes = _parseList(rawItems, DailyActivitySummary.fromJson);
      return switch (itemsRes) {
        Ok(:final value) => Ok(
          PaginatedActivityHistoryResponse(
            totalCount: totalCount,
            limit: limit,
            offset: offset,
            items: value,
          ),
        ),
        Err(:final error) => Err(error),
      };
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'total_count': totalCount,
    'limit': limit,
    'offset': offset,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

final class const LeaderboardEntry({
  required final int rank,
  required final String userId,
  required final String displayName,
  final String? avatarUrl,
  final String? equippedAccessoryCode,
  required final bool isCurrentUser,
  required final bool isStatsVisible,
  required final int weeklyCo2SavedGrams,
  required final int weeklySteps,
  required final int currentStreakDays,
}) {
  static Result<LeaderboardEntry, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'rank': final int rank,
      'user_id': final String userId,
      'display_name': final String displayName,
      'is_current_user': final bool isCurrentUser,
      'is_stats_visible': final bool isStatsVisible,
      'weekly_co2_saved_grams': final int weeklyCo2SavedGrams,
      'weekly_steps': final int weeklySteps,
      'current_streak_days': final int currentStreakDays,
    }) {
      return Ok(
        LeaderboardEntry(
          rank: rank,
          userId: userId,
          displayName: displayName,
          avatarUrl: json['avatar_url'] as String?,
          equippedAccessoryCode: json['equipped_accessory_code'] as String?,
          isCurrentUser: isCurrentUser,
          isStatsVisible: isStatsVisible,
          weeklyCo2SavedGrams: weeklyCo2SavedGrams,
          weeklySteps: weeklySteps,
          currentStreakDays: currentStreakDays,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'rank': rank,
    'user_id': userId,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'equipped_accessory_code': equippedAccessoryCode,
    'is_current_user': isCurrentUser,
    'is_stats_visible': isStatsVisible,
    'weekly_co2_saved_grams': weeklyCo2SavedGrams,
    'weekly_steps': weeklySteps,
    'current_streak_days': currentStreakDays,
  };
}

final class const FriendsLeaderboardResponse({
  required final int isoYear,
  required final int isoWeek,
  required final String weekStartDate,
  required final String weekEndDate,
  required final List<LeaderboardEntry> entries,
}) {
  static Result<FriendsLeaderboardResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'iso_year': final int isoYear,
      'iso_week': final int isoWeek,
      'week_start_date': final String weekStartDate,
      'week_end_date': final String weekEndDate,
      'entries': final Object? rawEntries,
    }) {
      final entriesRes = _parseList(rawEntries, LeaderboardEntry.fromJson);
      return switch (entriesRes) {
        Ok(:final value) => Ok(
          FriendsLeaderboardResponse(
            isoYear: isoYear,
            isoWeek: isoWeek,
            weekStartDate: weekStartDate,
            weekEndDate: weekEndDate,
            entries: value,
          ),
        ),
        Err(:final error) => Err(error),
      };
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'iso_year': isoYear,
    'iso_week': isoWeek,
    'week_start_date': weekStartDate,
    'week_end_date': weekEndDate,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
}

final class const SharedForestContributorItem({
  required final String userId,
  required final String displayName,
  final String? avatarUrl,
  required final int contributedCo2Grams,
  required final int contributedSteps,
}) {
  static Result<SharedForestContributorItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'user_id': final String userId,
      'display_name': final String displayName,
      'contributed_co2_grams': final int contributedCo2Grams,
      'contributed_steps': final int contributedSteps,
    }) {
      return Ok(
        SharedForestContributorItem(
          userId: userId,
          displayName: displayName,
          avatarUrl: json['avatar_url'] as String?,
          contributedCo2Grams: contributedCo2Grams,
          contributedSteps: contributedSteps,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'contributed_co2_grams': contributedCo2Grams,
    'contributed_steps': contributedSteps,
  };
}

final class const SharedForestChallengeResponse({
  required final String id,
  required final int isoYear,
  required final int isoWeek,
  required final String weekStartDate,
  required final String weekEndDate,
  required final String titleRu,
  required final int targetCo2SavedGrams,
  required final int currentCo2SavedGrams,
  required final double progressRatio,
  required final int treesEquivalentPlanted,
  required final int myContributedCo2Grams,
  required final bool isCompleted,
  required final List<SharedForestContributorItem> topFriendsContributors,
}) {
  static Result<SharedForestChallengeResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'id': final String id,
      'iso_year': final int isoYear,
      'iso_week': final int isoWeek,
      'week_start_date': final String weekStartDate,
      'week_end_date': final String weekEndDate,
      'title_ru': final String titleRu,
      'target_co2_saved_grams': final int targetCo2SavedGrams,
      'current_co2_saved_grams': final int currentCo2SavedGrams,
      'progress_ratio': final num progressRatio,
      'trees_equivalent_planted': final int treesEquivalentPlanted,
      'my_contributed_co2_grams': final int myContributedCo2Grams,
      'is_completed': final bool isCompleted,
      'top_friends_contributors': final Object? rawContributors,
    }) {
      final contribRes = _parseList(
        rawContributors,
        SharedForestContributorItem.fromJson,
      );
      return switch (contribRes) {
        Ok(:final value) => Ok(
          SharedForestChallengeResponse(
            id: id,
            isoYear: isoYear,
            isoWeek: isoWeek,
            weekStartDate: weekStartDate,
            weekEndDate: weekEndDate,
            titleRu: titleRu,
            targetCo2SavedGrams: targetCo2SavedGrams,
            currentCo2SavedGrams: currentCo2SavedGrams,
            progressRatio: progressRatio.toDouble(),
            treesEquivalentPlanted: treesEquivalentPlanted,
            myContributedCo2Grams: myContributedCo2Grams,
            isCompleted: isCompleted,
            topFriendsContributors: value,
          ),
        ),
        Err(:final error) => Err(error),
      };
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'iso_year': isoYear,
    'iso_week': isoWeek,
    'week_start_date': weekStartDate,
    'week_end_date': weekEndDate,
    'title_ru': titleRu,
    'target_co2_saved_grams': targetCo2SavedGrams,
    'current_co2_saved_grams': currentCo2SavedGrams,
    'progress_ratio': progressRatio,
    'trees_equivalent_planted': treesEquivalentPlanted,
    'my_contributed_co2_grams': myContributedCo2Grams,
    'is_completed': isCompleted,
    'top_friends_contributors': topFriendsContributors
        .map((c) => c.toJson())
        .toList(),
  };
}

abstract interface class StatsRepository() {
  Future<Result<EmissionsStatisticsResponse, AppError>> getEmissionsStatistics(
    String period, {
    String? referenceDate,
  });

  Future<Result<PaginatedActivityHistoryResponse, AppError>>
  getActivityHistory({int limit = 20, int offset = 0});

  Future<Result<EcoEquivalentsResponse, AppError>> getEcoEquivalents();

  Future<Result<FriendsLeaderboardResponse, AppError>> getWeeklyLeaderboard();

  Future<Result<SharedForestChallengeResponse, AppError>>
  getCurrentSharedForest();
}
