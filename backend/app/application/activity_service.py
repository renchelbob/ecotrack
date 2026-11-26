from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.activity_models import DailyActivitySummaryResponse, SyncDailyStepsRequest
from app.application.auth_service import AccessSession
from app.domain.hybrid_co2 import automatic_emissions, calculate_step_reward_delta
from app.infrastructure.db.repositories import badge_repo, social_repo, user_repo
from app.infrastructure.db.transactions import retry_deadlock


def assert_activity_access(user: asyncpg.Record, *, from_sensor: bool = False) -> None:
    if user["requires_formal_phone"]:
        raise CatalogException("GOOGLE_FORMAL_PHONE_REQUIRED")
    if not user["is_152fz_consent_active"]:
        raise CatalogException("FZ152_CONSENT_REVOKED")
    if from_sensor and not user["step_scope"]:
        raise CatalogException("FZ152_HEALTH_SENSOR_CONSENT_MISSING")


async def _activity_user(connection: asyncpg.Connection, user_id: UUID) -> asyncpg.Record:
    # Consent changes take the same user lock. Read the journal after acquiring it.
    await connection.fetchval("SELECT id FROM users WHERE id = $1 FOR UPDATE", user_id)
    user = await connection.fetchrow(
        """
        SELECT u.*, COALESCE((
            SELECT action <> 'revoked' AND (consent_scope->>'health_steps_sensor')::boolean
            FROM fz152_consent_journal WHERE user_id = u.id
            ORDER BY recorded_at DESC, id DESC LIMIT 1
        ), false) AS step_scope FROM users u WHERE u.id = $1
        """,
        user_id,
    )
    if user is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    assert_activity_access(user, from_sensor=True)
    return user


async def _read_previous_request(
    connection: asyncpg.Connection, key: UUID, user_id: UUID, activity_date: date
) -> asyncpg.Record | None:
    ledger = await connection.fetchrow(
        """
        SELECT p.user_id, p.operation_type, d.activity_date
        FROM point_ledger p LEFT JOIN daily_step_summaries d ON d.id = p.reference_entity_id
        WHERE p.idempotency_key = $1
        """,
        key,
    )
    if ledger is not None and (
        ledger["user_id"] != user_id
        or ledger["operation_type"] != "daily_steps_reward"
        or ledger["activity_date"] != activity_date
    ):
        raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
    return ledger


def _streak(
    user: asyncpg.Record, activity_date: date, steps: int, total_co2: int
) -> tuple[int, int, date | None]:
    previous = user["last_active_local_date"]
    current = user["current_streak_days"]
    freezes = user["streak_freeze_count"]
    if steps < 1000 and total_co2 < user["daily_co2_goal_grams"]:
        return current, freezes, previous
    if previous is not None:
        gap = (activity_date - previous).days
        if gap <= 0:
            return current, freezes, previous
        if gap == 1:
            return current + 1, freezes, activity_date
        if gap == 2 and freezes:
            return current + 1, freezes - 1, activity_date
    return 1, freezes, activity_date


def to_activity_summary(
    row: asyncpg.Record, *, balance: int, points_delta: int = 0
) -> DailyActivitySummaryResponse:
    fields = {
        name: row[name]
        for name in DailyActivitySummaryResponse.model_fields
        if name not in {"points_balance", "points_delta_applied"}
    }
    return DailyActivitySummaryResponse.model_validate(
        fields | {"points_balance": balance, "points_delta_applied": points_delta}
    )


async def _steps_snapshot(
    connection: asyncpg.Connection,
    user_id: UUID,
    key: UUID,
    body: SyncDailyStepsRequest,
    session: AccessSession | None,
) -> asyncpg.Record:
    # A stale sensor snapshot can return a consistent read without taking the user's write lock.
    row = await connection.fetchrow(
        """
        SELECT d.*, u.points_balance, u.is_152fz_consent_active, u.requires_formal_phone,
               COALESCE((
                   SELECT action <> 'revoked' AND (consent_scope->>'health_steps_sensor')::boolean
                   FROM fz152_consent_journal WHERE user_id = u.id
                   ORDER BY recorded_at DESC, id DESC LIMIT 1
               ), false) AS step_scope,
               ($5::uuid IS NULL OR EXISTS (
                   SELECT 1 FROM auth_refresh_sessions s
                   WHERE s.user_id = $1 AND s.id = $5 AND s.device_fingerprint = $6
                     AND s.revoked_at IS NULL AND s.expires_at > now()
               )) AS session_active
        FROM users u
        LEFT JOIN daily_step_summaries d
            ON d.user_id = u.id AND d.activity_date = $2 AND d.validated_steps >= $3
           AND NOT EXISTS (SELECT 1 FROM point_ledger WHERE idempotency_key = $4)
        WHERE u.id = $1
        """,
        user_id,
        body.activity_date,
        body.raw_sensor_steps,
        key,
        session.principal.session_id if session is not None else None,
        session.fingerprint if session is not None else None,
    )
    if row is None or not row["session_active"]:
        raise CatalogException("AUTH_TOKEN_INVALID")
    return row


