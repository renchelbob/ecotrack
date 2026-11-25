import 'dart:convert';

import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';
import 'package:ecotrack_mobile/features/stats/domain/stats_models.dart';
import 'package:sqflite/sqflite.dart';

({int year, int week, String weekStart, String weekEnd}) _isoWeekInfo(
  DateTime localDate,
) {
  final day = DateTime(localDate.year, localDate.month, localDate.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final jan4 = DateTime(thursday.year, 1, 4);
  final firstThursday = jan4.add(
    Duration(days: DateTime.thursday - jan4.weekday),
  );
  final week = 1 + (thursday.difference(firstThursday).inDays ~/ 7);
  final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
  final sunday = monday.add(const Duration(days: 6));
  return (
    year: thursday.year,
    week: week,
    weekStart: _formatIsoDate(monday),
    weekEnd: _formatIsoDate(sunday),
  );
}

String _formatIsoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

final class StatsSqliteDao([SqliteDatabase? db]) {
  final SqliteDatabase _db = db ?? SqliteDatabase.instance;

  Future<void> saveEmissionsSnapshot(EmissionsStatisticsResponse stats) async {
    final refDate = stats.buckets.isNotEmpty
        ? DateTime.tryParse(stats.buckets.last.endDate) ?? DateTime.now()
        : DateTime.now();
    final info = _isoWeekInfo(refDate);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final db = _db.database;

    final existing = await db.query(
      'cached_weekly_stats_snapshot',
      where: 'iso_year = ? AND iso_week = ?',
      whereArgs: [info.year, info.week],
      limit: 1,
    );

    final mergedBreakdown = <String, Object?>{};
    var equivalentsJson = jsonEncode(
      EcoEquivalentsResponse(
        lifetime: stats.equivalents,
        currentWeek: stats.equivalents,
      ).toJson(),
    );
    var sharedForestJson = '{}';

    if (existing.isNotEmpty) {
      final row = existing.first;
      final prevBreakdown = _decodeMap(row['daily_breakdown_json'] as String?);
      if (prevBreakdown != null) {
        mergedBreakdown.addAll(prevBreakdown);
      }
      final prevEq = row['equivalents_json'] as String?;
      if (prevEq != null && prevEq.isNotEmpty && prevEq != '{}') {
        equivalentsJson = prevEq;
      }
      final prevForest = row['shared_forest_json'] as String?;
      if (prevForest != null && prevForest.isNotEmpty) {
        sharedForestJson = prevForest;
      }
    }

    final encodedStats = stats.toJson();
    if (stats.period == 'days') {
      mergedBreakdown.addAll(encodedStats);
    }
    final rawPeriods = mergedBreakdown['periods'];
    final periodsMap = rawPeriods is Map<String, Object?>
        ? Map<String, Object?>.from(rawPeriods)
        : <String, Object?>{};
    periodsMap[stats.period] = encodedStats;
    mergedBreakdown['periods'] = periodsMap;

    await db.insert('cached_weekly_stats_snapshot', <String, Object?>{
      'iso_year': info.year,
      'iso_week': info.week,
      'daily_breakdown_json': jsonEncode(mergedBreakdown),
      'equivalents_json': equivalentsJson,
      'shared_forest_json': sharedForestJson,
      'updated_at_ms': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _pruneSnapshots(db);
  }

  Future<({EmissionsStatisticsResponse stats, int updatedAtMs})?>
  loadEmissionsSnapshot(String period) async {
    final db = _db.database;
    final rows = await db.query(
      'cached_weekly_stats_snapshot',
      orderBy: 'updated_at_ms DESC',
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final row = rows.first;
      final updatedAtMs = (row['updated_at_ms'] as num?)?.toInt() ?? 0;
      final decoded = _decodeMap(row['daily_breakdown_json'] as String?);
      if (decoded != null) {
        final targetMap = _extractPeriodMap(decoded, period);
        if (targetMap != null) {
          if (EmissionsStatisticsResponse.fromJson(targetMap) case Ok(
            :final value,
          )) {
            final enriched = await enrichWithTransportShares(value);
            return (stats: enriched, updatedAtMs: updatedAtMs);
          }
        }
      }
    }

    if (period == 'days') {
      return await _buildDaysFallbackFromLocalSummaries(db);
    }
    return null;
  }

  Future<void> saveEquivalentsSnapshot(
    EcoEquivalentsResponse equivalents,
  ) async {
    final info = _isoWeekInfo(DateTime.now());
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final db = _db.database;
    final existing = await db.query(
      'cached_weekly_stats_snapshot',
      where: 'iso_year = ? AND iso_week = ?',
      whereArgs: [info.year, info.week],
      limit: 1,
    );

    final dailyBreakdown = existing.isNotEmpty
        ? (existing.first['daily_breakdown_json'] as String? ?? '{}')
        : '{}';
    final sharedForest = existing.isNotEmpty
        ? (existing.first['shared_forest_json'] as String? ?? '{}')
        : '{}';

    await db.insert('cached_weekly_stats_snapshot', <String, Object?>{
      'iso_year': info.year,
      'iso_week': info.week,
      'daily_breakdown_json': dailyBreakdown,
      'equivalents_json': jsonEncode(equivalents.toJson()),
      'shared_forest_json': sharedForest,
      'updated_at_ms': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _pruneSnapshots(db);
  }

  Future<({EcoEquivalentsResponse equivalents, int updatedAtMs})?>
  loadEquivalentsSnapshot() async {
    final rows = await _db.database.query(
      'cached_weekly_stats_snapshot',
      orderBy: 'updated_at_ms DESC',
      limit: 6,
    );
    for (final row in rows) {
      final decoded = _decodeMap(row['equivalents_json'] as String?);
      if (decoded == null || decoded.isEmpty) {
        continue;
      }
      if (EcoEquivalentsResponse.fromJson(decoded) case Ok(:final value)) {
        final updatedAtMs = (row['updated_at_ms'] as num?)?.toInt() ?? 0;
        return (equivalents: value, updatedAtMs: updatedAtMs);
      }
    }
    return null;
  }

  Future<void> saveSharedForestSnapshot(
    SharedForestChallengeResponse challenge,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final db = _db.database;
    final existing = await db.query(
      'cached_weekly_stats_snapshot',
      where: 'iso_year = ? AND iso_week = ?',
      whereArgs: [challenge.isoYear, challenge.isoWeek],
      limit: 1,
    );
    final dailyBreakdown = existing.isNotEmpty
        ? (existing.first['daily_breakdown_json'] as String? ?? '{}')
        : '{}';
    final equivalentsJson = existing.isNotEmpty
        ? (existing.first['equivalents_json'] as String? ?? '{}')
        : '{}';

    await db.insert('cached_weekly_stats_snapshot', <String, Object?>{
      'iso_year': challenge.isoYear,
      'iso_week': challenge.isoWeek,
      'daily_breakdown_json': dailyBreakdown,
      'equivalents_json': equivalentsJson,
      'shared_forest_json': jsonEncode(challenge.toJson()),
      'updated_at_ms': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _pruneSnapshots(db);
  }

  Future<({SharedForestChallengeResponse challenge, int updatedAtMs})?>
  loadSharedForestSnapshot() async {
    final rows = await _db.database.query(
      'cached_weekly_stats_snapshot',
      orderBy: 'updated_at_ms DESC',
      limit: 6,
    );
    for (final row in rows) {
      final decoded = _decodeMap(row['shared_forest_json'] as String?);
      if (decoded == null || decoded.isEmpty) {
        continue;
      }
      if (SharedForestChallengeResponse.fromJson(decoded) case Ok(
        :final value,
      )) {
        final updatedAtMs = (row['updated_at_ms'] as num?)?.toInt() ?? 0;
        return (challenge: value, updatedAtMs: updatedAtMs);
      }
    }
    return null;
  }

  Future<void> saveLeaderboard(FriendsLeaderboardResponse board) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final db = _db.database;
    await db.transaction((txn) async {
      for (final entry in board.entries) {
        final existing = await txn.query(
          'cached_friends_leaderboard',
          columns: ['friend_code', 'last_nudge_date'],
          where: 'friend_user_id = ?',
          whereArgs: [entry.userId],
          limit: 1,
        );
        final friendCode = existing.isNotEmpty
            ? (existing.first['friend_code'] as String? ?? '')
            : '';
        final lastNudgeDate = existing.isNotEmpty
            ? existing.first['last_nudge_date'] as String?
            : null;
        await txn.insert('cached_friends_leaderboard', <String, Object?>{
          'friend_user_id': entry.userId,
          'display_name': entry.displayName,
          'avatar_url': entry.avatarUrl,
          'friend_code': friendCode,
          'friendship_status': 'accepted',
          'weekly_co2_saved_grams': entry.weeklyCo2SavedGrams,
          'weekly_steps': entry.weeklySteps,
          'current_streak_days': entry.currentStreakDays,
          'equipped_accessory_code': entry.equippedAccessoryCode,
          'is_stats_visible': entry.isStatsVisible ? 1 : 0,
          'last_nudge_date': lastNudgeDate,
          'updated_at_ms': nowMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.rawDelete('''
        DELETE FROM cached_friends_leaderboard
        WHERE friend_user_id NOT IN (
          SELECT friend_user_id FROM cached_friends_leaderboard
          ORDER BY updated_at_ms DESC LIMIT 500
        )
        ''');
    });
  }

  Future<({FriendsLeaderboardResponse board, int updatedAtMs})?>
  loadLeaderboard() async {
    final db = _db.database;
    final rows = await db.query(
      'cached_friends_leaderboard',
      where: "friendship_status = 'accepted'",
      orderBy: 'weekly_co2_saved_grams DESC',
    );
    if (rows.isEmpty) {
      return null;
    }
    final profileRows = await db.query(
      'local_user_profile',
      columns: ['user_id'],
      limit: 1,
    );
    final myUserId = profileRows.isNotEmpty
        ? profileRows.first['user_id'] as String?
        : null;
    var latestMs = 0;
    final entries = <LeaderboardEntry>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final updatedAtMs = (row['updated_at_ms'] as num?)?.toInt() ?? 0;
      if (updatedAtMs > latestMs) {
        latestMs = updatedAtMs;
      }
      final uid = row['friend_user_id'] as String? ?? '';
      entries.add(
        LeaderboardEntry(
          rank: i + 1,
          userId: uid,
          displayName: row['display_name'] as String? ?? 'Участник',
          avatarUrl: row['avatar_url'] as String?,
          equippedAccessoryCode: row['equipped_accessory_code'] as String?,
          isCurrentUser: myUserId != null && uid == myUserId,
          isStatsVisible: (row['is_stats_visible'] as num?)?.toInt() != 0,
          weeklyCo2SavedGrams:
              (row['weekly_co2_saved_grams'] as num?)?.toInt() ?? 0,
          weeklySteps: (row['weekly_steps'] as num?)?.toInt() ?? 0,
          currentStreakDays: (row['current_streak_days'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    final info = _isoWeekInfo(DateTime.now());
    return (
      board: FriendsLeaderboardResponse(
        isoYear: info.year,
        isoWeek: info.week,
        weekStartDate: info.weekStart,
        weekEndDate: info.weekEnd,
        entries: entries,
      ),
      updatedAtMs: latestMs,
    );
  }

  Future<PaginatedActivityHistoryResponse?> loadLocalHistory({
    required int limit,
    required int offset,
  }) async {
    final db = _db.database;
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM local_daily_step_summaries',
    );
    final totalCount = countRows.isNotEmpty
        ? (countRows.first['cnt'] as num?)?.toInt() ?? 0
        : 0;
    if (totalCount == 0) {
      return null;
    }
    final profileRows = await db.query(
      'local_user_profile',
      columns: ['points_balance'],
      limit: 1,
    );
    final balance = profileRows.isNotEmpty
        ? (profileRows.first['points_balance'] as num?)?.toInt() ?? 0
        : 0;
    final rows = await db.query(
      'local_daily_step_summaries',
      orderBy: 'activity_date DESC',
      limit: limit,
      offset: offset,
    );
    final items = <DailyActivitySummary>[];
    for (final row in rows) {
      if (DailyActivitySummary.fromSqliteRow(row, pointsBalance: balance)
          case Ok(:final value)) {
        items.add(value);
      }
    }
    return PaginatedActivityHistoryResponse(
      totalCount: totalCount,
      limit: limit,
      offset: offset,
      items: items,
    );
  }

  Future<EmissionsStatisticsResponse> enrichWithTransportShares(
    EmissionsStatisticsResponse stats,
  ) async {
    if (stats.transportShares.isNotEmpty ||
        stats.periodTotalCo2SavedGrams == 0) {
      return stats;
    }
    final startDate = stats.buckets.isNotEmpty
        ? stats.buckets.first.startDate
        : _formatIsoDate(DateTime.now().subtract(const Duration(days: 6)));
    final endDate = stats.buckets.isNotEmpty
        ? stats.buckets.last.endDate
        : _formatIsoDate(DateTime.now());

    var allocTotal = 0;
    var autoTotal = 0;
    for (final bucket in stats.buckets) {
      allocTotal += bucket.allocatedCo2SavedGrams;
      autoTotal += bucket.autoDefaultCo2SavedGrams;
    }

    final rows = await _db.database.rawQuery(
      '''
      SELECT replaced_transport_mode, SUM(co2_saved_grams) AS grams
      FROM local_route_segment_allocations
      WHERE activity_date >= ? AND activity_date <= ?
      GROUP BY replaced_transport_mode
      ''',
      [startDate, endDate],
    );

    final shares = _buildTransportShares(
      rows: rows,
      periodTotal: stats.periodTotalCo2SavedGrams,
      allocTotal: allocTotal,
      autoTotal: autoTotal,
    );
    return stats.copyWith(transportShares: shares);
  }

  List<TransportBreakdownShare> _buildTransportShares({
    required List<Map<String, Object?>> rows,
    required int periodTotal,
    required int allocTotal,
    required int autoTotal,
  }) {
    if (periodTotal <= 0) {
      return const [];
    }
    final byGroup = <String, ({String label, int grams})>{};
    var localAllocSum = 0;
    for (final row in rows) {
      final modeRaw = row['replaced_transport_mode'] as String?;
      final grams = (row['grams'] as num?)?.toInt() ?? 0;
      if (modeRaw == null || grams <= 0) {
        continue;
      }
      localAllocSum += grams;
      final group = _mapTransportGroup(modeRaw);
      final prev = byGroup[group.key];
      byGroup[group.key] = (
        label: group.label,
        grams: (prev?.grams ?? 0) + grams,
      );
    }

    final unattributedAlloc = allocTotal - localAllocSum;
    if (unattributedAlloc > 0) {
      final prev = byGroup['gps_allocated'];
      byGroup['gps_allocated'] = (
        label: 'GPS-маршруты',
        grams: (prev?.grams ?? 0) + unattributedAlloc,
      );
    }
    if (autoTotal > 0) {
      byGroup['auto_steps'] = (label: 'Авторасчёт по шагам', grams: autoTotal);
    }

    final totalDenominator = byGroup.values.fold<int>(
      0,
      (sum, item) => sum + item.grams,
    );
    if (totalDenominator <= 0) {
      return const [];
    }

    final shares =
        byGroup.entries
            .map(
              (entry) => TransportBreakdownShare(
                modeCode: entry.key,
                labelRu: entry.value.label,
                co2SavedGrams: entry.value.grams,
                percentage:
                    ((entry.value.grams * 1000) / totalDenominator).round() /
                    10,
              ),
            )
            .toList()
          ..sort((a, b) => b.co2SavedGrams.compareTo(a.co2SavedGrams));
    return shares;
  }

  ({String key, String label}) _mapTransportGroup(String modeRaw) {
    final mode = TransportModeCode.fromWire(modeRaw);
    return switch (mode) {
      TransportModeCode.bus => (key: 'bus', label: 'Автобус'),
      TransportModeCode.metro => (key: 'metro', label: 'Метро'),
      TransportModeCode.tram => (key: 'tram', label: 'Трамвай'),
      TransportModeCode.personalCar => (key: 'personal_car', label: 'Мой авто'),
      TransportModeCode.carCompact ||
      TransportModeCode.carSedan ||
      TransportModeCode.carSuv ||
      TransportModeCode.carEv => (key: 'car_avg', label: 'Авто (средний)'),
    };
  }

  Future<({EmissionsStatisticsResponse stats, int updatedAtMs})?>
  _buildDaysFallbackFromLocalSummaries(Database db) async {
    final rows = await db.query(
      'local_daily_step_summaries',
      orderBy: 'activity_date DESC',
      limit: 7,
    );
    if (rows.isEmpty) {
      return null;
    }
    final byDate = <String, Map<String, Object?>>{
      for (final row in rows)
        if (row['activity_date'] case final String date) date: row,
    };
    final now = DateTime.now();
    final buckets = <EmissionsBucketItem>[];
    var totalCo2 = 0;
    var totalSteps = 0;
    var totalDistanceM = 0.0;
    var latestMs = 0;

    for (var offset = 6; offset >= 0; offset--) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: offset));
      final iso = _formatIsoDate(day);
      final row = byDate[iso];
      final steps = (row?['validated_steps'] as num?)?.toInt() ?? 0;
      final dist = (row?['total_step_distance_m'] as num?)?.toDouble() ?? 0.0;
      final allocCo2 =
          (row?['allocated_co2_saved_grams'] as num?)?.toInt() ?? 0;
      final autoCo2 =
          (row?['auto_default_co2_saved_grams'] as num?)?.toInt() ?? 0;
      final dayTotal = (row?['total_co2_saved_grams'] as num?)?.toInt() ?? 0;
      final sensorMs = (row?['last_sensor_read_at_ms'] as num?)?.toInt() ?? 0;
      if (sensorMs > latestMs) {
        latestMs = sensorMs;
      }
      totalCo2 += dayTotal;
      totalSteps += steps;
      totalDistanceM += dist;
      buckets.add(
        EmissionsBucketItem(
          bucketLabel: '${day.day}',
          startDate: iso,
          endDate: iso,
          validatedSteps: steps,
          totalStepDistanceM: dist,
          allocatedCo2SavedGrams: allocCo2,
          autoDefaultCo2SavedGrams: autoCo2,
          totalCo2SavedGrams: dayTotal,
        ),
      );
    }

    final stats = await enrichWithTransportShares(
      EmissionsStatisticsResponse(
        period: 'days',
        periodTotalCo2SavedGrams: totalCo2,
        periodTotalSteps: totalSteps,
        periodTotalDistanceM: totalDistanceM,
        buckets: buckets,
        equivalents: EcoEquivalentsMetrics(
          totalCo2SavedGrams: totalCo2,
          treesPlantedEquivalent: ((totalCo2 / 20000.0) * 100).round() / 100,
          carKmAvoided: ((totalCo2 / 192.0) * 10).round() / 10,
          smartphoneChargesEquivalent: (totalCo2 / 8.22).floor(),
          plasticBottlesRecycledEquivalent: (totalCo2 / 82.80).floor(),
          ledBulbHoursEquivalent: (totalCo2 / 3.40).floor(),
        ),
      ),
    );
    return (
      stats: stats,
      updatedAtMs: latestMs > 0 ? latestMs : now.millisecondsSinceEpoch,
    );
  }

  Map<String, Object?>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?>? _extractPeriodMap(
    Map<String, Object?> decoded,
    String period,
  ) {
    final periods = decoded['periods'];
    if (periods is Map<String, Object?>) {
      final periodMap = periods[period];
      if (periodMap is Map<String, Object?>) {
        return periodMap;
      }
    }
    if (decoded['period'] == period) {
      return decoded;
    }
    return null;
  }

  Future<void> _pruneSnapshots(Database db) async {
    await db.rawDelete('''
      DELETE FROM cached_weekly_stats_snapshot
      WHERE (iso_year * 100 + iso_week) NOT IN (
        SELECT (iso_year * 100 + iso_week)
        FROM cached_weekly_stats_snapshot
        ORDER BY updated_at_ms DESC
        LIMIT 12
      )
      ''');
  }
}
