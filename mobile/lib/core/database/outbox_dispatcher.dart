import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
import 'package:ecotrack_mobile/core/utils/co2_math.dart';
import 'package:ecotrack_mobile/core/utils/uuid_v7.dart';
import 'package:sqflite/sqflite.dart';

sealed class const OutboxSendResponse();

final class const OutboxSendSuccess([final Object? responseData])
    extends OutboxSendResponse;

final class const OutboxSendRetryLater(
  final String code, [
  final int? retryAfterSec,
]) extends OutboxSendResponse;

final class const OutboxSendRequiresGate(final AppError error)
    extends OutboxSendResponse;

final class const OutboxSendPermanentFailure(final AppError error)
    extends OutboxSendResponse;

typedef OutboxMutationSender = Future<OutboxSendResponse> Function(
  OutboxItem item,
);

final class const OutboxItem({
  final int? outboxId,
  required final String idempotencyKey,
  required final String operationType,
  required final String httpMethod,
  required final String endpointPath,
  required final String payloadJson,
  required final int retryCount,
  required final int maxRetries,
  required final int nextRetryAtMs,
  final String? lastError,
  required final String status,
  required final int createdAtMs,
}) {
  factory fromMap(Map<String, Object?> map) => OutboxItem(
    outboxId: (map['outbox_id'] as num?)?.toInt(),
    idempotencyKey: map['idempotency_key'] as String? ?? '',
    operationType: map['operation_type'] as String? ?? '',
    httpMethod: map['http_method'] as String? ?? 'POST',
    endpointPath: map['endpoint_path'] as String? ?? '',
    payloadJson: map['payload_json'] as String? ?? '{}',
    retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
    maxRetries: (map['max_retries'] as num?)?.toInt() ?? 12,
    nextRetryAtMs: (map['next_retry_at_ms'] as num?)?.toInt() ?? 0,
    lastError: map['last_error'] as String?,
    status: map['status'] as String? ?? OutboxDispatcher.statusPending,
    createdAtMs: (map['created_at_ms'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (outboxId != null) 'outbox_id': outboxId,
    'idempotency_key': idempotencyKey,
    'operation_type': operationType,
    'http_method': httpMethod,
    'endpoint_path': endpointPath,
    'payload_json': payloadJson,
    'retry_count': retryCount,
    'max_retries': maxRetries,
    'next_retry_at_ms': nextRetryAtMs,
    'last_error': lastError,
    'status': status,
    'created_at_ms': createdAtMs,
  };

  String? get activityDate => OutboxDispatcher.extractActivityDate(
    payloadJson: payloadJson,
    endpointPath: endpointPath,
  );
}

final class OutboxDispatcher({
  final SqliteDatabase? db,
  final OutboxMutationSender? networkSender,
  final void Function(AppError error)? onPermanentError,
  final void Function(AppError error)? onGateError,
  final void Function()? onForceLogout,
}) {
  static const String tableName = 'offline_mutation_outbox';
  static const String statusPending = 'pending';
  static const String statusInFlight = 'in_flight';
  static const String statusFailedPermanent = 'failed_permanent';
  static const int defaultMaxRetries = 12;

  static const Set<String> _coalescingOps = {
    'sync_daily_steps',
    'upsert_segment_allocation',
  };

  static const Set<String> _allocationBarrierOps = {
    'upsert_segment_allocation',
    'delete_segment_allocation',
  };

  static const Set<String> _allocationPredecessorOps = {
    'sync_daily_steps',
    'upload_gps_track_batch',
  };

  static final math.Random _random = math.Random();

  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();
  Timer? _workerTimer;
  bool _isFlushing = false;
  bool _isPausedForGate = false;
  bool _disposed = false;

  SqliteDatabase get _database => db ?? SqliteDatabase.instance;

  Stream<int> get pendingCountStream => _pendingCountController.stream;

  bool get isPausedForGate => _isPausedForGate;

  static OutboxMutationSender senderFromDioClient(
    DioClient client,
  ) => (item) async {
    final Object? parsedBody = item.payloadJson.trim().isEmpty
        ? null
        : jsonDecode(item.payloadJson);
    final outcome = await client.sendWithOutcome(
      item.httpMethod,
      item.endpointPath,
      data: parsedBody,
      headers: <String, String>{'Idempotency-Key': item.idempotencyKey},
    );
    if (outcome.isSuccess) {
      return OutboxSendSuccess(outcome.data);
    }

    final error = outcome.error ?? AppError.fromCode('INTERNAL_SERVER_ERROR');
    if (outcome.statusCode == 409 && error.code == 'IDEMPOTENCY_IN_FLIGHT') {
      return OutboxSendRetryLater(error.code);
    }

    final retryAfterSec = int.tryParse(outcome.retryAfterHeader?.trim() ?? '');
    if (outcome.statusCode == 429 && error.retryable) {
      return OutboxSendRetryLater(error.code, retryAfterSec ?? 30);
    }

    if (error.clientAction == ClientErrorAction.openPhoneModal ||
        error.clientAction == ClientErrorAction.openConsentScreen ||
        error.clientAction == ClientErrorAction.forceLogout) {
      return OutboxSendRequiresGate(error);
    }

    if (error.retryable) {
      return OutboxSendRetryLater(error.code, retryAfterSec);
    }

    return OutboxSendPermanentFailure(error);
  };

  static int calcBackoffWithJitterMs(
    int nextRetryCount, {
    math.Random? random,
  }) {
    final exponent = math.min(math.max(nextRetryCount, 1), 8);
    final baseDelayMs = math.min(300000, 1000 * (1 << exponent));
    final jitterMs = (random ?? _random).nextInt(1501);
    return baseDelayMs + jitterMs;
  }

  static String? extractActivityDate({
    required String payloadJson,
    required String endpointPath,
  }) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map<Object?, Object?>) {
        final date = decoded['activity_date'];
        if (date is String && date.isNotEmpty) {
          return date;
        }
      }
    } on FormatException {
      // Fall back to endpoint path date extraction below.
    }
    final segments = Uri.tryParse(endpointPath)?.pathSegments ?? const [];
    if (segments.length >= 5 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'activity' &&
        segments[3] == 'daily') {
      final candidate = segments[4];
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  void startWorker({Duration interval = const Duration(seconds: 15)}) {
    if (_disposed) {
      return;
    }
    _workerTimer?.cancel();
    _workerTimer = Timer.periodic(interval, (_) => unawaited(flush()));
  }

  void stopWorker() {
    _workerTimer?.cancel();
    _workerTimer = null;
  }

  void pauseForGate() {
    _isPausedForGate = true;
  }

  void resumeQueue({bool autoFlush = true}) {
    _isPausedForGate = false;
    if (autoFlush) {
      unawaited(flush());
    }
  }

  Future<int> countPending() async {
    final rows = await _database.database.rawQuery(
      "SELECT COUNT(*) AS cnt FROM $tableName WHERE status IN ('$statusPending', '$statusInFlight')",
    );
    return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<List<OutboxItem>> getPendingItems() async {
    final rows = await _database.database.query(
      tableName,
      where: 'status IN (?, ?)',
      whereArgs: const [statusPending, statusInFlight],
      orderBy: 'outbox_id ASC',
    );
    return rows.map(OutboxItem.fromMap).toList();
  }

  Future<String> enqueue({
    required String operationType,
    required String httpMethod,
    required String endpointPath,
    required String payloadJson,
    String? idempotencyKey,
  }) async {
    if (operationType == 'create_shop_order') {
      throw ArgumentError.value(
        operationType,
        'operationType',
        'Shop checkout must execute online-direct, never in offline outbox',
      );
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final key = idempotencyKey ?? UuidV7.generate();
    final activityDate = extractActivityDate(
      payloadJson: payloadJson,
      endpointPath: endpointPath,
    );

    final resultKey = await _database.database.transaction((txn) async {
      if (_coalescingOps.contains(operationType) && activityDate != null) {
        final existing = await _findCoalesceTarget(
          txn: txn,
          operationType: operationType,
          activityDate: activityDate,
        );
        if (existing != null) {
          final mergedPayload = _mergeCoalescedPayload(
            operationType: operationType,
            existingPayloadJson: existing.payloadJson,
            incomingPayloadJson: payloadJson,
          );
          await txn.update(
            tableName,
            <String, Object?>{
              'idempotency_key': key,
              'http_method': httpMethod.toUpperCase(),
              'endpoint_path': endpointPath,
              'payload_json': mergedPayload,
              'next_retry_at_ms': nowMs,
            },
            where: 'outbox_id = ?',
            whereArgs: [existing.outboxId],
          );
          return key;
        }
      }

      await txn.insert(tableName, <String, Object?>{
        'idempotency_key': key,
        'operation_type': operationType,
        'http_method': httpMethod.toUpperCase(),
        'endpoint_path': endpointPath,
        'payload_json': payloadJson,
        'retry_count': 0,
        'max_retries': defaultMaxRetries,
        'next_retry_at_ms': nowMs,
        'last_error': null,
        'status': statusPending,
        'created_at_ms': nowMs,
      });
      return key;
    });

    await _emitPendingCount();
    return resultKey;
  }

  Future<void> flush({int? nowMsOverride}) async {
    final sender = networkSender;
    if (_disposed || _isFlushing || _isPausedForGate || sender == null) {
      return;
    }

    _isFlushing = true;
    try {
      final nowMs = nowMsOverride ?? DateTime.now().millisecondsSinceEpoch;
      final activeRows = await _database.database.query(
        tableName,
        where: 'status IN (?, ?)',
        whereArgs: const [statusPending, statusInFlight],
        orderBy: 'outbox_id ASC',
      );
      final activeItems = activeRows.map(OutboxItem.fromMap).toList();

      for (final item in activeItems) {
        if (_disposed || _isPausedForGate) {
          break;
        }
        if (item.status != statusPending || item.nextRetryAtMs > nowMs) {
          continue;
        }
        if (await _isBlockedByCausalBarrier(item)) {
          continue;
        }

        final itemId = item.outboxId;
        if (itemId == null) {
          continue;
        }

        await _database.database.update(
          tableName,
          <String, Object?>{'status': statusInFlight},
          where: 'outbox_id = ?',
          whereArgs: [itemId],
        );

        OutboxSendResponse response;
        try {
          response = await sender(item);
        } on Object catch (_) {
          response = const OutboxSendRetryLater('DATABASE_UNAVAILABLE');
        }

        await _applySendOutcome(
          item: item,
          response: response,
          nowMsOverride: nowMs,
        );
        await _emitPendingCount();
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<OutboxItem?> _findCoalesceTarget({
    required DatabaseExecutor txn,
    required String operationType,
    required String activityDate,
  }) async {
    final candidates = await txn.query(
      tableName,
      where: 'operation_type = ? AND status = ?',
      whereArgs: [operationType, statusPending],
      orderBy: 'outbox_id DESC',
    );
    for (final row in candidates) {
      final item = OutboxItem.fromMap(row);
      if (item.activityDate == activityDate) {
        return item;
      }
    }
    return null;
  }

  static String _mergeCoalescedPayload({
    required String operationType,
    required String existingPayloadJson,
    required String incomingPayloadJson,
  }) {
    if (operationType != 'sync_daily_steps') {
      return incomingPayloadJson;
    }
    try {
      final oldMap = jsonDecode(existingPayloadJson);
      final newMap = jsonDecode(incomingPayloadJson);
      if (oldMap is Map<Object?, Object?> && newMap is Map<Object?, Object?>) {
        final merged = <String, Object?>{};
        for (final entry in newMap.entries) {
          if (entry.key case final String key) {
            merged[key] = entry.value;
          }
        }
        final oldSteps = (oldMap['raw_sensor_steps'] as num?)?.toInt() ?? 0;
        final newSteps = (newMap['raw_sensor_steps'] as num?)?.toInt() ?? 0;
        merged['raw_sensor_steps'] = math.max(oldSteps, newSteps);
        return jsonEncode(merged);
      }
    } on FormatException {
      return incomingPayloadJson;
    }
    return incomingPayloadJson;
  }

  Future<bool> _isBlockedByCausalBarrier(OutboxItem item) async {
    final date = item.activityDate;
    if (date == null) {
      return false;
    }

    final activeSameDate = await _database.database.query(
      tableName,
      where: 'status IN (?, ?) AND outbox_id != ?',
      whereArgs: [statusPending, statusInFlight, item.outboxId ?? -1],
    );

    for (final row in activeSameDate) {
      final other = OutboxItem.fromMap(row);
      if (other.activityDate != date) {
        continue;
      }
      if (item.operationType == 'upload_gps_track_batch' &&
          other.operationType == 'sync_daily_steps') {
        return true;
      }
      if (_allocationBarrierOps.contains(item.operationType) &&
          _allocationPredecessorOps.contains(other.operationType)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _applySendOutcome({
    required OutboxItem item,
    required OutboxSendResponse response,
    int? nowMsOverride,
  }) async {
    final itemId = item.outboxId;
    if (itemId == null) {
      return;
    }
    final nowMs = nowMsOverride ?? DateTime.now().millisecondsSinceEpoch;

    switch (response) {
      case OutboxSendSuccess(:final responseData):
        await _database.database.transaction((txn) async {
          await _reconcileSuccessTxn(
            txn: txn,
            item: item,
            responseData: responseData,
            nowMs: nowMs,
          );
          await txn.delete(
            tableName,
            where: 'outbox_id = ?',
            whereArgs: [itemId],
          );
        });
      case OutboxSendRetryLater(:final code, :final retryAfterSec):
        final nextRetry = item.retryCount + 1;
        if (nextRetry >= item.maxRetries) {
          await _database.database.transaction((txn) async {
            await txn.update(
              tableName,
              <String, Object?>{
                'status': statusFailedPermanent,
                'retry_count': nextRetry,
                'last_error': 'MAX_RETRIES_EXHAUSTED',
              },
              where: 'outbox_id = ?',
              whereArgs: [itemId],
            );
            await _reconcileFailureTxn(
              txn: txn,
              item: item,
              nowMs: nowMs,
              rollbackAllocations: false,
            );
          });
          onPermanentError?.call(AppError.fromCode(code));
          return;
        }
        final delayMs = retryAfterSec != null
            ? retryAfterSec * 1000
            : calcBackoffWithJitterMs(nextRetry);
        await _database.database.update(
          tableName,
          <String, Object?>{
            'status': statusPending,
            'retry_count': nextRetry,
            'next_retry_at_ms': nowMs + delayMs,
            'last_error': code,
          },
          where: 'outbox_id = ?',
          whereArgs: [itemId],
        );
      case OutboxSendRequiresGate(:final error):
        await _database.database.update(
          tableName,
          <String, Object?>{'status': statusPending, 'last_error': error.code},
          where: 'outbox_id = ?',
          whereArgs: [itemId],
        );
        if (error.clientAction == ClientErrorAction.forceLogout) {
          stopWorker();
          onForceLogout?.call();
        } else {
          _isPausedForGate = true;
          onGateError?.call(error);
        }
      case OutboxSendPermanentFailure(:final error):
        await _database.database.transaction((txn) async {
          await txn.update(
            tableName,
            <String, Object?>{
              'status': statusFailedPermanent,
              'last_error': error.code,
            },
            where: 'outbox_id = ?',
            whereArgs: [itemId],
          );
          await _reconcileFailureTxn(
            txn: txn,
            item: item,
            nowMs: nowMs,
            rollbackAllocations: true,
          );
        });
        onPermanentError?.call(error);
    }
  }

  Future<void> _reconcileSuccessTxn({
    required Transaction txn,
    required OutboxItem item,
    required Object? responseData,
    required int nowMs,
  }) async {
    final responseMap = _asStringKeyMap(responseData);
    final summaryMap = _asStringKeyMap(responseMap?['summary']);
    final payloadMap = _decodeJsonMap(item.payloadJson);
    final activityDate =
        item.activityDate ??
        _extractDateFromMap(summaryMap) ??
        _extractDateFromMap(responseMap);

    if (_isDailyStepsOp(item)) {
      await _reconcileStepsSuccess(
        txn: txn,
        activityDate: activityDate,
        summarySource: summaryMap ?? responseMap,
        nowMs: nowMs,
      );
    } else if (_isGpsBatchOp(item)) {
      await _updateGpsPointsSyncStatus(
        txn: txn,
        activityDate: activityDate,
        payloadMap: payloadMap,
        syncStatus: 'synced',
      );
    } else if (_isAllocationsOp(item)) {
      await _reconcileAllocationsSuccess(
        txn: txn,
        activityDate: activityDate,
        summaryMap: summaryMap,
        nowMs: nowMs,
      );
    } else if (_isWasteReportOp(item)) {
      await _updateWasteReportSyncStatus(
        txn: txn,
        item: item,
        syncStatus: 'synced',
      );
    } else if (_isVehicleOp(item) && item.httpMethod != 'DELETE') {
      await _reconcileVehicleSuccess(
        txn: txn,
        responseMap: responseMap,
        nowMs: nowMs,
      );
    }

    await _reconcileProfileFromResponse(
      txn: txn,
      responseMap: responseMap,
      summaryMap: summaryMap,
      nowMs: nowMs,
    );
  }

  Future<void> _reconcileFailureTxn({
    required Transaction txn,
    required OutboxItem item,
    required int nowMs,
    required bool rollbackAllocations,
  }) async {
    final payloadMap = _decodeJsonMap(item.payloadJson);
    final activityDate = item.activityDate;

    if (_isDailyStepsOp(item)) {
      if (activityDate != null) {
        await txn.update(
          'local_daily_step_summaries',
          const <String, Object?>{'sync_status': 'failed'},
          where: 'activity_date = ?',
          whereArgs: [activityDate],
        );
      }
    } else if (_isGpsBatchOp(item)) {
      await _updateGpsPointsSyncStatus(
        txn: txn,
        activityDate: activityDate,
        payloadMap: payloadMap,
        syncStatus: 'failed',
      );
    } else if (_isAllocationsOp(item)) {
      await _reconcileAllocationsFailure(
        txn: txn,
        item: item,
        nowMs: nowMs,
        rollbackAllocations: rollbackAllocations,
      );
    } else if (_isWasteReportOp(item)) {
      await _updateWasteReportSyncStatus(
        txn: txn,
        item: item,
        syncStatus: 'failed',
      );
    }
  }

  Future<void> _reconcileStepsSuccess({
    required Transaction txn,
    required String? activityDate,
    required Map<String, Object?>? summarySource,
    required int nowMs,
  }) async {
    if (activityDate == null) {
      return;
    }
    final updates = <String, Object?>{
      'sync_status': 'synced',
      'last_synced_at_ms': nowMs,
    };
    if (summarySource != null) {
      _putNonNegInt(updates, summarySource, 'raw_sensor_steps');
      _putNonNegInt(updates, summarySource, 'validated_steps');
      _putBoundedInt(updates, summarySource, 'stride_length_cm', 40, 120);
      _putNonNegDouble(updates, summarySource, 'total_step_distance_m');
      _putNonNegDouble(updates, summarySource, 'allocated_gps_distance_m');
      _putNonNegDouble(updates, summarySource, 'unallocated_step_distance_m');
      _putNonNegInt(updates, summarySource, 'allocated_co2_saved_grams');
      _putNonNegInt(updates, summarySource, 'auto_default_co2_saved_grams');
      _putNonNegInt(updates, summarySource, 'total_co2_saved_grams');
      _putNonNegInt(updates, summarySource, 'points_awarded_for_day');
      _putBoolInt(updates, summarySource, 'is_auto_calculated');
    }
    await txn.update(
      'local_daily_step_summaries',
      updates,
      where: 'activity_date = ?',
      whereArgs: [activityDate],
    );
  }

  Future<void> _updateGpsPointsSyncStatus({
    required Transaction txn,
    required String? activityDate,
    required Map<String, Object?>? payloadMap,
    required String syncStatus,
  }) async {
    if (activityDate == null) {
      return;
    }
    final seqNos = _extractSeqNos(payloadMap);
    if (seqNos.isEmpty) {
      await txn.update(
        'local_gps_track_points',
        <String, Object?>{'sync_status': syncStatus},
        where: 'activity_date = ? AND sync_status = ?',
        whereArgs: [activityDate, 'pending'],
      );
      return;
    }
    const chunkSize = 400;
    for (var offset = 0; offset < seqNos.length; offset += chunkSize) {
      final end = math.min(offset + chunkSize, seqNos.length);
      final chunk = seqNos.sublist(offset, end);
      final placeholders = List<String>.filled(chunk.length, '?').join(',');
      await txn.rawUpdate(
        'UPDATE local_gps_track_points SET sync_status = ? '
        'WHERE activity_date = ? AND seq_no IN ($placeholders)',
        <Object?>[syncStatus, activityDate, ...chunk],
      );
    }
  }

  Future<void> _reconcileAllocationsSuccess({
    required Transaction txn,
    required String? activityDate,
    required Map<String, Object?>? summaryMap,
    required int nowMs,
  }) async {
    if (activityDate == null) {
      return;
    }
    await txn.update(
      'local_route_segment_allocations',
      <String, Object?>{'sync_status': 'synced', 'updated_at_ms': nowMs},
      where: 'activity_date = ?',
      whereArgs: [activityDate],
    );
    if (summaryMap != null) {
      await _reconcileStepsSuccess(
        txn: txn,
        activityDate: activityDate,
        summarySource: summaryMap,
        nowMs: nowMs,
      );
      return;
    }
    await txn.update(
      'local_daily_step_summaries',
      <String, Object?>{'sync_status': 'synced', 'last_synced_at_ms': nowMs},
      where: 'activity_date = ? AND sync_status = ?',
      whereArgs: [activityDate, 'pending'],
    );
  }

  Future<void> _reconcileAllocationsFailure({
    required Transaction txn,
    required OutboxItem item,
    required int nowMs,
    required bool rollbackAllocations,
  }) async {
    final activityDate = item.activityDate;
    if (activityDate == null) {
      return;
    }
    final payloadMap = _decodeJsonMap(item.payloadJson);
    if (!rollbackAllocations || item.httpMethod == 'DELETE') {
      await txn.update(
        'local_route_segment_allocations',
        <String, Object?>{'sync_status': 'failed', 'updated_at_ms': nowMs},
        where: 'activity_date = ? AND sync_status = ?',
        whereArgs: [activityDate, 'pending'],
      );
      await txn.update(
        'local_daily_step_summaries',
        const <String, Object?>{'sync_status': 'failed'},
        where: 'activity_date = ?',
        whereArgs: [activityDate],
      );
      return;
    }

    final keys = _extractAllocationKeys(payloadMap);
    if (keys.isNotEmpty) {
      final placeholders = List<String>.filled(keys.length, '?').join(',');
      await txn.rawDelete(
        'DELETE FROM local_route_segment_allocations '
        'WHERE idempotency_key IN ($placeholders)',
        keys,
      );
    }
    await txn.delete(
      'local_route_segment_allocations',
      where: 'activity_date = ? AND sync_status = ?',
      whereArgs: [activityDate, 'pending'],
    );
    await _recomputeSummaryAfterAllocationRollback(
      txn: txn,
      activityDate: activityDate,
    );
  }

  Future<void> _recomputeSummaryAfterAllocationRollback({
    required Transaction txn,
    required String activityDate,
  }) async {
    final summaryRows = await txn.query(
      'local_daily_step_summaries',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
      limit: 1,
    );
    if (summaryRows.isEmpty) {
      return;
    }
    final remaining = await txn.query(
      'local_route_segment_allocations',
      where: 'activity_date = ?',
      whereArgs: [activityDate],
    );
    var allocDist = 0.0;
    var allocCo2 = 0;
    for (final row in remaining) {
      allocDist += (row['segment_distance_m'] as num?)?.toDouble() ?? 0.0;
      allocCo2 += (row['co2_saved_grams'] as num?)?.toInt() ?? 0;
    }
    final totalStepDist =
        (summaryRows.first['total_step_distance_m'] as num?)?.toDouble() ?? 0.0;
    final unallocDist = math.max(0.0, totalStepDist - allocDist);
    final autoCo2 = Co2Math.computeAutoDefaultCo2Grams(unallocDist);

    await txn.update(
      'local_daily_step_summaries',
      <String, Object?>{
        'allocated_gps_distance_m': allocDist,
        'unallocated_step_distance_m': unallocDist,
        'allocated_co2_saved_grams': allocCo2,
        'auto_default_co2_saved_grams': autoCo2,
        'total_co2_saved_grams': allocCo2 + autoCo2,
        'is_auto_calculated': remaining.isEmpty ? 1 : 0,
        'sync_status': 'failed',
      },
      where: 'activity_date = ?',
      whereArgs: [activityDate],
    );
  }

  Future<void> _updateWasteReportSyncStatus({
    required Transaction txn,
    required OutboxItem item,
    required String syncStatus,
  }) async {
    final updated = await txn.update(
      'pending_waste_point_reports',
      <String, Object?>{'sync_status': syncStatus},
      where: 'idempotency_key = ?',
      whereArgs: [item.idempotencyKey],
    );
    if (updated > 0) {
      return;
    }
    final wastePointId = _extractWastePointId(item.endpointPath);
    if (wastePointId != null) {
      await txn.update(
        'pending_waste_point_reports',
        <String, Object?>{'sync_status': syncStatus},
        where: 'waste_point_id = ? AND sync_status = ?',
        whereArgs: [wastePointId, 'pending'],
      );
    }
  }

  Future<void> _reconcileVehicleSuccess({
    required Transaction txn,
    required Map<String, Object?>? responseMap,
    required int nowMs,
  }) async {
    final updates = <String, Object?>{'is_dirty': 0, 'updated_at_ms': nowMs};
    if (responseMap != null) {
      _putNonNegDouble(updates, responseMap, 'computed_co2_g_per_km');
      _putNonNegDouble(updates, responseMap, 'computed_co2_g_per_meter');
    }
    await txn.update('local_user_vehicle', updates);
  }

  Future<void> _reconcileProfileFromResponse({
    required Transaction txn,
    required Map<String, Object?>? responseMap,
    required Map<String, Object?>? summaryMap,
    required int nowMs,
  }) async {
    if (responseMap == null && summaryMap == null) {
      return;
    }
    final updates = <String, Object?>{};
    for (final source in [summaryMap, responseMap]) {
      if (source == null) {
        continue;
      }
      _putNonNegInt(updates, source, 'points_balance');
      if (!updates.containsKey('points_balance')) {
        final remaining = (source['remaining_points_balance'] as num?)?.toInt();
        if (remaining != null && remaining >= 0) {
          updates['points_balance'] = remaining;
        }
      }
      _putNonNegInt(updates, source, 'lifetime_points_earned');
      _putNonNegInt(updates, source, 'lifetime_co2_saved_grams');
      _putNonNegInt(updates, source, 'current_streak_days');
      _putNonNegInt(updates, source, 'longest_streak_days');
      _putNonNegInt(updates, source, 'streak_freeze_count');
      _putBoundedInt(updates, source, 'daily_step_goal', 1000, 50000);
      _putBoundedInt(updates, source, 'daily_co2_goal_grams', 100, 20000);
      _putBoundedInt(updates, source, 'stride_length_cm', 40, 120);
      _putBoundedInt(updates, source, 'gps_interval_seconds', 5, 300);
      _putBoolInt(updates, source, 'is_152fz_consent_active');
      _putBoolInt(updates, source, 'requires_formal_phone');
    }
    if (updates.isEmpty) {
      return;
    }
    updates['updated_at_ms'] = nowMs;
    await txn.update('local_user_profile', updates);
  }

  static bool _isDailyStepsOp(OutboxItem item) =>
      item.operationType == 'sync_daily_steps' ||
      item.endpointPath == '/api/v1/activity/steps/daily';

  static bool _isGpsBatchOp(OutboxItem item) =>
      item.operationType == 'upload_gps_track_batch' ||
      item.endpointPath.contains('/activity/tracks/points');

  static bool _isAllocationsOp(OutboxItem item) =>
      item.operationType == 'upsert_segment_allocation' ||
      item.operationType == 'delete_segment_allocation' ||
      item.endpointPath.contains('/allocations');

  static bool _isWasteReportOp(OutboxItem item) =>
      item.operationType == 'submit_waste_point_report' ||
      (item.endpointPath.contains('/waste-points/') &&
          item.endpointPath.endsWith('/reports'));

  static bool _isVehicleOp(OutboxItem item) =>
      item.operationType == 'update_user_vehicle' ||
      item.endpointPath == '/api/v1/users/me/vehicle';

  static Map<String, Object?>? _asStringKeyMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return null;
    }
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key case final String key) {
        result[key] = entry.value;
      }
    }
    return result;
  }

  static Map<String, Object?>? _decodeJsonMap(String rawJson) {
    if (rawJson.trim().isEmpty) {
      return null;
    }
    try {
      return _asStringKeyMap(jsonDecode(rawJson));
    } on FormatException {
      return null;
    }
  }

  static String? _extractDateFromMap(Map<String, Object?>? map) {
    final date = map?['activity_date'];
    return date is String && date.isNotEmpty ? date : null;
  }

  static List<int> _extractSeqNos(Map<String, Object?>? payloadMap) {
    final rawPoints = payloadMap?['points'];
    if (rawPoints is! List<Object?>) {
      return const [];
    }
    final seqNos = <int>[];
    for (final pt in rawPoints) {
      if (pt is Map<Object?, Object?>) {
        final seqNo = (pt['seq_no'] as num?)?.toInt();
        if (seqNo != null) {
          seqNos.add(seqNo);
        }
      }
    }
    return seqNos;
  }

  static List<String> _extractAllocationKeys(Map<String, Object?>? payloadMap) {
    final rawAllocs = payloadMap?['allocations'];
    if (rawAllocs is! List<Object?>) {
      return const [];
    }
    final keys = <String>[];
    for (final alloc in rawAllocs) {
      if (alloc is Map<Object?, Object?>) {
        final key = alloc['idempotency_key'];
        if (key is String && key.isNotEmpty) {
          keys.add(key);
        }
      }
    }
    return keys;
  }

  static String? _extractWastePointId(String endpointPath) {
    final segments = Uri.tryParse(endpointPath)?.pathSegments ?? const [];
    if (segments.length >= 6 &&
        segments[0] == 'api' &&
        segments[1] == 'v1' &&
        segments[2] == 'map' &&
        segments[3] == 'waste-points' &&
        segments[5] == 'reports') {
      return segments[4];
    }
    return null;
  }

  static void _putNonNegInt(
    Map<String, Object?> target,
    Map<String, Object?> source,
    String key,
  ) {
    final val = (source[key] as num?)?.toInt();
    if (val != null && val >= 0) {
      target[key] = val;
    }
  }

  static void _putBoundedInt(
    Map<String, Object?> target,
    Map<String, Object?> source,
    String key,
    int min,
    int max,
  ) {
    final val = (source[key] as num?)?.toInt();
    if (val != null && val >= min && val <= max) {
      target[key] = val;
    }
  }

  static void _putNonNegDouble(
    Map<String, Object?> target,
    Map<String, Object?> source,
    String key,
  ) {
    final val = (source[key] as num?)?.toDouble();
    if (val != null && val.isFinite && val >= 0.0) {
      target[key] = val;
    }
  }

  static void _putBoolInt(
    Map<String, Object?> target,
    Map<String, Object?> source,
    String key,
  ) {
    final raw = source[key];
    if (raw is bool) {
      target[key] = raw ? 1 : 0;
    } else if (raw is num && (raw == 0 || raw == 1)) {
      target[key] = raw.toInt();
    }
  }

  Future<void> _emitPendingCount() async {
    if (_disposed || _pendingCountController.isClosed) {
      return;
    }
    final count = await countPending();
    if (!_disposed && !_pendingCountController.isClosed) {
      _pendingCountController.add(count);
    }
  }

  void dispose() {
    _disposed = true;
    stopWorker();
    if (!_pendingCountController.isClosed) {
      unawaited(_pendingCountController.close());
    }
  }
}
