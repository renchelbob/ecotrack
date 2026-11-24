import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQLite Schema & Outbox Invariant Tests', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      // Read schema asset
      final schemaFile = File('assets/db/client_sqlite_schema.sql');
      expect(schemaFile.existsSync(), isTrue);
      final sqlStatements = await schemaFile.readAsString();

      // Execute schema statements
      for (final raw in sqlStatements.split(';')) {
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty) {
          await db.execute(trimmed);
        }
      }
    });

    tearDown(() async {
      await db.close();
    });

    test('All required client tables are created', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tables
          .map((r) => r['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();

      expect(tableNames, contains('offline_mutation_outbox'));
      expect(tableNames, contains('local_daily_step_summaries'));
      expect(tableNames, contains('local_gps_track_points'));
      expect(tableNames, contains('local_user_profile'));
      expect(tableNames, contains('cached_waste_points'));
    });

    test('Offline mutation outbox state machine transitions', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // 1. Enqueue mutation
      await db.insert('offline_mutation_outbox', {
        'idempotency_key': '01935c10-0000-7000-8000-000000000001',
        'operation_type': 'sync_daily_steps',
        'endpoint_path': '/v1/steps',
        'http_method': 'PUT',
        'payload_json': '{"date": "2026-11-24", "steps": 5000}',
        'status': 'pending',
        'retry_count': 0,
        'next_retry_at_ms': nowMs,
        'created_at_ms': nowMs,
      });

      // Assert pending
      var records = await db.query(
        'offline_mutation_outbox',
        where: "status = 'pending'",
      );
      expect(records.length, equals(1));
      expect(
        records.first['idempotency_key'],
        equals('01935c10-0000-7000-8000-000000000001'),
      );

      // 2. Transition to in_flight
      const inFlightStatus = <String, Object?>{'status': 'in_flight'};
      await db.update(
        'offline_mutation_outbox',
        inFlightStatus,
        where: "idempotency_key = '01935c10-0000-7000-8000-000000000001'",
      );

      records = await db.query(
        'offline_mutation_outbox',
        where: "status = 'in_flight'",
      );
      expect(records.length, equals(1));

      // 3. Mark completed (e.g. deleted or final status)
      await db.delete(
        'offline_mutation_outbox',
        where: "idempotency_key = '01935c10-0000-7000-8000-000000000001'",
      );

      records = await db.query('offline_mutation_outbox');
      expect(records.isEmpty, isTrue);
    });
  });
}