@retry_deadlock
async def sync_steps(
    connection: asyncpg.Connection,
    user_id: UUID,
    key: UUID,
    body: SyncDailyStepsRequest,
    *,
    session: AccessSession | None = None,
) -> DailyActivitySummaryResponse:
    snapshot = await _steps_snapshot(connection, user_id, key, body, session)
    now = datetime.now(UTC)
    if body.activity_date > (now + timedelta(minutes=body.timezone_offset_minutes)).date():
        raise CatalogException("ACTIVITY_DATE_IN_FUTURE")
    if body.raw_sensor_steps > 100_000:
        raise CatalogException("ANTIFRAUD_DAILY_STEP_CAP_EXCEEDED")
    if snapshot["id"] is not None:
        assert_activity_access(snapshot, from_sensor=True)
        return to_activity_summary(snapshot, balance=snapshot["points_balance"])
    async with connection.transaction():
        user = await _activity_user(connection, user_id)
        await connection.execute("SELECT pg_advisory_xact_lock(hashtextextended($1, 1))", str(key))
        replay = await _read_previous_request(connection, key, user_id, body.activity_date)
        current = await connection.fetchrow(
            "SELECT * FROM daily_step_summaries WHERE user_id = $1 AND activity_date = $2",
            user_id,
            body.activity_date,
        )
        if replay is not None and current is not None:
            return to_activity_summary(current, balance=user["points_balance"])
        return await _save_steps(connection, user, current, key, body, now)


async def _save_steps(
    connection: asyncpg.Connection,
    user: asyncpg.Record,
    current: asyncpg.Record | None,
    key: UUID,
    body: SyncDailyStepsRequest,
    now: datetime,
) -> DailyActivitySummaryResponse:
    previous_steps = current["validated_steps"] if current else 0
    previous_points = current["points_awarded_for_day"] if current else 0
    allocated_distance = current["allocated_gps_distance_m"] if current else Decimal(0)
    allocated_grams = current["allocated_co2_saved_grams"] if current else 0
    previous_co2 = current["total_co2_saved_grams"] if current else 0
    step_increase = body.raw_sensor_steps - previous_steps
    if current:
        elapsed = (now - current["last_synced_at"]).total_seconds()
        if elapsed >= 30 and step_increase > 500 and step_increase / elapsed > 4.5:
            raise CatalogException("ANTIFRAUD_STEP_SPIKE_DETECTED")
    validated = max(previous_steps, body.raw_sensor_steps)
    stride = body.stride_length_cm or (current["stride_length_cm"] if current else None)
    stride = stride or user["stride_length_cm"]
    if current and body.raw_sensor_steps <= previous_steps:
        # A stale snapshot must not overwrite the stride or timestamp of a newer one.
        return to_activity_summary(current, balance=user["points_balance"])
    estimate = max(Decimal(0), Decimal(validated * stride).scaleb(-2) - allocated_distance)
    auto_grams = automatic_emissions(estimate)
    total = allocated_grams + auto_grams
    reward = calculate_step_reward_delta(validated, previous_points)
    co2_delta = total - previous_co2
    summary = await connection.fetchrow(
        """
        INSERT INTO daily_step_summaries (
            user_id, activity_date, timezone_offset_minutes, raw_sensor_steps,
            validated_steps, stride_length_cm, auto_default_co2_saved_grams, points_awarded_for_day
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (user_id, activity_date) DO UPDATE SET
            raw_sensor_steps = EXCLUDED.raw_sensor_steps,
            validated_steps = EXCLUDED.validated_steps,
            stride_length_cm = EXCLUDED.stride_length_cm,
            timezone_offset_minutes = EXCLUDED.timezone_offset_minutes,
            auto_default_co2_saved_grams = EXCLUDED.auto_default_co2_saved_grams,
            points_awarded_for_day = EXCLUDED.points_awarded_for_day,
            last_synced_at = now()
        RETURNING *
        """,
        user["id"],
        body.activity_date,
        body.timezone_offset_minutes,
        body.raw_sensor_steps,
        validated,
        stride,
        auto_grams,
        previous_points + reward,
    )
    assert summary is not None  # noqa: S101 — INSERT ... RETURNING always returns one row.
    if reward:
        await connection.execute(
            """
            INSERT INTO point_ledger (
                user_id, idempotency_key, operation_type, points_delta, co2_delta_grams,
                reference_entity_type, reference_entity_id, description
            ) VALUES ($1, $2, 'daily_steps_reward', $3, $4, 'daily_step_summaries', $5, 'Шаги')
            """,
            user["id"],
            key,
            reward,
            co2_delta,
            summary["id"],
        )
    streak, freezes, active_date = _streak(user, body.activity_date, validated, total)
    await connection.execute(
        """
        UPDATE users SET
            lifetime_co2_saved_grams = GREATEST(0, lifetime_co2_saved_grams + $2::bigint),
            current_streak_days = $3, longest_streak_days = GREATEST(longest_streak_days, $3),
            streak_freeze_count = $4, last_active_local_date = $5, updated_at = now()
        WHERE id = $1
        """,
        user["id"],
        0 if reward else co2_delta,
        streak,
        freezes,
        active_date,
    )
    await social_repo.update_forest(
        connection,
        user["id"],
        body.activity_date,
        grams=co2_delta,
        steps=validated - previous_steps,
    )
    await badge_repo.award_badges(connection, user["id"])
    balance = await user_repo.load_points_balance(connection, user["id"])
    return to_activity_summary(summary, balance=balance, points_delta=reward)
