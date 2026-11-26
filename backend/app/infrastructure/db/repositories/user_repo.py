from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.auth_models import MascotMoodState, MascotVisualState, UserProfileResponse


async def lock_user(connection: asyncpg.Connection, user_id: UUID) -> None:
    if not await connection.fetchval("SELECT id FROM users WHERE id = $1 FOR UPDATE", user_id):
        raise CatalogException("AUTH_TOKEN_INVALID")


async def load_points_balance(connection: asyncpg.Connection, user_id: UUID) -> int:
    balance = await connection.fetchval("SELECT points_balance FROM users WHERE id = $1", user_id)
    if not isinstance(balance, int):
        raise CatalogException("AUTH_TOKEN_INVALID")
    return balance


async def load_profile(connection: asyncpg.Connection, user_id: UUID) -> UserProfileResponse:
    row = await connection.fetchrow(
        """
        SELECT u.id, u.email, u.display_name, u.avatar_url, u.friend_code, u.formal_phone_e164,
               u.requires_formal_phone, u.points_balance, u.lifetime_points_earned,
               u.lifetime_co2_saved_grams, u.current_streak_days, u.longest_streak_days,
               u.streak_freeze_count, u.last_active_local_date, u.daily_step_goal,
               u.daily_co2_goal_grams, u.stride_length_cm, u.gps_interval_seconds,
               u.is_gps_tracking_enabled, u.is_stats_visible_to_friends,
               u.is_152fz_consent_active, u.created_at,
               u.equipped_accessory_code,
               ARRAY(SELECT accessory_code FROM user_mascot_inventory
                     WHERE user_id = u.id ORDER BY accessory_code) AS unlocked_accessory_codes,
               COALESCE(d.total_co2_saved_grams, 0) AS today_co2,
               CASE WHEN v.id IS NOT NULL THEN jsonb_build_object(
                   'id', v.id, 'vehicle_name', v.vehicle_name, 'fuel', v.fuel,
                   'consumption_per_100km', v.consumption_per_100km,
                   'fuel_emission_factor_g_per_unit', v.fuel_emission_factor_g_per_unit,
                   'computed_co2_g_per_km', v.computed_co2_g_per_km,
                   'computed_co2_g_per_meter', v.computed_co2_g_per_meter,
                   'updated_at', v.updated_at
               ) END AS personal_vehicle
        FROM users u
        LEFT JOIN user_vehicles v ON v.user_id = u.id
        LEFT JOIN daily_step_summaries d ON d.user_id = u.id
            AND d.activity_date = (now() AT TIME ZONE 'Europe/Moscow')::date
        WHERE u.id = $1
        """,
        user_id,
    )
    if row is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    values = dict(row)
    ratio = values.pop("today_co2") / values["daily_co2_goal_grams"]
    mood: MascotMoodState = "sleepy"
    if ratio >= 1:
        mood = "thriving"
    elif ratio >= 0.5:
        mood = "happy"
    elif ratio > 0:
        mood = "neutral"
    values["mascot"] = MascotVisualState(
        mood=mood,
        daily_goal_progress_ratio=ratio,
        equipped_accessory_code=values.pop("equipped_accessory_code"),
        unlocked_accessory_codes=values.pop("unlocked_accessory_codes"),
    )
    return UserProfileResponse.model_validate(values)
