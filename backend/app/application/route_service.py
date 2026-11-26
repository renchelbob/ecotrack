from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from itertools import pairwise
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.route_models import (
    DailyActivityDetailResponse,
    GpsTrackPointClassified,
    GpsTrackPointsBatchRequest,
    GpsTrackPointsBatchResponse,
    RouteSegmentAllocationInput,
)
from app.application.activity_service import assert_activity_access, to_activity_summary
from app.domain.hybrid_co2 import automatic_emissions
from app.infrastructure.db.repositories import badge_repo, social_repo
from app.infrastructure.db.repositories.allocation_repo import (
    list_allocations,
    replace_allocations,
)
from app.infrastructure.db.repositories.track_repo import (
    append_track_points,
    classify_points,
    ensure_track,
    find_new_points,
    route_context,
)
from app.infrastructure.db.repositories.user_repo import load_points_balance, lock_user
from app.infrastructure.db.transactions import retry_deadlock


def _local_today(user: asyncpg.Record) -> date:
    return (datetime.now(UTC) + timedelta(minutes=user["offset"])).date()


def _editable(user: asyncpg.Record, activity_date: date) -> bool:
    return (_local_today(user) - activity_date).days in (0, 1)


async def ingest_track(
    connection: asyncpg.Connection, user_id: UUID, body: GpsTrackPointsBatchRequest
) -> GpsTrackPointsBatchResponse:
    async with connection.transaction():
        await lock_user(connection, user_id)
        user = await route_context(connection, user_id, body.activity_date)
        assert_activity_access(user)
        if not user["gps_scope"]:
            raise CatalogException("FZ152_GEOLOCATION_CONSENT_MISSING")
        if body.activity_date > _local_today(user):
            raise CatalogException("ACTIVITY_DATE_IN_FUTURE")
        if any(
            left.seq_no >= right.seq_no or left.recorded_at >= right.recorded_at
            for left, right in pairwise(body.points)
        ):
            raise CatalogException("VALIDATION_ERROR")
        track_id = await ensure_track(connection, user, body.activity_date)
        fresh = await find_new_points(connection, track_id, body.points)
        if fresh:
            classified = await classify_points(connection, track_id, fresh)
            await append_track_points(connection, user_id, track_id, classified)
        counts = await connection.fetchrow(
            """
            SELECT point_count, total_gps_walking_distance_m FROM gps_daily_tracks WHERE id = $1
            """,
            track_id,
        )
        if counts is None:
            raise CatalogException("INTERNAL_SERVER_ERROR")
        return GpsTrackPointsBatchResponse(
            track_id=track_id,
            activity_date=body.activity_date,
            ingested_count=len(fresh),
            total_point_count=counts["point_count"],
            total_gps_walking_distance_m=counts["total_gps_walking_distance_m"],
        )


async def _activity_rows(
    connection: asyncpg.Connection, user_id: UUID, activity_date: date
) -> tuple[asyncpg.Record, asyncpg.Record | None]:
    summary = await connection.fetchrow(
        "SELECT * FROM daily_step_summaries WHERE user_id = $1 AND activity_date = $2",
        user_id,
        activity_date,
    )
    if summary is None:
        raise CatalogException("DAILY_ACTIVITY_NOT_FOUND")
    track = await connection.fetchrow(
        """
        SELECT id, total_gps_walking_distance_m FROM gps_daily_tracks
        WHERE daily_summary_id = $1
        """,
        summary["id"],
    )
    return summary, track


async def _details(
    connection: asyncpg.Connection,
    user: asyncpg.Record,
    summary: asyncpg.Record,
    track: asyncpg.Record | None,
    co2_delta: int = 0,
) -> DailyActivityDetailResponse:
    points: list[GpsTrackPointClassified] = []
    if track is not None:
        rows = await connection.fetch(
            """
            SELECT seq_no, recorded_at, lat, lon, accuracy_m, speed_mps, cumulative_steps,
                   delta_steps, delta_distance_m, motion_class
            FROM gps_track_points WHERE track_id = $1 ORDER BY seq_no
            """,
            track["id"],
        )
        points = [GpsTrackPointClassified.model_validate(dict(row)) for row in rows]
    return DailyActivityDetailResponse(
        summary=to_activity_summary(
            summary, balance=await load_points_balance(connection, user["id"])
        ),
        is_editable=_editable(user, summary["activity_date"]),
        total_gps_walking_distance_m=track["total_gps_walking_distance_m"] if track else 0,
        track_points=points,
        allocations=await list_allocations(connection, summary["id"]),
        co2_delta_applied_grams=co2_delta,
    )


