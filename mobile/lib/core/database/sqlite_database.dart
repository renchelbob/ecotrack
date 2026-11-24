import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

final class SqliteDatabase {
  SqliteDatabase._();
  static final SqliteDatabase instance = SqliteDatabase._();

  Database? _db;

  Database get database {
    final db = _db;
    if (db == null) {
      throw StateError(
        'SqliteDatabase has not been initialized. Call initialize() first.',
      );
    }
    return db;
  }

  Future<void> initialize({Database? overrideDb}) async {
    if (overrideDb != null) {
      _db = overrideDb;
      return;
    }
    if (_db != null) {
      return;
    }

    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, 'ecotrack_client.db');

    Future<Database> open() => openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _executeSchema(db);
      },
      onConfigure: (db) async {
        // Enforce WAL mode and foreign keys for high performance and integrity
        await db.rawQuery('PRAGMA journal_mode = WAL;');
        await db.rawQuery('PRAGMA synchronous = NORMAL;');
        await db.execute('PRAGMA foreign_keys = ON;');
      },
    );

    try {
      _db = await open();
    } catch (_) {
      // If previous schema creation aborted midway, purge corrupted DB and rebuild clean
      await deleteDatabase(dbPath);
      _db = await open();
    }
  }

  Future<void> _executeSchema(Database db) async {
    String schemaSql;
    try {
      schemaSql = await rootBundle.loadString(
        'assets/db/client_sqlite_schema.sql',
      );
    } catch (_) {
      schemaSql = _fallbackSchemaSql;
    }

    // Strip single-line SQL comments (-- ...) before statement splitting
    final cleanedSql = schemaSql
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');

    final statements = cleanedSql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final stmt in statements) {
      if (stmt.toUpperCase().startsWith('PRAGMA')) {
        continue;
      }
      await db.execute(stmt);
    }
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  static const String _fallbackSchemaSql = '''
CREATE TABLE IF NOT EXISTS local_user_profile (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    email TEXT,
    phone_masked TEXT,
    friend_code TEXT NOT NULL UNIQUE,
    points_balance INTEGER NOT NULL DEFAULT 0,
    daily_step_goal INTEGER NOT NULL DEFAULT 10000,
    mascot_mood TEXT NOT NULL DEFAULT 'happy',
    synced_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS local_daily_step_summaries (
    id TEXT PRIMARY KEY,
    activity_date TEXT NOT NULL UNIQUE,
    validated_steps INTEGER NOT NULL DEFAULT 0,
    total_step_distance_m REAL NOT NULL DEFAULT 0.0,
    allocated_gps_distance_m REAL NOT NULL DEFAULT 0.0,
    unallocated_step_distance_m REAL NOT NULL DEFAULT 0.0,
    allocated_co2_saved_grams INTEGER NOT NULL DEFAULT 0,
    auto_default_co2_saved_grams INTEGER NOT NULL DEFAULT 0,
    total_co2_saved_grams INTEGER NOT NULL DEFAULT 0,
    points_balance INTEGER NOT NULL DEFAULT 0,
    is_auto_calculated INTEGER NOT NULL DEFAULT 1,
    synced_at TEXT
);

CREATE TABLE IF NOT EXISTS offline_mutation_outbox (
    id TEXT PRIMARY KEY,
    mutation_type TEXT NOT NULL,
    endpoint_path TEXT NOT NULL,
    http_method TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL,
    retry_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'PENDING'
);

CREATE TABLE IF NOT EXISTS cached_waste_points (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    address TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    waste_types TEXT NOT NULL,
    schedule TEXT,
    trust_score REAL NOT NULL DEFAULT 1.0,
    synced_at TEXT NOT NULL
);
''';
}
