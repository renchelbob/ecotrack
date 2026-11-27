import 'package:ecotrack_mobile/core/error/app_error.dart';
import 'package:ecotrack_mobile/core/error/result.dart';
import 'package:ecotrack_mobile/features/map_activity/domain/map_models.dart';

enum AuthProviderType(final String wireName, final String displayNameRu) {
  yandex('yandex', 'Яндекс ID'),
  vk('vk', 'VK ID'),
  google('google', 'Google · Лаб. режим');

  static AuthProviderType fromWire(String? raw) => switch (raw) {
    'vk' => .vk,
    'google' => .google,
    _ => .yandex,
  };
}

enum FuelType(
  final String wireName,
  final String displayNameRu,
  final double emissionFactorGPerUnit,
  final String consumptionUnitRu,
) {
  petrol92('petrol_92', 'Бензин АИ-92', 2310.0, 'л/100 км'),
  petrol95('petrol_95', 'Бензин АИ-95', 2330.0, 'л/100 км'),
  petrol98('petrol_98', 'Бензин АИ-98', 2350.0, 'л/100 км'),
  diesel('diesel', 'Дизель (ДТ)', 2680.0, 'л/100 км'),
  lpg('lpg', 'Газ Пропан (LPG)', 1660.0, 'л/100 км'),
  cng('cng', 'Газ Метан (CNG)', 1960.0, 'м³/100 км'),
  hybrid('hybrid', 'Гибрид', 2310.0, 'л/100 км'),
  electric('electric', 'Электромобиль (кВт·ч)', 340.0, 'кВт·ч/100 км');

  static FuelType fromWire(String? raw) => switch (raw) {
    'petrol_92' => .petrol92,
    'petrol_95' => .petrol95,
    'petrol_98' => .petrol98,
    'diesel' => .diesel,
    'lpg' => .lpg,
    'cng' => .cng,
    'hybrid' => .hybrid,
    'electric' => .electric,
    _ => .petrol95,
  };
}

enum MascotMoodState(final String wireName) {
  sleepy('sleepy'),
  neutral('neutral'),
  happy('happy'),
  thriving('thriving'),
  squinting('squinting');

  static MascotMoodState fromWire(String? raw) => switch (raw) {
    'sleepy' => .sleepy,
    'neutral' => .neutral,
    'happy' => .happy,
    'thriving' => .thriving,
    'squinting' => .squinting,
    _ => .sleepy,
  };
}

enum FriendshipStatus(final String wireName) {
  pending('pending'),
  accepted('accepted'),
  blocked('blocked');

  static FriendshipStatus fromWire(String? raw) => switch (raw) {
    'accepted' => .accepted,
    'blocked' => .blocked,
    _ => .pending,
  };
}

