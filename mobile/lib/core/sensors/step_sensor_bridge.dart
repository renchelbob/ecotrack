import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

final class StepSensorBridge({
  final Health? customHealth,
  final SqliteDatabase? db,
  final OutboxDispatcher? outboxDispatcher,
}) with WidgetsBindingObserver {
  static const String _prevBootPrefsKey =
      'ecotrack_pedometer_prev_boot_counter';
  static const int _autoSyncStepThreshold = 100;
  static const Duration _periodicSyncInterval = Duration(minutes: 15);
  static const MethodChannel _permissionsChannel = MethodChannel(
    'ru.vyatsu.ecotrack/permissions',
  );

  final Health _health = customHealth ?? Health();
  final StreamController<int> _liveStepsController =
      StreamController<int>.broadcast();

  StreamSubscription<StepCount>? _pedometerSub;
  Timer? _periodicSyncTimer;
  int _latestCumulativeSteps = 0;
  int? _previousBootCounter;
  int _latestLiveSteps = 0;
  int _lastAutoQueuedSteps = 0;
  bool _hasBootReading = false;
  bool _bootCounterLoaded = false;
  bool _hasSyncedYesterdayThisLaunch = false;
  bool _hasLifecycleObserver = false;
  bool _disposed = false;

  SqliteDatabase get _database => db ?? SqliteDatabase.instance;

  int get latestCumulativeSteps => _latestCumulativeSteps;

  int? get authoritativeBootStepsOrNull =>
      _hasBootReading ? _latestCumulativeSteps : null;

  int get latestLiveSteps => _latestLiveSteps;

  Stream<int> get liveStepsStream => _liveStepsController.stream;

  Future<bool> _requestActivityRecognitionPermission() async {
    if (customHealth != null) {
      return true;
    }
    try {
      final granted = await _permissionsChannel.invokeMethod<bool>(
        'requestActivityRecognition',
      );
      return granted ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    final activityGranted = await _requestActivityRecognitionPermission();
    final types = <HealthDataType>[HealthDataType.STEPS];
    final permissions = <HealthDataAccess>[HealthDataAccess.READ];

    try {
      if (customHealth == null) {
        await _health.configure();
        final hcAvailable = await _health.isHealthConnectAvailable();
        if (!hcAvailable) {
          return activityGranted;
        }
      }
      final healthGranted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      return healthGranted && activityGranted;
    } on PlatformException {
      return activityGranted && customHealth == null;
    } on MissingPluginException {
      return false;
    }
  }

  Future<int?> readPersistedBootCounter() async {
    if (_hasBootReading) {
      return _latestCumulativeSteps;
    }
    if (_bootCounterLoaded) {
      return _previousBootCounter;
    }
    _bootCounterLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_prevBootPrefsKey);
      if (stored != null && stored >= 0) {
        _previousBootCounter ??= stored;
      }
    } on PlatformException {
      return _previousBootCounter;
    } on MissingPluginException {
      return _previousBootCounter;
    }
    return _previousBootCounter;
  }

  Future<void> _persistBootCounter(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prevBootPrefsKey, value);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
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
    if (_disposed) {
      return;
    }
    unawaited(_pedometerSub?.cancel());
    unawaited(readPersistedBootCounter());
    _registerLifecycleObserver();
    _startPeriodicSyncTimer();
    unawaited(_syncYesterdayIfNeeded());

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) {
      unawaited(onAppResumed());
    }
  }

  Future<void> onAppResumed() async {
    if (_disposed) {
      return;
    }
    await syncFromLocalProfile();
    await outboxDispatcher?.onAppResumed();
  }

  void _registerLifecycleObserver() {
    if (_hasLifecycleObserver) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized().addObserver(this);
    _hasLifecycleObserver = true;
  }

  void _unregisterLifecycleObserver() {
    if (!_hasLifecycleObserver) {
      return;
    }
    _hasLifecycleObserver = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  void _startPeriodicSyncTimer() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(
      _periodicSyncInterval,
      (_) => unawaited(syncFromLocalProfile()),
    );
  }

  Future<void> _handleBootCounterUpdate(
    int cumulativeBootSteps, {
    void Function(int liveSteps)? onStepUpdate,
  }) async {
    await readPersistedBootCounter();
    final safeBoot = math.max(0, cumulativeBootSteps);
    final prevBoot = _previousBootCounter;
    _previousBootCounter = safeBoot;
    _latestCumulativeSteps = safeBoot;
    _hasBootReading = true;
    unawaited(_persistBootCounter(safeBoot));

    final now = DateTime.now();
    final todayIso = _formatLocalDate(now);
    final saved = await _loadSummaryRow(todayIso);
    var savedRaw = (saved?['raw_sensor_steps'] as num?)?.toInt() ?? 0;
    var baseline = (saved?['pedometer_boot_baseline'] as num?)?.toInt();

    if (baseline == null) {
      final healthSteps = await fetchAuthoritativeDailySteps(now);
      savedRaw = math.max(savedRaw, healthSteps);
      baseline = safeBoot - savedRaw;
    } else if (prevBoot != null && prevBoot > 0 && safeBoot < prevBoot) {
      baseline = safeBoot - savedRaw;
    }

    final liveFromPedometer = math.max(0, safeBoot - baseline);
    final rawReconciled = math.max(savedRaw, liveFromPedometer);
    final cappedSteps = math.min(rawReconciled, Co2Math.maxDailySteps);
    _latestLiveSteps = cappedSteps;

    await _persistPedometerSummaryUpdate(
      now: now,
      todayIso: todayIso,
      saved: saved,
      savedRaw: savedRaw,
      baseline: baseline,
      cappedSteps: cappedSteps,
    );

    if (!_liveStepsController.isClosed) {
      _liveStepsController.add(cappedSteps);
    }
    onStepUpdate?.call(cappedSteps);

    if (cappedSteps - _lastAutoQueuedSteps >= _autoSyncStepThreshold) {
      _lastAutoQueuedSteps = cappedSteps;
      await _enqueueStepsOutboxIfConfigured(
        activityDate: todayIso,
        now: now,
        steps: cappedSteps,
      );
    }
  }

  Future<void> _persistPedometerSummaryUpdate({
    required DateTime now,
    required String todayIso,
    required Map<String, Object?>? saved,
    required int savedRaw,
    required int baseline,
    required int cappedSteps,
  }) async {
    if (!_database.isInitialized) {
      return;
    }
    final profile = await _readLocalProfileMeta();
    final strideLengthCm =
        (saved?['stride_length_cm'] as num?)?.toInt() ??
        profile?.strideLengthCm ??
        Co2Math.defaultStrideLengthCm;
    final totalDistM = Co2Math.computeStepDistanceM(
      cappedSteps,
      strideLengthCm,
    );
    final allocDistM =
        (saved?['allocated_gps_distance_m'] as num?)?.toDouble() ?? 0.0;
    final allocCo2G =
        (saved?['allocated_co2_saved_grams'] as num?)?.toInt() ?? 0;
    final unallocDistM = math.max(0.0, totalDistM - allocDistM);
    final autoCo2G = Co2Math.computeAutoDefaultCo2Grams(unallocDistM);
    final pointsTarget = Co2Math.computeDailyStepPointsTarget(cappedSteps);

    if (saved != null) {
      final existingSyncStatus = saved['sync_status'] as String? ?? 'pending';
      final nextSyncStatus = cappedSteps > savedRaw
          ? 'pending'
          : existingSyncStatus;
      await _database.database.update(
        'local_daily_step_summaries',
        <String, Object?>{
          'pedometer_boot_baseline': baseline,
          'raw_sensor_steps': cappedSteps,
          'validated_steps': cappedSteps,
          'total_step_distance_m': totalDistM,
          'unallocated_step_distance_m': unallocDistM,
          'auto_default_co2_saved_grams': autoCo2G,
          'total_co2_saved_grams': allocCo2G + autoCo2G,
          'points_awarded_for_day': pointsTarget,
          'sync_status': nextSyncStatus,
          'last_sensor_read_at_ms': now.millisecondsSinceEpoch,
        },
        where: 'activity_date = ?',
        whereArgs: [todayIso],
      );
      return;
    }

    if (profile != null) {
      await _database.database.insert(
        'local_daily_step_summaries',
        <String, Object?>{
          'activity_date': todayIso,
          'user_id': profile.userId,
          'timezone_offset_minutes': now.timeZoneOffset.inMinutes,
          'raw_sensor_steps': cappedSteps,
          'validated_steps': cappedSteps,
          'pedometer_boot_baseline': baseline,
          'stride_length_cm': strideLengthCm,
          'total_step_distance_m': totalDistM,
          'allocated_gps_distance_m': 0.0,
          'unallocated_step_distance_m': totalDistM,
          'allocated_co2_saved_grams': 0,
          'auto_default_co2_saved_grams': autoCo2G,
          'total_co2_saved_grams': autoCo2G,
          'points_awarded_for_day': pointsTarget,
          'is_auto_calculated': 1,
          'sync_status': 'pending',
          'last_sensor_read_at_ms': now.millisecondsSinceEpoch,
          'last_synced_at_ms': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<int?> syncFromLocalProfile() async {
    if (!_database.isInitialized || _disposed) {
      return null;
    }
    final profile = await _readLocalProfileMeta();
    if (profile == null) {
      return null;
    }
    final steps = await syncTodaySteps(
      userId: profile.userId,
      strideLengthCm: profile.strideLengthCm,
    );
    await _syncYesterdayIfNeeded(profile: profile);
    if (steps > 0) {
      await _enqueueStepsOutboxIfConfigured(
        activityDate: _formatLocalDate(DateTime.now()),
        now: DateTime.now(),
        steps: steps,
        strideLengthCm: profile.strideLengthCm,
      );
    }
    return steps;
  }

  Future<void> _syncYesterdayIfNeeded({
    ({String userId, int strideLengthCm})? profile,
  }) async {
    if (_hasSyncedYesterdayThisLaunch || !_database.isInitialized) {
      return;
    }
    _hasSyncedYesterdayThisLaunch = true;
    final resolvedProfile = profile ?? await _readLocalProfileMeta();
    if (resolvedProfile == null) {
      return;
    }

    final now = DateTime.now();
    final startOfTodayMs = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayIso = _formatLocalDate(yesterday);
    final row = await _loadSummaryRow(yesterdayIso);
    final lastSyncedMs = (row?['last_synced_at_ms'] as num?)?.toInt();
    if (row != null &&
        row['sync_status'] == 'synced' &&
        lastSyncedMs != null &&
        lastSyncedMs >= startOfTodayMs) {
      return;
    }

    final healthSteps = await fetchAuthoritativeDailySteps(yesterday);
    final savedRaw = (row?['raw_sensor_steps'] as num?)?.toInt() ?? 0;
    final effective = math.min(
      math.max(healthSteps, savedRaw),
      Co2Math.maxDailySteps,
    );
    if (effective <= 0 && row == null) {
      return;
    }

    await _upsertSummaryPreservingSyncTimestamp(
      activityDate: yesterdayIso,
      now: now,
      userId: resolvedProfile.userId,
      strideLengthCm: resolvedProfile.strideLengthCm,
      existingRow: row,
      effectiveSteps: effective,
      baseline: (row?['pedometer_boot_baseline'] as num?)?.toInt(),
    );

    if (effective > savedRaw || row?['sync_status'] != 'synced') {
      await _enqueueStepsOutboxIfConfigured(
        activityDate: yesterdayIso,
        now: now,
        steps: effective,
        strideLengthCm: resolvedProfile.strideLengthCm,
      );
    }
  }

  Future<int> syncTodaySteps({
    required String userId,
    required int strideLengthCm,
  }) async {
    await readPersistedBootCounter();
    final now = DateTime.now();
    final todayIso = _formatLocalDate(now);
    final healthSteps = await fetchAuthoritativeDailySteps(now);
    final row = await _loadSummaryRow(todayIso);
    final savedRaw = (row?['raw_sensor_steps'] as num?)?.toInt() ?? 0;
    var baseline = (row?['pedometer_boot_baseline'] as num?)?.toInt();

    if (baseline == null && _hasBootReading) {
      baseline = _latestCumulativeSteps - math.max(healthSteps, savedRaw);
    }

    final pedometerLive = baseline != null && _hasBootReading
        ? math.max(0, _latestCumulativeSteps - baseline)
        : savedRaw;
    final reconciledRaw = math.max(
      healthSteps,
      math.max(savedRaw, pedometerLive),
    );
    var effectiveSteps = math.min(reconciledRaw, Co2Math.maxDailySteps);

    final lastSyncedMs = (row?['last_synced_at_ms'] as num?)?.toInt();
    if (row != null && lastSyncedMs != null) {
      final dtSec = (now.millisecondsSinceEpoch - lastSyncedMs) / 1000.0;
      final delta = effectiveSteps - savedRaw;
      if (dtSec >= 30.0 &&
          delta > 500 &&
          delta / dtSec > Co2Math.maxSustainedCadenceSps) {
        debugPrint(
          'StepSensorBridge antifraud spike suppressed: delta=$delta dt=${dtSec.toStringAsFixed(1)}s',
        );
        effectiveSteps = savedRaw;
      }
    }

    await _upsertSummaryPreservingSyncTimestamp(
      activityDate: todayIso,
      now: now,
      userId: userId,
      strideLengthCm: strideLengthCm,
      existingRow: row,
      effectiveSteps: effectiveSteps,
      baseline: baseline,
    );

    _latestLiveSteps = effectiveSteps;
    if (!_liveStepsController.isClosed) {
      _liveStepsController.add(effectiveSteps);
    }
    return effectiveSteps;
  }

  Future<void> _upsertSummaryPreservingSyncTimestamp({
    required String activityDate,
    required DateTime now,
    required String userId,
    required int strideLengthCm,
    required Map<String, Object?>? existingRow,
    required int effectiveSteps,
    required int? baseline,
  }) async {
    if (!_database.isInitialized) {
      return;
    }
    final savedRaw = (existingRow?['raw_sensor_steps'] as num?)?.toInt() ?? 0;
    final totalDistM = Co2Math.computeStepDistanceM(
      effectiveSteps,
      strideLengthCm,
    );
    final allocDistM =
        (existingRow?['allocated_gps_distance_m'] as num?)?.toDouble() ?? 0.0;
    final allocCo2G =
        (existingRow?['allocated_co2_saved_grams'] as num?)?.toInt() ?? 0;
    final unallocDistM = math.max(0.0, totalDistM - allocDistM);
    final autoCo2G = Co2Math.computeAutoDefaultCo2Grams(unallocDistM);
    final totalCo2G = allocCo2G + autoCo2G;
    final pointsTarget = Co2Math.computeDailyStepPointsTarget(effectiveSteps);

    final existingLastSyncedMs = (existingRow?['last_synced_at_ms'] as num?)
        ?.toInt();
    final existingSyncStatus = existingRow?['sync_status'] as String?;
    final existingStride = (existingRow?['stride_length_cm'] as num?)?.toInt();
    final unchangedSinceSync =
        existingRow != null &&
        existingSyncStatus == 'synced' &&
        effectiveSteps == savedRaw &&
        strideLengthCm == existingStride;
    final nextSyncStatus = unchangedSinceSync ? 'synced' : 'pending';

    final values = <String, Object?>{
      'user_id': userId,
      'timezone_offset_minutes': now.timeZoneOffset.inMinutes,
      'raw_sensor_steps': effectiveSteps,
      'validated_steps': effectiveSteps,
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
      'sync_status': nextSyncStatus,
      'last_sensor_read_at_ms': now.millisecondsSinceEpoch,
      'last_synced_at_ms': existingLastSyncedMs,
    };

    if (existingRow == null) {
      await _database.database.insert(
        'local_daily_step_summaries',
        <String, Object?>{'activity_date': activityDate, ...values},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return;
    }

    await _database.database.update(
      'local_daily_step_summaries',
      values,
      where: 'activity_date = ?',
      whereArgs: [activityDate],
    );
  }

  Future<void> _enqueueStepsOutboxIfConfigured({
    required String activityDate,
    required DateTime now,
    required int steps,
    int? strideLengthCm,
  }) async {
    final outbox = outboxDispatcher;
    if (outbox == null || !_database.isInitialized) {
      return;
    }
    final resolvedStride =
        strideLengthCm ??
        (await _readLocalProfileMeta())?.strideLengthCm ??
        Co2Math.defaultStrideLengthCm;
    final payload = <String, Object?>{
      'activity_date': activityDate,
      'timezone_offset_minutes': now.timeZoneOffset.inMinutes,
      'raw_sensor_steps': math.min(steps, Co2Math.maxDailySteps),
      'stride_length_cm': resolvedStride,
    };
    await outbox.enqueue(
      operationType: 'sync_daily_steps',
      httpMethod: 'PUT',
      endpointPath: '/api/v1/activity/steps/daily',
      payloadJson: jsonEncode(payload),
    );
    unawaited(outbox.flush());
  }

  Future<({String userId, int strideLengthCm})?> _readLocalProfileMeta() async {
    if (!_database.isInitialized) {
      return null;
    }
    final rows = await _database.database.query(
      'local_user_profile',
      columns: const ['user_id', 'stride_length_cm'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final userId = rows.first['user_id'] as String?;
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final stride =
        (rows.first['stride_length_cm'] as num?)?.toInt() ??
        Co2Math.defaultStrideLengthCm;
    return (userId: userId, strideLengthCm: stride.clamp(40, 120));
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
    _disposed = true;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _unregisterLifecycleObserver();
    await _pedometerSub?.cancel();
    _pedometerSub = null;
    if (!_liveStepsController.isClosed) {
      await _liveStepsController.close();
    }
  }
}
