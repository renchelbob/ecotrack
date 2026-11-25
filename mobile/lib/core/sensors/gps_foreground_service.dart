import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/sensors/step_sensor_bridge.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

final class GpsForegroundService({
  final SqliteDatabase? db,
  final OutboxDispatcher? outboxDispatcher,
  final StepSensorBridge? stepBridge,
}) {
  static const int _batchSizeThreshold = 20;
  static const int _batchMaxAgeMs = 180000;
  static const int _maxBatchPoints = 500;
  static const Distance _geoDistance = Distance();

  final StreamController<({double lat, double lon, double accuracy})>
  _positionController =
      StreamController<({double lat, double lon, double accuracy})>.broadcast();

  StreamSubscription<Position>? _positionSub;
  bool _isTracking = false;
  bool _foregroundInitialized = false;
  int _lastBatchFlushMs = 0;

  SqliteDatabase get _database => db ?? SqliteDatabase.instance;

  bool get isTracking => _isTracking;

  Stream<({double lat, double lon, double accuracy})> get positionStream =>
      _positionController.stream;

  void _ensureForegroundTaskInitialized() {
    if (_foregroundInitialized) {
      return;
    }
    _foregroundInitialized = true;
    try {
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
      return (lat: pos.latitude, lon: pos.longitude, accuracy: pos.accuracy);
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
      if (pos == null) {
        return null;
      }
      return (lat: pos.latitude, lon: pos.longitude, accuracy: pos.accuracy);
    } on PlatformException {
      return null;
    }
  }

  Future<void> startTracking({required int intervalSeconds}) async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      return;
    }

    _ensureForegroundTaskInitialized();
    _isTracking = true;
    _lastBatchFlushMs = DateTime.now().millisecondsSinceEpoch;

    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'EcoTrack записывает пеший маршрут',
        notificationText: 'Интервал GPS: $intervalSeconds сек · Идёт запись',
        notificationButtons: const [
          NotificationButton(id: 'stop_gps', text: 'Остановить GPS'),
        ],
      );
    } on PlatformException {
      // Continue stream capture when foreground service notification is unavailable.
    } on MissingPluginException {
      // Continue stream capture in unit test environments without platform channel.
    }

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

  Future<void> _handlePositionFix(Position pos) async {
    if (!_positionController.isClosed) {
      _positionController.add((
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy,
      ));
    }
    if (!_database.isInitialized) {
      return;
    }

    final recordedAtMs = pos.timestamp.millisecondsSinceEpoch;
    final activityDate = _formatLocalDate(pos.timestamp);
    final cumulativeSteps = stepBridge?.latestCumulativeSteps ?? 0;

    await _database.database.transaction((txn) async {
      final prevRows = await txn.query(
        'local_gps_track_points',
        where: 'activity_date = ?',
        whereArgs: [activityDate],
        orderBy: 'seq_no DESC',
        limit: 1,
      );

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
        deltaDistanceM = _geoDistance.as(
          LengthUnit.Meter,
          LatLng(prevLat, prevLon),
          LatLng(pos.latitude, pos.longitude),
        );
        final prevSteps = (prev['cumulative_steps'] as num?)?.toInt() ?? 0;
        deltaSteps = Co2Math.computeRebootSafeStepDelta(
          prevSteps,
          cumulativeSteps,
        );
        motionClass = Co2Math.classifyMotionInterval(
          deltaTSec: deltaTSec,
          deltaDistM: deltaDistanceM,
          deltaSteps: deltaSteps,
          accuracyM: math.max(0.0, pos.accuracy),
        );
      }

      await txn.insert('local_gps_track_points', <String, Object?>{
        'activity_date': activityDate,
        'seq_no': seqNo,
        'recorded_at_ms': recordedAtMs,
        'lat': pos.latitude,
        'lon': pos.longitude,
        'accuracy_m': math.max(0.0, pos.accuracy),
        'speed_mps': math.max(0.0, pos.speed),
        'cumulative_steps': math.max(0, cumulativeSteps),
        'delta_steps': deltaSteps,
        'delta_distance_m': deltaDistanceM,
        'motion_class': motionClass,
        'sync_status': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });

    await _maybeFlushPendingPoints(activityDate);
  }

  Future<void> _maybeFlushPendingPoints(
    String activityDate, {
    bool force = false,
  }) async {
    if (!_database.isInitialized) {
      return;
    }
    final rows = await _database.database.query(
      'local_gps_track_points',
      where: 'activity_date = ? AND sync_status = ?',
      whereArgs: [activityDate, 'pending'],
      orderBy: 'seq_no ASC',
      limit: _maxBatchPoints,
    );
    if (rows.isEmpty) {
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageMs = nowMs - _lastBatchFlushMs;
    if (!force && rows.length < _batchSizeThreshold && ageMs < _batchMaxAgeMs) {
      return;
    }

    final pointsPayload = rows.map((row) {
      final ms = (row['recorded_at_ms'] as num?)?.toInt() ?? nowMs;
      return <String, Object?>{
        'seq_no': (row['seq_no'] as num?)?.toInt() ?? 0,
        'recorded_at': DateTime.fromMillisecondsSinceEpoch(
          ms,
          isUtc: true,
        ).toIso8601String(),
        'lat': (row['lat'] as num?)?.toDouble() ?? 0.0,
        'lon': (row['lon'] as num?)?.toDouble() ?? 0.0,
        'accuracy_m': (row['accuracy_m'] as num?)?.toDouble() ?? 0.0,
        'speed_mps': (row['speed_mps'] as num?)?.toDouble() ?? 0.0,
        'cumulative_steps': (row['cumulative_steps'] as num?)?.toInt() ?? 0,
      };
    }).toList();

    final outbox = outboxDispatcher;
    if (outbox != null) {
      await outbox.enqueue(
        operationType: 'upload_gps_track_batch',
        httpMethod: 'POST',
        endpointPath: '/api/v1/activity/tracks/points:batch',
        payloadJson: jsonEncode(<String, Object?>{
          'activity_date': activityDate,
          'points': pointsPayload,
        }),
      );
      final ids = rows
          .map((r) => (r['local_id'] as num?)?.toInt())
          .whereType<int>()
          .toList();
      if (ids.isNotEmpty) {
        final placeholders = List<String>.filled(ids.length, '?').join(',');
        await _database.database.rawUpdate(
          "UPDATE local_gps_track_points SET sync_status = 'synced' WHERE local_id IN ($placeholders)",
          ids,
        );
      }
      _lastBatchFlushMs = nowMs;
      unawaited(outbox.flush());
    }
  }

  Future<void> flushPendingToday() =>
      _maybeFlushPendingPoints(_formatLocalDate(DateTime.now()), force: true);

  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionSub?.cancel();
    _positionSub = null;
    await flushPendingToday();

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
    await stopTracking();
    if (!_positionController.isClosed) {
      await _positionController.close();
    }
  }
}
