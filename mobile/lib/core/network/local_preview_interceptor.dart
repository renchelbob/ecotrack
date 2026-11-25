import 'package:dio/dio.dart';
import 'package:ecotrack_mobile/core/network/token_store.dart';

/// Offline local-preview interceptor activated solely when the active
/// session uses the local preview token (`local-preview-access-token`).
/// Real backend OAuth sessions always bypass this interceptor.
final class LocalPreviewInterceptor(final TokenStore _tokenStore)
    extends Interceptor {
  static const String previewToken = 'local-preview-access-token';

  String _displayName = 'Артём Волков';
  String? _avatarUrl;
  int _pointsBalance = 450;
  final int _lifetimePointsEarned = 1280;
  final int _lifetimeCo2SavedGrams = 18450;
  int _streakFreezeCount = 2;
  int _dailyStepGoal = 8000;
  int _dailyCo2GoalGrams = 1500;
  int _strideLengthCm = 74;
  int _gpsIntervalSeconds = 15;
  bool _isGpsTrackingEnabled = true;
  bool _isStatsVisibleToFriends = true;
  bool _isConsentActive = true;
  String? _equippedAccessory = 'leaf_crown';
  final List<String> _unlockedAccessories = ['leaf_crown', 'eco_scarf'];

  Map<String, Object?>? _vehicle = {
    'id': 'veh-local-1',
    'vehicle_name': 'Lada Vesta',
    'fuel': 'petrol_95',
    'consumption_per_100km': 7.8,
    'fuel_emission_factor_g_per_unit': 2330.0,
    'computed_co2_g_per_km': 181.74,
    'computed_co2_g_per_meter': 0.18174,
    'updated_at': '2026-11-25T10:00:00Z',
  };

  final List<Map<String, Object?>> _orders = [
    {
      'id': 'ord-demo-1',
      'idempotency_key': '01936300-0000-7000-8000-000000000001',
      'status': 'completed',
      'total_points': 120,
      'remaining_points_balance': 450,
      'item_count': 1,
      'created_at': '2026-11-24T12:30:00Z',
      'line_items': [
        {
          'id': 'line-demo-1',
          'shop_item_id': 'item-coffee',
          'title': 'Скидка 25% в кофейню «ЭкоЗерно»',
          'item_type': 'partner_qr',
          'quantity': 1,
          'unit_price_points': 120,
          'line_total_points': 120,
          'coupon_code': 'ECO-ZRN-25',
          'qr_payload': 'ecotrack://voucher/ECO-ZRN-25',
          'expires_at': '2026-12-31T23:59:59Z',
        },
      ],
    },
    {
      'id': 'ord-demo-2',
      'idempotency_key': '01936300-0000-7000-8000-000000000002',
      'status': 'completed',
      'total_points': 180,
      'remaining_points_balance': 570,
      'item_count': 1,
      'created_at': '2026-11-23T18:10:00Z',
      'line_items': [
        {
          'id': 'line-demo-2',
          'shop_item_id': 'item-bike',
          'title': 'Промокод 45 минут в «ВелоВятка»',
          'item_type': 'partner_coupon',
          'quantity': 1,
          'unit_price_points': 180,
          'line_total_points': 180,
          'coupon_code': 'VELO-VYATKA-45',
          'qr_payload': '',
          'expires_at': '2026-12-31T23:59:59Z',
        },
      ],
    },
  ];

  final List<Map<String, Object?>> _allocations = [
    {
      'id': 'alloc-demo-1',
      'idempotency_key': '01936300-0000-7000-8000-000000000010',
      'start_seq_no': 1,
      'end_seq_no': 4,
      'segment_distance_m': 1150.0,
      'segment_steps': 1550,
      'replaced_transport_mode': 'bus',
      'applied_co2_g_per_meter': 0.089,
      'confidence_factor': 1.0,
      'is_auto_calculated': false,
      'co2_saved_grams': 102,
      'coordinates': [
        {'lat': 58.6035, 'lon': 49.6680},
        {'lat': 58.6048, 'lon': 49.6712},
        {'lat': 58.6061, 'lon': 49.6744},
        {'lat': 58.6075, 'lon': 49.6768},
      ],
    },
  ];

  final List<Map<String, Object?>> _consents = [
    {
      'id': 'cons-demo-1',
      'policy_version': '1.0.0-2026',
      'action': 'granted',
      'consent_scope': {
        'personal_data_152fz': true,
        'health_steps_sensor': true,
        'background_geolocation': true,
      },
      'recorded_at': '2026-11-25T10:00:00Z',
    },
  ];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStore.getAccessToken();
    if (token != previewToken) {
      handler.next(options);
      return;
    }

    final uri = Uri.tryParse(options.path);
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.length < 3 || segments[0] != 'api' || segments[1] != 'v1') {
      handler.next(options);
      return;
    }

    final route = segments.skip(2).join('/');
    final method = options.method.toUpperCase();
    final payload = _dispatch(
      method: method,
      route: route,
      segments: segments.skip(2).toList(),
      query: Map<String, Object?>.of(options.queryParameters),
      body: options.data,
    );

    if (payload == null) {
      handler.next(options);
      return;
    }

    handler.resolve(
      Response<Object?>(
        requestOptions: options,
        statusCode: method == 'POST' ? 201 : 200,
        data: payload,
      ),
    );
  }

  Object? _dispatch({
    required String method,
    required String route,
    required List<String> segments,
    required Map<String, Object?> query,
    required Object? body,
  }) {
    final bodyMap = body is Map<String, Object?>
        ? body
        : const <String, Object?>{};

    if (route == 'users/me') {
      if (method == 'GET') {
        return _profilePayload();
      }
      if (method == 'PATCH') {
        if (bodyMap['display_name'] case final String name
            when name.isNotEmpty) {
          _displayName = name;
        }
        if (bodyMap.containsKey('avatar_url')) {
          _avatarUrl = bodyMap['avatar_url'] as String?;
        }
        if (bodyMap['daily_step_goal'] case final int g) {
          _dailyStepGoal = g;
        }
        if (bodyMap['daily_co2_goal_grams'] case final int g) {
          _dailyCo2GoalGrams = g;
        }
        if (bodyMap['stride_length_cm'] case final int s) {
          _strideLengthCm = s;
        }
        if (bodyMap['gps_interval_seconds'] case final int s) {
          _gpsIntervalSeconds = s;
        }
        if (bodyMap['is_gps_tracking_enabled'] case final bool b) {
          _isGpsTrackingEnabled = b;
        }
        if (bodyMap['is_stats_visible_to_friends'] case final bool b) {
          _isStatsVisibleToFriends = b;
        }
        return _profilePayload();
      }
      if (method == 'DELETE') {
        return {
          'receipt_id': 'rcpt-local-152fz',
          'anonymized_user_hash': 'sha256:9f2c8d1b7a44e0',
          'purged_at': DateTime.now().toUtc().toIso8601String(),
          'verification_signature': 'hmac-local-preview-verified',
        };
      }
    }

    if (route == 'users/me/vehicle') {
      if (method == 'GET') {
        return _vehicle ?? const <String, Object?>{};
      }
      if (method == 'PUT') {
        final fuel = bodyMap['fuel'] as String? ?? 'petrol_95';
        final consumption =
            (bodyMap['consumption_per_100km'] as num?)?.toDouble() ?? 8.0;
        final factor = switch (fuel) {
          'diesel' => 2640.0,
          'lpg' => 1660.0,
          'electric' => 380.0,
          _ => 2330.0,
        };
        final gPerKm = (consumption * factor) / 100.0;
        return _vehicle = {
          'id': 'veh-local-1',
          'vehicle_name':
              bodyMap['vehicle_name'] as String? ?? 'Мой автомобиль',
          'fuel': fuel,
          'consumption_per_100km': consumption,
          'fuel_emission_factor_g_per_unit': factor,
          'computed_co2_g_per_km': gPerKm,
          'computed_co2_g_per_meter': gPerKm / 1000.0,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
      }
      if (method == 'DELETE') {
        _vehicle = null;
        return const <String, Object?>{'deleted': true};
      }
    }

    if (route == 'transport/presets' && method == 'GET') {
      return {
        'presets': [
          {
            'mode_code': 'bus',
            'display_name_ru': 'Автобус',
            'display_name_en': 'Bus',
            'co2_grams_per_km': 89.0,
            'co2_grams_per_meter': 0.089,
            'is_personal_vehicle_slot': false,
          },
          {
            'mode_code': 'tram_trolley',
            'display_name_ru': 'Трамвай / Троллейбус',
            'display_name_en': 'Tram / Trolleybus',
            'co2_grams_per_km': 42.0,
            'co2_grams_per_meter': 0.042,
            'is_personal_vehicle_slot': false,
          },
          {
            'mode_code': 'metro',
            'display_name_ru': 'Метро / Городская электричка',
            'display_name_en': 'Metro / Rail',
            'co2_grams_per_km': 35.0,
            'co2_grams_per_meter': 0.035,
            'is_personal_vehicle_slot': false,
          },
          {
            'mode_code': 'taxi',
            'display_name_ru': 'Такси / Каршеринг',
            'display_name_en': 'Taxi',
            'co2_grams_per_km': 192.0,
            'co2_grams_per_meter': 0.192,
            'is_personal_vehicle_slot': false,
          },
          {
            'mode_code': 'personal_car',
            'display_name_ru': 'Личный автомобиль',
            'display_name_en': 'Personal car',
            'co2_grams_per_km':
                (_vehicle?['computed_co2_g_per_km'] as num?)?.toDouble() ??
                181.74,
            'co2_grams_per_meter':
                (_vehicle?['computed_co2_g_per_meter'] as num?)?.toDouble() ??
                0.18174,
            'is_personal_vehicle_slot': true,
          },
        ],
      };
    }

    if (route == 'badges' && method == 'GET') {
      return {
        'unlocked_count': 3,
        'total_count': 5,
        'badges': [
          {
            'code': 'first_step',
            'title_ru': 'Первые шаги',
            'description_ru': 'Пройдите 5 000 шагов за один день',
            'icon_vector_key': 'footprints',
            'threshold_type': 'steps',
            'threshold_value': 5000,
            'current_value': 5420,
            'reward_points': 50,
            'reward_accessory_code': 'leaf_crown',
            'is_unlocked': true,
            'awarded_at': '2026-11-22T18:00:00Z',
          },
          {
            'code': 'streak_5',
            'title_ru': 'Пять дней подряд',
            'description_ru': 'Сохраняйте серию активности 5 дней',
            'icon_vector_key': 'flame',
            'threshold_type': 'streak_days',
            'threshold_value': 5,
            'current_value': 6,
            'reward_points': 100,
            'reward_accessory_code': 'eco_scarf',
            'is_unlocked': true,
            'awarded_at': '2026-11-24T20:00:00Z',
          },
          {
            'code': 'co2_10kg',
            'title_ru': 'Хранитель воздуха',
            'description_ru': 'Сэкономьте 10 кг CO₂ вместо поездок на авто',
            'icon_vector_key': 'wind',
            'threshold_type': 'co2_grams',
            'threshold_value': 10000,
            'current_value': _lifetimeCo2SavedGrams,
            'reward_points': 150,
            'is_unlocked': true,
            'awarded_at': '2026-11-24T21:00:00Z',
          },
          {
            'code': 'explorer_50k',
            'title_ru': 'Пешеход-исследователь',
            'description_ru': 'Пройдите 50 000 шагов за неделю',
            'icon_vector_key': 'compass',
            'threshold_type': 'weekly_steps',
            'threshold_value': 50000,
            'current_value': 34200,
            'reward_points': 200,
            'reward_accessory_code': 'explorer_glasses',
            'is_unlocked': false,
          },
          {
            'code': 'forest_guardian',
            'title_ru': 'Хранитель рощи',
            'description_ru': 'Сэкономьте 50 кг CO₂ за всё время',
            'icon_vector_key': 'trees',
            'threshold_type': 'co2_grams',
            'threshold_value': 50000,
            'current_value': _lifetimeCo2SavedGrams,
            'reward_points': 350,
            'reward_accessory_code': 'firefly_aura',
            'is_unlocked': false,
          },
        ],
      };
    }

    if (route == 'mascot/inventory' && method == 'GET') {
      return {
        'accessories': [
          {
            'code': 'leaf_crown',
            'name_ru': 'Венок из листьев',
            'slot': 'head',
            'vector_layer_key': 'leaf_crown',
            'unlock_type': 'badge',
            'is_unlocked': _unlockedAccessories.contains('leaf_crown'),
            'is_equipped': _equippedAccessory == 'leaf_crown',
            'acquired_at': '2026-11-22T18:00:00Z',
          },
          {
            'code': 'eco_scarf',
            'name_ru': 'Вязаный эко-шарф',
            'slot': 'neck',
            'vector_layer_key': 'eco_scarf',
            'unlock_type': 'badge',
            'is_unlocked': _unlockedAccessories.contains('eco_scarf'),
            'is_equipped': _equippedAccessory == 'eco_scarf',
            'acquired_at': '2026-11-24T20:00:00Z',
          },
          {
            'code': 'explorer_glasses',
            'name_ru': 'Очки путешественника',
            'slot': 'eyes',
            'vector_layer_key': 'explorer_glasses',
            'unlock_type': 'shop',
            'is_unlocked': _unlockedAccessories.contains('explorer_glasses'),
            'is_equipped': _equippedAccessory == 'explorer_glasses',
          },
          {
            'code': 'firefly_aura',
            'name_ru': 'Аура светлячков',
            'slot': 'aura',
            'vector_layer_key': 'firefly_aura',
            'unlock_type': 'badge',
            'is_unlocked': _unlockedAccessories.contains('firefly_aura'),
            'is_equipped': _equippedAccessory == 'firefly_aura',
          },
        ],
      };
    }

    if (route == 'users/me/mascot/accessory' &&
        (method == 'PUT' || method == 'PATCH')) {
      _equippedAccessory = bodyMap['accessory_code'] as String?;
      return _profilePayload();
    }

    if (route == 'users/me/consents') {
      if (method == 'GET') {
        return {
          'is_152fz_consent_active': _isConsentActive,
          'entries': _consents,
        };
      }
      if (method == 'POST') {
        final action = bodyMap['action'] as String? ?? 'granted';
        final scope =
            bodyMap['consent_scope'] as Map<String, Object?>? ??
            const <String, Object?>{
              'personal_data_152fz': true,
              'health_steps_sensor': true,
              'background_geolocation': true,
            };
        _isConsentActive =
            action != 'revoked' && (scope['personal_data_152fz'] == true);
        final entry = {
          'id': 'cons-${DateTime.now().millisecondsSinceEpoch}',
          'policy_version':
              bodyMap['policy_version'] as String? ?? '1.0.0-2026',
          'action': action,
          'consent_scope': scope,
          'recorded_at': DateTime.now().toUtc().toIso8601String(),
        };
        _consents.insert(0, entry);
        return entry;
      }
    }

    if (route == 'friends' && method == 'GET') {
      return {
        'my_friend_code': 'ECO-4219-DEMO',
        'friends': [
          {
            'friendship_id': 'fr-1',
            'user_id': 'usr-friend-1',
            'display_name': 'Мария Соколова',
            'friend_code': 'ECO-8821-MARS',
            'status': 'accepted',
            'current_streak_days': 9,
            'equipped_accessory_code': 'eco_scarf',
            'is_stats_visible_to_friends': true,
            'weekly_co2_saved_grams': 5240,
            'weekly_steps': 48120,
            'can_send_wakeup_nudge_today': true,
          },
          {
            'friendship_id': 'fr-2',
            'user_id': 'usr-friend-2',
            'display_name': 'Илья Морозов',
            'friend_code': 'ECO-1903-ILIA',
            'status': 'accepted',
            'current_streak_days': 4,
            'is_stats_visible_to_friends': true,
            'weekly_co2_saved_grams': 3180,
            'weekly_steps': 29450,
            'can_send_wakeup_nudge_today': false,
          },
        ],
        'incoming_requests': const <Object?>[],
        'outgoing_requests': const <Object?>[],
      };
    }

    if (segments.length == 3 &&
        segments[0] == 'friends' &&
        segments[2] == 'nudge' &&
        method == 'POST') {
      return {
        'nudge_id': 'ndg-${DateTime.now().millisecondsSinceEpoch}',
        'receiver_id': segments[1],
        'nudge_date': DateTime.now().toIso8601String().substring(0, 10),
        'push_delivered': true,
        'sent_at': DateTime.now().toUtc().toIso8601String(),
      };
    }

    if (route == 'friends/leaderboard' && method == 'GET') {
      return {
        'iso_year': 2026,
        'iso_week': 48,
        'week_start_date': '2026-11-23',
        'week_end_date': '2026-11-29',
        'entries': [
          {
            'rank': 1,
            'user_id': 'usr-friend-1',
            'display_name': 'Мария Соколова',
            'equipped_accessory_code': 'eco_scarf',
            'is_current_user': false,
            'is_stats_visible': true,
            'weekly_co2_saved_grams': 5240,
            'weekly_steps': 48120,
            'current_streak_days': 9,
          },
          {
            'rank': 2,
            'user_id': 'usr-local-preview',
            'display_name': _displayName,
            'equipped_accessory_code': _equippedAccessory,
            'is_current_user': true,
            'is_stats_visible': _isStatsVisibleToFriends,
            'weekly_co2_saved_grams': 4380,
            'weekly_steps': 39200,
            'current_streak_days': 6,
          },
          {
            'rank': 3,
            'user_id': 'usr-friend-2',
            'display_name': 'Илья Морозов',
            'is_current_user': false,
            'is_stats_visible': true,
            'weekly_co2_saved_grams': 3180,
            'weekly_steps': 29450,
            'current_streak_days': 4,
          },
        ],
      };
    }

    if (route == 'challenges/shared-forest/current' && method == 'GET') {
      return {
        'id': 'forest-2026-w48',
        'iso_year': 2026,
        'iso_week': 48,
        'week_start_date': '2026-11-23',
        'week_end_date': '2026-11-29',
        'title_ru': 'Общий лес друзей · Неделя 48',
        'target_co2_saved_grams': 20000,
        'current_co2_saved_grams': 12800,
        'progress_ratio': 0.64,
        'trees_equivalent_planted': 25,
        'my_contributed_co2_grams': 4380,
        'is_completed': false,
        'top_friends_contributors': [
          {
            'user_id': 'usr-friend-1',
            'display_name': 'Мария Соколова',
            'contributed_co2_grams': 5240,
            'contributed_steps': 48120,
          },
          {
            'user_id': 'usr-local-preview',
            'display_name': _displayName,
            'contributed_co2_grams': 4380,
            'contributed_steps': 39200,
          },
          {
            'user_id': 'usr-friend-2',
            'display_name': 'Илья Морозов',
            'contributed_co2_grams': 3180,
            'contributed_steps': 29450,
          },
        ],
      };
    }

    if (route == 'activity/steps/daily' && method == 'POST') {
      final date =
          bodyMap['activity_date'] as String? ??
          DateTime.now().toIso8601String().substring(0, 10);
      final rawSteps = (bodyMap['raw_sensor_steps'] as num?)?.toInt() ?? 5420;
      final effectiveSteps = rawSteps > 0 ? rawSteps : 5420;
      return _summaryFor(date, steps: effectiveSteps);
    }

    if (segments.length == 3 &&
        segments[0] == 'activity' &&
        segments[1] == 'daily' &&
        method == 'GET') {
      return _dailyDetailFor(segments[2]);
    }

    if (segments.length == 4 &&
        segments[0] == 'activity' &&
        segments[1] == 'daily' &&
        segments[3] == 'allocations' &&
        method == 'PUT') {
      final date = segments[2];
      final rawList = bodyMap['allocations'] as List<Object?>? ?? const [];
      _allocations.clear();
      for (var i = 0; i < rawList.length; i++) {
        if (rawList[i] case final Map<String, Object?> item) {
          final mode = item['replaced_transport_mode'] as String? ?? 'bus';
          final gPerM = switch (mode) {
            'personal_car' => 0.18174,
            'taxi' => 0.192,
            'tram_trolley' => 0.042,
            'metro' => 0.035,
            _ => 0.089,
          };
          _allocations.add({
            'id': 'alloc-${i + 1}',
            'idempotency_key':
                item['idempotency_key'] as String? ?? 'key-${i + 1}',
            'start_seq_no': item['start_seq_no'] ?? 1,
            'end_seq_no': item['end_seq_no'] ?? 4,
            'segment_distance_m': 1150.0,
            'segment_steps': 1550,
            'replaced_transport_mode': mode,
            'applied_co2_g_per_meter': gPerM,
            'confidence_factor': 1.0,
            'is_auto_calculated': false,
            'co2_saved_grams': (1150.0 * gPerM).round(),
            'coordinates': const [
              {'lat': 58.6035, 'lon': 49.6680},
              {'lat': 58.6048, 'lon': 49.6712},
              {'lat': 58.6061, 'lon': 49.6744},
              {'lat': 58.6075, 'lon': 49.6768},
            ],
          });
        }
      }
      return _dailyDetailFor(date);
    }

    if (route == 'activity/tracks/points:batch' && method == 'POST') {
      return {'accepted_count': 1, 'status': 'ok'};
    }

    if (route == 'map/waste-points' && method == 'GET') {
      return {
        'attribution_banner_ru': '© Участники OpenStreetMap (ODbL 1.0) · data.mos.ru · Муниципальные реестры',
        'total_returned': 4,
        'points': _wastePoints(),
      };
    }

    if (segments.length == 3 &&
        segments[0] == 'map' &&
        segments[1] == 'waste-points' &&
        method == 'GET') {
      final pointId = segments[2];
      final found = _wastePoints().firstWhere(
        (p) => p['id'] == pointId,
        orElse: () => _wastePoints().first,
      );
      return {
        ...found,
        'operator_name': 'ЭкоПункт Вятка',
        'opening_hours': 'Ежедневно 08:00–21:00',
        'attribution_text':
            '© Участники OpenStreetMap (ODbL 1.0) · Муниципальный реестр',
        'last_verified_at': '2026-11-24T12:00:00Z',
        'sources': [
          {
            'source_record_id': 'osm-1',
            'source_type': 'osm',
            'external_record_id': 'node/49281723',
            'license_name': 'ODbL 1.0',
            'match_distance_m': 2.0,
          },
        ],
        'recent_reports': const <Object?>[],
        'updated_at': '2026-11-24T12:00:00Z',
      };
    }

    if (route == 'stats/emissions' && method == 'GET') {
      final period = query['period'] as String? ?? 'week';
      return {
        'period': period,
        'period_total_co2_saved_grams': 4380,
        'period_total_steps': 39200,
        'period_total_distance_m': 29008.0,
        'buckets': [
          {
            'bucket_label': 'Пн',
            'start_date': '2026-11-19',
            'end_date': '2026-11-19',
            'validated_steps': 5100,
            'total_step_distance_m': 3774.0,
            'allocated_co2_saved_grams': 180,
            'auto_default_co2_saved_grams': 410,
            'total_co2_saved_grams': 590,
          },
          {
            'bucket_label': 'Вт',
            'start_date': '2026-11-20',
            'end_date': '2026-11-20',
            'validated_steps': 6800,
            'total_step_distance_m': 5032.0,
            'allocated_co2_saved_grams': 320,
            'auto_default_co2_saved_grams': 480,
            'total_co2_saved_grams': 800,
          },
          {
            'bucket_label': 'Ср',
            'start_date': '2026-11-21',
            'end_date': '2026-11-21',
            'validated_steps': 4200,
            'total_step_distance_m': 3108.0,
            'allocated_co2_saved_grams': 0,
            'auto_default_co2_saved_grams': 495,
            'total_co2_saved_grams': 495,
          },
          {
            'bucket_label': 'Чт',
            'start_date': '2026-11-22',
            'end_date': '2026-11-22',
            'validated_steps': 7900,
            'total_step_distance_m': 5846.0,
            'allocated_co2_saved_grams': 420,
            'auto_default_co2_saved_grams': 520,
            'total_co2_saved_grams': 940,
          },
          {
            'bucket_label': 'Пт',
            'start_date': '2026-11-23',
            'end_date': '2026-11-23',
            'validated_steps': 6100,
            'total_step_distance_m': 4514.0,
            'allocated_co2_saved_grams': 210,
            'auto_default_co2_saved_grams': 470,
            'total_co2_saved_grams': 680,
          },
          {
            'bucket_label': 'Сб',
            'start_date': '2026-11-24',
            'end_date': '2026-11-24',
            'validated_steps': 3680,
            'total_step_distance_m': 2723.0,
            'allocated_co2_saved_grams': 0,
            'auto_default_co2_saved_grams': 330,
            'total_co2_saved_grams': 330,
          },
          {
            'bucket_label': 'Вс',
            'start_date': '2026-11-25',
            'end_date': '2026-11-25',
            'validated_steps': 5420,
            'total_step_distance_m': 4011.0,
            'allocated_co2_saved_grams': 102,
            'auto_default_co2_saved_grams': 443,
            'total_co2_saved_grams': 545,
          },
        ],
        'equivalents': {
          'total_co2_saved_grams': 4380,
          'trees_planted_equivalent': 8.8,
          'car_km_avoided': 24.1,
          'smartphone_charges_equivalent': 540,
          'plastic_bottles_recycled_equivalent': 73,
          'led_bulb_hours_equivalent': 1210,
        },
        'transport_shares': [
          {
            'mode_code': 'auto_default',
            'label_ru': 'Авто-формула',
            'co2_saved_grams': 3148,
            'percentage': 71.9,
          },
          {
            'mode_code': 'bus',
            'label_ru': 'Автобус',
            'co2_saved_grams': 812,
            'percentage': 18.5,
          },
          {
            'mode_code': 'personal_car',
            'label_ru': 'Личное авто',
            'co2_saved_grams': 420,
            'percentage': 9.6,
          },
        ],
      };
    }

    if (route == 'stats/history' && method == 'GET') {
      return {
        'total_count': 3,
        'limit': 20,
        'offset': 0,
        'items': [
          _summaryFor('2026-11-25'),
          _summaryFor('2026-11-24', steps: 6120),
          _summaryFor('2026-11-23', steps: 7900),
        ],
      };
    }

    if (route == 'stats/equivalents' && method == 'GET') {
      return {
        'lifetime': {
          'total_co2_saved_grams': _lifetimeCo2SavedGrams,
          'trees_planted_equivalent': 36.9,
          'car_km_avoided': 101.5,
          'smartphone_charges_equivalent': 2240,
          'plastic_bottles_recycled_equivalent': 307,
          'led_bulb_hours_equivalent': 5080,
        },
        'current_week': {
          'total_co2_saved_grams': 4380,
          'trees_planted_equivalent': 8.8,
          'car_km_avoided': 24.1,
          'smartphone_charges_equivalent': 540,
          'plastic_bottles_recycled_equivalent': 73,
          'led_bulb_hours_equivalent': 1210,
        },
      };
    }

    if (route == 'shop/items' && method == 'GET') {
      return {
        'fictional_shop_banner_ru': 'Демонстрационный магазин: все бренды партнёров, промокоды и QR-купоны являются вымышленными.',
        'categories': [
          'Все',
          'Еда и напитки',
          'Транспорт',
          'Зверёк',
          'Экология',
        ],
        'items': _shopCatalogItems(),
      };
    }

    if (route == 'shop/orders') {
      if (method == 'GET') {
        return {'total_count': _orders.length, 'orders': _orders};
      }
      if (method == 'POST') {
        final rawItems = bodyMap['items'] as List<Object?>? ?? const [];
        final catalog = _shopCatalogItems();
        var total = 0;
        final lines = <Map<String, Object?>>[];
        for (final rawLine in rawItems) {
          if (rawLine is Map<String, Object?>) {
            final itemId = rawLine['shop_item_id'] as String? ?? '';
            final qty = (rawLine['quantity'] as num?)?.toInt() ?? 1;
            final found = catalog.firstWhere(
              (c) => c['id'] == itemId,
              orElse: () => catalog.first,
            );
            final unitPrice = found['price_points'] as int? ?? 100;
            final lineTotal = unitPrice * qty;
            total += lineTotal;
            final acc = found['accessory_code'] as String?;
            if (acc != null && !_unlockedAccessories.contains(acc)) {
              _unlockedAccessories.add(acc);
            }
            lines.add({
              'id': 'line-${DateTime.now().millisecondsSinceEpoch}',
              'shop_item_id': itemId,
              'title': found['title'] as String? ?? 'Бонус',
              'item_type': found['item_type'] as String? ?? 'partner_coupon',
              'quantity': qty,
              'unit_price_points': unitPrice,
              'line_total_points': lineTotal,
              'coupon_code': 'ECO-${DateTime.now().millisecond + 100}',
              'qr_payload': found['item_type'] == 'partner_qr'
                  ? 'ecotrack://voucher/DEMO-${DateTime.now().millisecondsSinceEpoch}'
                  : '',
              'expires_at': '2026-12-31T23:59:59Z',
            });
          }
        }
        _pointsBalance = (_pointsBalance - total).clamp(0, 1000000);
        final order = {
          'id': 'ord-${DateTime.now().millisecondsSinceEpoch}',
          'idempotency_key': 'local-${DateTime.now().millisecondsSinceEpoch}',
          'status': 'completed',
          'total_points': total,
          'remaining_points_balance': _pointsBalance,
          'item_count': lines.length,
          'line_items': lines,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        _orders.insert(0, order);
        return order;
      }
    }

    if (route == 'shop/virtual-items/streak-freeze:activate' &&
        method == 'POST') {
      if (_streakFreezeCount > 0) {
        _streakFreezeCount -= 1;
      }
      return _profilePayload();
    }

    if (route == 'ledger' && method == 'GET') {
      return {
        'points_balance': _pointsBalance,
        'lifetime_points_earned': _lifetimePointsEarned,
        'total_count': 3,
        'items': [
          {
            'id': 'ldg-1',
            'idempotency_key': '01936300-0000-7000-8000-000000000101',
            'operation_type': 'daily_steps_reward',
            'points_delta': 65,
            'co2_delta_grams': 545,
            'description': 'Ежедневная активность: 5 420 шагов',
            'created_at': '2026-11-25T12:00:00Z',
          },
          {
            'id': 'ldg-2',
            'idempotency_key': '01936300-0000-7000-8000-000000000102',
            'operation_type': 'segment_annotation_delta',
            'points_delta': 25,
            'co2_delta_grams': 102,
            'description': 'Уточнение участка маршрута (Автобус)',
            'created_at': '2026-11-25T11:20:00Z',
          },
          {
            'id': 'ldg-3',
            'idempotency_key': '01936300-0000-7000-8000-000000000103',
            'operation_type': 'shop_purchase',
            'points_delta': -120,
            'co2_delta_grams': 0,
            'description': 'Заказ в магазине «ЭкоЗерно»',
            'created_at': '2026-11-24T12:30:00Z',
          },
        ],
      };
    }

    return null;
  }

  Map<String, Object?> _profilePayload() => {
    'id': 'usr-local-preview',
    'email': 'preview@ecotrack.local',
    'display_name': _displayName,
    'avatar_url': _avatarUrl,
    'friend_code': 'ECO-4219-DEMO',
    'requires_formal_phone': false,
    'points_balance': _pointsBalance,
    'lifetime_points_earned': _lifetimePointsEarned,
    'lifetime_co2_saved_grams': _lifetimeCo2SavedGrams,
    'current_streak_days': 6,
    'longest_streak_days': 14,
    'streak_freeze_count': _streakFreezeCount,
    'last_active_local_date': '2026-11-25',
    'daily_step_goal': _dailyStepGoal,
    'daily_co2_goal_grams': _dailyCo2GoalGrams,
    'stride_length_cm': _strideLengthCm,
    'gps_interval_seconds': _gpsIntervalSeconds,
    'is_gps_tracking_enabled': _isGpsTrackingEnabled,
    'is_stats_visible_to_friends': _isStatsVisibleToFriends,
    'is_152fz_consent_active': _isConsentActive,
    'mascot': {
      'mood': 'happy',
      'daily_goal_progress_ratio': 0.72,
      'equipped_accessory_code': _equippedAccessory,
      'unlocked_accessory_codes': _unlockedAccessories,
    },
    'personal_vehicle': _vehicle,
    'created_at': '2026-11-20T09:00:00Z',
    'auth_provider': 'yandex',
    'is_foreign_provider_lab_mode': false,
  };

  Map<String, Object?> _summaryFor(String date, {int steps = 5420}) {
    final allocCo2 = _allocations.fold<int>(
      0,
      (sum, item) => sum + (item['co2_saved_grams'] as int? ?? 0),
    );
    final totalDist = steps * (_strideLengthCm / 100.0);
    final allocDist = _allocations.isEmpty ? 0.0 : 1150.0;
    final unallocDist = (totalDist - allocDist).clamp(0.0, totalDist);
    final autoCo2 = (unallocDist * 0.145 * 0.8 * 0.7).round();
    return {
      'id': 'sum-$date',
      'activity_date': date,
      'raw_sensor_steps': steps,
      'validated_steps': steps,
      'stride_length_cm': _strideLengthCm,
      'total_step_distance_m': totalDist,
      'allocated_gps_distance_m': allocDist,
      'unallocated_step_distance_m': unallocDist,
      'allocated_co2_saved_grams': allocCo2,
      'auto_default_co2_saved_grams': autoCo2,
      'total_co2_saved_grams': allocCo2 + autoCo2,
      'points_awarded_for_day': 65,
      'points_delta_applied': 0,
      'points_balance': _pointsBalance,
      'is_auto_calculated': _allocations.isEmpty,
      'antifraud_flagged': false,
    };
  }

  Map<String, Object?> _dailyDetailFor(String date) => {
    'summary': _summaryFor(date),
    'is_editable': true,
    'total_gps_walking_distance_m': 2480.0,
    'track_points': [
      {
        'seq_no': 1,
        'recorded_at': '${date}T08:30:00Z',
        'lat': 58.6035,
        'lon': 49.6680,
        'accuracy_m': 6.0,
        'speed_mps': 1.35,
        'cumulative_steps': 0,
        'delta_steps': 0,
        'delta_distance_m': 0.0,
        'motion_class': 'walking',
      },
      {
        'seq_no': 2,
        'recorded_at': '${date}T08:35:00Z',
        'lat': 58.6048,
        'lon': 49.6712,
        'accuracy_m': 5.5,
        'speed_mps': 1.42,
        'cumulative_steps': 520,
        'delta_steps': 520,
        'delta_distance_m': 384.0,
        'motion_class': 'walking',
      },
      {
        'seq_no': 3,
        'recorded_at': '${date}T08:40:00Z',
        'lat': 58.6061,
        'lon': 49.6744,
        'accuracy_m': 5.0,
        'speed_mps': 1.38,
        'cumulative_steps': 1040,
        'delta_steps': 520,
        'delta_distance_m': 383.0,
        'motion_class': 'walking',
      },
      {
        'seq_no': 4,
        'recorded_at': '${date}T08:45:00Z',
        'lat': 58.6075,
        'lon': 49.6768,
        'accuracy_m': 6.2,
        'speed_mps': 1.40,
        'cumulative_steps': 1550,
        'delta_steps': 510,
        'delta_distance_m': 383.0,
        'motion_class': 'walking',
      },
      {
        'seq_no': 5,
        'recorded_at': '${date}T12:15:00Z',
        'lat': 58.6090,
        'lon': 49.6730,
        'accuracy_m': 6.5,
        'speed_mps': 1.31,
        'cumulative_steps': 2100,
        'delta_steps': 550,
        'delta_distance_m': 410.0,
        'motion_class': 'walking',
      },
      {
        'seq_no': 6,
        'recorded_at': '${date}T12:22:00Z',
        'lat': 58.6068,
        'lon': 49.6695,
        'accuracy_m': 5.8,
        'speed_mps': 1.45,
        'cumulative_steps': 2700,
        'delta_steps': 600,
        'delta_distance_m': 444.0,
        'motion_class': 'walking',
      },
    ],
    'allocations': _allocations,
    'co2_delta_applied_grams': 0,
  };

  List<Map<String, Object?>> _wastePoints() => [
    {
      'id': 'wp-1',
      'title': 'ЭкоПункт у ВятГУ (Московская, 36)',
      'address_text': 'ул. Московская, 36',
      'accepted_fractions': ['plastic', 'paper', 'batteries'],
      'lat': 58.6042,
      'lon': 49.6698,
      'status': 'verified',
      'trust_score': 94.0,
      'confirmations_count': 28,
      'issues_count': 0,
    },
    {
      'id': 'wp-2',
      'title': 'Раздельный сбор · Театральная площадь',
      'address_text': 'ул. Карла Либкнехта, 69',
      'accepted_fractions': ['plastic', 'glass', 'metal'],
      'lat': 58.6019,
      'lon': 49.6652,
      'status': 'verified',
      'trust_score': 88.5,
      'confirmations_count': 19,
      'issues_count': 1,
    },
    {
      'id': 'wp-3',
      'title': 'Контейнер РСО · Александровский сад',
      'address_text': 'ул. Казанская, 51',
      'accepted_fractions': ['plastic', 'glass', 'paper'],
      'lat': 58.6079,
      'lon': 49.6810,
      'status': 'active',
      'trust_score': 76.0,
      'confirmations_count': 8,
      'issues_count': 1,
    },
    {
      'id': 'wp-4',
      'title': 'Приём электроники и ламп · Октябрьский пр.',
      'address_text': 'Октябрьский проспект, 84',
      'accepted_fractions': ['ewaste', 'batteries'],
      'lat': 58.5985,
      'lon': 49.6604,
      'status': 'verified',
      'trust_score': 91.0,
      'confirmations_count': 15,
      'issues_count': 0,
    },
  ];

  List<Map<String, Object?>> _shopCatalogItems() => [
    {
      'id': 'item-coffee',
      'sku': 'ECO-COFFEE-25',
      'item_type': 'partner_qr',
      'title': 'Скидка 25% в кофейню «ЭкоЗерно»',
      'subtitle': 'На любой напиток в свою кружку',
      'description': 'Покажите QR-купон бариста и получите скидку 25%.',
      'price_points': 120,
      'max_per_user_per_day': 2,
      'image_asset_key': 'coffee',
      'partner': {
        'id': 'part-1',
        'slug': 'ecozerno',
        'name': 'ЭкоЗерно',
        'category_name': 'Еда и напитки',
        'logo_asset_key': 'coffee',
        'is_fictional_disclaimer': 'Демонстрационный вымышленный партнёр.',
      },
    },
    {
      'id': 'item-bike',
      'sku': 'VELO-45MIN',
      'item_type': 'partner_coupon',
      'title': 'Промокод 45 минут в «ВелоВятка»',
      'subtitle': 'Бесплатная поездка на городском велопрокате',
      'description': 'Активируйте буквенный промокод в приложении партнёра.',
      'price_points': 180,
      'max_per_user_per_day': 1,
      'image_asset_key': 'bike',
      'partner': {
        'id': 'part-2',
        'slug': 'velovyatka',
        'name': 'ВелоВятка',
        'category_name': 'Транспорт',
        'logo_asset_key': 'bike',
        'is_fictional_disclaimer': 'Демонстрационный вымышленный партнёр.',
      },
    },
    {
      'id': 'item-glasses',
      'sku': 'MASCOT-GLASSES',
      'item_type': 'mascot_accessory',
      'title': 'Очки путешественника для зверька',
      'subtitle': 'Аксессуар для гардероба маскота',
      'description': 'Открывает стильные очки в разделе «Значки и гардероб».',
      'price_points': 90,
      'max_per_user_per_day': 1,
      'accessory_code': 'explorer_glasses',
      'image_asset_key': 'glasses',
    },
    {
      'id': 'item-freeze',
      'sku': 'STREAK-FREEZE',
      'item_type': 'virtual_streak_freeze',
      'title': 'Заморозка серии на 1 день',
      'subtitle': 'Защитит серию дней при пропуске прогулки',
      'description': 'Автоматически сохраняет ваш стрик на один день.',
      'price_points': 150,
      'max_per_user_per_day': 2,
      'image_asset_key': 'snowflake',
    },
    {
      'id': 'item-tree',
      'sku': 'ECO-DONATION-TREE',
      'item_type': 'virtual_eco_donation',
      'title': 'Посадка саженца в городском лесопарке',
      'subtitle': 'Виртуальный эко-вклад в фонд озеленения',
      'description':
          'Баллы конвертируются в поддержку локальной высадки деревьев.',
      'price_points': 250,
      'max_per_user_per_day': 5,
      'image_asset_key': 'tree',
    },
  ];
}
