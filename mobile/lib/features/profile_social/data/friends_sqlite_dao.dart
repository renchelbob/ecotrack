import 'dart:convert';

import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:sqflite/sqflite.dart';

final class FriendsSqliteDao(final SqliteDatabase _db) {
  static String todayIsoLocal() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  Future<FriendsOverviewResponse?> getCachedOverview(
    String myFriendCode,
  ) async {
    final rows = await _db.database.query(
      'cached_friends_leaderboard',
      orderBy: 'weekly_co2_saved_grams DESC',
    );
    if (rows.isEmpty) {
      return null;
    }
    final today = todayIsoLocal();
    final friends = <FriendProfileSummary>[];
    final incoming = <FriendProfileSummary>[];
    for (final row in rows) {
      final status = FriendshipStatus.fromWire(
        row['friendship_status'] as String?,
      );
      final lastNudge = row['last_nudge_date'] as String?;
      final summary = FriendProfileSummary(
        friendshipId: row['friend_user_id'] as String? ?? '',
        userId: row['friend_user_id'] as String? ?? '',
        displayName: row['display_name'] as String? ?? 'Друг',
        avatarUrl: row['avatar_url'] as String?,
        friendCode: row['friend_code'] as String? ?? 'ECO-0000-0000',
        status: status,
        currentStreakDays: (row['current_streak_days'] as num?)?.toInt() ?? 0,
        equippedAccessoryCode: row['equipped_accessory_code'] as String?,
        isStatsVisibleToFriends: (row['is_stats_visible'] as int? ?? 1) == 1,
        weeklyCo2SavedGrams:
            (row['weekly_co2_saved_grams'] as num?)?.toInt() ?? 0,
        weeklySteps: (row['weekly_steps'] as num?)?.toInt() ?? 0,
        canSendWakeupNudgeToday: lastNudge != today,
      );
      if (status == .accepted) {
        friends.add(summary);
      } else if (status == .pending) {
        incoming.add(summary);
      }
    }
    return FriendsOverviewResponse(
      myFriendCode: myFriendCode,
      friends: friends,
      incomingRequests: incoming,
      outgoingRequests: const [],
    );
  }

  Future<void> replaceCachedFriends(FriendsOverviewResponse overview) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final today = todayIsoLocal();
    await _db.database.transaction((txn) async {
      await txn.delete('cached_friends_leaderboard');
      for (final friend in [
        ...overview.friends,
        ...overview.incomingRequests,
      ]) {
        await txn.insert('cached_friends_leaderboard', {
          'friend_user_id': friend.userId,
          'display_name': friend.displayName,
          'avatar_url': friend.avatarUrl,
          'friend_code': friend.friendCode,
          'friendship_status': friend.status.wireName,
          'weekly_co2_saved_grams': friend.weeklyCo2SavedGrams ?? 0,
          'weekly_steps': friend.weeklySteps ?? 0,
          'current_streak_days': friend.currentStreakDays,
          'equipped_accessory_code': friend.equippedAccessoryCode,
          'is_stats_visible': friend.isStatsVisibleToFriends ? 1 : 0,
          'last_nudge_date': friend.canSendWakeupNudgeToday ? null : today,
          'updated_at_ms': nowMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> markNudgedToday(String friendUserId, String nudgeDate) async {
    await _db.database.update(
      'cached_friends_leaderboard',
      {
        'last_nudge_date': nudgeDate,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'friend_user_id = ?',
      whereArgs: [friendUserId],
    );
  }

  Future<void> removeCachedFriend(String friendUserId) async {
    await _db.database.delete(
      'cached_friends_leaderboard',
      where: 'friend_user_id = ?',
      whereArgs: [friendUserId],
    );
  }

  Future<void> enqueueWakeupNudgeOutbox({
    required String friendUserId,
    required String idempotencyKey,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.database.insert('offline_mutation_outbox', {
      'idempotency_key': idempotencyKey,
      'operation_type': 'send_friend_wakeup_nudge',
      'http_method': 'POST',
      'endpoint_path': '/api/v1/friends/$friendUserId/nudge',
      'payload_json': jsonEncode(<String, Object?>{}),
      'retry_count': 0,
      'max_retries': 12,
      'next_retry_at_ms': nowMs,
      'status': 'pending',
      'created_at_ms': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
