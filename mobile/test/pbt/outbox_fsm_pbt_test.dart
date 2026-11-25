import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:glados/glados.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

enum _FsmOp() {
  enqueueSteps,
  enqueueGpsBatch,
  enqueueSegmentAllocation,
  networkDrop,
  networkRestore,
  http429,
  http200,
}

void main() {
  late String schemaSql;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    schemaSql = File('assets/db/client_sqlite_schema.sql').readAsStringSync();
    final catalogJson = File('assets/errors/error_catalog.json')
        .readAsStringSync();
    ErrorCatalogRegistry.instance.loadFromJsonString(catalogJson);
  });

  Future<Database> openMemoryDb() async {
    await SqliteDatabase.instance.close();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteDatabase.instance.initialize(
      overrideDb: db,
      schemaSqlOverride: schemaSql,
    );
    return db;
  }

  group('Offline Mutation Outbox FSM & Causal Barrier PBT', () {
    Glados(any.intInRange(1, 13)).test(
      'Exponential backoff with jitter stays within spec bounds',
      (retry) {
        final value = OutboxDispatcher.calcBackoffWithJitterMs(retry);
        final exp = retry.clamp(1, 8);
        final expectedBase = (1000 * (1 << exp)).clamp(0, 300000);
        expect(value, greaterThanOrEqualTo(expectedBase));
        expect(value, lessThanOrEqualTo(expectedBase + 1500));
      },
    );

    Glados3(
      any.intInRange(2000, 2030),
      any.intInRange(1, 12),
      any.intInRange(1, 28),
    ).test(
      'Outbox extractActivityDate parses daily endpoint routes & payload',
      (year, month, day) {
        final y = year.toString().padLeft(4, '0');
        final m = month.toString().padLeft(2, '0');
        final d = day.toString().padLeft(2, '0');
        final date = '$y-$m-$d';
        final extractedFromPath = OutboxDispatcher.extractActivityDate(
          payloadJson: '{}',
          endpointPath: '/api/v1/activity/daily/$date/allocations',
        );
        expect(extractedFromPath, equals(date));
        final extractedFromPayload = OutboxDispatcher.extractActivityDate(
          payloadJson: '{"activity_date":"$date"}',
          endpointPath: '/api/v1/activity/steps/daily',
        );
        expect(extractedFromPayload, equals(date));
      },
    );

    test('Per-date causal barrier, coalescing, and idempotency key invariance hold across randomized traces', () async {
      final rng = math.Random(20261124);
      for (var run = 0; run < 25; run++) {
        final length = 3 + rng.nextInt(10);
        final ops = List<_FsmOp>.generate(
          length,
          (_) => _FsmOp.values[rng.nextInt(_FsmOp.values.length)],
        );

        await openMemoryDb();
        var isOnline = true;
        var forceRateLimit = false;
        var stepCounter = 100;
        final seenKeysByOutboxId = <int, String>{};

        final dispatcher = OutboxDispatcher(
          db: SqliteDatabase.instance,
          networkSender: (item) async {
            final outboxId = item.outboxId;
            if (outboxId != null) {
              final prevKey = seenKeysByOutboxId[outboxId];
              if (prevKey != null) {
                expect(item.idempotencyKey, equals(prevKey));
              } else {
                seenKeysByOutboxId[outboxId] = item.idempotencyKey;
              }
            }

            if (item.operationType == 'upsert_segment_allocation') {
              final allRows = await SqliteDatabase.instance.database.query(
                OutboxDispatcher.tableName,
                where: 'status IN (?, ?) AND outbox_id != ?',
                whereArgs: [
                  OutboxDispatcher.statusPending,
                  OutboxDispatcher.statusInFlight,
                  outboxId ?? -1,
                ],
              );
              for (final row in allRows) {
                final other = OutboxItem.fromMap(row);
                if (other.activityDate == item.activityDate) {
                  expect(
                    other.operationType,
                    isNot(equals('sync_daily_steps')),
                    reason:
                        'Allocation bypassed pending sync_daily_steps barrier',
                  );
                  expect(
                    other.operationType,
                    isNot(equals('upload_gps_track_batch')),
                    reason: 'Allocation bypassed pending GPS batch barrier',
                  );
                }
              }
            }

            if (!isOnline) {
              return const OutboxSendRetryLater('DATABASE_UNAVAILABLE');
            }
            if (forceRateLimit) {
              forceRateLimit = false;
              return const OutboxSendRetryLater('RATE_LIMIT_EXCEEDED', 0);
            }
            return const OutboxSendSuccess(<String, Object?>{'ok': true});
          },
        );

        try {
          const activityDate = '2026-11-24';
          var virtualNow = DateTime.now().millisecondsSinceEpoch;
          for (final op in ops) {
            switch (op) {
              case _FsmOp.enqueueSteps:
                stepCounter += 150;
                await dispatcher.enqueue(
                  operationType: 'sync_daily_steps',
                  httpMethod: 'PUT',
                  endpointPath: '/api/v1/activity/steps/daily',
                  payloadJson: jsonEncode(<String, Object?>{
                    'activity_date': activityDate,
                    'timezone_offset_minutes': 180,
                    'raw_sensor_steps': stepCounter,
                  }),
                );
              case _FsmOp.enqueueGpsBatch:
                await dispatcher.enqueue(
                  operationType: 'upload_gps_track_batch',
                  httpMethod: 'POST',
                  endpointPath: '/api/v1/activity/tracks/points:batch',
                  payloadJson: jsonEncode(<String, Object?>{
                    'activity_date': activityDate,
                    'points': const <Object?>[],
                  }),
                );
              case _FsmOp.enqueueSegmentAllocation:
                await dispatcher.enqueue(
                  operationType: 'upsert_segment_allocation',
                  httpMethod: 'PUT',
                  endpointPath:
                      '/api/v1/activity/daily/$activityDate/allocations',
                  payloadJson: jsonEncode(<String, Object?>{
                    'allocations': const <Object?>[],
                  }),
                );
              case _FsmOp.networkDrop:
                isOnline = false;
              case _FsmOp.networkRestore:
                isOnline = true;
              case _FsmOp.http429:
                forceRateLimit = true;
              case _FsmOp.http200:
                isOnline = true;
                forceRateLimit = false;
            }

            virtualNow += 600000;
            await dispatcher.flush(nowMsOverride: virtualNow);

            final pending = await dispatcher.getPendingItems();
            final pendingStepsCount = pending
                .where(
                  (i) =>
                      i.operationType == 'sync_daily_steps' &&
                      i.status == OutboxDispatcher.statusPending,
                )
                .length;
            expect(pendingStepsCount, lessThanOrEqualTo(1));
          }

          isOnline = true;
          forceRateLimit = false;
          for (var pass = 0; pass < 15; pass++) {
            virtualNow += 600000;
            await dispatcher.flush(nowMsOverride: virtualNow);
          }
          final leftover = await dispatcher.getPendingItems();
          expect(
            await dispatcher.countPending(),
            equals(0),
            reason:
                'Run $run leftover: ${leftover.map((e) => '${e.operationType}:${e.status}:r${e.retryCount}:nr=${e.nextRetryAtMs}:v=$virtualNow').toList()}',
          );
        } finally {
          dispatcher.dispose();
          await SqliteDatabase.instance.close();
        }
      }
    });

    test('Retries transition to pending for <12 failures and failed_permanent on 12th', () async {
      await openMemoryDb();
      final permanentErrors = <AppError>[];
      final dispatcher = OutboxDispatcher(
        db: SqliteDatabase.instance,
        networkSender: (_) async =>
            const OutboxSendRetryLater('DATABASE_UNAVAILABLE'),
        onPermanentError: permanentErrors.add,
      );

      try {
        await dispatcher.enqueue(
          operationType: 'update_user_settings',
          httpMethod: 'PATCH',
          endpointPath: '/api/v1/users/me',
          payloadJson: '{"daily_step_goal":9000}',
        );

        var futureNow = DateTime.now().millisecondsSinceEpoch;
        for (var attempt = 1; attempt <= 11; attempt++) {
          futureNow += 600000;
          await dispatcher.flush(nowMsOverride: futureNow);
          final rows = await SqliteDatabase.instance.database.query(
            OutboxDispatcher.tableName,
          );
          expect(rows.single['status'], equals('pending'));
          expect(rows.single['retry_count'], equals(attempt));
          expect(permanentErrors, isEmpty);
        }

        futureNow += 600000;
        await dispatcher.flush(nowMsOverride: futureNow);
        final rows = await SqliteDatabase.instance.database.query(
          OutboxDispatcher.tableName,
        );
        expect(rows.single['status'], equals('failed_permanent'));
        expect(rows.single['retry_count'], equals(12));
        expect(rows.single['last_error'], equals('MAX_RETRIES_EXHAUSTED'));
        expect(permanentErrors, hasLength(1));
      } finally {
        dispatcher.dispose();
        await SqliteDatabase.instance.close();
      }
    });

    test('409 IDEMPOTENCY_IN_FLIGHT, 429 Retry-After, 403 gate, and 422 dead-letter FSM transitions', () async {
      await openMemoryDb();
      OutboxSendResponse nextOutcome = const OutboxSendRetryLater(
        'IDEMPOTENCY_IN_FLIGHT',
      );
      final gateErrors = <AppError>[];
      final permanentErrors = <AppError>[];

      final dispatcher = OutboxDispatcher(
        db: SqliteDatabase.instance,
        networkSender: (_) async => nextOutcome,
        onGateError: gateErrors.add,
        onPermanentError: permanentErrors.add,
      );

      try {
        await dispatcher.enqueue(
          operationType: 'update_user_vehicle',
          httpMethod: 'PUT',
          endpointPath: '/api/v1/users/me/vehicle',
          payloadJson: '{"vehicle_name":"Auto","fuel":"petrol_95","consumption_per_100km":8.5}',
        );

        var now = DateTime.now().millisecondsSinceEpoch;
        await dispatcher.flush(nowMsOverride: now);
        var row = (await SqliteDatabase.instance.database.query(
          OutboxDispatcher.tableName,
        )).single;
        expect(row['status'], equals('pending'));
        expect(row['last_error'], equals('IDEMPOTENCY_IN_FLIGHT'));

        now += 600000;
        nextOutcome = const OutboxSendRetryLater('RATE_LIMIT_EXCEEDED', 45);
        await dispatcher.flush(nowMsOverride: now);
        row = (await SqliteDatabase.instance.database.query(
          OutboxDispatcher.tableName,
        )).single;
        expect(row['status'], equals('pending'));
        expect(row['last_error'], equals('RATE_LIMIT_EXCEEDED'));
        final nextRetryAt = (row['next_retry_at_ms'] as num?)?.toInt() ?? 0;
        expect(nextRetryAt >= now + 40000, isTrue);

        now += 600000;
        nextOutcome = OutboxSendRequiresGate(
          AppError.fromCode('FZ152_CONSENT_REVOKED'),
        );
        await dispatcher.flush(nowMsOverride: now);
        expect(dispatcher.isPausedForGate, isTrue);
        expect(gateErrors, hasLength(1));
        expect(gateErrors.single.code, equals('FZ152_CONSENT_REVOKED'));

        nextOutcome = OutboxSendPermanentFailure(
          AppError.fromCode('EDIT_WINDOW_EXPIRED'),
        );
        dispatcher.resumeQueue(autoFlush: false);
        await dispatcher.flush(nowMsOverride: now + 600000);
        row = (await SqliteDatabase.instance.database.query(
          OutboxDispatcher.tableName,
        )).single;
        expect(row['status'], equals('failed_permanent'));
        expect(row['last_error'], equals('EDIT_WINDOW_EXPIRED'));
        expect(permanentErrors.single.code, equals('EDIT_WINDOW_EXPIRED'));
      } finally {
        dispatcher.dispose();
        await SqliteDatabase.instance.close();
      }
    });
  });
}