final class const MascotVisualState({
  required final MascotMoodState mood,
  required final double dailyGoalProgressRatio,
  final String? equippedAccessoryCode,
  final List<String> unlockedAccessoryCodes = const [],
}) {
  factory initial() =>
      const MascotVisualState(mood: .sleepy, dailyGoalProgressRatio: 0.0);

  static Result<MascotVisualState, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'mood': final String moodRaw,
      'daily_goal_progress_ratio': final num ratio,
      'unlocked_accessory_codes': final List<Object?> unlockedRaw,
    }) {
      return Ok(
        MascotVisualState(
          mood: .fromWire(moodRaw),
          dailyGoalProgressRatio: ratio.toDouble(),
          equippedAccessoryCode: json['equipped_accessory_code'] as String?,
          unlockedAccessoryCodes: unlockedRaw.whereType<String>().toList(),
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'mood': mood.wireName,
    'daily_goal_progress_ratio': dailyGoalProgressRatio,
    'equipped_accessory_code': equippedAccessoryCode,
    'unlocked_accessory_codes': unlockedAccessoryCodes,
  };

  MascotVisualState copyWith({
    MascotMoodState? mood,
    double? dailyGoalProgressRatio,
    String? equippedAccessoryCode,
    bool clearEquippedAccessory = false,
    List<String>? unlockedAccessoryCodes,
  }) => MascotVisualState(
    mood: mood ?? this.mood,
    dailyGoalProgressRatio:
        dailyGoalProgressRatio ?? this.dailyGoalProgressRatio,
    equippedAccessoryCode: clearEquippedAccessory
        ? null
        : (equippedAccessoryCode ?? this.equippedAccessoryCode),
    unlockedAccessoryCodes:
        unlockedAccessoryCodes ?? this.unlockedAccessoryCodes,
  );
}

final class const UserVehicle({
  required final String id,
  required final String vehicleName,
  required final FuelType fuel,
  required final double consumptionPer100km,
  required final double fuelEmissionFactorGPerUnit,
  required final double computedCo2GPerKm,
  required final double computedCo2GPerMeter,
  required final String updatedAt,
}) {
  factory fromSqliteRow(Map<String, Object?> row) {
    final updatedMs = (row['updated_at_ms'] as num?)?.toInt() ?? 0;
    return UserVehicle(
      id: row['id'] as String? ?? '',
      vehicleName: row['vehicle_name'] as String? ?? 'Мой автомобиль',
      fuel: .fromWire(row['fuel'] as String?),
      consumptionPer100km:
          (row['consumption_per_100km'] as num?)?.toDouble() ?? 8.5,
      fuelEmissionFactorGPerUnit:
          (row['fuel_emission_factor_g_per_unit'] as num?)?.toDouble() ??
          2330.0,
      computedCo2GPerKm:
          (row['computed_co2_g_per_km'] as num?)?.toDouble() ?? 198.05,
      computedCo2GPerMeter:
          (row['computed_co2_g_per_meter'] as num?)?.toDouble() ?? 0.19805,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        updatedMs,
        isUtc: true,
      ).toIso8601String(),
    );
  }

  static Result<UserVehicle, AppError> fromJson(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'vehicle_name': final String name,
      'fuel': final String fuelRaw,
      'consumption_per_100km': final num consumption,
      'fuel_emission_factor_g_per_unit': final num factor,
      'computed_co2_g_per_km': final num gPerKm,
      'computed_co2_g_per_meter': final num gPerMeter,
      'updated_at': final String updatedAt,
    }) {
      return Ok(
        UserVehicle(
          id: id,
          vehicleName: name,
          fuel: .fromWire(fuelRaw),
          consumptionPer100km: consumption.toDouble(),
          fuelEmissionFactorGPerUnit: factor.toDouble(),
          computedCo2GPerKm: gPerKm.toDouble(),
          computedCo2GPerMeter: gPerMeter.toDouble(),
          updatedAt: updatedAt,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'vehicle_name': vehicleName,
    'fuel': fuel.wireName,
    'consumption_per_100km': consumptionPer100km,
    'fuel_emission_factor_g_per_unit': fuelEmissionFactorGPerUnit,
    'computed_co2_g_per_km': computedCo2GPerKm,
    'computed_co2_g_per_meter': computedCo2GPerMeter,
    'updated_at': updatedAt,
  };
}

final class const UserProfile({
  required final String id,
  required final String displayName,
  required final String friendCode,
  required final bool requiresFormalPhone,
  required final int pointsBalance,
  required final int lifetimePointsEarned,
  required final int lifetimeCo2SavedGrams,
  required final int currentStreakDays,
  required final int longestStreakDays,
  required final int streakFreezeCount,
  required final bool isGpsTrackingEnabled,
  required final bool isStatsVisibleToFriends,
  required final bool is152fzConsentActive,
  required final MascotVisualState mascot,
  required final String createdAt,
  final String? email,
  final String? avatarUrl,
  final String? formalPhoneE164,
  final String? lastActiveLocalDate,
  final int dailyStepGoal = 8000,
  final int dailyCo2GoalGrams = 1000,
  final int strideLengthCm = 74,
  final int gpsIntervalSeconds = 15,
  final UserVehicle? personalVehicle,
  final AuthProviderType authProvider = .yandex,
  final bool isForeignProviderLabMode = false,
}) {
  factory fromSqliteRow(
    Map<String, Object?> row, {
    UserVehicle? vehicle,
    MascotVisualState? mascot,
  }) {
    final updatedMs = (row['updated_at_ms'] as num?)?.toInt() ?? 0;
    final equipped = row['equipped_accessory_code'] as String?;
    final resolvedMascot =
        mascot ??
        MascotVisualState(
          mood: .sleepy,
          dailyGoalProgressRatio: 0.0,
          equippedAccessoryCode: equipped,
        );
    return UserProfile(
      id: row['user_id'] as String? ?? '',
      email: row['email'] as String?,
      displayName: row['display_name'] as String? ?? 'Пользователь',
      avatarUrl: row['avatar_url'] as String?,
      friendCode: row['friend_code'] as String? ?? 'ECO-0000-0000',
      formalPhoneE164: row['formal_phone_e164'] as String?,
      requiresFormalPhone: (row['requires_formal_phone'] as int? ?? 0) == 1,
      pointsBalance: (row['points_balance'] as num?)?.toInt() ?? 0,
      lifetimePointsEarned:
          (row['lifetime_points_earned'] as num?)?.toInt() ?? 0,
      lifetimeCo2SavedGrams:
          (row['lifetime_co2_saved_grams'] as num?)?.toInt() ?? 0,
      currentStreakDays: (row['current_streak_days'] as num?)?.toInt() ?? 0,
      longestStreakDays: (row['longest_streak_days'] as num?)?.toInt() ?? 0,
      streakFreezeCount: (row['streak_freeze_count'] as num?)?.toInt() ?? 0,
      lastActiveLocalDate: row['last_active_local_date'] as String?,
      dailyStepGoal: (row['daily_step_goal'] as num?)?.toInt() ?? 8000,
      dailyCo2GoalGrams: (row['daily_co2_goal_grams'] as num?)?.toInt() ?? 1000,
      strideLengthCm: (row['stride_length_cm'] as num?)?.toInt() ?? 74,
      gpsIntervalSeconds: (row['gps_interval_seconds'] as num?)?.toInt() ?? 15,
      isGpsTrackingEnabled: (row['is_gps_tracking_enabled'] as int? ?? 0) == 1,
      isStatsVisibleToFriends:
          (row['is_stats_visible_to_friends'] as int? ?? 1) == 1,
      is152fzConsentActive: (row['is_152fz_consent_active'] as int? ?? 1) == 1,
      mascot: resolvedMascot,
      personalVehicle: vehicle,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        updatedMs,
        isUtc: true,
      ).toIso8601String(),
      authProvider: .fromWire(row['auth_provider'] as String?),
      isForeignProviderLabMode:
          (row['is_foreign_provider_lab_mode'] as int? ?? 0) == 1,
    );
  }

  static final Object _invalidVehicleMarker = Object();

  static Result<UserProfile, AppError> fromJson(
    Map<String, Object?> json, {
    AuthProviderType? authProviderOverride,
    bool? isForeignLabModeOverride,
  }) {
    final core = _parseCoreIdentity(json);
    final stats = _parseStats(json);
    final prefs = _parsePrefs(json);
    final mascotRaw = json['mascot'];
    if (core == null ||
        stats == null ||
        prefs == null ||
        mascotRaw is! Map<String, Object?>) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    final mascotRes = MascotVisualState.fromJson(mascotRaw);
    if (mascotRes case Err(:final error)) {
      return Err(error);
    }
    final vehicle = _parseOptionalVehicle(json['personal_vehicle']);
    if (vehicle == _invalidVehicleMarker) {
      return Err(AppError.fromCode('VALIDATION_ERROR'));
    }
    return Ok(
      UserProfile(
        id: core.id,
        email: core.email,
        displayName: core.displayName,
        avatarUrl: core.avatarUrl,
        friendCode: core.friendCode,
        formalPhoneE164: core.formalPhoneE164,
        requiresFormalPhone: core.requiresFormalPhone,
        pointsBalance: stats.pointsBalance,
        lifetimePointsEarned: stats.lifetimePointsEarned,
        lifetimeCo2SavedGrams: stats.lifetimeCo2SavedGrams,
        currentStreakDays: stats.currentStreakDays,
        longestStreakDays: stats.longestStreakDays,
        streakFreezeCount: stats.streakFreezeCount,
        lastActiveLocalDate: stats.lastActiveLocalDate,
        dailyStepGoal: prefs.dailyStepGoal,
        dailyCo2GoalGrams: prefs.dailyCo2GoalGrams,
        strideLengthCm: prefs.strideLengthCm,
        gpsIntervalSeconds: prefs.gpsIntervalSeconds,
        isGpsTrackingEnabled: prefs.isGpsTrackingEnabled,
        isStatsVisibleToFriends: prefs.isStatsVisibleToFriends,
        is152fzConsentActive: prefs.is152fzConsentActive,
        mascot: switch (mascotRes) {
          Ok(:final value) => value,
          Err() => MascotVisualState.initial(),
        },
        personalVehicle: vehicle is UserVehicle ? vehicle : null,
        createdAt: core.createdAt,
        authProvider:
            authProviderOverride ?? .fromWire(json['auth_provider'] as String?),
        isForeignProviderLabMode:
            isForeignLabModeOverride ??
            (json['is_foreign_provider_lab_mode'] as bool? ?? false),
      ),
    );
  }

  static Object? _parseOptionalVehicle(Object? rawVehicle) {
    if (rawVehicle == null) {
      return null;
    }
    if (rawVehicle is! Map<String, Object?>) {
      return _invalidVehicleMarker;
    }
    return switch (UserVehicle.fromJson(rawVehicle)) {
      Ok(:final value) => value,
      Err() => _invalidVehicleMarker,
    };
  }

  static ({
    String id,
    String? email,
    String displayName,
    String? avatarUrl,
    String friendCode,
    String? formalPhoneE164,
    bool requiresFormalPhone,
    String createdAt,
  })?
  _parseCoreIdentity(Map<String, Object?> json) {
    if (json case {
      'id': final String id,
      'display_name': final String displayName,
      'friend_code': final String friendCode,
      'requires_formal_phone': final bool requiresFormalPhone,
      'created_at': final String createdAt,
    }) {
      return (
        id: id,
        email: json['email'] as String?,
        displayName: displayName,
        avatarUrl: json['avatar_url'] as String?,
        friendCode: friendCode,
        formalPhoneE164: json['formal_phone_e164'] as String?,
        requiresFormalPhone: requiresFormalPhone,
        createdAt: createdAt,
      );
    }
    return null;
  }

  static ({
    int pointsBalance,
    int lifetimePointsEarned,
    int lifetimeCo2SavedGrams,
    int currentStreakDays,
    int longestStreakDays,
    int streakFreezeCount,
    String? lastActiveLocalDate,
  })?
  _parseStats(Map<String, Object?> json) {
    if (json case {
      'points_balance': final int pointsBalance,
      'lifetime_points_earned': final int lifetimePointsEarned,
      'lifetime_co2_saved_grams': final int lifetimeCo2SavedGrams,
      'current_streak_days': final int currentStreakDays,
      'longest_streak_days': final int longestStreakDays,
      'streak_freeze_count': final int streakFreezeCount,
    }) {
      return (
        pointsBalance: pointsBalance,
        lifetimePointsEarned: lifetimePointsEarned,
        lifetimeCo2SavedGrams: lifetimeCo2SavedGrams,
        currentStreakDays: currentStreakDays,
        longestStreakDays: longestStreakDays,
        streakFreezeCount: streakFreezeCount,
        lastActiveLocalDate: json['last_active_local_date'] as String?,
      );
    }
    return null;
  }

  static ({
    int dailyStepGoal,
    int dailyCo2GoalGrams,
    int strideLengthCm,
    int gpsIntervalSeconds,
    bool isGpsTrackingEnabled,
    bool isStatsVisibleToFriends,
    bool is152fzConsentActive,
  })?
  _parsePrefs(Map<String, Object?> json) {
    if (json case {
      'is_gps_tracking_enabled': final bool isGps,
      'is_stats_visible_to_friends': final bool isStatsVisible,
      'is_152fz_consent_active': final bool isConsentActive,
    }) {
      return (
        dailyStepGoal: (json['daily_step_goal'] as num?)?.toInt() ?? 8000,
        dailyCo2GoalGrams:
            (json['daily_co2_goal_grams'] as num?)?.toInt() ?? 1000,
        strideLengthCm: (json['stride_length_cm'] as num?)?.toInt() ?? 74,
        gpsIntervalSeconds:
            (json['gps_interval_seconds'] as num?)?.toInt() ?? 15,
        isGpsTrackingEnabled: isGps,
        isStatsVisibleToFriends: isStatsVisible,
        is152fzConsentActive: isConsentActive,
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'friend_code': friendCode,
    'formal_phone_e164': formalPhoneE164,
    'requires_formal_phone': requiresFormalPhone,
    'points_balance': pointsBalance,
    'lifetime_points_earned': lifetimePointsEarned,
    'lifetime_co2_saved_grams': lifetimeCo2SavedGrams,
    'current_streak_days': currentStreakDays,
    'longest_streak_days': longestStreakDays,
    'streak_freeze_count': streakFreezeCount,
    'last_active_local_date': lastActiveLocalDate,
    'daily_step_goal': dailyStepGoal,
    'daily_co2_goal_grams': dailyCo2GoalGrams,
    'stride_length_cm': strideLengthCm,
    'gps_interval_seconds': gpsIntervalSeconds,
    'is_gps_tracking_enabled': isGpsTrackingEnabled,
    'is_stats_visible_to_friends': isStatsVisibleToFriends,
    'is_152fz_consent_active': is152fzConsentActive,
    'mascot': mascot.toJson(),
    'personal_vehicle': personalVehicle?.toJson(),
    'created_at': createdAt,
    'auth_provider': authProvider.wireName,
    'is_foreign_provider_lab_mode': isForeignProviderLabMode,
  };

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? formalPhoneE164,
    bool? requiresFormalPhone,
    int? pointsBalance,
    int? lifetimePointsEarned,
    int? lifetimeCo2SavedGrams,
    int? currentStreakDays,
    int? longestStreakDays,
    int? streakFreezeCount,
    String? lastActiveLocalDate,
    int? dailyStepGoal,
    int? dailyCo2GoalGrams,
    int? strideLengthCm,
    int? gpsIntervalSeconds,
    bool? isGpsTrackingEnabled,
    bool? isStatsVisibleToFriends,
    bool? is152fzConsentActive,
    MascotVisualState? mascot,
    UserVehicle? personalVehicle,
    bool clearPersonalVehicle = false,
    AuthProviderType? authProvider,
    bool? isForeignProviderLabMode,
  }) => UserProfile(
    id: id,
    email: email,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    friendCode: friendCode,
    formalPhoneE164: formalPhoneE164 ?? this.formalPhoneE164,
    requiresFormalPhone: requiresFormalPhone ?? this.requiresFormalPhone,
    pointsBalance: pointsBalance ?? this.pointsBalance,
    lifetimePointsEarned: lifetimePointsEarned ?? this.lifetimePointsEarned,
    lifetimeCo2SavedGrams: lifetimeCo2SavedGrams ?? this.lifetimeCo2SavedGrams,
    currentStreakDays: currentStreakDays ?? this.currentStreakDays,
    longestStreakDays: longestStreakDays ?? this.longestStreakDays,
    streakFreezeCount: streakFreezeCount ?? this.streakFreezeCount,
    lastActiveLocalDate: lastActiveLocalDate ?? this.lastActiveLocalDate,
    dailyStepGoal: dailyStepGoal ?? this.dailyStepGoal,
    dailyCo2GoalGrams: dailyCo2GoalGrams ?? this.dailyCo2GoalGrams,
    strideLengthCm: strideLengthCm ?? this.strideLengthCm,
    gpsIntervalSeconds: gpsIntervalSeconds ?? this.gpsIntervalSeconds,
    isGpsTrackingEnabled: isGpsTrackingEnabled ?? this.isGpsTrackingEnabled,
    isStatsVisibleToFriends:
        isStatsVisibleToFriends ?? this.isStatsVisibleToFriends,
    is152fzConsentActive: is152fzConsentActive ?? this.is152fzConsentActive,
    mascot: mascot ?? this.mascot,
    personalVehicle: clearPersonalVehicle
        ? null
        : (personalVehicle ?? this.personalVehicle),
    createdAt: createdAt,
    authProvider: authProvider ?? this.authProvider,
    isForeignProviderLabMode:
        isForeignProviderLabMode ?? this.isForeignProviderLabMode,
  );
}

