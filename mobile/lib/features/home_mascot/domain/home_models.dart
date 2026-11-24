import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';

enum MascotMood {
  sleepy('sleepy'),
  happy('happy'),
  thriving('thriving'),
  squinting('squinting');

  const MascotMood(this.wireName);
  final String wireName;

  static MascotMood fromWire(String? raw) => switch (raw) {
    'sleepy' => MascotMood.sleepy,
    'thriving' => MascotMood.thriving,
    'squinting' => MascotMood.squinting,
    _ => MascotMood.happy,
  };
}

final class DailyActivitySummary {
  const DailyActivitySummary({
    required this.id,
    required this.activityDate,
    required this.validatedSteps,
    required this.totalStepDistanceM,
    required this.allocatedGpsDistanceM,
    required this.unallocatedStepDistanceM,
    required this.allocatedCo2SavedGrams,
    required this.autoDefaultCo2SavedGrams,
    required this.totalCo2SavedGrams,
    required this.pointsBalance,
    required this.isAutoCalculated,
    this.mascotMood = MascotMood.happy,
    this.streakDays = 1,
  });

  final String id;
  final String activityDate;
  final int validatedSteps;
  final double totalStepDistanceM;
  final double allocatedGpsDistanceM;
  final double unallocatedStepDistanceM;
  final int allocatedCo2SavedGrams;
  final int autoDefaultCo2SavedGrams;
  final int totalCo2SavedGrams;
  final int pointsBalance;
  final bool isAutoCalculated;
  final MascotMood mascotMood;
  final int streakDays;

  static Result<DailyActivitySummary, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'id': final String id,
      'activity_date': final String activityDate,
      'validated_steps': final int validatedSteps,
      'total_step_distance_m': final num totalDist,
      'allocated_gps_distance_m': final num allocDist,
      'unallocated_step_distance_m': final num unallocDist,
      'allocated_co2_saved_grams': final int allocCo2,
      'auto_default_co2_saved_grams': final int autoCo2,
      'total_co2_saved_grams': final int totalCo2,
      'points_balance': final int balance,
      'is_auto_calculated': final bool isAuto,
    }) {
      return Ok(
        DailyActivitySummary(
          id: id,
          activityDate: activityDate,
          validatedSteps: validatedSteps,
          totalStepDistanceM: totalDist.toDouble(),
          allocatedGpsDistanceM: allocDist.toDouble(),
          unallocatedStepDistanceM: unallocDist.toDouble(),
          allocatedCo2SavedGrams: allocCo2,
          autoDefaultCo2SavedGrams: autoCo2,
          totalCo2SavedGrams: totalCo2,
          pointsBalance: balance,
          isAutoCalculated: isAuto,
          mascotMood: MascotMood.fromWire(json['mascot_mood'] as String?),
          streakDays: (json['streak_days'] as num?)?.toInt() ?? 1,
        ),
      );
    }
    return Err(
      AppError.fromCode(
        'VALIDATION_ERROR',
        'Неверный формат сводки активности',
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'activity_date': activityDate,
    'validated_steps': validatedSteps,
    'total_step_distance_m': totalStepDistanceM,
    'allocated_gps_distance_m': allocatedGpsDistanceM,
    'unallocated_step_distance_m': unallocatedStepDistanceM,
    'allocated_co2_saved_grams': allocatedCo2SavedGrams,
    'auto_default_co2_saved_grams': autoDefaultCo2SavedGrams,
    'total_co2_saved_grams': totalCo2SavedGrams,
    'points_balance': pointsBalance,
    'is_auto_calculated': isAutoCalculated,
    'mascot_mood': mascotMood.wireName,
    'streak_days': streakDays,
  };
}

abstract interface class HomeRepository {
  Future<Result<DailyActivitySummary, AppError>> getTodaySummary();
  Future<Result<DailyActivitySummary, AppError>> syncSteps(int rawSteps);
}
