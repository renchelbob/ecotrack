import 'dart:async';

import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:ecotrack_mobile/features/home_mascot/domain/home_models.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';

final class const HomeAggregatedSnapshot({
  required final UserProfile profile,
  required final DailyActivitySummary todaySummary,
  required final MascotVisualSnapshot mascotSnapshot,
  required final TodayCardMetrics todayMetrics,
});

final class HomeSummaryAggregator() {
  static String todayLocalIso([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  HomeAggregatedSnapshot aggregate({
    required UserProfile profile,
    required DailyActivitySummary summary,
    bool isPointerSquinting = false,
  }) {
    final ratio = profile.dailyCo2GoalGrams <= 0
        ? 0.0
        : summary.totalCo2SavedGrams / profile.dailyCo2GoalGrams;
    final syncedMascot = profile.mascot.copyWith(
      mood: MascotVisualSnapshot.resolveMood(
        ratio: ratio,
        isPointerSquinting: isPointerSquinting,
      ),
      dailyGoalProgressRatio: ratio,
    );
    final syncedProfile = profile.copyWith(mascot: syncedMascot);
    return HomeAggregatedSnapshot(
      profile: syncedProfile,
      todaySummary: summary,
      mascotSnapshot: MascotVisualSnapshot.fromProfileAndSummary(
        profile: syncedProfile,
        summary: summary,
        isPointerSquinting: isPointerSquinting,
      ),
      todayMetrics: TodayCardMetrics.fromProfileAndSummary(
        profile: syncedProfile,
        summary: summary,
      ),
    );
  }

  DailyActivitySummary recomputeLocalSummary({
    required DailyActivitySummary current,
    required List<RouteSegmentAllocationItem> allocations,
    int? strideLengthCmOverride,
  }) {
    final strideCm = strideLengthCmOverride ?? current.strideLengthCm;
    final totalStepDistM = Co2Math.computeStepDistanceM(
      current.validatedSteps,
      strideCm,
    );
    var allocDistM = 0.0;
    var allocCo2G = 0;
    for (final item in allocations) {
      allocDistM += item.segmentDistanceM;
      allocCo2G += item.co2SavedGrams;
    }
    final unallocDistM = (totalStepDistM - allocDistM) < 0.0
        ? 0.0
        : (totalStepDistM - allocDistM);
    final autoCo2G = Co2Math.computeAutoDefaultCo2Grams(unallocDistM);
    final totalCo2G = allocCo2G + autoCo2G;
    final pointsTarget = Co2Math.computeDailyStepPointsTarget(
      current.validatedSteps,
    );
    return DailyActivitySummary(
      id: current.id,
      activityDate: current.activityDate,
      rawSensorSteps: current.rawSensorSteps,
      validatedSteps: current.validatedSteps,
      strideLengthCm: strideCm,
      totalStepDistanceM: totalStepDistM,
      allocatedGpsDistanceM: allocDistM,
      unallocatedStepDistanceM: unallocDistM,
      allocatedCo2SavedGrams: allocCo2G,
      autoDefaultCo2SavedGrams: autoCo2G,
      totalCo2SavedGrams: totalCo2G,
      pointsAwardedForDay: pointsTarget,
      pointsDeltaApplied: current.pointsDeltaApplied,
      pointsBalance: current.pointsBalance,
      isAutoCalculated: allocations.isEmpty,
      antifraudFlagged: current.antifraudFlagged,
      antifraudReason: current.antifraudReason,
      lastSyncedAt: current.lastSyncedAt,
    );
  }

  Future<HomeAggregatedSnapshot?> loadSnapshot({
    required ProfileRepository profileRepository,
    required MapActivityRepository mapRepository,
  }) async {
    final profileRes = await profileRepository.getProfile();
    final summaryRes = await mapRepository.getTodaySummary();
    final profile = switch (profileRes) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (profile == null) return null;
    final summary = switch (summaryRes) {
      Ok(:final value) => value,
      Err() => DailyActivitySummary.emptyForDate(
        todayLocalIso(),
        strideLengthCm: profile.strideLengthCm,
        pointsBalance: profile.pointsBalance,
      ),
    };
    return aggregate(profile: profile, summary: summary);
  }
}
