import 'dart:async';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sqflite/sqflite.dart';

final class StepSensorBridge({
  final Health? customHealth,
  final SqliteDatabase? db,
}) {
  final Health _health = customHealth ?? Health();
  final StreamController<int> _liveStepsController =
      StreamController<int>.broadcast();

  StreamSubscription<StepCount>? _pedometerSub;
  int _latestCumulativeSteps = 0;
  int _previousBootCounter = 0;
  int _latestLiveSteps = 0;

  SqliteDatabase get _database => db ?? SqliteDatabase.instance;

  int get latestCumulativeSteps => _latestCumulativeSteps;

  int get latestLiveSteps => _latestLiveSteps;

  Stream<int> get liveStepsStream => _liveStepsController.stream;

  Future<bool> requestPermissions() async {
    try {
      final types = <HealthDataType>[HealthDataType.STEPS];
      final permissions = <HealthDataAccess>[HealthDataAccess.READ];
      return await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<int> fetchAuthoritativeDailySteps(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final endOfRange = isToday
        ? now
        : DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

    try {
      final steps = await _health.getTotalStepsInInterval(
        startOfDay,
        endOfRange,
        includeManualEntry: false,
      );
      return math.max(0, steps ?? 0);
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  void startLivePedometer({void Function(int liveSteps)? onStepUpdate}) {
    unawaited(_pedometerSub?.cancel());
    try {
      _pedometerSub = Pedometer.stepCountStream.listen(
        (event) {
          unawaited(
            _handleBootCounterUpdate(event.steps, onStepUpdate: onStepUpdate),
          );
        },
        onError: (Object _) {
          if (!_liveStepsController.isClosed) {
            _liveStepsController.add(_latestLiveSteps);
          }
        },
      );
    } on PlatformException {
      _pedometerSub = null;
    } on MissingPluginException {
      _pedometerSub = null;
    }
  }

  Future<void> _handleBootCounterUpdate(
    int cumulativeBootSteps, {
    void Function(int liveSteps)? onStepUpdate,
  }) async {
    final safeBoot = math.max(0, cumulativeBootSteps);
    final prevBoot = _previousBootCounter;
    _previousBootCounter = safeBoot;
    _latestCumulativeSteps = safeBoot;

    final todayIso = _formatLocalDate(DateTime.now());
    final saved = await _loadSummaryRow(todayIso);
    final savedRaw = (saved?['raw_sensor_steps'] as num?)?.toInt() ?? 0;
    var baseline = (saved?['pedometer_boot_baseline'] as num?)?.toInt();

    if (baseline == null) {
      baseline = safeBoot - savedRaw;
    } else if (prevBoot > 0 && safeBoot < prevBoot) {
      baseline = safeBoot - savedRaw;
    }

    final liveFromPedometer = math.max(0, safeBoot - baseline);
    final reconciled = math.max(savedRaw, liveFromPedometer);
    _latestLiveSteps = reconciled;

    if (saved != null && _database.isInitialized) {
      await _database.database.update(
        'local_daily_step_summaries',
        <String, Object?>{
          'pedometer_boot_baseline': baseline,
          'raw_sensor_steps': reconciled,
          'validated_steps': math.min(reconciled, Co2Math.maxDailySteps),
          'last_sensor_read_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'activity_date = ?',
        whereArgs: [todayIso],
      );
    }

    if (!_liveStepsController.isClosed) {
      _liveStepsController.add(reconciled);
    }
    onStepUpdate?.call(reconciled);
  }

  Future<int> syncTodaySteps({
    required String userId,
    required int strideLengthCm,
  }) async {
    final now = DateTime.now();
    final todayIso = _formatLocalDate(now);
    final healthSteps = await fetchAuthoritativeDailySteps(now);
    final row = await _loadSummaryRow(todayIso);
    final savedRaw = (row?['raw_sensor_steps'] as num?)?.toInt() ?? 0;
    var baseline = (row?['pedometer_boot_baseline'] as num?)?.toInt();

    if (baseline == null && _latestCumulativeSteps > 0) {
      baseline = _latestCumulativeSteps - math.max(healthSteps, savedRaw);
    }

    final pedometerLive = baseline != null && _latestCumulativeSteps > 0
        ? math.max(0, _latestCumulativeSteps - baseline)
        : savedRaw;
    final reconciledRaw = math.max(
      healthSteps,
      math.max(savedRaw, pedometerLive),
    );
    final validated = math.min(reconciledRaw, Co2Math.maxDailySteps);
    final totalDistM = Co2Math.computeStepDistanceM(validated, strideLengthCm);
    final allocDistM =
        (row?['allocated_gps_distance_m'] as num?)?.toDouble() ?? 0.0;
    final allocCo2G = (row?['allocated_co2_saved_grams'] as num?)?.toInt() ?? 0;
    final unallocDistM = math.max(0.0, totalDistM - allocDistM);
    final autoCo2G = Co2Math.computeAutoDefaultCo2Grams(unallocDistM);
    final totalCo2G = allocCo2G + autoCo2G;
    final pointsTarget = Co2Math.computeDailyStepPointsTarget(validated);

    if (_database.isInitialized) {
      await _database.database.insert(
        'local_daily_step_summaries',
        <String, Object?>{
          'activity_date': todayIso,
          'user_id': userId,
          'timezone_offset_minutes': now.timeZoneOffset.inMinutes,
          'raw_sensor_steps': reconciledRaw,
          'validated_steps': validated,
          'pedometer_boot_baseline': baseline,
          'stride_length_cm': strideLengthCm,
          'total_step_distance_m': totalDistM,
          'allocated_gps_distance_m': allocDistM,
          'unallocated_step_distance_m': unallocDistM,
          'allocated_co2_saved_grams': allocCo2G,
          'auto_default_co2_saved_grams': autoCo2G,
          'total_co2_saved_grams': totalCo2G,
          'points_awarded_for_day': pointsTarget,
          'is_auto_calculated': allocDistM == 0.0 ? 1 : 0,
          'sync_status': 'pending',
          'last_sensor_read_at_ms': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    _latestLiveSteps = reconciledRaw;
    if (!_liveStepsController.isClosed) {
      _liveStepsController.add(reconciledRaw);
    }
    return reconciledRaw;
  }

  Future<Map<String, Object?>?> _loadSummaryRow(String activityDate) async {
    if (!_database.isInitialized) {
      return null;
    }
    final rows = await _database.database.query(
      'local_daily_step_summaries',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static String _formatLocalDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> dispose() async {
    await _pedometerSub?.cancel();
    _pedometerSub = null;
    if (!_liveStepsController.isClosed) {
      await _liveStepsController.close();
    }
  }
}