async def read_activity(
    connection: asyncpg.Connection, user_id: UUID, activity_date: date
) -> DailyActivityDetailResponse:
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        user = await route_context(connection, user_id, activity_date)
        assert_activity_access(user)
        summary, track = await _activity_rows(connection, user_id, activity_date)
        return await _details(connection, user, summary, track)


async def _reload_summary(
    connection: asyncpg.Connection, summary: asyncpg.Record
) -> tuple[asyncpg.Record, int]:
    totals = await connection.fetchrow(
        """
        SELECT COALESCE(sum(segment_distance_m), 0) AS allocated_m,
               COALESCE(sum(co2_saved_grams), 0) AS allocated_grams,
               count(*) = 0 AS automatic
        FROM route_segment_allocations WHERE daily_summary_id = $1
        """,
        summary["id"],
    )
    if totals is None:
        raise CatalogException("INTERNAL_SERVER_ERROR")
    remaining = max(Decimal(0), summary["total_step_distance_m"] - totals["allocated_m"])
    grams = automatic_emissions(remaining)
    if totals["allocated_m"] > 99_999_999.99 or totals["allocated_grams"] + grams > 2_147_483_647:
        raise CatalogException("TRACK_POINT_INVALID_GEOMETRY")
    updated = await connection.fetchrow(
        """
        UPDATE daily_step_summaries SET allocated_gps_distance_m = $2,
            allocated_co2_saved_grams = $3, auto_default_co2_saved_grams = $4,
            is_auto_calculated = $5
        WHERE id = $1 RETURNING *
        """,
        summary["id"],
        totals["allocated_m"],
        totals["allocated_grams"],
        grams,
        totals["automatic"],
    )
    if updated is None:
        raise CatalogException("DAILY_ACTIVITY_NOT_FOUND")
    delta = updated["total_co2_saved_grams"] - summary["total_co2_saved_grams"]
    if delta:
        await connection.execute(
            """
            UPDATE users
            SET lifetime_co2_saved_grams = GREATEST(0, lifetime_co2_saved_grams + $2::bigint),
                updated_at = now()
            WHERE id = $1
            """,
            summary["user_id"],
            delta,
        )
        await social_repo.update_forest(
            connection, summary["user_id"], summary["activity_date"], grams=delta
        )
        await badge_repo.award_badges(connection, summary["user_id"])
    return updated, delta


async def _lock_edit_context(
    connection: asyncpg.Connection, user_id: UUID, activity_date: date
) -> tuple[asyncpg.Record, asyncpg.Record, asyncpg.Record | None]:
    await lock_user(connection, user_id)
    user = await route_context(connection, user_id, activity_date)
    assert_activity_access(user)
    if not _editable(user, activity_date):
        raise CatalogException("EDIT_WINDOW_EXPIRED")
    summary, track = await _activity_rows(connection, user_id, activity_date)
    return user, summary, track


@retry_deadlock
async def save_allocations(
    connection: asyncpg.Connection,
    user_id: UUID,
    activity_date: date,
    items: list[RouteSegmentAllocationInput],
) -> DailyActivityDetailResponse:
    async with connection.transaction():
        user, summary, track = await _lock_edit_context(connection, user_id, activity_date)
        await replace_allocations(connection, summary, track["id"] if track else None, items)
        summary, delta = await _reload_summary(connection, summary)
        return await _details(connection, user, summary, track, delta)


@retry_deadlock
async def remove_allocation(
    connection: asyncpg.Connection, user_id: UUID, activity_date: date, allocation_id: UUID
) -> DailyActivityDetailResponse:
    async with connection.transaction():
        user, summary, track = await _lock_edit_context(connection, user_id, activity_date)
        deleted = await connection.fetchval(
            """
            DELETE FROM route_segment_allocations
            WHERE id = $1 AND daily_summary_id = $2 RETURNING id
            """,
            allocation_id,
            summary["id"],
        )
        if deleted is None:
            raise CatalogException("ALLOCATION_NOT_FOUND")
        summary, delta = await _reload_summary(connection, summary)
        return await _details(connection, user, summary, track, delta)
