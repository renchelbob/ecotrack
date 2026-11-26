import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

/// A snapshot of one row in offline_mutation_outbox. The DAO derives
/// activityDate from the endpoint/body; it is not an extra SQLite column.
final class const OutboxMutation({
  required final int id,
  required final String operation,
  required final String method,
  required final String path,
  required final String payloadJson,
  required final String idempotencyKey,
  required final int retryCount,
  required final int nextRetryAtMs,
  final String? activityDate,
  final int maxRetries = 12,
  final String status = 'pending',
}) {
  bool get isSteps => operation == 'sync_daily_steps';
  bool get isGps => operation == 'upload_gps_track_batch';
  bool get isAllocation =>
      operation == 'upsert_segment_allocation' ||
      operation == 'delete_segment_allocation';
}

final class const OutboxResponse(
  final int statusCode, {
  final String? errorCode,
  final bool retryable = false,
  final Duration? retryAfter,
  final Object? body,
});

enum OutboxDependencyStatus() {
  ready,
  waiting,
  failed,
}

/// Implementations back these operations with the canonical SQLite schema.
/// ack/fail must reconcile the local entity and change the queue atomically.

abstract interface class OutboxStore() {
  /// Restore interrupted rows without replacing their key or payload.
  Future<void> recoverInFlight();
  Future<List<OutboxMutation>> loadActive();

  /// Determines causal readiness from durable state. For GPS this checks
  /// last_synced_at_ms, since a deleted queue row cannot prove a step sync.
  /// For allocation writes it also checks the relevant local GPS point sync
  /// statuses. A permanently failed predecessor without a replacement fails
  /// the dependent row. An absent initial sync keeps it waiting.
  Future<OutboxDependencyStatus> activityDependencies(OutboxMutation mutation);

  /// Claim only if the stored row still matches this snapshot (including
  /// idempotency key), so producer coalescing cannot race the sender.
  /// Recheck causal readiness in the same SQLite transaction as the claim.
  /// Only ready rows or rows with definitively failed dependencies are claimable.
  Future<bool> claim(OutboxMutation expected);
  Future<void> ack(OutboxMutation mutation, OutboxResponse response);
  Future<void> retry(
    OutboxMutation mutation, {
    required int count,
    required int nextRetryAtMs,
    required String error,
  });
  Future<void> fail(OutboxMutation mutation, String error);
  Future<void> wipeUserData();
}

/// Domain reconciliation runs in the same SQLite transaction as the queue update.
typedef OutboxReconcile = Future<void> Function(
  Transaction tx,
  OutboxMutation mutation,
  OutboxResponse? response,
  String? error,
);

