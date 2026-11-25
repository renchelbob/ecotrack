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

    Glados2(any.intInRange(0, 50000), any.intInRange(0, 500000)).test(
      'OutboxSendSuccess reconciles local_daily_step_summaries and local_user_profile',
      (newBalance, newLifetimeCo2) async {
        final db = await openMemoryDb();
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await db.insert('local_user_profile', <String, Object?>{
          'user_id': 'u-1',
          'display_name': 'EcoUser',
          'friend_code': 'ECO-1111-2222',
          'auth_provider': 'yandex',
          'points_balance': 5,
          'lifetime_co2_saved_grams': 100,
          'updated_at_ms': nowMs,
        });
        await db.insert('local_daily_step_summaries', <String, Object?>{
          'activity_date': '2026-11-24',
          'user_id': 'u-1',
          'raw_sensor_steps': 3500,
          'validated_steps': 3500,
          'total_step_distance_m': 2590.0,
          'unallocated_step_distance_m': 2590.0,
          'auto_default_co2_saved_grams': 119,
          'total_co2_saved_grams': 119,
          'points_awarded_for_day': 35,
          'sync_status': 'pending',
          'last_sensor_read_at_ms': nowMs,
        });

        final dispatcher = OutboxDispatcher(
          db: SqliteDatabase.instance,
          networkSender: (_) async => OutboxSendSuccess(<String, Object?>{
            'activity_date': '2026-11-24',
            'validated_steps': 3500,
            'total_co2_saved_grams': 119,
            'points_balance': newBalance,
            'lifetime_co2_saved_grams': newLifetimeCo2,
          }),
        );

        try {
          await dispatcher.enqueue(
            operationType: 'sync_daily_steps',
            httpMethod: 'PUT',
            endpointPath: '/api/v1/activity/steps/daily',
            payloadJson: jsonEncode(<String, Object?>{
              'activity_date': '2026-11-24',
              'timezone_offset_minutes': 180,
              'raw_sensor_steps': 3500,
            }),
          );
          await dispatcher.flush(nowMsOverride: nowMs + 1000);

          final summary = (await db.query(
            'local_daily_step_summaries',
            where: 'activity_date = ?',
            whereArgs: const ['2026-11-24'],
          )).single;
          expect(summary['sync_status'], equals('synced'));
          expect(summary['last_synced_at_ms'], isNotNull);

          final profile = (await db.query(
            'local_user_profile',
            where: 'user_id = ?',
            whereArgs: const ['u-1'],
          )).single;
          expect(profile['points_balance'], equals(newBalance));
          expect(profile['lifetime_co2_saved_grams'], equals(newLifetimeCo2));
        } finally {
          dispatcher.dispose();
          await SqliteDatabase.instance.close();
        }
      },
    );

    test('OutboxSendSuccess reconciles GPS points, segment allocations (nested summary), and waste reports', () async {
      final db = await openMemoryDb();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await db.insert('local_user_profile', <String, Object?>{
        'user_id': 'u-2',
        'display_name': 'EcoUser2',
        'friend_code': 'ECO-3333-4444',
        'auth_provider': 'vk',
        'points_balance': 10,
        'lifetime_co2_saved_grams': 200,
        'updated_at_ms': nowMs,
      });
      await db.insert('local_daily_step_summaries', <String, Object?>{
        'activity_date': '2026-11-24',
        'user_id': 'u-2',
        'raw_sensor_steps': 2000,
        'validated_steps': 2000,
        'total_step_distance_m': 1480.0,
        'allocated_gps_distance_m': 500.0,
        'unallocated_step_distance_m': 980.0,
        'allocated_co2_saved_grams': 90,
        'auto_default_co2_saved_grams': 45,
        'total_co2_saved_grams': 135,
        'sync_status': 'pending',
        'last_sensor_read_at_ms': nowMs,
      });
      for (var seq = 0; seq < 3; seq++) {
        await db.insert('local_gps_track_points', <String, Object?>{
          'activity_date': '2026-11-24',
          'seq_no': seq,
          'recorded_at_ms': nowMs + seq * 5000,
          'lat': 55.75 + seq * 0.001,
          'lon': 37.61 + seq * 0.001,
          'accuracy_m': 5.0,
          'cumulative_steps': 100 + seq * 20,
          'motion_class': 'walking',
          'sync_status': 'pending',
        });
      }
      await db.insert('local_route_segment_allocations', <String, Object?>{
        'id': 'alloc-key-1',
        'idempotency_key': 'alloc-key-1',
        'activity_date': '2026-11-24',
        'start_seq_no': 0,
        'end_seq_no': 1,
        'polyline_json': '[[55.75,37.61],[55.751,37.611]]',
        'segment_distance_m': 500.0,
        'segment_steps': 20,
        'replaced_transport_mode': 'bus',
        'applied_co2_g_per_meter': 0.082,
        'co2_saved_grams': 41,
        'sync_status': 'pending',
        'created_at_ms': nowMs,
        'updated_at_ms': nowMs,
      });
      await db.insert('pending_waste_point_reports', <String, Object?>{
        'id': 'rep-1',
        'idempotency_key': 'rep-key-1',
        'waste_point_id': 'wp-99',
        'report_type': 'confirm_working',
        'user_lat': 55.75,
        'user_lon': 37.61,
        'distance_to_point_m': 12.0,
        'sync_status': 'pending',
        'created_at_ms': nowMs,
      });

      final dispatcher = OutboxDispatcher(
        db: SqliteDatabase.instance,
        networkSender: (item) async {
          if (item.operationType == 'upsert_segment_allocation') {
            return const OutboxSendSuccess(<String, Object?>{
              'summary': <String, Object?>{
                'activity_date': '2026-11-24',
                'points_balance': 77,
                'lifetime_co2_saved_grams': 450,
                'total_co2_saved_grams': 150,
              },
            });
          }
          return const OutboxSendSuccess(<String, Object?>{'ok': true});
        },
      );

      try {
        await dispatcher.enqueue(
          operationType: 'upload_gps_track_batch',
          httpMethod: 'POST',
          endpointPath: '/api/v1/activity/tracks/points:batch',
          payloadJson: jsonEncode(<String, Object?>{
            'activity_date': '2026-11-24',
            'points': const <Object?>[
              <String, Object?>{'seq_no': 0},
              <String, Object?>{'seq_no': 1},
            ],
          }),
        );
        await dispatcher.enqueue(
          operationType: 'upsert_segment_allocation',
          httpMethod: 'PUT',
          endpointPath: '/api/v1/activity/daily/2026-11-24/allocations',
          payloadJson: jsonEncode(<String, Object?>{
            'allocations': const <Object?>[
              <String, Object?>{'idempotency_key': 'alloc-key-1'},
            ],
          }),
        );
        await dispatcher.enqueue(
          operationType: 'submit_waste_point_report',
          httpMethod: 'POST',
          endpointPath: '/api/v1/map/waste-points/wp-99/reports',
          idempotencyKey: 'rep-key-1',
          payloadJson: '{"report_type":"confirm_working"}',
        );

        await dispatcher.flush(nowMsOverride: nowMs + 2000);

        final pts = await db.query(
          'local_gps_track_points',
          orderBy: 'seq_no ASC',
        );
        expect(pts[0]['sync_status'], equals('synced'));
        expect(pts[1]['sync_status'], equals('synced'));
        expect(pts[2]['sync_status'], equals('pending'));

        final alloc = (await db.query('local_route_segment_allocations'))
            .single;
        expect(alloc['sync_status'], equals('synced'));

        final summary = (await db.query('local_daily_step_summaries')).single;
        expect(summary['sync_status'], equals('synced'));
        expect(summary['total_co2_saved_grams'], equals(150));

        final report = (await db.query('pending_waste_point_reports')).single;
        expect(report['sync_status'], equals('synced'));

        final profile = (await db.query('local_user_profile')).single;
        expect(profile['points_balance'], equals(77));
        expect(profile['lifetime_co2_saved_grams'], equals(450));
      } finally {
        dispatcher.dispose();
        await SqliteDatabase.instance.close();
      }
    });

    test('OutboxSendPermanentFailure marks entities failed and rolls back invalid optimistic allocations', () async {
      final db = await openMemoryDb();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await db.insert('local_daily_step_summaries', <String, Object?>{
        'activity_date': '2026-11-24',
        'user_id': 'u-3',
        'raw_sensor_steps': 1000,
        'validated_steps': 1000,
        'total_step_distance_m': 740.0,
        'allocated_gps_distance_m': 400.0,
        'unallocated_step_distance_m': 340.0,
        'allocated_co2_saved_grams': 80,
        'auto_default_co2_saved_grams': 16,
        'total_co2_saved_grams': 96,
        'is_auto_calculated': 0,
        'sync_status': 'pending',
        'last_sensor_read_at_ms': nowMs,
      });
      await db.insert('local_daily_step_summaries', <String, Object?>{
        'activity_date': '2026-11-23',
        'user_id': 'u-3',
        'raw_sensor_steps': 500,
        'validated_steps': 500,
        'sync_status': 'pending',
        'last_sensor_read_at_ms': nowMs,
      });
      await db.insert('local_gps_track_points', <String, Object?>{
        'activity_date': '2026-11-24',
        'seq_no': 0,
        'recorded_at_ms': nowMs,
        'lat': 55.75,
        'lon': 37.61,
        'accuracy_m': 5.0,
        'cumulative_steps': 100,
        'motion_class': 'vehicle_suspected',
        'sync_status': 'pending',
      });
      await db.insert('local_route_segment_allocations', <String, Object?>{
        'id': 'bad-alloc-1',
        'idempotency_key': 'bad-alloc-1',
        'activity_date': '2026-11-24',
        'start_seq_no': 0,
        'end_seq_no': 1,
        'polyline_json': '[[55.75,37.61],[55.751,37.611]]',
        'segment_distance_m': 400.0,
        'segment_steps': 10,
        'replaced_transport_mode': 'bus',
        'applied_co2_g_per_meter': 0.082,
        'co2_saved_grams': 80,
        'sync_status': 'pending',
        'created_at_ms': nowMs,
        'updated_at_ms': nowMs,
      });
      await db.insert('pending_waste_point_reports', <String, Object?>{
        'id': 'rep-bad',
        'idempotency_key': 'rep-bad-key',
        'waste_point_id': 'wp-12',
        'report_type': 'overflowing',
        'user_lat': 55.75,
        'user_lon': 37.61,
        'distance_to_point_m': 5000.0,
        'sync_status': 'pending',
        'created_at_ms': nowMs,
      });

      final dispatcher = OutboxDispatcher(
        db: SqliteDatabase.instance,
        networkSender: (_) async => OutboxSendPermanentFailure(
          AppError.fromCode('SEGMENT_CONTAINS_VEHICLE_MOTION'),
        ),
      );

      try {
        await dispatcher.enqueue(
          operationType: 'sync_daily_steps',
          httpMethod: 'PUT',
          endpointPath: '/api/v1/activity/steps/daily',
          payloadJson: '{"activity_date":"2026-11-23","raw_sensor_steps":500}',
        );
        await dispatcher.enqueue(
          operationType: 'upload_gps_track_batch',
          httpMethod: 'POST',
          endpointPath: '/api/v1/activity/tracks/points:batch',
          payloadJson: jsonEncode(<String, Object?>{
            'activity_date': '2026-11-24',
            'points': const <Object?>[
              <String, Object?>{'seq_no': 0},
            ],
          }),
        );
        await dispatcher.enqueue(
          operationType: 'upsert_segment_allocation',
          httpMethod: 'PUT',
          endpointPath: '/api/v1/activity/daily/2026-11-24/allocations',
          payloadJson: jsonEncode(<String, Object?>{
            'allocations': const <Object?>[
              <String, Object?>{'idempotency_key': 'bad-alloc-1'},
            ],
          }),
        );
        await dispatcher.enqueue(
          operationType: 'submit_waste_point_report',
          httpMethod: 'POST',
          endpointPath: '/api/v1/map/waste-points/wp-12/reports',
          idempotencyKey: 'rep-bad-key',
          payloadJson: '{"report_type":"overflowing"}',
        );

        await dispatcher.flush(nowMsOverride: nowMs + 3000);

        final step23 = (await db.query(
          'local_daily_step_summaries',
          where: 'activity_date = ?',
          whereArgs: const ['2026-11-23'],
        )).single;
        expect(step23['sync_status'], equals('failed'));

        final gpsPt = (await db.query('local_gps_track_points')).single;
        expect(gpsPt['sync_status'], equals('failed'));

        final remainingAllocs = await db.query(
          'local_route_segment_allocations',
        );
        expect(remainingAllocs, isEmpty);

        final step24 = (await db.query(
          'local_daily_step_summaries',
          where: 'activity_date = ?',
          whereArgs: const ['2026-11-24'],
        )).single;
        expect(step24['sync_status'], equals('failed'));
        expect(step24['allocated_gps_distance_m'], equals(0.0));
        expect(step24['allocated_co2_saved_grams'], equals(0));
        expect(step24['is_auto_calculated'], equals(1));

        final report = (await db.query('pending_waste_point_reports')).single;
        expect(report['sync_status'], equals('failed'));
      } finally {
        dispatcher.dispose();
        await SqliteDatabase.instance.close();
      }
    });
  });
}
