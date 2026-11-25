import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/sensors/gps_foreground_service.dart';
import 'package:ecotrack_mobile/core/sensors/step_sensor_bridge.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

final class MapRepositoryImpl(
  final DioClient _dioClient,
  final SqliteDatabase _db,
  final OutboxDispatcher _outbox,
  final StepSensorBridge _steps,
  final GpsForegroundService _gps,
) implements MapActivityRepository {
  static const int _maxCachedWastePoints = 10000;
  static const int _wastePointsTtlMs = 24 * 60 * 60 * 1000;
  static const Distance _distance = Distance();

  final StreamController<DailyActivitySummary> _summaryController =
      StreamController<DailyActivitySummary>.broadcast();

  Future<void> dispose() => _summaryController.close();

  @override
  Stream<DailyActivitySummary> watchDailySummary(String activityDate) =>
      _summaryController.stream.where((s) => s.activityDate == activityDate);

  @override
  Future<Result<DailyActivitySummary, AppError>> getTodaySummary() async {
    final todayIso = _todayLocalIso();
    final pointsBalance = await _readProfilePointsBalance();
    final cached = await _readLocalSummary(
      todayIso,
      pointsBalance: pointsBalance,
    );

    final netRes = await _dioClient.get<DailyActivityDetail>(
      '/api/v1/activity/daily/$todayIso',
      parser: (data) => _parseOrThrow(data, DailyActivityDetail.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _persistDailyDetail(value);
        _emitSummary(value.summary);
        return Ok(value.summary);
      case Err(:final error):
        if (_isOfflineOrNotFound(error)) {
          final fallback =
              cached ??
              DailyActivitySummary.emptyForDate(
                todayIso,
                strideLengthCm: await _readProfileStrideCm(),
                pointsBalance: pointsBalance,
              );
          return Ok(fallback);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<DailyActivitySummary, AppError>> syncDailySteps({
    required String activityDate,
    required int rawSensorSteps,
    bool manualRefresh = false,
  }) async {
    final profileMeta = await _readProfileMeta();
    var effectiveSteps = rawSensorSteps;
    if (manualRefresh && activityDate == _todayLocalIso()) {
      final sensorSteps = await _steps.syncTodaySteps(
        userId: profileMeta.userId,
        strideLengthCm: profileMeta.strideLengthCm,
      );
      effectiveSteps = math.max(rawSensorSteps, sensorSteps);
    }

    final tzOffsetMin = DateTime.now().timeZoneOffset.inMinutes;
    final payload = <String, Object?>{
      'activity_date': activityDate,
      'timezone_offset_minutes': tzOffsetMin,
      'raw_sensor_steps': effectiveSteps,
      'stride_length_cm': profileMeta.strideLengthCm,
    };
    final idempotencyKey = UuidV7.generate();

    final netRes = await _dioClient.put<DailyActivitySummary>(
      '/api/v1/activity/steps/daily',
      data: payload,
      headers: <String, String>{'Idempotency-Key': idempotencyKey},
      parser: (data) => _parseOrThrow(data, DailyActivitySummary.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _upsertLocalSummary(
          value,
          userId: profileMeta.userId,
          tzOffsetMinutes: tzOffsetMin,
          syncStatus: 'synced',
        );
        _emitSummary(value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final localSummary = await _saveOptimisticStepSummary(
            activityDate: activityDate,
            rawSensorSteps: effectiveSteps,
            userId: profileMeta.userId,
            strideLengthCm: profileMeta.strideLengthCm,
            pointsBalance: profileMeta.pointsBalance,
            tzOffsetMin: tzOffsetMin,
          );
          await _outbox.enqueue(
            operationType: 'sync_daily_steps',
            httpMethod: 'PUT',
            endpointPath: '/api/v1/activity/steps/daily',
            payloadJson: jsonEncode(payload),
            idempotencyKey: idempotencyKey,
          );
          unawaited(_outbox.flush());
          _emitSummary(localSummary);
          return Ok(localSummary);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<DailyActivityDetail, AppError>> getDailyActivityDetail(
    String activityDate,
  ) async {
    final netRes = await _dioClient.get<DailyActivityDetail>(
      '/api/v1/activity/daily/$activityDate',
      parser: (data) => _parseOrThrow(data, DailyActivityDetail.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _persistDailyDetail(value);
        _emitSummary(value.summary);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineOrNotFound(error)) {
          final localDetail = await _loadLocalDailyDetail(activityDate);
          return Ok(localDetail);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<DailyActivityDetail, AppError>> saveRouteAllocations({
    required String activityDate,
    required List<RouteSegmentAllocationInput> allocations,
  }) async {
    final endpoint = '/api/v1/activity/daily/$activityDate/allocations';
    final payload = <String, Object?>{
      'allocations': allocations.map((a) => a.toJson()).toList(),
    };
    final idempotencyKey = UuidV7.generate();

    final netRes = await _dioClient.put<DailyActivityDetail>(
      endpoint,
      data: payload,
      headers: <String, String>{'Idempotency-Key': idempotencyKey},
      parser: (data) => _parseOrThrow(data, DailyActivityDetail.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _persistDailyDetail(value);
        _emitSummary(value.summary);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final optimistic = await _saveOptimisticAllocations(
            activityDate: activityDate,
            inputs: allocations,
          );
          await _outbox.enqueue(
            operationType: 'upsert_segment_allocation',
            httpMethod: 'PUT',
            endpointPath: endpoint,
            payloadJson: jsonEncode(payload),
            idempotencyKey: idempotencyKey,
          );
          unawaited(_outbox.flush());
          _emitSummary(optimistic.summary);
          return Ok(optimistic);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<DailyActivityDetail, AppError>> deleteRouteAllocation({
    required String activityDate,
    required String allocationId,
  }) async {
    final endpoint =
        '/api/v1/activity/daily/$activityDate/allocations/$allocationId';
    final idempotencyKey = UuidV7.generate();

    final netRes = await _dioClient.delete<DailyActivityDetail>(
      endpoint,
      headers: <String, String>{'Idempotency-Key': idempotencyKey},
      parser: (data) => _parseOrThrow(data, DailyActivityDetail.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _persistDailyDetail(value);
        _emitSummary(value.summary);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          await _db.database.delete(
            'local_route_segment_allocations',
            where: 'id = ?',
            whereArgs: [allocationId],
          );
          final recomputed = await _recomputeSummaryAfterAllocationChange(
            activityDate,
          );
          await _outbox.enqueue(
            operationType: 'delete_segment_allocation',
            httpMethod: 'DELETE',
            endpointPath: endpoint,
            payloadJson: jsonEncode(<String, Object?>{
              'activity_date': activityDate,
              'allocation_id': allocationId,
            }),
            idempotencyKey: idempotencyKey,
          );
          unawaited(_outbox.flush());
          _emitSummary(recomputed.summary);
          return Ok(recomputed);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<WastePointsBboxResponse, AppError>> queryWastePoints({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    required int zoom,
    List<WasteFractionCode> fractions = const <WasteFractionCode>[],
  }) async {
    final query = <String, Object?>{
      'min_lat': minLat,
      'min_lon': minLon,
      'max_lat': maxLat,
      'max_lon': maxLon,
      'zoom': zoom.clamp(3, 20),
      'min_trust_score': 0.0,
      'include_unverified': true,
      if (fractions.isNotEmpty)
        'fractions': fractions.map((f) => f.wireName).join(','),
    };

    final netRes = await _dioClient.get<WastePointsBboxResponse>(
      '/api/v1/map/waste-points',
      queryParameters: query,
      parser: (data) => _parseOrThrow(data, WastePointsBboxResponse.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _cacheWastePoints(value.points);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _queryCachedWastePoints(
            minLat: minLat,
            minLon: minLon,
            maxLat: maxLat,
            maxLon: maxLon,
            fractions: fractions,
          );
          return Ok(
            WastePointsBboxResponse(
              attributionBannerRu:
                  WastePointsBboxResponse.defaultAttributionBannerRu,
              totalReturned: cached.length,
              points: cached,
            ),
          );
        }
        return Err(error);
    }
  }

  @override
  Future<Result<WastePointDetail, AppError>> getWastePointDetail(
    String pointId,
  ) async {
    final netRes = await _dioClient.get<WastePointDetail>(
      '/api/v1/map/waste-points/$pointId',
      parser: (data) => _parseOrThrow(data, WastePointDetail.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _upsertSingleWastePoint(value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final cached = await _readCachedWastePointDetail(pointId);
          if (cached != null) {
            return Ok(cached);
          }
        }
        return Err(error);
    }
  }

  @override
  Future<Result<WastePointReportCreatedResponse, AppError>>
  submitWastePointReport({
    required String pointId,
    required ReportType reportType,
    String? comment,
    required double userLat,
    required double userLon,
  }) async {
    final endpoint = '/api/v1/map/waste-points/$pointId/reports';
    final idempotencyKey = UuidV7.generate();
    final payload = <String, Object?>{
      'report_type': reportType.wireName,
      'user_lat': userLat,
      'user_lon': userLon,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    };

    final netRes = await _dioClient.post<WastePointReportCreatedResponse>(
      endpoint,
      data: payload,
      headers: <String, String>{'Idempotency-Key': idempotencyKey},
      parser: (data) =>
          _parseOrThrow(data, WastePointReportCreatedResponse.fromJson),
    );

    switch (netRes) {
      case Ok(:final value):
        await _applyReportTrustUpdate(pointId, value);
        return Ok(value);
      case Err(:final error):
        if (_isOfflineError(error)) {
          final distM = await _distanceToCachedPoint(pointId, userLat, userLon);
          await _db.database.insert('pending_waste_point_reports', {
            'id': UuidV7.generate(),
            'idempotency_key': idempotencyKey,
            'waste_point_id': pointId,
            'report_type': reportType.wireName,
            'comment': comment?.trim(),
            'user_lat': userLat,
            'user_lon': userLon,
            'distance_to_point_m': distM,
            'sync_status': 'pending',
            'created_at_ms': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await _outbox.enqueue(
            operationType: 'submit_waste_point_report',
            httpMethod: 'POST',
            endpointPath: endpoint,
            payloadJson: jsonEncode(payload),
            idempotencyKey: idempotencyKey,
          );
          unawaited(_outbox.flush());
          return Err(error);
        }
        return Err(error);
    }
  }

  @override
  Future<Result<WastePointDetail, AppError>> suggestWastePoint(
    SuggestWastePointRequest req,
  ) async {
    final res = await _dioClient.post<WastePointDetail>(
      '/api/v1/map/waste-points/suggestions',
      data: req.toJson(),
      headers: <String, String>{'Idempotency-Key': UuidV7.generate()},
      parser: (data) => _parseOrThrow(data, WastePointDetail.fromJson),
    );
    if (res case Ok(:final value)) {
      await _upsertSingleWastePoint(value);
    }
    return res;
  }

  @override
  Future<void> setGpsTrackingEnabled(
    bool enabled, {
    int? intervalSeconds,
  }) async {
    if (enabled) {
      await _gps.startTracking(intervalSeconds: intervalSeconds ?? 15);
    } else {
      await _gps.stopTracking();
    }
  }

  @override
  Stream<({double lat, double lon, double accuracy})>
  get currentPositionStream => _gps.positionStream;

  @override
  Future<({double lat, double lon, double accuracy})?>
  getLastKnownOrCurrentPosition() => _gps.getCurrentPosition();

  Future<({String userId, int strideLengthCm, int pointsBalance})>
  _readProfileMeta() async {
    if (!_db.isInitialized) {
      return (userId: 'local-user', strideLengthCm: 74, pointsBalance: 0);
    }
    final rows = await _db.database.query('local_user_profile', limit: 1);
    if (rows.isEmpty) {
      return (userId: 'local-user', strideLengthCm: 74, pointsBalance: 0);
    }
    final row = rows.first;
    return (
      userId: row['user_id'] as String? ?? 'local-user',
      strideLengthCm: (row['stride_length_cm'] as num?)?.toInt() ?? 74,
      pointsBalance: (row['points_balance'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int> _readProfilePointsBalance() async =>
      (await _readProfileMeta()).pointsBalance;

  Future<int> _readProfileStrideCm() async =>
      (await _readProfileMeta()).strideLengthCm;

  Future<DailyActivitySummary?> _readLocalSummary(
    String activityDate, {
    required int pointsBalance,
  }) async {
    if (!_db.isInitialized) return null;
    final rows = await _db.database.query(
      'local_daily_step_summaries',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyActivitySummary.fromSqliteRow(
      rows.first,
      pointsBalance: pointsBalance,
    ).valueOrNull;
  }

  Future<DailyActivitySummary> _saveOptimisticStepSummary({
    required String activityDate,
    required int rawSensorSteps,
    required String userId,
    required int strideLengthCm,
    required int pointsBalance,
    required int tzOffsetMin,
  }) async {
    final existing = await _readLocalSummary(
      activityDate,
      pointsBalance: pointsBalance,
    );
    final validated = math.min(rawSensorSteps, Co2Math.maxDailySteps);
    final totalDistM = Co2Math.computeStepDistanceM(validated, strideLengthCm);
    final allocDistM = existing?.allocatedGpsDistanceM ?? 0.0;
    final allocCo2 = existing?.allocatedCo2SavedGrams ?? 0;
    final unallocDistM = math.max(0.0, totalDistM - allocDistM);
    final autoCo2 = Co2Math.computeAutoDefaultCo2Grams(unallocDistM);
    final summary = DailyActivitySummary(
      id: existing?.id ?? 'local-$activityDate',
      activityDate: activityDate,
      rawSensorSteps: rawSensorSteps,
      validatedSteps: validated,
      strideLengthCm: strideLengthCm,
      totalStepDistanceM: totalDistM,
      allocatedGpsDistanceM: allocDistM,
      unallocatedStepDistanceM: unallocDistM,
      allocatedCo2SavedGrams: allocCo2,
      autoDefaultCo2SavedGrams: autoCo2,
      totalCo2SavedGrams: allocCo2 + autoCo2,
      pointsAwardedForDay: Co2Math.computeDailyStepPointsTarget(validated),
      pointsDeltaApplied: 0,
      pointsBalance: pointsBalance,
      isAutoCalculated: allocDistM == 0.0,
      antifraudFlagged: false,
    );
    await _upsertLocalSummary(
      summary,
      userId: userId,
      tzOffsetMinutes: tzOffsetMin,
      syncStatus: 'pending',
    );
    return summary;
  }

  Future<void> _upsertLocalSummary(
    DailyActivitySummary summary, {
    required String userId,
    required int tzOffsetMinutes,
    required String syncStatus,
  }) async {
    if (!_db.isInitialized) return;
    final existing = await _db.database.query(
      'local_daily_step_summaries',
      columns: ['pedometer_boot_baseline'],
      where: 'activity_date = ?',
      whereArgs: [summary.activityDate],
      limit: 1,
    );
    final baseline = existing.isEmpty
        ? null
        : existing.first['pedometer_boot_baseline'];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.database.insert('local_daily_step_summaries', {
      'activity_date': summary.activityDate,
      'user_id': userId,
      'timezone_offset_minutes': tzOffsetMinutes,
      'raw_sensor_steps': summary.rawSensorSteps,
      'validated_steps': summary.validatedSteps,
      'pedometer_boot_baseline': baseline,
      'stride_length_cm': summary.strideLengthCm,
      'total_step_distance_m': summary.totalStepDistanceM,
      'allocated_gps_distance_m': summary.allocatedGpsDistanceM,
      'unallocated_step_distance_m': summary.unallocatedStepDistanceM,
      'allocated_co2_saved_grams': summary.allocatedCo2SavedGrams,
      'auto_default_co2_saved_grams': summary.autoDefaultCo2SavedGrams,
      'total_co2_saved_grams': summary.totalCo2SavedGrams,
      'points_awarded_for_day': summary.pointsAwardedForDay,
      'is_auto_calculated': summary.isAutoCalculated ? 1 : 0,
      'sync_status': syncStatus,
      'last_sensor_read_at_ms': nowMs,
      'last_synced_at_ms': syncStatus == 'synced' ? nowMs : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _persistDailyDetail(DailyActivityDetail detail) async {
    if (!_db.isInitialized) return;
    final meta = await _readProfileMeta();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final date = detail.summary.activityDate;

    await _upsertLocalSummary(
      detail.summary,
      userId: meta.userId,
      tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      syncStatus: 'synced',
    );

    await _db.database.transaction((txn) async {
      await txn.delete(
        'local_route_segment_allocations',
        where: 'activity_date = ?',
        whereArgs: [date],
      );
      for (final alloc in detail.allocations) {
        final polyJson = jsonEncode(
          alloc.coordinates.map((c) => [c.lat, c.lon]).toList(),
        );
        await txn.insert('local_route_segment_allocations', {
          'id': alloc.id,
          'idempotency_key': alloc.idempotencyKey,
          'activity_date': date,
          'start_seq_no': alloc.startSeqNo,
          'end_seq_no': alloc.endSeqNo,
          'polyline_json': polyJson,
          'segment_distance_m': alloc.segmentDistanceM,
          'segment_steps': alloc.segmentSteps,
          'replaced_transport_mode': alloc.replacedTransportMode.wireName,
          'applied_co2_g_per_meter': alloc.appliedCo2GPerMeter,
          'confidence_factor': alloc.confidenceFactor == 0.7 ? 0.7 : 1.0,
          'is_auto_calculated': alloc.isAutoCalculated ? 1 : 0,
          'co2_saved_grams': alloc.co2SavedGrams,
          'sync_status': 'synced',
          'created_at_ms': nowMs,
          'updated_at_ms': nowMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      if (detail.trackPoints.isNotEmpty) {
        for (final pt in detail.trackPoints) {
          final ms =
              DateTime.tryParse(pt.recordedAt)?.millisecondsSinceEpoch ?? nowMs;
          await txn.insert('local_gps_track_points', {
            'activity_date': date,
            'seq_no': pt.seqNo,
            'recorded_at_ms': ms,
            'lat': pt.lat,
            'lon': pt.lon,
            'accuracy_m': pt.accuracyM,
            'speed_mps': pt.speedMps,
            'cumulative_steps': pt.cumulativeSteps,
            'delta_steps': pt.deltaSteps,
            'delta_distance_m': pt.deltaDistanceM,
            'motion_class': pt.motionClass.wireName,
            'sync_status': 'synced',
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  Future<DailyActivityDetail> _loadLocalDailyDetail(String activityDate) async {
    final meta = await _readProfileMeta();
    final summary =
        await _readLocalSummary(
          activityDate,
          pointsBalance: meta.pointsBalance,
        ) ??
        DailyActivitySummary.emptyForDate(
          activityDate,
          strideLengthCm: meta.strideLengthCm,
          pointsBalance: meta.pointsBalance,
        );

    if (!_db.isInitialized) {
      return DailyActivityDetail(
        summary: summary,
        isEditable: _isDateEditable(activityDate),
        totalGpsWalkingDistanceM: 0.0,
        trackPoints: const [],
        allocations: const [],
        co2DeltaAppliedGrams: 0,
      );
    }

    final ptRows = await _db.database.query(
      'local_gps_track_points',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
      orderBy: 'seq_no ASC',
    );
    final trackPoints = ptRows
        .map((r) => GpsTrackPointClassified.fromSqliteRow(r).valueOrNull)
        .whereType<GpsTrackPointClassified>()
        .toList();

    final allocRows = await _db.database.query(
      'local_route_segment_allocations',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
      orderBy: 'start_seq_no ASC',
    );
    final allocations = allocRows
        .map((r) => RouteSegmentAllocationItem.fromSqliteRow(r).valueOrNull)
        .whereType<RouteSegmentAllocationItem>()
        .toList();

    final walkingDist = trackPoints
        .where((p) => p.motionClass == .walking)
        .fold<double>(0.0, (acc, p) => acc + p.deltaDistanceM);

    return DailyActivityDetail(
      summary: summary,
      isEditable: _isDateEditable(activityDate),
      totalGpsWalkingDistanceM: walkingDist,
      trackPoints: trackPoints,
      allocations: allocations,
      co2DeltaAppliedGrams: 0,
    );
  }

  Future<DailyActivityDetail> _saveOptimisticAllocations({
    required String activityDate,
    required List<RouteSegmentAllocationInput> inputs,
  }) async {
    final existingDetail = await _loadLocalDailyDetail(activityDate);
    final trackPoints = existingDetail.trackPoints;
    final presets = await _readLocalTransportGPerM();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.database.transaction((txn) async {
      await txn.delete(
        'local_route_segment_allocations',
        where: 'activity_date = ?',
        whereArgs: [activityDate],
      );
      for (final input in inputs) {
        final segmentPts = trackPoints
            .where(
              (p) => p.seqNo >= input.startSeqNo && p.seqNo <= input.endSeqNo,
            )
            .toList();
        final intervalPts = trackPoints.where(
          (p) => p.seqNo > input.startSeqNo && p.seqNo <= input.endSeqNo,
        );
        final distM = math.max(
          1.0,
          intervalPts.fold<double>(0.0, (acc, p) => acc + p.deltaDistanceM),
        );
        final steps = intervalPts.fold<int>(0, (acc, p) => acc + p.deltaSteps);
        final rate =
            presets[input.replacedTransportMode.wireName] ??
            input.replacedTransportMode.defaultCo2GramsPerMeter;
        final co2G = Co2Math.computeSegmentCo2Grams(distM, rate);
        final polyJson = jsonEncode(
          segmentPts.map((p) => [p.lat, p.lon]).toList(),
        );
        await txn.insert('local_route_segment_allocations', {
          'id': input.idempotencyKey,
          'idempotency_key': input.idempotencyKey,
          'activity_date': activityDate,
          'start_seq_no': input.startSeqNo,
          'end_seq_no': input.endSeqNo,
          'polyline_json': polyJson,
          'segment_distance_m': distM,
          'segment_steps': steps,
          'replaced_transport_mode': input.replacedTransportMode.wireName,
          'applied_co2_g_per_meter': rate,
          'confidence_factor': 1.0,
          'is_auto_calculated': 0,
          'co2_saved_grams': co2G,
          'sync_status': 'pending',
          'created_at_ms': nowMs,
          'updated_at_ms': nowMs,
        });
      }
    });

    return await _recomputeSummaryAfterAllocationChange(activityDate);
  }

  Future<DailyActivityDetail> _recomputeSummaryAfterAllocationChange(
    String activityDate,
  ) async {
    final detail = await _loadLocalDailyDetail(activityDate);
    final meta = await _readProfileMeta();
    final allocDist = detail.allocations.fold<double>(
      0.0,
      (acc, a) => acc + a.segmentDistanceM,
    );
    final allocCo2 = detail.allocations.fold<int>(
      0,
      (acc, a) => acc + a.co2SavedGrams,
    );
    final unallocDist = math.max(
      0.0,
      detail.summary.totalStepDistanceM - allocDist,
    );
    final autoCo2 = Co2Math.computeAutoDefaultCo2Grams(unallocDist);

    final updated = DailyActivitySummary(
      id: detail.summary.id,
      activityDate: activityDate,
      rawSensorSteps: detail.summary.rawSensorSteps,
      validatedSteps: detail.summary.validatedSteps,
      strideLengthCm: detail.summary.strideLengthCm,
      totalStepDistanceM: detail.summary.totalStepDistanceM,
      allocatedGpsDistanceM: allocDist,
      unallocatedStepDistanceM: unallocDist,
      allocatedCo2SavedGrams: allocCo2,
      autoDefaultCo2SavedGrams: autoCo2,
      totalCo2SavedGrams: allocCo2 + autoCo2,
      pointsAwardedForDay: detail.summary.pointsAwardedForDay,
      pointsDeltaApplied: 0,
      pointsBalance: meta.pointsBalance,
      isAutoCalculated: detail.allocations.isEmpty,
      antifraudFlagged: detail.summary.antifraudFlagged,
      antifraudReason: detail.summary.antifraudReason,
      lastSyncedAt: detail.summary.lastSyncedAt,
    );

    await _upsertLocalSummary(
      updated,
      userId: meta.userId,
      tzOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      syncStatus: 'pending',
    );
    return DailyActivityDetail(
      summary: updated,
      isEditable: detail.isEditable,
      totalGpsWalkingDistanceM: detail.totalGpsWalkingDistanceM,
      trackPoints: detail.trackPoints,
      allocations: detail.allocations,
      co2DeltaAppliedGrams: 0,
    );
  }

  Future<Map<String, double>> _readLocalTransportGPerM() async {
    if (!_db.isInitialized) return const {};
    final map = <String, double>{};
    final catalog = await _db.database.query('local_transport_catalog');
    for (final row in catalog) {
      final code = row['mode_code'] as String?;
      final rate = (row['co2_grams_per_meter'] as num?)?.toDouble();
      if (code != null && rate != null) {
        map[code] = rate;
      }
    }
    final vehicle = await _db.database.query('local_user_vehicle', limit: 1);
    if (vehicle.isNotEmpty) {
      final rate = (vehicle.first['computed_co2_g_per_meter'] as num?)
          ?.toDouble();
      if (rate != null) {
        map['personal_car'] = rate;
      }
    }
    return map;
  }

  Future<void> _cacheWastePoints(List<WastePointMapItem> points) async {
    if (!_db.isInitialized || points.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final batch = _db.database.batch();
    for (final pt in points) {
      batch.insert('cached_waste_points', {
        'id': pt.id,
        'title': pt.title,
        'address_text': pt.addressText,
        'accepted_fractions_csv': pt.acceptedFractions
            .map((f) => f.wireName)
            .join(','),
        'lat': pt.lat,
        'lon': pt.lon,
        'status': pt.status.wireName,
        'trust_score': pt.trustScore,
        'confirmations_count': pt.confirmationsCount,
        'issues_count': pt.issuesCount,
        'attribution_text': WastePointsBboxResponse.defaultAttributionBannerRu,
        'cached_at_ms': nowMs,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);

    final countRows = await _db.database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM cached_waste_points',
    );
    final total = countRows.isEmpty
        ? 0
        : (countRows.first['cnt'] as num?)?.toInt() ?? 0;
    if (total > _maxCachedWastePoints) {
      final excess = total - _maxCachedWastePoints;
      await _db.database.rawDelete(
        'DELETE FROM cached_waste_points WHERE id IN '
        '(SELECT id FROM cached_waste_points ORDER BY cached_at_ms ASC LIMIT ?)',
        [excess],
      );
    }
  }

  Future<List<WastePointMapItem>> _queryCachedWastePoints({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    required List<WasteFractionCode> fractions,
  }) async {
    if (!_db.isInitialized) return const [];
    final cutoffMs = DateTime.now().millisecondsSinceEpoch - _wastePointsTtlMs;
    final rows = await _db.database.query(
      'cached_waste_points',
      where:
          'lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? AND cached_at_ms >= ?',
      whereArgs: [minLat, maxLat, minLon, maxLon, cutoffMs],
    );
    final filterSet = fractions.toSet();
    final out = <WastePointMapItem>[];
    for (final row in rows) {
      final parsed = WastePointMapItem.fromSqliteRow(row).valueOrNull;
      if (parsed == null) continue;
      if (filterSet.isEmpty ||
          parsed.acceptedFractions.any(filterSet.contains)) {
        out.add(parsed);
      }
    }
    return out;
  }

  Future<void> _upsertSingleWastePoint(WastePointDetail pt) async {
    if (!_db.isInitialized) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final verifiedRaw = pt.lastVerifiedAt;
    final verifiedMs = verifiedRaw != null
        ? DateTime.tryParse(verifiedRaw)?.millisecondsSinceEpoch
        : null;
    await _db.database.insert('cached_waste_points', {
      'id': pt.id,
      'title': pt.title,
      'address_text': pt.addressText,
      'operator_name': pt.operatorName,
      'opening_hours': pt.openingHours,
      'accepted_fractions_csv': pt.acceptedFractions
          .map((f) => f.wireName)
          .join(','),
      'lat': pt.lat,
      'lon': pt.lon,
      'status': pt.status.wireName,
      'trust_score': pt.trustScore,
      'confirmations_count': pt.confirmationsCount,
      'issues_count': pt.issuesCount,
      'attribution_text': pt.attributionText,
      'last_verified_at_ms': verifiedMs,
      'cached_at_ms': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<WastePointDetail?> _readCachedWastePointDetail(String pointId) async {
    if (!_db.isInitialized) return null;
    final rows = await _db.database.query(
      'cached_waste_points',
      where: 'id = ?',
      whereArgs: [pointId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WastePointDetail.fromSqliteRow(rows.first).valueOrNull;
  }

  Future<void> _applyReportTrustUpdate(
    String pointId,
    WastePointReportCreatedResponse response,
  ) async {
    if (!_db.isInitialized) return;
    await _db.database.update(
      'cached_waste_points',
      {
        'trust_score': response.updatedTrustScore,
        'status': response.updatedStatus.wireName,
        'cached_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [pointId],
    );
  }

  Future<double> _distanceToCachedPoint(
    String pointId,
    double userLat,
    double userLon,
  ) async {
    final cached = await _readCachedWastePointDetail(pointId);
    if (cached == null) return 0.0;
    return _distance.as(
      LengthUnit.Meter,
      LatLng(userLat, userLon),
      LatLng(cached.lat, cached.lon),
    );
  }

  void _emitSummary(DailyActivitySummary summary) {
    if (!_summaryController.isClosed) {
      _summaryController.add(summary);
    }
  }

  bool _isDateEditable(String activityDate) {
    final now = DateTime.now();
    final today = _formatDate(now);
    final yesterday = _formatDate(now.subtract(const Duration(days: 1)));
    return activityDate == today || activityDate == yesterday;
  }

  static String _todayLocalIso() => _formatDate(DateTime.now());

  static String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isOfflineError(AppError error) =>
      error.clientAction == ClientErrorAction.queueRetry ||
      error.httpStatus == 0 ||
      error.httpStatus == 503;

  bool _isOfflineOrNotFound(AppError error) =>
      _isOfflineError(error) || error.httpStatus == 404;

  T _parseOrThrow<T>(
    Object? data,
    Result<T, AppError> Function(Map<String, Object?>) parser,
  ) {
    if (data is Map<String, Object?>) {
      return switch (parser(data)) {
        Ok(:final value) => value,
        Err(:final error) => throw error,
      };
    }
    throw AppError.fromCode('VALIDATION_ERROR');
  }
}
