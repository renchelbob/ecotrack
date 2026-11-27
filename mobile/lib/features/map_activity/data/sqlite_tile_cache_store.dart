import 'dart:async';
import 'dart:convert';

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

final class SqliteTileCacheStore({
  final String dbFileName = defaultDbFileName,
  Database? overrideDb,
  final Future<String> Function()? _dbPathResolver,
}) extends CacheStore implements TileCacheStorage {
  static const String defaultDbFileName = 'ecotrack_tile_cache.db';
  static const String defaultSchemaAssetPath =
      'assets/db/tile_cache_schema.sql';
  static const String tableName = 'tile_cache';
  static const int _schemaVersion = 1;

  Database? _db = overrideDb;
  Future<Database?>? _openingFuture;
  bool _unavailable = false;

  Future<Database?> _resolveDatabase() async {
    if (_unavailable) return null;
    final existing = _db;
    if (existing != null && existing.isOpen) {
      return existing;
    }
    final inFlight = _openingFuture;
    if (inFlight != null) {
      return await inFlight;
    }
    final future = _openDatabaseSafely();
    _openingFuture = future;
    final opened = await future;
    _openingFuture = null;
    return opened;
  }

  Future<Database?> _openDatabaseSafely() async {
    try {
      final dbPath = await _resolveDbPath();
      final db = await openDatabase(
        dbPath,
        version: _schemaVersion,
        onConfigure: _configurePragmas,
        onCreate: (db, _) => _createSchema(db),
      );
      _db = db;
      return db;
    } on MissingPluginException {
      _unavailable = true;
      return null;
    } on PlatformException {
      _unavailable = true;
      return null;
    } on DatabaseException {
      _unavailable = true;
      return null;
    }
  }

  Future<String> _resolveDbPath() async {
    final resolver = _dbPathResolver;
    if (resolver != null) {
      return await resolver();
    }
    try {
      final supportDir = await getApplicationSupportDirectory();
      return p.join(supportDir.path, dbFileName);
    } on MissingPluginException {
      final dbDir = await getDatabasesPath();
      return p.join(dbDir, dbFileName);
    } on PlatformException {
      final dbDir = await getDatabasesPath();
      return p.join(dbDir, dbFileName);
    }
  }

  static Future<void> _configurePragmas(Database db) async {
    await db.rawQuery('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA synchronous = NORMAL;');
    await db.rawQuery('PRAGMA busy_timeout = 5000;');
  }

  static Future<void> _createSchema(Database db) async {
    final schemaSql = await rootBundle.loadString(defaultSchemaAssetPath);
    final batch = db.batch();
    for (final rawStatement in schemaSql.split(';')) {
      final statement = rawStatement
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('--'))
          .join('\n')
          .trim();
      if (statement.isNotEmpty) {
        batch.execute(statement);
      }
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<bool> exists(String key) async {
    final db = await _resolveDatabase();
    if (db == null) return false;
    final rows = await db.query(
      tableName,
      columns: const ['cache_key'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<CacheResponse?> get(String key) async {
    final record = await getRecord(key);
    return record != null ? _toCacheResponse(record) : null;
  }

  @override
  Future<List<CacheResponse>> getFromPath(
    RegExp pathPattern, {
    Map<String, String?>? queryParams,
  }) async {
    final records = await getAllRecords();
    final out = <CacheResponse>[];
    for (final record in records) {
      if (pathExists(record.url, pathPattern, queryParams: queryParams)) {
        out.add(_toCacheResponse(record));
      }
    }
    return out;
  }

  @override
  Future<void> set(CacheResponse response) =>
      upsertRecord(_fromCacheResponse(response));

  @override
  Future<void> delete(String key, {bool staleOnly = false}) =>
      deleteRecord(key, staleOnly: staleOnly);

  @override
  Future<void> deleteFromPath(
    RegExp pathPattern, {
    Map<String, String?>? queryParams,
  }) async {
    final db = await _resolveDatabase();
    if (db == null) return;
    final rows = await db.query(tableName, columns: const ['cache_key', 'url']);
    final keysToDelete = <String>[];
    for (final row in rows) {
      final key = row['cache_key'];
      final url = row['url'];
      if (key is String &&
          url is String &&
          pathExists(url, pathPattern, queryParams: queryParams)) {
        keysToDelete.add(key);
      }
    }
    await deleteRecords(keysToDelete);
  }

  @override
  Future<void> clean({
    CachePriority priorityOrBelow = CachePriority.high,
    bool staleOnly = false,
  }) => cleanRecords(
    maxPriorityIndex: priorityOrBelow.index,
    staleOnly: staleOnly,
  );

  @override
  Future<void> close() => closeStorage();

  @override
  Future<TileCacheEntryRecord?> getRecord(String key) async {
    final db = await _resolveDatabase();
    if (db == null) return null;
    final rows = await db.query(
      tableName,
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _recordFromRow(rows.first);
  }

  @override
  Future<List<TileCacheEntryRecord>> getAllRecords() async {
    final db = await _resolveDatabase();
    if (db == null) return const [];
    final rows = await db.query(tableName);
    final out = <TileCacheEntryRecord>[];
    for (final row in rows) {
      final record = _recordFromRow(row);
      if (record != null) {
        out.add(record);
      }
    }
    return out;
  }

  @override
  Future<void> upsertRecord(TileCacheEntryRecord record) async {
    final db = await _resolveDatabase();
    if (db == null) return;
    await db.insert(
      tableName,
      _recordToRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteRecord(String key, {bool staleOnly = false}) async {
    final db = await _resolveDatabase();
    if (db == null) return;
    if (!staleOnly) {
      await db.delete(tableName, where: 'cache_key = ?', whereArgs: [key]);
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.delete(
      tableName,
      where: 'cache_key = ? AND max_stale_ms IS NOT NULL AND max_stale_ms < ?',
      whereArgs: [key, nowMs],
    );
  }

  @override
  Future<void> deleteRecords(List<String> keys) async {
    if (keys.isEmpty) return;
    final db = await _resolveDatabase();
    if (db == null) return;
    final batch = db.batch();
    for (final key in keys) {
      batch.delete(tableName, where: 'cache_key = ?', whereArgs: [key]);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> cleanRecords({
    required int maxPriorityIndex,
    bool staleOnly = false,
  }) async {
    final db = await _resolveDatabase();
    if (db == null) return;
    if (!staleOnly) {
      await db.delete(
        tableName,
        where: 'priority <= ?',
        whereArgs: [maxPriorityIndex],
      );
      return;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.delete(
      tableName,
      where: 'priority <= ? AND max_stale_ms IS NOT NULL AND max_stale_ms < ?',
      whereArgs: [maxPriorityIndex, nowMs],
    );
  }

  @override
  Future<void> closeStorage() async {
    final existing = _db;
    _db = null;
    if (existing != null && existing.isOpen) {
      await existing.close();
    }
  }

  static Map<String, Object?> _recordToRow(TileCacheEntryRecord r) =>
      <String, Object?>{
        'cache_key': r.key,
        'url': r.url,
        'status_code': r.statusCode,
        'priority': r.priorityIndex,
        'request_date_ms': r.requestDateMs,
        'response_date_ms': r.responseDateMs,
        'date_ms': r.dateMs,
        'expires_ms': r.expiresMs,
        'max_stale_ms': r.maxStaleMs,
        'etag': r.eTag,
        'last_modified': r.lastModified,
        'content': _toBlob(r.content),
        'headers': _toBlob(r.headers),
        'cc_max_age': r.ccMaxAge,
        'cc_max_stale': r.ccMaxStale,
        'cc_min_fresh': r.ccMinFresh,
        'cc_must_revalidate': r.ccMustRevalidate ? 1 : 0,
        'cc_no_cache': r.ccNoCache ? 1 : 0,
        'cc_no_store': r.ccNoStore ? 1 : 0,
        'cc_privacy': r.ccPrivacy,
        'cc_other_json': r.ccOther.isEmpty ? null : jsonEncode(r.ccOther),
      };

  static Uint8List? _toBlob(List<int>? bytes) => switch (bytes) {
    final Uint8List u => u,
    final List<int> list => Uint8List.fromList(list),
    null => null,
  };

  static DateTime? _dtFromMs(int? ms) =>
      ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

  static TileCacheEntryRecord? _recordFromRow(Map<String, Object?> row) {
    final key = row['cache_key'];
    final url = row['url'];
    final statusCode = row['status_code'];
    final reqMs = row['request_date_ms'];
    final respMs = row['response_date_ms'];
    if (key is! String ||
        url is! String ||
        statusCode is! int ||
        reqMs is! int ||
        respMs is! int) {
      return null;
    }
    return TileCacheEntryRecord(
      key: key,
      url: url,
      statusCode: statusCode,
      priorityIndex: (row['priority'] as int?) ?? CachePriority.normal.index,
      requestDateMs: reqMs,
      responseDateMs: respMs,
      dateMs: row['date_ms'] as int?,
      expiresMs: row['expires_ms'] as int?,
      maxStaleMs: row['max_stale_ms'] as int?,
      eTag: row['etag'] as String?,
      lastModified: row['last_modified'] as String?,
      content: _decodeBlob(row['content']),
      headers: _decodeBlob(row['headers']),
      ccMaxAge: (row['cc_max_age'] as int?) ?? -1,
      ccMaxStale: (row['cc_max_stale'] as int?) ?? -1,
      ccMinFresh: (row['cc_min_fresh'] as int?) ?? -1,
      ccMustRevalidate: ((row['cc_must_revalidate'] as int?) ?? 0) != 0,
      ccNoCache: ((row['cc_no_cache'] as int?) ?? 0) != 0,
      ccNoStore: ((row['cc_no_store'] as int?) ?? 0) != 0,
      ccPrivacy: row['cc_privacy'] as String?,
      ccOther: _decodeOther(row['cc_other_json']),
    );
  }

  static List<int>? _decodeBlob(Object? raw) => switch (raw) {
    final Uint8List bytes => bytes,
    final List<int> bytes => bytes,
    _ => null,
  };

  static List<String> _decodeOther(Object? raw) {
    if (raw is! String || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<Object?>) {
        return decoded.whereType<String>().toList();
      }
    } on FormatException {
      return const <String>[];
    }
    return const <String>[];
  }

  static TileCacheEntryRecord _fromCacheResponse(CacheResponse r) =>
      TileCacheEntryRecord(
        key: r.key,
        url: r.url,
        statusCode: r.statusCode,
        priorityIndex: r.priority.index,
        requestDateMs: r.requestDate.millisecondsSinceEpoch,
        responseDateMs: r.responseDate.millisecondsSinceEpoch,
        dateMs: r.date?.millisecondsSinceEpoch,
        expiresMs: r.expires?.millisecondsSinceEpoch,
        maxStaleMs: r.maxStale?.millisecondsSinceEpoch,
        eTag: r.eTag,
        lastModified: r.lastModified,
        content: r.content,
        headers: r.headers,
        ccMaxAge: r.cacheControl.maxAge,
        ccMaxStale: r.cacheControl.maxStale,
        ccMinFresh: r.cacheControl.minFresh,
        ccMustRevalidate: r.cacheControl.mustRevalidate,
        ccNoCache: r.cacheControl.noCache,
        ccNoStore: r.cacheControl.noStore,
        ccPrivacy: r.cacheControl.privacy,
        ccOther: r.cacheControl.other,
      );

  static CacheResponse _toCacheResponse(TileCacheEntryRecord r) {
    final idx = r.priorityIndex.clamp(0, CachePriority.values.length - 1);
    return CacheResponse(
      key: r.key,
      url: r.url,
      statusCode: r.statusCode,
      priority: CachePriority.values[idx],
      requestDate: DateTime.fromMillisecondsSinceEpoch(r.requestDateMs),
      responseDate: DateTime.fromMillisecondsSinceEpoch(r.responseDateMs),
      date: _dtFromMs(r.dateMs),
      expires: _dtFromMs(r.expiresMs),
      maxStale: _dtFromMs(r.maxStaleMs),
      eTag: r.eTag,
      lastModified: r.lastModified,
      content: r.content,
      headers: r.headers,
      cacheControl: CacheControl(
        maxAge: r.ccMaxAge,
        maxStale: r.ccMaxStale,
        minFresh: r.ccMinFresh,
        mustRevalidate: r.ccMustRevalidate,
        noCache: r.ccNoCache,
        noStore: r.ccNoStore,
        privacy: r.ccPrivacy,
        other: r.ccOther,
      ),
    );
  }
}
