import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/network/dio_client.dart';
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
      case OutboxSendSuccess():
        await _database.database.delete(
          tableName,
          where: 'outbox_id = ?',
          whereArgs: [itemId],
        );
      case OutboxSendRetryLater(:final code, :final retryAfterSec):
        final nextRetry = item.retryCount + 1;
        if (nextRetry >= item.maxRetries) {
          await _database.database.update(
            tableName,
            <String, Object?>{
              'status': statusFailedPermanent,
              'retry_count': nextRetry,
              'last_error': 'MAX_RETRIES_EXHAUSTED',
            },
            where: 'outbox_id = ?',
            whereArgs: [itemId],
          );
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
        await _database.database.update(
          tableName,
          <String, Object?>{
            'status': statusFailedPermanent,
            'last_error': error.code,
          },
          where: 'outbox_id = ?',
          whereArgs: [itemId],
        );
        onPermanentError?.call(error);
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