final class SqliteOutboxStore(
  final Database database, {
  required final OutboxReconcile reconcile,
  required final Future<void> Function() wipe,
}) implements OutboxStore {
  static const _queue = 'offline_mutation_outbox';

  @override
  Future<void> recoverInFlight() async {
    await database.update(_queue, {
      'status': 'pending',
      'last_error': 'DISPATCH_INTERRUPTED',
    }, where: "status = 'in_flight'");
  }

  @override
  Future<List<OutboxMutation>> loadActive() => _active(database);

  static Future<List<OutboxMutation>> _active(DatabaseExecutor executor) async {
    final rows = await executor.query(
      _queue,
      where: "status IN ('pending', 'in_flight')",
      orderBy: 'outbox_id',
    );
    return rows.map(_mutation).toList(growable: false);
  }

  static T _required<T>(Map<String, Object?> fields, String key) {
    final value = fields[key];
    if (value is! T) throw StateError('Invalid outbox field: $key');
    return value;
  }

  static OutboxMutation _mutation(Map<String, Object?> row) {
    final path = _required<String>(row, 'endpoint_path');
    final payload = _required<String>(row, 'payload_json');
    final raw = jsonDecode(payload);
    final date = raw is Map<String, Object?> ? raw['activity_date'] : null;
    final pathDate = RegExp(r'/daily/(\d{4}-\d{2}-\d{2})(?:/|$)')
        .firstMatch(path)
        ?.group(1);
    return OutboxMutation(
      id: _required<int>(row, 'outbox_id'),
      operation: _required<String>(row, 'operation_type'),
      method: _required<String>(row, 'http_method'),
      path: path,
      payloadJson: payload,
      idempotencyKey: _required<String>(row, 'idempotency_key'),
      retryCount: _required<int>(row, 'retry_count'),
      nextRetryAtMs: _required<int>(row, 'next_retry_at_ms'),
      maxRetries: _required<int>(row, 'max_retries'),
      status: _required<String>(row, 'status'),
      activityDate: date is String ? date : pathDate,
    );
  }

  @override
  Future<OutboxDependencyStatus> activityDependencies(
    OutboxMutation mutation,
  ) => _dependencies(database, mutation);

  static Future<OutboxDependencyStatus> _dependencies(
    DatabaseExecutor executor,
    OutboxMutation mutation,
  ) async {
    final date = mutation.activityDate;
    if (date == null || (!mutation.isGps && !mutation.isAllocation)) {
      return OutboxDependencyStatus.ready;
    }
    final rows = await executor.query(
      'local_daily_step_summaries',
      columns: ['last_synced_at_ms', 'sync_status'],
      where: 'activity_date = ?',
      whereArgs: [date],
    );
    if (rows.isEmpty || rows.single['last_synced_at_ms'] == null) {
      return rows.isNotEmpty && rows.single['sync_status'] == 'failed'
          ? OutboxDependencyStatus.failed
          : OutboxDependencyStatus.waiting;
    }
    final body = jsonDecode(mutation.payloadJson);
    if (mutation.isGps && body is Map<String, Object?>) {
      final points = body['points'];
      if (points case [final Map<String, Object?> first, ...]) {
        if (first['seq_no'] case final int seq when seq > 0) {
          return await _gpsRange(executor, date, seq - 1, seq - 1);
        }
      }
    } else if (mutation.operation == 'upsert_segment_allocation' &&
        body is Map<String, Object?> &&
        body['allocations'] is List<Object?>) {
      for (final item in _required<List<Object?>>(body, 'allocations')) {
        if (item case {
          'start_seq_no': final int start,
          'end_seq_no': final int end,
        }) {
          final status = await _gpsRange(executor, date, start, end);
          if (status != OutboxDependencyStatus.ready) return status;
        }
      }
    }
    return OutboxDependencyStatus.ready;
  }

  static Future<OutboxDependencyStatus> _gpsRange(
    DatabaseExecutor executor,
    String date,
    int start,
    int end,
  ) async {
    final rows = await executor.query(
      'local_gps_track_points',
      columns: ['sync_status'],
      where: 'activity_date = ? AND seq_no BETWEEN ? AND ?',
      whereArgs: [date, start, end],
    );
    if (rows.any((row) => row['sync_status'] == 'failed')) {
      return OutboxDependencyStatus.failed;
    }
    if (rows.length != end - start + 1 ||
        rows.any((row) => row['sync_status'] != 'synced')) {
      return OutboxDependencyStatus.waiting;
    }
    return OutboxDependencyStatus.ready;
  }

  /// Called by producers inside their SQLite transaction. The supplied key must
  /// be new. Coalescing preserves FIFO position and only touches unsent rows.
  Future<int> enqueue(Transaction tx, OutboxMutation mutation) async {
    if (mutation.isSteps || mutation.operation == 'upsert_segment_allocation') {
      final rows = await tx.query(
        _queue,
        where:
            "operation_type = ? AND endpoint_path = ? AND status = 'pending' "
            'AND retry_count = 0 AND last_error IS NULL',
        whereArgs: [mutation.operation, mutation.path],
        orderBy: 'outbox_id DESC',
      );
      for (final row in rows) {
        final previous = _mutation(row);
        if (previous.activityDate != mutation.activityDate) continue;
        if (mutation.isAllocation &&
            (await _active(tx)).any(
              (row) =>
                  row.isAllocation &&
                  row.activityDate == mutation.activityDate &&
                  row.id > previous.id,
            )) {
          break;
        }
        var payload = mutation.payloadJson;
        if (mutation.isSteps) {
          final oldBody =
              jsonDecode(previous.payloadJson) as Map<String, Object?>;
          final newBody = jsonDecode(payload) as Map<String, Object?>;
          if ((_required<int>(oldBody, 'raw_sensor_steps')) >
              (_required<int>(newBody, 'raw_sensor_steps'))) {
            payload = previous.payloadJson;
          }
        }
        await tx.update(
          _queue,
          {
            'idempotency_key': mutation.idempotencyKey,
            'payload_json': payload,
            'next_retry_at_ms': mutation.nextRetryAtMs,
          },
          where: 'outbox_id = ?',
          whereArgs: [previous.id],
        );
        return previous.id;
      }
    }
    return await tx.insert(_queue, {
      'idempotency_key': mutation.idempotencyKey,
      'operation_type': mutation.operation,
      'http_method': mutation.method,
      'endpoint_path': mutation.path,
      'payload_json': mutation.payloadJson,
      'next_retry_at_ms': mutation.nextRetryAtMs,
      'max_retries': mutation.maxRetries,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<bool> claim(OutboxMutation expected) => database.transaction((
    tx,
  ) async {
    if ((expected.isGps || expected.isAllocation) &&
        (_hasPredecessor(expected, await _active(tx)) ||
            await _dependencies(tx, expected) ==
                OutboxDependencyStatus.waiting)) {
      return false;
    }
    final updated = await tx.update(
      _queue,
      {'status': 'in_flight', 'last_error': 'DISPATCH_STARTED'},
      where:
          "outbox_id = ? AND status = 'pending' AND idempotency_key = ? "
          'AND payload_json = ? AND retry_count = ? AND next_retry_at_ms = ?',
      whereArgs: [
        expected.id,
        expected.idempotencyKey,
        expected.payloadJson,
        expected.retryCount,
        expected.nextRetryAtMs,
      ],
    );
    return updated == 1;
  });

  @override
  Future<void> ack(OutboxMutation mutation, OutboxResponse response) =>
      database.transaction((tx) async {
        final deleted = await tx.delete(
          _queue,
          where: _claimed,
          whereArgs: _identity(mutation),
        );
        if (deleted == 1) {
          await _recordActivityResult(tx, mutation, succeeded: true);
          await reconcile(tx, mutation, response, null);
        }
      });

  @override
  Future<void> retry(
    OutboxMutation mutation, {
    required int count,
    required int nextRetryAtMs,
    required String error,
  }) async {
    await database.update(
      _queue,
      {
        'status': 'pending',
        'retry_count': count,
        'next_retry_at_ms': nextRetryAtMs,
        'last_error': error,
      },
      where: _claimed,
      whereArgs: _identity(mutation),
    );
  }

  @override
  Future<void> fail(OutboxMutation mutation, String error) =>
      database.transaction((tx) async {
        final updated = await tx.update(
          _queue,
          {'status': 'failed_permanent', 'last_error': error},
          where: _claimed,
          whereArgs: _identity(mutation),
        );
        if (updated == 1) {
          await _recordActivityResult(tx, mutation, succeeded: false);
          await reconcile(tx, mutation, null, error);
        }
      });

  static Future<void> _recordActivityResult(
    Transaction tx,
    OutboxMutation mutation, {
    required bool succeeded,
  }) async {
    final date = mutation.activityDate;
    if (date == null) return;
    final status = succeeded ? 'synced' : 'failed';
    if (mutation.isSteps) {
      final hasNewer = (await _active(tx)).any(
        (row) =>
            row.isSteps && row.activityDate == date && row.id != mutation.id,
      );
      await tx.update(
        'local_daily_step_summaries',
        {
          'sync_status': hasNewer ? 'pending' : status,
          if (succeeded)
            'last_synced_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'activity_date = ?',
        whereArgs: [date],
      );
    } else if (mutation.isGps) {
      final body = jsonDecode(mutation.payloadJson);
      if (body case {'points': final List<Object?> points}) {
        final batch = tx.batch();
        for (final point in points) {
          if (point case {'seq_no': final int sequence}) {
            batch.update(
              'local_gps_track_points',
              {'sync_status': status},
              where: 'activity_date = ? AND seq_no = ?',
              whereArgs: [date, sequence],
            );
          }
        }
        await batch.commit(noResult: true);
      }
    }
  }

  static const _claimed =
      "outbox_id = ? AND idempotency_key = ? AND status = 'in_flight'";

  static List<Object?> _identity(OutboxMutation mutation) => [
    mutation.id,
    mutation.idempotencyKey,
  ];

  @override
  Future<void> wipeUserData() => wipe();
}

/// Transport attaches the row's Idempotency-Key and performs token refresh.
/// It returns catalog errors as OutboxResponse and wraps connectivity errors
/// in OutboxNetworkException; malformed successful responses are errors.
typedef OutboxSender = Future<OutboxResponse> Function(OutboxMutation mutation);

final class const OutboxNetworkException() implements Exception;

/// One dispatcher per user database. Enqueue and coalescing happen in the
/// producer's transaction before wake() is called. Once first attempted, a row
/// must retain its payload/key even if it goes back to pending after a timeout.
final class OutboxDispatcher({
  required final OutboxStore _store,
  required final OutboxSender _send,
  required final void Function(String code) _onBlocked,
  required final void Function(Object error, StackTrace stack) _onError,
  int Function()? nowMs,
  Random? random,
}) {
  final int Function() _nowMs = nowMs ?? _systemTime;
  final Random _random = random ?? Random();
  Timer? _timer;
  Future<void>? _running;
  bool _online = false;
  bool _paused = false;
  bool _closed = false;
  bool _started = false;
  bool _wakeRequested = false;

  static int _systemTime() => DateTime.now().millisecondsSinceEpoch;

  Future<void> start({required bool online}) async {
    if (_started || _closed) return;
    _started = true;
    _online = online;
    final recovery = Future<void>.sync(_store.recoverInFlight);
    _running = recovery;
    try {
      await recovery;
    } catch (_) {
      _started = false;
      rethrow;
    } finally {
      _running = null;
    }
    wake();
  }

  void setOnline(bool online) {
    _online = online;
    if (online) {
      wake();
    } else {
      _timer?.cancel();
    }
  }

  void resume() {
    _paused = false;
    wake();
  }

  void wake() {
    if (!_started || !_online || _paused || _closed) return;
    _timer?.cancel();
    _wakeRequested = true;
    if (_running != null) return;
    _running = Future<void>.microtask(_run);
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _running;
  }

  Future<void> _run() async {
    try {
      do {
        _wakeRequested = false;
        await _drain();
      } while (_wakeRequested && _online && !_paused && !_closed);
    } catch (error, stack) {
      _paused = true;
      _onError(error, stack);
    } finally {
      _running = null;
    }
  }

  Future<void> _drain() async {
    while (_online && !_paused && !_closed) {
      final rows = List<OutboxMutation>.of(await _store.loadActive())
        ..sort((a, b) => a.id.compareTo(b.id));
      if (!_online || _paused || _closed) return;
      final now = _nowMs();
      OutboxMutation? next;
      int? wakeAt;
      for (final row in rows) {
        if (row.status != 'pending' || _hasPredecessor(row, rows)) continue;
        final dependency = row.isGps || row.isAllocation
            ? await _store.activityDependencies(row)
            : OutboxDependencyStatus.ready;
        if (dependency == OutboxDependencyStatus.waiting) continue;
        if (row.nextRetryAtMs <= now) {
          next = row;
          break;
        }
        wakeAt = min(wakeAt ?? row.nextRetryAtMs, row.nextRetryAtMs);
      }
      if (next == null) {
        if (wakeAt != null) {
          _timer?.cancel();
          _timer = Timer(
            Duration(milliseconds: max(0, wakeAt - _nowMs())),
            wake,
          );
        }
        return;
      }
      if (!await _store.claim(next)) continue;
      if (!_online || _paused || _closed) {
        await _store.retry(
          next,
          count: next.retryCount,
          nextRetryAtMs: now,
          error: 'DISPATCH_PAUSED',
        );
        return;
      }
      final dependency = next.isGps || next.isAllocation
          ? await _store.activityDependencies(next)
          : OutboxDependencyStatus.ready;
      if (dependency == OutboxDependencyStatus.waiting) {
        await _store.retry(
          next,
          count: next.retryCount,
          nextRetryAtMs: now,
          error: 'ACTIVITY_DEPENDENCY_WAITING',
        );
        continue;
      }
      if (dependency == OutboxDependencyStatus.failed) {
        await _store.fail(next, 'ACTIVITY_DEPENDENCY_FAILED');
      } else {
        await _dispatch(next);
      }
    }
  }

  Future<void> _dispatch(OutboxMutation row) async {
    if (row.operation == 'create_shop_order') {
      await _store.fail(row, 'SHOP_CHECKOUT_REQUIRES_ONLINE');
      return;
    }
    OutboxResponse response;
    try {
      response = await _send(row);
    } on OutboxNetworkException {
      await _scheduleRetry(row, 'DATABASE_UNAVAILABLE');
      return;
    } on TimeoutException {
      await _scheduleRetry(row, 'DATABASE_UNAVAILABLE');
      return;
    }
    final code = response.errorCode ?? 'HTTP_${response.statusCode}';
    if (const {200, 201, 204}.contains(response.statusCode)) {
      await _store.ack(row, response);
    } else if (response.statusCode == 401 &&
        code == 'REFRESH_TOKEN_EXPIRED_OR_REVOKED') {
      _paused = true;
      await _store.wipeUserData();
      _onBlocked(code);
    } else if (code == 'AUTH_TOKEN_EXPIRED' ||
        code == 'FZ152_CONSENT_REVOKED' ||
        code == 'GOOGLE_FORMAL_PHONE_REQUIRED') {
      _paused = true;
      await _store.retry(
        row,
        count: row.retryCount,
        nextRetryAtMs: _nowMs(),
        error: code,
      );
      _onBlocked(code);
    } else if (response.statusCode == 429) {
      if (row.operation == 'send_friend_wakeup_nudge') {
        await _store.fail(row, code);
      } else {
        await _scheduleRetry(
          row,
          code,
          response.retryAfter ?? const Duration(seconds: 30),
        );
      }
    } else if (response.retryable ||
        response.statusCode >= 500 ||
        code == 'IDEMPOTENCY_IN_FLIGHT') {
      await _scheduleRetry(row, code);
    } else {
      await _store.fail(row, code);
    }
  }

  Future<void> _scheduleRetry(
    OutboxMutation row,
    String code, [
    Duration? retryAfter,
  ]) async {
    final count = row.retryCount + 1;
    if (count >= row.maxRetries) {
      await _store.fail(row, 'MAX_RETRIES_EXHAUSTED');
      return;
    }
    final delay = retryAfter == null
        ? min(300000, 1000 * (1 << min(count, 8))) + _random.nextInt(1501)
        : max(0, retryAfter.inMilliseconds);
    await _store.retry(
      row,
      count: count,
      nextRetryAtMs: _nowMs() + delay,
      error: code,
    );
  }
}

bool _hasPredecessor(OutboxMutation row, List<OutboxMutation> rows) {
  if (row.activityDate == null) return false;
  return rows.any((other) {
    if (other.id == row.id ||
        other.activityDate != row.activityDate ||
        other.status == 'failed_permanent') {
      return false;
    }
    if (row.isGps) {
      return other.isSteps || (other.isGps && other.id < row.id);
    }
    return row.isAllocation &&
        (other.isSteps ||
            other.isGps ||
            (other.isAllocation && other.id < row.id));
  });
}