final class const UpdateUserProfileRequest({
  final String? displayName,
  final String? avatarUrl,
  final int? dailyStepGoal,
  final int? dailyCo2GoalGrams,
  final int? strideLengthCm,
  final int? gpsIntervalSeconds,
  final bool? isGpsTrackingEnabled,
  final bool? isStatsVisibleToFriends,
}) {
  Map<String, Object?> toJson() => {
    if (displayName != null) 'display_name': displayName,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    if (dailyStepGoal != null) 'daily_step_goal': dailyStepGoal,
    if (dailyCo2GoalGrams != null) 'daily_co2_goal_grams': dailyCo2GoalGrams,
    if (strideLengthCm != null) 'stride_length_cm': strideLengthCm,
    if (gpsIntervalSeconds != null) 'gps_interval_seconds': gpsIntervalSeconds,
    if (isGpsTrackingEnabled != null)
      'is_gps_tracking_enabled': isGpsTrackingEnabled,
    if (isStatsVisibleToFriends != null)
      'is_stats_visible_to_friends': isStatsVisibleToFriends,
  };
}

final class const TransportPresetItem({
  required final TransportModeCode modeCode,
  required final String displayNameRu,
  required final String displayNameEn,
  required final double co2GramsPerKm,
  required final double co2GramsPerMeter,
  required final bool isPersonalVehicleSlot,
}) {
  factory fromSqliteRow(Map<String, Object?> row) => TransportPresetItem(
    modeCode: .fromWire(row['mode_code'] as String?),
    displayNameRu: row['display_name_ru'] as String? ?? '',
    displayNameEn: row['display_name_en'] as String? ?? '',
    co2GramsPerKm: (row['co2_grams_per_km'] as num?)?.toDouble() ?? 82.0,
    co2GramsPerMeter: (row['co2_grams_per_meter'] as num?)?.toDouble() ?? 0.082,
    isPersonalVehicleSlot: (row['is_personal_vehicle_slot'] as int? ?? 0) == 1,
  );

  static Result<TransportPresetItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'mode_code': final String codeRaw,
      'display_name_ru': final String nameRu,
      'display_name_en': final String nameEn,
      'co2_grams_per_km': final num gPerKm,
      'co2_grams_per_meter': final num gPerM,
      'is_personal_vehicle_slot': final bool isPersonal,
    }) {
      return Ok(
        TransportPresetItem(
          modeCode: .fromWire(codeRaw),
          displayNameRu: nameRu,
          displayNameEn: nameEn,
          co2GramsPerKm: gPerKm.toDouble(),
          co2GramsPerMeter: gPerM.toDouble(),
          isPersonalVehicleSlot: isPersonal,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'mode_code': modeCode.wireName,
    'display_name_ru': displayNameRu,
    'display_name_en': displayNameEn,
    'co2_grams_per_km': co2GramsPerKm,
    'co2_grams_per_meter': co2GramsPerMeter,
    'is_personal_vehicle_slot': isPersonalVehicleSlot,
  };
}

final class const BadgeCatalogProgressItem({
  required final String code,
  required final String titleRu,
  required final String descriptionRu,
  required final String iconVectorKey,
  required final String thresholdType,
  required final int thresholdValue,
  required final int currentValue,
  required final int rewardPoints,
  required final bool isUnlocked,
  final String? rewardAccessoryCode,
  final String? awardedAt,
}) {
  static Result<BadgeCatalogProgressItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'code': final String code,
      'title_ru': final String titleRu,
      'description_ru': final String descriptionRu,
      'icon_vector_key': final String iconKey,
      'threshold_type': final String thresholdType,
      'threshold_value': final int thresholdValue,
      'current_value': final int currentValue,
      'reward_points': final int rewardPoints,
      'is_unlocked': final bool isUnlocked,
    }) {
      return Ok(
        BadgeCatalogProgressItem(
          code: code,
          titleRu: titleRu,
          descriptionRu: descriptionRu,
          iconVectorKey: iconKey,
          thresholdType: thresholdType,
          thresholdValue: thresholdValue,
          currentValue: currentValue,
          rewardPoints: rewardPoints,
          rewardAccessoryCode: json['reward_accessory_code'] as String?,
          isUnlocked: isUnlocked,
          awardedAt: json['awarded_at'] as String?,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'code': code,
    'title_ru': titleRu,
    'description_ru': descriptionRu,
    'icon_vector_key': iconVectorKey,
    'threshold_type': thresholdType,
    'threshold_value': thresholdValue,
    'current_value': currentValue,
    'reward_points': rewardPoints,
    'reward_accessory_code': rewardAccessoryCode,
    'is_unlocked': isUnlocked,
    'awarded_at': awardedAt,
  };
}

final class const BadgesListResponse({
  required final int unlockedCount,
  required final int totalCount,
  required final List<BadgeCatalogProgressItem> badges,
}) {
  static Result<BadgesListResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'unlocked_count': final int unlockedCount,
      'total_count': final int totalCount,
      'badges': final List<Object?> rawBadges,
    }) {
      final parsed = <BadgeCatalogProgressItem>[];
      for (final item in rawBadges) {
        if (item is Map<String, Object?>) {
          if (BadgeCatalogProgressItem.fromJson(item) case Ok(:final value)) {
            parsed.add(value);
          }
        }
      }
      return Ok(
        BadgesListResponse(
          unlockedCount: unlockedCount,
          totalCount: totalCount,
          badges: parsed,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'unlocked_count': unlockedCount,
    'total_count': totalCount,
    'badges': badges.map((b) => b.toJson()).toList(),
  };
}

final class const MascotAccessoryItem({
  required final String code,
  required final String nameRu,
  required final String slot,
  required final String vectorLayerKey,
  required final String unlockType,
  required final bool isUnlocked,
  required final bool isEquipped,
  final String? acquiredAt,
}) {
  static Result<MascotAccessoryItem, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'code': final String code,
      'name_ru': final String nameRu,
      'slot': final String slot,
      'vector_layer_key': final String layerKey,
      'unlock_type': final String unlockType,
      'is_unlocked': final bool isUnlocked,
      'is_equipped': final bool isEquipped,
    }) {
      return Ok(
        MascotAccessoryItem(
          code: code,
          nameRu: nameRu,
          slot: slot,
          vectorLayerKey: layerKey,
          unlockType: unlockType,
          isUnlocked: isUnlocked,
          isEquipped: isEquipped,
          acquiredAt: json['acquired_at'] as String?,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'code': code,
    'name_ru': nameRu,
    'slot': slot,
    'vector_layer_key': vectorLayerKey,
    'unlock_type': unlockType,
    'is_unlocked': isUnlocked,
    'is_equipped': isEquipped,
    'acquired_at': acquiredAt,
  };
}

final class const MascotInventoryResponse({
  required final List<MascotAccessoryItem> accessories,
}) {
  static Result<MascotInventoryResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {'accessories': final List<Object?> rawAccessories}) {
      final parsed = <MascotAccessoryItem>[];
      for (final item in rawAccessories) {
        if (item is Map<String, Object?>) {
          if (MascotAccessoryItem.fromJson(item) case Ok(:final value)) {
            parsed.add(value);
          }
        }
      }
      return Ok(MascotInventoryResponse(accessories: parsed));
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'accessories': accessories.map((a) => a.toJson()).toList(),
  };
}

