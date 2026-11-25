import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

final class SqliteDatabase._() {
  static const String dbFileName = 'ecotrack_client_v1.db';
  static const int schemaVersion = 1;
  static const String defaultSchemaAssetPath =
      'assets/db/client_sqlite_schema.sql';

  static final SqliteDatabase instance = SqliteDatabase._();

  static const List<String> _userDataTables = [
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

  static const List<Map<String, Object?>> _transportCatalogSeeds = [
    {
      'mode_code': 'bus',
      'display_name_ru': 'Автобус / электробус',
      'display_name_en': 'City Bus',
      'co2_grams_per_km': 82.00,
      'co2_grams_per_meter': 0.08200,
      'is_personal_vehicle_slot': 0,
      'sort_order': 1,
    },
    {
      'mode_code': 'metro',
      'display_name_ru': 'Метро / МЦК / МЦД',
      'display_name_en': 'Metro / Urban Rail',
      'co2_grams_per_km': 28.00,
      'co2_grams_per_meter': 0.02800,
      'is_personal_vehicle_slot': 0,
      'sort_order': 2,
    },
    {
      'mode_code': 'tram',
      'display_name_ru': 'Трамвай',
      'display_name_en': 'Tram',
      'co2_grams_per_km': 35.00,
      'co2_grams_per_meter': 0.03500,
      'is_personal_vehicle_slot': 0,
      'sort_order': 3,
    },
    {
      'mode_code': 'personal_car',
      'display_name_ru': 'Мой автомобиль',
      'display_name_en': 'My Personal Vehicle',
      'co2_grams_per_km': 192.00,
      'co2_grams_per_meter': 0.19200,
      'is_personal_vehicle_slot': 1,
      'sort_order': 4,
    },
    {
      'mode_code': 'car_compact',
      'display_name_ru': 'Авто (компакт B-класс)',
      'display_name_en': 'Compact Car',
      'co2_grams_per_km': 145.00,
      'co2_grams_per_meter': 0.14500,
      'is_personal_vehicle_slot': 0,
      'sort_order': 5,
    },
    {
      'mode_code': 'car_sedan',
      'display_name_ru': 'Авто (седан C/D-класс)',
      'display_name_en': 'Average Sedan',
      'co2_grams_per_km': 192.00,
      'co2_grams_per_meter': 0.19200,
      'is_personal_vehicle_slot': 0,
      'sort_order': 6,
    },
    {
      'mode_code': 'car_suv',
      'display_name_ru': 'Авто (кроссовер / SUV)',
      'display_name_en': 'SUV / Crossover',
      'co2_grams_per_km': 255.00,
      'co2_grams_per_meter': 0.25500,
      'is_personal_vehicle_slot': 0,
      'sort_order': 7,
    },
    {
      'mode_code': 'car_ev',
      'display_name_ru': 'Электромобиль (РФ сеть)',
      'display_name_en': 'Electric Vehicle',
      'co2_grams_per_km': 58.00,
      'co2_grams_per_meter': 0.05800,
      'is_personal_vehicle_slot': 0,
      'sort_order': 8,
    },
  ];

  Database? _db;

  bool get isInitialized => _db != null;

  Database get database {
    final db = _db;
    if (db == null) {
      throw StateError(
        'SqliteDatabase has not been initialized. Call initialize() first.',
      );
    }
    return db;
  }

  Future<void> initialize({
    Database? overrideDb,
    String? schemaSqlOverride,
  }) async {
    if (overrideDb != null) {
      _db = overrideDb;
      await _configurePragmas(overrideDb);
      if (schemaSqlOverride != null) {
        await _executeSchemaScript(overrideDb, schemaSqlOverride);
      }
      await _runOpenTasksIfTablesExist(overrideDb);
      return;
    }

    if (_db != null) {
      return;
    }

    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, dbFileName);

    _db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: _configurePragmas,
      onCreate: (db, version) async {
        final script =
            schemaSqlOverride ??
            await rootBundle.loadString(defaultSchemaAssetPath);
        await _executeSchemaScript(db, script);
      },
      onOpen: _onOpen,
    );
  }

  Future<void> _configurePragmas(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
    await db.rawQuery('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA synchronous = NORMAL;');
    await db.rawQuery('PRAGMA busy_timeout = 5000;');
  }

  Future<void> _executeSchemaScript(Database db, String schemaSql) async {
    final batch = db.batch();
    for (final statement in _splitSqlStatements(schemaSql)) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _runOpenTasksIfTablesExist(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('offline_mutation_outbox', 'local_transport_catalog')",
    );
    final existingNames = rows
        .map((row) => row['name'])
        .whereType<String>()
        .toSet();
    if (existingNames.contains('offline_mutation_outbox')) {
      await _resetInFlightOutboxRows(db);
    }
    if (existingNames.contains('local_transport_catalog')) {
      await _seedTransportCatalog(db);
    }
  }

  Future<void> _onOpen(Database db) async {
    await _resetInFlightOutboxRows(db);
    await _seedTransportCatalog(db);
  }

  Future<void> _resetInFlightOutboxRows(Database db) => db.update(
    'offline_mutation_outbox',
    <String, Object?>{'status': 'pending'},
    where: "status = 'in_flight'",
  );

  Future<void> _seedTransportCatalog(Database db) async {
    final existing = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM local_transport_catalog',
    );
    final count = existing.isEmpty
        ? 0
        : (existing.first['cnt'] as num?)?.toInt() ?? 0;
    if (count >= _transportCatalogSeeds.length) {
      return;
    }

    final batch = db.batch();
    for (final row in _transportCatalogSeeds) {
      batch.insert(
        'local_transport_catalog',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> wipeAllUserData() async {
    final db = database;
    await db.transaction((txn) async {
      for (final table in _userDataTables) {
        await txn.delete(table);
      }
    });
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
    await db.execute('VACUUM;');
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  static List<String> _splitSqlStatements(String rawSql) {
    final cleaned = rawSql
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');

    final statements = <String>[];
    for (final part in cleaned.split(';')) {
      final stmt = part.trim();
      if (stmt.isEmpty) {
        continue;
      }
      if (stmt.toUpperCase().startsWith('PRAGMA')) {
        continue;
      }
      statements.add(stmt);
    }
    return statements;
  }
}
