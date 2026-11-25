import 'dart:io';

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late String schemaSql;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final schemaFile = File('assets/db/client_sqlite_schema.sql');
    expect(schemaFile.existsSync(), isTrue);
    schemaSql = schemaFile.readAsStringSync();
  });

  group('SQLite Schema & Wipe Invariants', () {
    late Database rawDb;

    setUp(() async {
      rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await SqliteDatabase.instance.initialize(
        overrideDb: rawDb,
        schemaSqlOverride: schemaSql,
      );
    });

    tearDown(() async {
      await SqliteDatabase.instance.close();
    });

    test(
      'All 12 contract tables exist and 8 transport presets are seeded',
      () async {
        final db = SqliteDatabase.instance.database;
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
        );
        final tableNames = tables
            .map((r) => r['name'])
            .whereType<String>()
            .toSet();

        const expectedTables = <String>{
          'local_user_profile',
          'local_user_vehicle',
          'local_transport_catalog',
          'local_daily_step_summaries',
          'local_gps_track_points',
          'local_route_segment_allocations',
          'offline_mutation_outbox',
          'cached_waste_points',
          'pending_waste_point_reports',
          'cached_weekly_stats_snapshot',
          'cached_friends_leaderboard',
          'cached_badges_and_inventory',
        };

        for (final table in expectedTables) {
          expect(tableNames, contains(table));
        }

        final presets = await db.query(
          'local_transport_catalog',
          orderBy: 'sort_order ASC',
        );
        expect(presets.length, equals(8));
        expect(
          presets.map((row) => row['mode_code']).toList(),
          equals([
            'bus',
            'metro',
            'tram',
            'personal_car',
            'car_compact',
            'car_sedan',
            'car_suv',
            'car_ev',
          ]),
        );
      },
    );

    test(
      'OutboxDispatcher and wipeAllUserData enforce 10-table erasure',
      () async {
        final db = SqliteDatabase.instance.database;
        final nowMs = DateTime.now().millisecondsSinceEpoch;

        await db.insert('local_user_profile', <String, Object?>{
          'user_id': '01935c10-0000-7000-8000-000000000001',
          'display_name': 'Тест Пользователь',
          'friend_code': 'ECO-TEST-1234',
          'auth_provider': 'yandex',
          'updated_at_ms': nowMs,
        });
        await db.insert('local_user_vehicle', <String, Object?>{
          'id': '01935c10-0000-7000-8000-000000000002',
          'user_id': '01935c10-0000-7000-8000-000000000001',
          'vehicle_name': 'Мой седан',
          'fuel': 'petrol_95',
          'consumption_per_100km': 8.5,
          'fuel_emission_factor_g_per_unit': 2330.0,
          'computed_co2_g_per_km': 198.05,
          'computed_co2_g_per_meter': 0.19805,
          'updated_at_ms': nowMs,
        });
        await db.insert('local_daily_step_summaries', <String, Object?>{
          'activity_date': '2026-11-24',
          'user_id': '01935c10-0000-7000-8000-000000000001',
          'raw_sensor_steps': 5000,
          'validated_steps': 5000,
          'last_sensor_read_at_ms': nowMs,
        });
        await db.insert('local_gps_track_points', <String, Object?>{
          'activity_date': '2026-11-24',
          'seq_no': 0,
          'recorded_at_ms': nowMs,
          'lat': 58.6035,
          'lon': 49.6680,
          'accuracy_m': 8.0,
          'speed_mps': 1.2,
          'cumulative_steps': 100,
        });
        await db.insert('local_route_segment_allocations', <String, Object?>{
          'id': '01935c10-0000-7000-8000-000000000003',
          'idempotency_key': '01935c10-0000-7000-8000-000000000004',
          'activity_date': '2026-11-24',
          'start_seq_no': 0,
          'end_seq_no': 1,
          'polyline_json': '[[58.6035,49.6680],[58.6040,49.6690]]',
          'segment_distance_m': 120.0,
          'segment_steps': 160,
          'replaced_transport_mode': 'bus',
          'applied_co2_g_per_meter': 0.082,
          'confidence_factor': 1.0,
          'co2_saved_grams': 10,
          'created_at_ms': nowMs,
          'updated_at_ms': nowMs,
        });
        await db.insert('cached_waste_points', <String, Object?>{
          'id': '01935c10-0000-7000-8000-000000000005',
          'title': 'Пункт РСО',
          'accepted_fractions_csv': 'plastic,glass',
          'lat': 58.6035,
          'lon': 49.6680,
          'status': 'active',
          'trust_score': 80.0,
          'attribution_text': 'OpenStreetMap',
          'cached_at_ms': nowMs,
        });
        await db.insert('pending_waste_point_reports', <String, Object?>{
          'id': '01935c10-0000-7000-8000-000000000006',
          'idempotency_key': '01935c10-0000-7000-8000-000000000007',
          'waste_point_id': '01935c10-0000-7000-8000-000000000005',
          'report_type': 'confirm_working',
          'user_lat': 58.6035,
          'user_lon': 49.6680,
          'distance_to_point_m': 15.0,
          'created_at_ms': nowMs,
        });
        await db.insert('cached_weekly_stats_snapshot', <String, Object?>{
          'iso_year': 2026,
          'iso_week': 48,
          'daily_breakdown_json': '{}',
          'equivalents_json': '{}',
          'shared_forest_json': '{}',
          'updated_at_ms': nowMs,
        });
        await db.insert('cached_friends_leaderboard', <String, Object?>{
          'friend_user_id': '01935c10-0000-7000-8000-000000000008',
          'display_name': 'Друг',
          'friend_code': 'ECO-FRND-0001',
          'friendship_status': 'accepted',
          'updated_at_ms': nowMs,
        });
        await db.insert('cached_badges_and_inventory', <String, Object?>{
          'item_kind': 'badge',
          'code': 'first_10k_steps',
          'title_ru': 'Первые 10 000 шагов',
          'description_ru': 'Пройдите 10 000 шагов',
          'icon_or_layer_key': 'steps',
          'updated_at_ms': nowMs,
        });

        final dispatcher = OutboxDispatcher(db: SqliteDatabase.instance);
        await dispatcher.enqueue(
          operationType: 'sync_daily_steps',
          httpMethod: 'PUT',
          endpointPath: '/api/v1/activity/steps/daily',
          payloadJson: '{"activity_date":"2026-11-24","raw_sensor_steps":5000}',
        );
        expect(await dispatcher.countPending(), equals(1));

        await SqliteDatabase.instance.wipeAllUserData();

        const wipedTables = <String>[
          'offline_mutation_outbox',
          'pending_waste_point_reports',
          'local_route_segment_allocations',
          'local_gps_track_points',
          'local_daily_step_summaries',
          'local_user_vehicle',
          'cached_friends_leaderboard',
          'cached_weekly_stats_snapshot',
          'cached_badges_and_inventory',
          'local_user_profile',
        ];
        for (final table in wipedTables) {
          final rows = await db.query(table);
          expect(
            rows,
            isEmpty,
            reason: 'Table $table must be empty after wipe',
          );
        }

        final presetsAfterWipe = await db.query('local_transport_catalog');
        expect(presetsAfterWipe.length, equals(8));
        dispatcher.dispose();
      },
    );

    test(
      'Database re-open resets stuck in_flight outbox rows to pending',
      () async {
        final db = SqliteDatabase.instance.database;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        await db.insert('offline_mutation_outbox', <String, Object?>{
          'idempotency_key': '01935c10-0000-7000-8000-000000000099',
          'operation_type': 'sync_daily_steps',
          'http_method': 'PUT',
          'endpoint_path': '/api/v1/activity/steps/daily',
          'payload_json':
              '{"activity_date":"2026-11-24","raw_sensor_steps":10}',
          'status': 'in_flight',
          'retry_count': 0,
          'max_retries': 12,
          'next_retry_at_ms': nowMs,
          'created_at_ms': nowMs,
        });

        await SqliteDatabase.instance.initialize(overrideDb: db);
        final rows = await db.query('offline_mutation_outbox');
        expect(rows.single['status'], equals('pending'));
      },
    );
  });
}