final class const AccountDeletionReceipt({
  required final String receiptId,
  required final String anonymizedUserHash,
  required final String purgedAt,
  required final String verificationSignature,
}) {
  static Result<AccountDeletionReceipt, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'receipt_id': final String receiptId,
      'anonymized_user_hash': final String hash,
      'purged_at': final String purgedAt,
      'verification_signature': final String signature,
    }) {
      return Ok(
        AccountDeletionReceipt(
          receiptId: receiptId,
          anonymizedUserHash: hash,
          purgedAt: purgedAt,
          verificationSignature: signature,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'receipt_id': receiptId,
    'anonymized_user_hash': anonymizedUserHash,
    'purged_at': purgedAt,
    'verification_signature': verificationSignature,
  };
}

final class const FriendProfileSummary({
  required final String friendshipId,
  required final String userId,
  required final String displayName,
  required final String friendCode,
  required final FriendshipStatus status,
  required final int currentStreakDays,
  required final bool isStatsVisibleToFriends,
  required final bool canSendWakeupNudgeToday,
  final String? avatarUrl,
  final String? equippedAccessoryCode,
  final int? weeklyCo2SavedGrams,
  final int? weeklySteps,
}) {
  static Result<FriendProfileSummary, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'friendship_id': final String friendshipId,
      'user_id': final String userId,
      'display_name': final String displayName,
      'friend_code': final String friendCode,
      'status': final String statusRaw,
      'current_streak_days': final int streakDays,
      'is_stats_visible_to_friends': final bool isStatsVisible,
      'can_send_wakeup_nudge_today': final bool canNudge,
    }) {
      return Ok(
        FriendProfileSummary(
          friendshipId: friendshipId,
          userId: userId,
          displayName: displayName,
          avatarUrl: json['avatar_url'] as String?,
          friendCode: friendCode,
          status: .fromWire(statusRaw),
          currentStreakDays: streakDays,
          equippedAccessoryCode: json['equipped_accessory_code'] as String?,
          isStatsVisibleToFriends: isStatsVisible,
          weeklyCo2SavedGrams: (json['weekly_co2_saved_grams'] as num?)
              ?.toInt(),
          weeklySteps: (json['weekly_steps'] as num?)?.toInt(),
          canSendWakeupNudgeToday: canNudge,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'friendship_id': friendshipId,
    'user_id': userId,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'friend_code': friendCode,
    'status': status.wireName,
    'current_streak_days': currentStreakDays,
    'equipped_accessory_code': equippedAccessoryCode,
    'is_stats_visible_to_friends': isStatsVisibleToFriends,
    'weekly_co2_saved_grams': weeklyCo2SavedGrams,
    'weekly_steps': weeklySteps,
    'can_send_wakeup_nudge_today': canSendWakeupNudgeToday,
  };
}

final class const FriendsOverviewResponse({
  required final String myFriendCode,
  required final List<FriendProfileSummary> friends,
  required final List<FriendProfileSummary> incomingRequests,
  required final List<FriendProfileSummary> outgoingRequests,
}) {
  static Result<FriendsOverviewResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'my_friend_code': final String myFriendCode,
      'friends': final List<Object?> friendsRaw,
      'incoming_requests': final List<Object?> incomingRaw,
      'outgoing_requests': final List<Object?> outgoingRaw,
    }) {
      return Ok(
        FriendsOverviewResponse(
          myFriendCode: myFriendCode,
          friends: _parseList(friendsRaw),
          incomingRequests: _parseList(incomingRaw),
          outgoingRequests: _parseList(outgoingRaw),
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  static List<FriendProfileSummary> _parseList(List<Object?> raw) {
    final items = <FriendProfileSummary>[];
    for (final entry in raw) {
      if (entry is Map<String, Object?>) {
        if (FriendProfileSummary.fromJson(entry) case Ok(:final value)) {
          items.add(value);
        }
      }
    }
    return items;
  }

  Map<String, Object?> toJson() => {
    'my_friend_code': myFriendCode,
    'friends': friends.map((f) => f.toJson()).toList(),
    'incoming_requests': incomingRequests.map((f) => f.toJson()).toList(),
    'outgoing_requests': outgoingRequests.map((f) => f.toJson()).toList(),
  };
}

final class const FriendshipRecord({
  required final String id,
  required final String requesterId,
  required final String addresseeId,
  required final FriendshipStatus status,
  required final String createdAt,
  final String? respondedAt,
}) {
  static Result<FriendshipRecord, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'id': final String id,
      'requester_id': final String requesterId,
      'addressee_id': final String addresseeId,
      'status': final String statusRaw,
      'created_at': final String createdAt,
    }) {
      return Ok(
        FriendshipRecord(
          id: id,
          requesterId: requesterId,
          addresseeId: addresseeId,
          status: .fromWire(statusRaw),
          createdAt: createdAt,
          respondedAt: json['responded_at'] as String?,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'requester_id': requesterId,
    'addressee_id': addresseeId,
    'status': status.wireName,
    'created_at': createdAt,
    'responded_at': respondedAt,
  };
}

final class const WakeupNudgeResponse({
  required final String nudgeId,
  required final String receiverId,
  required final String nudgeDate,
  required final bool pushDelivered,
  required final String sentAt,
}) {
  static Result<WakeupNudgeResponse, AppError> fromJson(
    Map<String, Object?> json,
  ) {
    if (json case {
      'nudge_id': final String nudgeId,
      'receiver_id': final String receiverId,
      'nudge_date': final String nudgeDate,
      'push_delivered': final bool pushDelivered,
      'sent_at': final String sentAt,
    }) {
      return Ok(
        WakeupNudgeResponse(
          nudgeId: nudgeId,
          receiverId: receiverId,
          nudgeDate: nudgeDate,
          pushDelivered: pushDelivered,
          sentAt: sentAt,
        ),
      );
    }
    return Err(AppError.fromCode('VALIDATION_ERROR'));
  }

  Map<String, Object?> toJson() => {
    'nudge_id': nudgeId,
    'receiver_id': receiverId,
    'nudge_date': nudgeDate,
    'push_delivered': pushDelivered,
    'sent_at': sentAt,
  };
}

abstract interface class const ProfileRepository() {
  Stream<UserProfile> watchUserProfile();

  Future<Result<UserProfile, AppError>> getProfile({bool forceRefresh = false});

  Future<Result<UserProfile, AppError>> updateProfile(
    UpdateUserProfileRequest req,
  );

  Future<Result<UserVehicle, AppError>> getMyVehicle();

  Future<Result<UserVehicle, AppError>> upsertVehicle(
    String vehicleName,
    FuelType fuel,
    double consumptionPer100km,
  );

  Future<Result<void, AppError>> deleteVehicle();

  Future<Result<List<TransportPresetItem>, AppError>> listTransportPresets();

  Future<Result<BadgesListResponse, AppError>> listBadges();

  Future<Result<MascotInventoryResponse, AppError>> listMascotAccessories();

  Future<Result<UserProfile, AppError>> equipMascotAccessory(
    String? accessoryCode,
  );

  Future<Result<AccountDeletionReceipt, AppError>> deleteAccount(
    String reason,
    String confirmationPhrase,
  );

  Future<void> cacheProfile(
    UserProfile profile, {
    AuthProviderType? authProvider,
    bool? isForeignLabMode,
  });

  Future<UserProfile?> getCachedProfileSnapshot();

  Future<void> updateLocalConsentActive({required bool isActive});

  Future<void> clearAllLocalUserData();
}

abstract interface class const FriendsRepository() {
  Future<Result<FriendsOverviewResponse, AppError>> getFriendsOverview();

  Future<Result<FriendshipRecord, AppError>> sendFriendRequest(
    String friendCode,
  );

  Future<Result<FriendshipRecord, AppError>> respondToRequest(
    String friendshipId,
    String action,
  );

  Future<Result<void, AppError>> removeFriend(String friendUserId);

  Future<Result<WakeupNudgeResponse, AppError>> sendWakeupNudge(
    String friendUserId,
  );
}
