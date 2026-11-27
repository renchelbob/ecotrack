import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/sensors/step_sensor_bridge.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

final class _EcoTrackGpsTaskHandler() extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) =>
      Future<void>.value();

  @override
  void onRepeatEvent(DateTime timestamp) =>
      FlutterForegroundTask.sendDataToMain(
        GpsForegroundService.heartbeatActionId,
      );

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) =>
      Future<void>.value();

  @override
  void onNotificationButtonPressed(String id) {
    if (id == GpsForegroundService.stopGpsActionId) {
      FlutterForegroundTask.sendDataToMain(id);
    }
  }
}

final class GpsForegroundService({
  final SqliteDatabase? db,
  final OutboxDispatcher? outboxDispatcher,
  final StepSensorBridge? stepBridge,
}) with WidgetsBindingObserver {
  @pragma('vm:entry-point')
  static void _foregroundTaskCallback() {
    FlutterForegroundTask.setTaskHandler(_EcoTrackGpsTaskHandler());
  }

  static const String stopGpsActionId = 'stop_gps';
  static const String heartbeatActionId = 'gps_heartbeat';
  static const int _batchSizeThreshold = 20;
  static const int _batchMaxAgeMs = 180000;
  static const int _maxBatchPoints = 500;
  static const int _staleFixToleranceMs = 2000;
  static const Distance _geoDistance = Distance(roundResult: false);

  final StreamController<({double lat, double lon, double accuracy})>
  _positionController =
      StreamController<({double lat, double lon, double accuracy})>.broadcast();

  final Map<String, int> _maxRecordedAtMsByDate = <String, int>{};
  final Map<String, Set<int>> _unseededSeqNosByDate = <String, Set<int>>{};

  StreamSubscription<Position>? _positionSub;
  Timer? _batchAgeTimer;
  bool _isTracking = false;
  bool _foregroundInitialized = false;
  bool _taskCallbackRegistered = false;
  bool _hasLifecycleObserver = false;
  bool _disposed = false;
  int _lastBatchFlushMs = 0;

  SqliteDatabase get _database => db ?? SqliteDatabase.instance;

  bool get isTracking => _isTracking;

  Stream<({double lat, double lon, double accuracy})> get positionStream =>
      _positionController.stream;

  static double _sanitizeNonNegFinite(double value) =>
      value.isFinite && value >= 0.0 ? value : 0.0;

  static bool _isValidCoordinate(double lat, double lon) =>
      lat.isFinite &&
      lon.isFinite &&
      lat >= -90.0 &&
      lat <= 90.0 &&
      lon >= -180.0 &&
      lon <= 180.0;

  void _ensureForegroundTaskInitialized() {
    if (_foregroundInitialized) {
      return;
    }
    _foregroundInitialized = true;
    try {
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'ecotrack_gps_tracking',
          channelName: 'Запись эко-маршрута EcoTrack',
          channelDescription: 'Фоновая запись геолокации для точного расчёта сэкономленного CO₂',
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(15000),
        ),
      );
    } on PlatformException {
      _foregroundInitialized = false;
    } on MissingPluginException {
      _foregroundInitialized = false;
    }
  }

  void _handleTaskData(Object data) {
    final action = switch (data) {
      final String id => id,
      {'action': final String id} => id,
      _ => null,
    };
    if (action == stopGpsActionId && _isTracking) {
      unawaited(stopTracking());
    }
  }

  void _registerTaskCallback() {
    if (_taskCallbackRegistered) {
      return;
    }
    try {
      FlutterForegroundTask.addTaskDataCallback(_handleTaskData);
      _taskCallbackRegistered = true;
    } on PlatformException {
      _taskCallbackRegistered = false;
    } on MissingPluginException {
      _taskCallbackRegistered = false;
    }
  }

  void _unregisterTaskCallback() {
    if (!_taskCallbackRegistered) {
      return;
    }
    _taskCallbackRegistered = false;
    try {
      FlutterForegroundTask.removeTaskDataCallback(_handleTaskData);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        _isTracking &&
        !_disposed) {
      unawaited(flushPendingAllDates());
    }
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

  Future<bool> checkAndRequestPermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<({double lat, double lon, double accuracy})?>
  getCurrentPosition() async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      return null;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!_isValidCoordinate(pos.latitude, pos.longitude)) {
        return null;
      }
      return (
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: _sanitizeNonNegFinite(pos.accuracy),
      );
    } on TimeoutException {
      return await _readLastKnownPosition();
    } on PlatformException {
      return await _readLastKnownPosition();
    } on MissingPluginException {
      return null;
    }
  }

  Future<({double lat, double lon, double accuracy})?>
  _readLastKnownPosition() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null || !_isValidCoordinate(pos.latitude, pos.longitude)) {
        return null;
      }
      return (
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: _sanitizeNonNegFinite(pos.accuracy),
      );
    } on PlatformException {
      return null;
    }
  }

  Future<void> startTracking({required int intervalSeconds}) async {
    if (_disposed) {
      return;
    }
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      return;
    }

    _ensureForegroundTaskInitialized();
    _registerTaskCallback();
    _registerLifecycleObserver();
    _isTracking = true;
    _lastBatchFlushMs = DateTime.now().millisecondsSinceEpoch;
    unawaited(stepBridge?.readPersistedBootCounter());

    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'EcoTrack записывает пеший маршрут',
        notificationText: 'Интервал GPS: $intervalSeconds сек · Идёт запись',
        notificationButtons: const [
          NotificationButton(id: stopGpsActionId, text: 'Остановить GPS'),
        ],
        callback: _foregroundTaskCallback,
      );
    } on PlatformException {
      // Continue stream capture when foreground service notification is unavailable.
    } on MissingPluginException {
      // Continue stream capture in unit test environments without platform channel.
    }

    _batchAgeTimer?.cancel();
    _batchAgeTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_flushExpiredPendingDates()),
    );

    await _positionSub?.cancel();
    final settings = _locationSettingsForInterval(intervalSeconds);
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (pos) => unawaited(_handlePositionFix(pos)),
          onError: (Object _) {
            _isTracking = false;
          },
        );
  }

  Future<void> _flushExpiredPendingDates() async {
    if (!_database.isInitialized || _disposed) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastBatchFlushMs < _batchMaxAgeMs) {
      return;
    }
    final dates = await _loadPendingDates();
    for (final date in dates) {
      await _maybeFlushPendingPoints(date);
    }
  }

  Future<void> _handlePositionFix(Position pos) async {
    if (!_isValidCoordinate(pos.latitude, pos.longitude)) {
      return;
    }
    final safeAccuracy = _sanitizeNonNegFinite(pos.accuracy);
    final safeSpeed = _sanitizeNonNegFinite(pos.speed);

    if (!_positionController.isClosed) {
      _positionController.add((
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: safeAccuracy,
      ));
    }
    if (!_database.isInitialized) {
      return;
    }

    final rawRecordedAtMs = pos.timestamp.millisecondsSinceEpoch;
    final activityDate = _formatLocalDate(pos.timestamp);
    var liveBootSteps = stepBridge?.authoritativeBootStepsOrNull;
    if (liveBootSteps == null && stepBridge != null) {
      liveBootSteps = await stepBridge?.readPersistedBootCounter();
    }

    final inserted = await _database.database.transaction((txn) async {
      final highWaterMs = await _resolveHighWaterMs(txn, activityDate);
      if (highWaterMs > 0 &&
          rawRecordedAtMs < highWaterMs - _staleFixToleranceMs) {
        return false;
      }
      final recordedAtMs = (highWaterMs > 0 && rawRecordedAtMs <= highWaterMs)
          ? highWaterMs + 1
          : rawRecordedAtMs;

      final prevRows = await txn.query(
        'local_gps_track_points',
        where: 'activity_date = ?',
        whereArgs: [activityDate],
        orderBy: 'seq_no DESC',
        limit: 1,
      );

      final int cumulativeSteps;
      if (liveBootSteps != null) {
        cumulativeSteps = math.max(0, liveBootSteps);
        await _backfillUnseededStepsTxn(txn, activityDate, cumulativeSteps);
      } else if (prevRows.isNotEmpty) {
        cumulativeSteps =
            (prevRows.first['cumulative_steps'] as num?)?.toInt() ?? 0;
      } else {
        cumulativeSteps = 0;
      }

      final int seqNo;
      final int deltaSteps;
      final double deltaDistanceM;
      final String motionClass;

      if (prevRows.isEmpty) {
        seqNo = 0;
        deltaSteps = 0;
        deltaDistanceM = 0.0;
        motionClass = 'stationary';
      } else {
        final prev = prevRows.first;
        seqNo = ((prev['seq_no'] as num?)?.toInt() ?? 0) + 1;
        final prevMs =
            (prev['recorded_at_ms'] as num?)?.toInt() ?? recordedAtMs;
        final deltaTSec = math.max(1.0, (recordedAtMs - prevMs) / 1000.0);
        final prevLat = (prev['lat'] as num?)?.toDouble() ?? pos.latitude;
        final prevLon = (prev['lon'] as num?)?.toDouble() ?? pos.longitude;
        final rawDist = _geoDistance.as(
          LengthUnit.Meter,
          LatLng(prevLat, prevLon),
          LatLng(pos.latitude, pos.longitude),
        );
        deltaDistanceM = _sanitizeNonNegFinite(rawDist);
        final prevSteps =
            liveBootSteps != null &&
                (_unseededSeqNosByDate[activityDate]?.contains(
                      (prev['seq_no'] as num?)?.toInt(),
                    ) ??
                    false)
            ? cumulativeSteps
            : (prev['cumulative_steps'] as num?)?.toInt() ?? 0;
        deltaSteps = Co2Math.computeRebootSafeStepDelta(
          prevSteps,
          cumulativeSteps,
        );
        final classification = Co2Math.classifyMotionIntervalSafe(
          deltaTSec: deltaTSec,
          deltaDistM: deltaDistanceM,
          deltaSteps: deltaSteps,
          accuracyM: safeAccuracy,
        );
        if (classification.antifraudCode case final code?) {
          debugPrint('GpsForegroundService antifraud rejected point: $code');
          return false;
        }
        motionClass = classification.motionClass;
      }

      await txn.insert('local_gps_track_points', <String, Object?>{
        'activity_date': activityDate,
        'seq_no': seqNo,
        'recorded_at_ms': recordedAtMs,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'accuracy_m': safeAccuracy,
        'speed_mps': safeSpeed,
        'cumulative_steps': cumulativeSteps,
        'delta_steps': deltaSteps,
        'delta_distance_m': deltaDistanceM,
        'motion_class': motionClass,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      _maxRecordedAtMsByDate[activityDate] = recordedAtMs;
      if (liveBootSteps == null && stepBridge != null) {
        _unseededSeqNosByDate
            .putIfAbsent(activityDate, () => <int>{})
            .add(seqNo);
      } else {
        _unseededSeqNosByDate.remove(activityDate);
      }
      return true;
    });

    if (inserted) {
      await _maybeFlushPendingPoints(activityDate);
    }
  }

  Future<int> _resolveHighWaterMs(Transaction txn, String activityDate) async {
    final cached = _maxRecordedAtMsByDate[activityDate];
    if (cached != null) {
      return cached;
    }
    final rows = await txn.rawQuery(
      'SELECT MAX(recorded_at_ms) AS max_ms FROM local_gps_track_points '
      'WHERE activity_date = ?',
      [activityDate],
    );
    final dbMax = rows.isEmpty
        ? 0
        : (rows.first['max_ms'] as num?)?.toInt() ?? 0;
    _maxRecordedAtMsByDate[activityDate] = dbMax;
    return dbMax;
  }

  Future<void> _backfillUnseededStepsTxn(
    Transaction txn,
    String activityDate,
    int seededSteps,
  ) async {
    final unseeded = _unseededSeqNosByDate[activityDate];
    if (unseeded == null || unseeded.isEmpty) {
      return;
    }
    final seqList = unseeded.toList();
    final placeholders = List<String>.filled(seqList.length, '?').join(',');
    await txn.rawUpdate(
      'UPDATE local_gps_track_points SET cumulative_steps = ?, delta_steps = 0 '
      'WHERE activity_date = ? AND sync_status = ? AND seq_no IN ($placeholders)',
      <Object?>[seededSteps, activityDate, 'pending', ...seqList],
    );
  }

  Future<bool> _maybeFlushPendingPoints(
    String activityDate, {
    bool force = false,
  }) async {
    if (!_database.isInitialized) {
      return false;
    }
    final rows = await _database.database.query(
      'local_gps_track_points',
      where: 'activity_date = ? AND sync_status = ?',
      whereArgs: [activityDate, 'pending'],
      orderBy: 'seq_no ASC',
      limit: _maxBatchPoints,
    );
    if (rows.isEmpty) {
      return false;
    }
    final queuedSeqNos = await _loadQueuedSeqNos(activityDate);
    final unqueuedRows = rows
        .where(
          (row) => !queuedSeqNos.contains((row['seq_no'] as num?)?.toInt()),
        )
        .toList();
    if (unqueuedRows.isEmpty) {
      return false;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageMs = nowMs - _lastBatchFlushMs;
    if (!force &&
        unqueuedRows.length < _batchSizeThreshold &&
        ageMs < _batchMaxAgeMs) {
      return false;
    }

    final pointsPayload = <Map<String, Object?>>[];
    for (final row in unqueuedRows) {
      final lat = (row['lat'] as num?)?.toDouble();
      final lon = (row['lon'] as num?)?.toDouble();
      if (lat == null || lon == null || !_isValidCoordinate(lat, lon)) {
        continue;
      }
      final ms = (row['recorded_at_ms'] as num?)?.toInt() ?? nowMs;
      final acc = _sanitizeNonNegFinite(
        (row['accuracy_m'] as num?)?.toDouble() ?? 0.0,
      );
      final spd = _sanitizeNonNegFinite(
        (row['speed_mps'] as num?)?.toDouble() ?? 0.0,
      );
      pointsPayload.add(<String, Object?>{
        'seq_no': (row['seq_no'] as num?)?.toInt() ?? 0,
        'recorded_at': DateTime.fromMillisecondsSinceEpoch(
          ms,
          isUtc: true,
        ).toIso8601String(),
        'lat': lat,
        'lon': lon,
        'accuracy_m': acc,
        'speed_mps': spd,
        'cumulative_steps': math.max(
          0,
          (row['cumulative_steps'] as num?)?.toInt() ?? 0,
        ),
      });
    }
    if (pointsPayload.isEmpty) {
      return false;
    }

    final outbox = outboxDispatcher;
    if (outbox == null) {
      return false;
    }

    await outbox.enqueue(
      operationType: 'upload_gps_track_batch',
      httpMethod: 'POST',
      endpointPath: '/api/v1/activity/tracks/points:batch',
      payloadJson: jsonEncode(<String, Object?>{
        'activity_date': activityDate,
        'points': pointsPayload,
      }),
    );
    _lastBatchFlushMs = nowMs;
    unawaited(outbox.flush());
    return true;
  }

  Future<List<String>> _loadPendingDates() async {
    final rows = await _database.database.rawQuery(
      'SELECT DISTINCT activity_date FROM local_gps_track_points '
      'WHERE sync_status = ? ORDER BY activity_date ASC',
      const ['pending'],
    );
    return rows
        .map((row) => row['activity_date'])
        .whereType<String>()
        .where((date) => date.isNotEmpty)
        .toList();
  }

  Future<Set<int>> _loadQueuedSeqNos(String activityDate) async {
    final outboxRows = await _database.database.query(
      OutboxDispatcher.tableName,
      columns: const ['payload_json'],
      where: 'operation_type = ? AND status IN (?, ?)',
      whereArgs: const [
        'upload_gps_track_batch',
        OutboxDispatcher.statusPending,
        OutboxDispatcher.statusInFlight,
      ],
    );
    final result = <int>{};
    for (final row in outboxRows) {
      _collectQueuedSeqNosFromPayload(
        row['payload_json'] as String?,
        activityDate,
        result,
      );
    }
    return result;
  }

  static void _collectQueuedSeqNosFromPayload(
    String? payloadJson,
    String activityDate,
    Set<int> target,
  ) {
    if (payloadJson == null || payloadJson.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map<Object?, Object?>) {
        return;
      }
      if (decoded['activity_date'] != activityDate) {
        return;
      }
      final points = decoded['points'];
      if (points is! List<Object?>) {
        return;
      }
      for (final point in points) {
        if (point is Map<Object?, Object?>) {
          final seqNo = (point['seq_no'] as num?)?.toInt();
          if (seqNo != null) {
            target.add(seqNo);
          }
        }
      }
    } on FormatException {
      return;
    }
  }

  Future<void> flushPendingAllDates() async {
    if (!_database.isInitialized) {
      return;
    }
    final dates = await _loadPendingDates();
    for (final date in dates) {
      var enqueued = true;
      while (enqueued) {
        enqueued = await _maybeFlushPendingPoints(date, force: true);
      }
    }
  }

  Future<void> flushPendingToday() => flushPendingAllDates();

  Future<void> stopTracking() async {
    _isTracking = false;
    _batchAgeTimer?.cancel();
    _batchAgeTimer = null;
    _unregisterTaskCallback();
    _unregisterLifecycleObserver();
    await _positionSub?.cancel();
    _positionSub = null;
    await flushPendingAllDates();
    if (stepBridge != null) {
      unawaited(stepBridge?.syncFromLocalProfile());
    }

    try {
      await FlutterForegroundTask.stopService();
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  LocationSettings _locationSettingsForInterval(int intervalSeconds) {
    final (
      int distanceFilter,
      LocationAccuracy accuracy,
    ) = switch (intervalSeconds) {
      <= 5 => (5, LocationAccuracy.best),
      <= 15 => (10, LocationAccuracy.high),
      _ => (20, LocationAccuracy.medium),
    };
    return AndroidSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      intervalDuration: Duration(seconds: math.max(5, intervalSeconds)),
    );
  }

  static String _formatLocalDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopTracking();
    if (!_positionController.isClosed) {
      await _positionController.close();
    }
  }
}
