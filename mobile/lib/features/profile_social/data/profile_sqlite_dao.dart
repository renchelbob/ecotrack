import 'dart:convert';

import 'package:ecotrack_mobile/core/database/outbox_dispatcher.dart';
import 'package:ecotrack_mobile/core/database/sqlite_database.dart';
import 'package:ecotrack_mobile/features/profile_social/domain/profile_models.dart';
import 'package:sqflite/sqflite.dart';

final class ProfileSqliteDao(
  final SqliteDatabase _db,
  final OutboxDispatcher _outbox,
) {
  Future<UserProfile?> getCachedProfile({UserVehicle? vehicle}) async {
    final rows = await _db.database.query('local_user_profile', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final accRows = await _db.database.query(
      'cached_badges_and_inventory',
      where: "item_kind = 'accessory' AND is_unlocked = 1",
    );
    final unlocked = accRows.map((r) => r['code']).whereType<String>().toList();
    final equipped = row['equipped_accessory_code'] as String?;
    final mascot = MascotVisualState(
      mood: .sleepy,
      dailyGoalProgressRatio: 0.0,
      equippedAccessoryCode: equipped,
      unlockedAccessoryCodes: unlocked,
    );
    return UserProfile.fromSqliteRow(row, vehicle: vehicle, mascot: mascot);
  }

  Future<void> upsertProfile(
    UserProfile profile, {
    AuthProviderType? authProvider,
    bool? isForeignLabMode,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final resolvedProvider = authProvider ?? profile.authProvider;
    final resolvedLabMode =
        isForeignLabMode ?? profile.isForeignProviderLabMode;

    await _db.database.transaction((txn) async {
      await _upsertProfileTxn(
        txn,
        profile.copyWith(
          authProvider: resolvedProvider,
          isForeignProviderLabMode: resolvedLabMode,
        ),
        nowMs,
      );
      final vehicle = profile.personalVehicle;
      if (vehicle != null) {
        await txn.insert('local_user_vehicle', {
          'id': vehicle.id,
          'user_id': profile.id,
          'vehicle_name': vehicle.vehicleName,
          'fuel': vehicle.fuel.wireName,
          'consumption_per_100km': vehicle.consumptionPer100km,
          'fuel_emission_factor_g_per_unit': vehicle.fuelEmissionFactorGPerUnit,
          'computed_co2_g_per_km': vehicle.computedCo2GPerKm,
          'computed_co2_g_per_meter': vehicle.computedCo2GPerMeter,
          'is_dirty': 0,
          'updated_at_ms': nowMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> updateConsentActive({required bool isActive}) async {
    await _db.database.update('local_user_profile', {
      'is_152fz_consent_active': isActive ? 1 : 0,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateProfileAndEnqueueOutbox({
    required UserProfile optimisticProfile,
    required Map<String, Object?> patchPayload,
    required String idempotencyKey,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.database.transaction(
      (txn) => _upsertProfileTxn(txn, optimisticProfile, nowMs),
    );
    await _outbox.enqueue(
      operationType: 'update_user_settings',
      httpMethod: 'PATCH',
      endpointPath: '/api/v1/users/me',
      payloadJson: jsonEncode(patchPayload),
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> saveEquippedAccessoryAndEnqueueOutbox({
    required UserProfile optimisticProfile,
    required String? accessoryCode,
    required String idempotencyKey,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.database.transaction((txn) async {
      await _upsertProfileTxn(txn, optimisticProfile, nowMs);
      await txn.update('cached_badges_and_inventory', {
        'is_equipped': 0,
        'updated_at_ms': nowMs,
      }, where: "item_kind = 'accessory'");
      if (accessoryCode != null) {
        await txn.update(
          'cached_badges_and_inventory',
          {'is_equipped': 1, 'updated_at_ms': nowMs},
          where: "item_kind = 'accessory' AND code = ?",
          whereArgs: [accessoryCode],
        );
      }
    });
    await _outbox.enqueue(
      operationType: 'equip_mascot_accessory',
      httpMethod: 'PUT',
      endpointPath: '/api/v1/users/me/mascot/accessory',
      payloadJson: jsonEncode({'accessory_code': accessoryCode}),
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> cacheBadges(BadgesListResponse badges) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.database.transaction((txn) async {
      await txn.delete(
        'cached_badges_and_inventory',
        where: "item_kind = 'badge'",
      );
      for (final item in badges.badges) {
        final slotPayload = jsonEncode({
          'threshold_type': item.thresholdType,
          'reward_points': item.rewardPoints,
          if (item.rewardAccessoryCode != null)
            'reward_accessory_code': item.rewardAccessoryCode,
          if (item.awardedAt != null) 'awarded_at': item.awardedAt,
        });
        await txn.insert('cached_badges_and_inventory', {
          'item_kind': 'badge',
          'code': item.code,
          'title_ru': item.titleRu,
          'description_ru': item.descriptionRu,
          'icon_or_layer_key': item.iconVectorKey,
          'slot': slotPayload,
          'is_unlocked': item.isUnlocked ? 1 : 0,
          'is_equipped': 0,
          'progress_value': item.currentValue,
          'threshold_value': item.thresholdValue,
          'updated_at_ms': nowMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<BadgesListResponse?> getCachedBadges() async {
    final rows = await _db.database.query(
      'cached_badges_and_inventory',
      where: "item_kind = 'badge'",
    );
    if (rows.isEmpty) {
      return null;
    }
    final items = rows.map((r) {
      final meta = _parseBadgeSlotMetadata(r['slot'] as String?);
      return BadgeCatalogProgressItem(
        code: r['code'] as String? ?? '',
        titleRu: r['title_ru'] as String? ?? '',
        descriptionRu: r['description_ru'] as String? ?? '',
        iconVectorKey: r['icon_or_layer_key'] as String? ?? '',
        thresholdType: meta.thresholdType,
        thresholdValue: (r['threshold_value'] as num?)?.toInt() ?? 1,
        currentValue: (r['progress_value'] as num?)?.toInt() ?? 0,
        rewardPoints: meta.rewardPoints,
        rewardAccessoryCode: meta.rewardAccessoryCode,
        awardedAt: meta.awardedAt,
        isUnlocked: (r['is_unlocked'] as int? ?? 0) == 1,
      );
    }).toList();
    final unlocked = items.where((b) => b.isUnlocked).length;
    return BadgesListResponse(
      unlockedCount: unlocked,
      totalCount: items.length,
      badges: items,
    );
  }

  ({
    String thresholdType,
    int rewardPoints,
    String? rewardAccessoryCode,
    String? awardedAt,
  })
  _parseBadgeSlotMetadata(String? rawSlot) {
    if (rawSlot == null || rawSlot.isEmpty) {
      return (
        thresholdType: 'steps_total',
        rewardPoints: 0,
        rewardAccessoryCode: null,
        awardedAt: null,
      );
    }
    if (!rawSlot.startsWith('{')) {
      return (
        thresholdType: rawSlot,
        rewardPoints: 0,
        rewardAccessoryCode: null,
        awardedAt: null,
      );
    }
    try {
      final decoded = jsonDecode(rawSlot);
      if (decoded is Map<Object?, Object?>) {
        return (
          thresholdType: decoded['threshold_type'] as String? ?? 'steps_total',
          rewardPoints: (decoded['reward_points'] as num?)?.toInt() ?? 0,
          rewardAccessoryCode: decoded['reward_accessory_code'] as String?,
          awardedAt: decoded['awarded_at'] as String?,
        );
      }
    } on FormatException {
      return (
        thresholdType: 'steps_total',
        rewardPoints: 0,
        rewardAccessoryCode: null,
        awardedAt: null,
      );
    }
    return (
      thresholdType: 'steps_total',
      rewardPoints: 0,
      rewardAccessoryCode: null,
      awardedAt: null,
    );
  }

  Future<void> cacheAccessories(MascotInventoryResponse inventory) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.database.transaction((txn) async {
      await txn.delete(
        'cached_badges_and_inventory',
        where: "item_kind = 'accessory'",
      );
      for (final item in inventory.accessories) {
        await txn.insert('cached_badges_and_inventory', {
          'item_kind': 'accessory',
          'code': item.code,
          'title_ru': item.nameRu,
          'description_ru': item.unlockType,
          'icon_or_layer_key': item.vectorLayerKey,
          'slot': item.slot,
          'is_unlocked': item.isUnlocked ? 1 : 0,
          'is_equipped': item.isEquipped ? 1 : 0,
          'progress_value': item.isUnlocked ? 1 : 0,
          'threshold_value': 1,
          'updated_at_ms': nowMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<MascotInventoryResponse?> getCachedAccessories() async {
    final rows = await _db.database.query(
      'cached_badges_and_inventory',
      where: "item_kind = 'accessory'",
    );
    if (rows.isEmpty) {
      return null;
    }
    final items = rows
        .map(
          (r) => MascotAccessoryItem(
            code: r['code'] as String? ?? '',
            nameRu: r['title_ru'] as String? ?? '',
            slot: r['slot'] as String? ?? 'head',
            vectorLayerKey: r['icon_or_layer_key'] as String? ?? '',
            unlockType: r['description_ru'] as String? ?? 'shop',
            isUnlocked: (r['is_unlocked'] as int? ?? 0) == 1,
            isEquipped: (r['is_equipped'] as int? ?? 0) == 1,
          ),
        )
        .toList();
    return MascotInventoryResponse(accessories: items);
  }

  Future<void> _upsertProfileTxn(
    DatabaseExecutor txn,
    UserProfile profile,
    int nowMs,
  ) async {
    await txn.insert('local_user_profile', {
      'user_id': profile.id,
      'email': profile.email,
      'display_name': profile.displayName,
      'avatar_url': profile.avatarUrl,
      'friend_code': profile.friendCode,
      'auth_provider': profile.authProvider.wireName,
      'is_foreign_provider_lab_mode': profile.isForeignProviderLabMode ? 1 : 0,
      'formal_phone_e164': profile.formalPhoneE164,
      'requires_formal_phone': profile.requiresFormalPhone ? 1 : 0,
      'points_balance': profile.pointsBalance,
      'lifetime_points_earned': profile.lifetimePointsEarned,
      'lifetime_co2_saved_grams': profile.lifetimeCo2SavedGrams,
      'current_streak_days': profile.currentStreakDays,
      'longest_streak_days': profile.longestStreakDays,
      'streak_freeze_count': profile.streakFreezeCount,
      'last_active_local_date': profile.lastActiveLocalDate,
      'daily_step_goal': profile.dailyStepGoal,
      'daily_co2_goal_grams': profile.dailyCo2GoalGrams,
      'stride_length_cm': profile.strideLengthCm,
      'gps_interval_seconds': profile.gpsIntervalSeconds,
      'is_gps_tracking_enabled': profile.isGpsTrackingEnabled ? 1 : 0,
      'is_stats_visible_to_friends': profile.isStatsVisibleToFriends ? 1 : 0,
      'is_152fz_consent_active': profile.is152fzConsentActive ? 1 : 0,
      'equipped_accessory_code': profile.mascot.equippedAccessoryCode,
      'updated_at_ms': nowMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
