import 'dart:math' as math;

import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';

final class const MascotVisualSnapshot({
  required final MascotMoodState mood,
  required final double dailyGoalProgressRatio,
  required final int remainingCo2Grams,
  required final int goalPercent,
  required final String statusCaptionRu,
  final String? equippedAccessoryCode,
  final List<String> unlockedAccessoryCodes = const <String>[],
  final bool isPointerSquinting = false,
}) {
  factory fromProfileAndSummary({
    required UserProfile profile,
    required DailyActivitySummary summary,
    bool isPointerSquinting = false,
  }) {
    final goal = math.max(1, profile.dailyCo2GoalGrams);
    final ratio = math.max(0.0, summary.totalCo2SavedGrams / goal);
    final remaining = math.max(0, goal - summary.totalCo2SavedGrams);
    final percent = (ratio * 100).round();
    final mood = resolveMood(
      ratio: ratio,
      isPointerSquinting: isPointerSquinting,
    );
    return MascotVisualSnapshot(
      mood: mood,
      dailyGoalProgressRatio: ratio,
      remainingCo2Grams: remaining,
      goalPercent: percent,
      statusCaptionRu: captionForMood(
        mood: mood,
        remainingCo2Grams: remaining,
        goalPercent: percent,
      ),
      equippedAccessoryCode: profile.mascot.equippedAccessoryCode,
      unlockedAccessoryCodes: profile.mascot.unlockedAccessoryCodes,
      isPointerSquinting: isPointerSquinting,
    );
  }

  static MascotMoodState resolveMood({
    required double ratio,
    required bool isPointerSquinting,
  }) {
    if (isPointerSquinting) return .squinting;
    if (ratio <= 0.0) return .sleepy;
    if (ratio < 0.50) return .neutral;
    if (ratio < 1.00) return .happy;
    return .thriving;
  }

  static String captionForMood({
    required MascotMoodState mood,
    required int remainingCo2Grams,
    required int goalPercent,
  }) => switch (mood) {
    .sleepy => 'Зверёк дремлет · Начните шагать, чтобы разбудить его!',
    .neutral || .happy =>
      'Зверёк бодрствует · До цели дня осталось $remainingCo2Grams г CO₂',
    .thriving =>
      'Дневная цель выполнена ($goalPercent%)! Зверёк гордится вами!',
    .squinting => 'Щекотно! Пойдём гулять?',
  };
}

final class const TodayCardMetrics({
  required final int validatedSteps,
  required final int dailyStepGoal,
  required final double stepGoalProgress,
  required final double totalStepDistanceKm,
  required final int estimatedKcal,
  required final int strideLengthCm,
  required final int pointsAwardedForDay,
  required final int totalCo2SavedGrams,
  required final int dailyCo2GoalGrams,
  required final double co2GoalProgress,
  required final bool isAutoCalculated,
  required final int allocatedCo2SavedGrams,
  required final double allocatedGpsDistanceM,
  required final int autoDefaultCo2SavedGrams,
  required final double unallocatedStepDistanceM,
}) {
  factory fromProfileAndSummary({
    required UserProfile profile,
    required DailyActivitySummary summary,
  }) {
    final stepGoal = math.max(1, profile.dailyStepGoal);
    final co2Goal = math.max(1, profile.dailyCo2GoalGrams);
    return TodayCardMetrics(
      validatedSteps: summary.validatedSteps,
      dailyStepGoal: stepGoal,
      stepGoalProgress: (summary.validatedSteps / stepGoal).clamp(0.0, 1.0),
      totalStepDistanceKm: summary.totalStepDistanceM / 1000.0,
      estimatedKcal: (summary.validatedSteps * 0.04).round(),
      strideLengthCm: summary.strideLengthCm,
      pointsAwardedForDay: summary.pointsAwardedForDay,
      totalCo2SavedGrams: summary.totalCo2SavedGrams,
      dailyCo2GoalGrams: co2Goal,
      co2GoalProgress: (summary.totalCo2SavedGrams / co2Goal).clamp(0.0, 1.0),
      isAutoCalculated: summary.isAutoCalculated,
      allocatedCo2SavedGrams: summary.allocatedCo2SavedGrams,
      allocatedGpsDistanceM: summary.allocatedGpsDistanceM,
      autoDefaultCo2SavedGrams: summary.autoDefaultCo2SavedGrams,
      unallocatedStepDistanceM: summary.unallocatedStepDistanceM,
    );
  }

  bool get isEmptyDay => validatedSteps == 0;
}
