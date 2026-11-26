from datetime import UTC, date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated

import asyncpg
from fastapi import APIRouter, Query, Response

from app.api.dependencies import Db, SignedAccess
from app.api.errors import CatalogException, ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.activity_models import (
    EcoEquivalentsMetrics,
    EcoEquivalentsResponse,
    EmissionsBucketItem,
    EmissionsStatisticsResponse,
    PaginatedActivityHistoryResponse,
    Period,
)
from app.application.activity_service import assert_activity_access, to_activity_summary
from app.application.auth_service import AccessSession

router = APIRouter(prefix=f"{API_PREFIX}/stats", tags=["Statistics"])
ERRORS: dict[int | str, dict[str, type[ErrorResponse]]] = {
    401: {"model": ErrorResponse},
    403: {"model": ErrorResponse},
    422: {"model": ErrorResponse},
}


async def _stats_user(connection: asyncpg.Connection, session: AccessSession) -> asyncpg.Record:
    row = await connection.fetchrow(
        """
        SELECT u.id, is_152fz_consent_active, requires_formal_phone, points_balance,
               lifetime_co2_saved_grams, COALESCE((
                   SELECT timezone_offset_minutes FROM daily_step_summaries
                   WHERE user_id = $1 ORDER BY activity_date DESC LIMIT 1
               ), 180) AS timezone_offset
        FROM auth_refresh_sessions s JOIN users u ON u.id = s.user_id
        WHERE s.user_id = $1 AND s.id = $2 AND s.device_fingerprint = $3
              AND s.revoked_at IS NULL AND s.expires_at > now()
        """,
        session.principal.user_id,
        session.principal.session_id,
        session.fingerprint,
    )
    if row is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    assert_activity_access(row)
    return row


def _equivalents(grams: int) -> EcoEquivalentsMetrics:
    value = Decimal(grams)
    return EcoEquivalentsMetrics(
        total_co2_saved_grams=grams,
        trees_planted_equivalent=float(
            (value / 20000).quantize(Decimal(".01"), rounding=ROUND_HALF_UP)
        ),
        car_km_avoided=float((value / 192).quantize(Decimal(".1"), rounding=ROUND_HALF_UP)),
        smartphone_charges_equivalent=int(value // Decimal("8.22")),
        plastic_bottles_recycled_equivalent=int(value // Decimal("82.80")),
        led_bulb_hours_equivalent=int(value // Decimal("3.40")),
    )


def _local_date(user: asyncpg.Record) -> date:
    return (datetime.now(UTC) + timedelta(minutes=user["timezone_offset"])).date()


@router.get("/history", operation_id="listActivityHistory", responses=ERRORS)
async def history(
    session: SignedAccess,
    connection: Db,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> PaginatedActivityHistoryResponse:
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        user = await _stats_user(connection, session)
        total: int = await connection.fetchval(
            "SELECT count(*) FROM daily_step_summaries WHERE user_id = $1", user["id"]
        )
        rows = await connection.fetch(
            """
            SELECT * FROM daily_step_summaries WHERE user_id = $1
            ORDER BY activity_date DESC LIMIT $2 OFFSET $3
            """,
            user["id"],
            limit,
            min(offset, total),
        )
    return PaginatedActivityHistoryResponse(
        total_count=total,
        limit=limit,
        offset=offset,
        items=[to_activity_summary(row, balance=user["points_balance"]) for row in rows],
    )


@router.get(
    "/emissions",
    operation_id="getEmissionsStatistics",
    response_model=EmissionsStatisticsResponse,
    responses=ERRORS,
)
async def emissions(
    session: SignedAccess, connection: Db, period: Period, reference_date: date | None = None
) -> Response:
    rows = await connection.fetch(
        """
        WITH account AS (
            SELECT u.is_152fz_consent_active, u.requires_formal_phone,
                   COALESCE($5::date, (
                       ($6::timestamptz AT TIME ZONE 'UTC') + make_interval(mins => COALESCE((
                           SELECT timezone_offset_minutes FROM daily_step_summaries
                           WHERE user_id = $1 ORDER BY activity_date DESC LIMIT 1
                       ), 180))
                   )::date) AS anchor
            FROM auth_refresh_sessions s JOIN users u ON u.id = s.user_id
            WHERE s.user_id = $1 AND s.id = $2 AND s.device_fingerprint = $3
              AND s.revoked_at IS NULL AND s.expires_at > now()
        ), starts AS (
            SELECT a.anchor, CASE $4::text
                WHEN 'days' THEN a.anchor - n
                WHEN 'weeks' THEN date_trunc('week', a.anchor::timestamp)::date - (7 * n)
                ELSE (date_trunc('month', a.anchor::timestamp) - make_interval(months => n))::date
            END AS start_date
            FROM account a
            CROSS JOIN LATERAL generate_series(0, CASE WHEN $4 = 'days' THEN 6 ELSE 11 END) AS n
        ), buckets AS (
            SELECT start_date, COALESCE(lead(start_date) OVER (ORDER BY start_date) - 1, anchor)
                       AS end_date
            FROM starts WHERE start_date >= DATE '0001-01-01'
        )
        SELECT a.is_152fz_consent_active, a.requires_formal_phone, a.anchor,
               b.start_date, b.end_date,
               COALESCE(sum(d.validated_steps), 0) AS validated_steps,
               COALESCE(sum(d.total_step_distance_m), 0) AS total_step_distance_m,
               COALESCE(sum(d.allocated_co2_saved_grams), 0) AS allocated_co2_saved_grams,
               COALESCE(sum(d.auto_default_co2_saved_grams), 0) AS auto_default_co2_saved_grams,
               COALESCE(sum(d.total_co2_saved_grams), 0) AS total_co2_saved_grams
        FROM account a LEFT JOIN buckets b ON true
        LEFT JOIN daily_step_summaries d ON d.user_id = $1
             AND d.activity_date BETWEEN b.start_date AND b.end_date
        GROUP BY a.is_152fz_consent_active, a.requires_formal_phone, a.anchor,
                 b.start_date, b.end_date
        ORDER BY b.start_date
        """,
        session.principal.user_id,
        session.principal.session_id,
        session.fingerprint,
        period,
        reference_date,
        datetime.now(UTC),
    )
    if not rows:
        raise CatalogException("AUTH_TOKEN_INVALID")
    assert_activity_access(rows[0])
    if rows[0]["anchor"].toordinal() <= 84:
        raise CatalogException("VALIDATION_ERROR")
    buckets = [
        EmissionsBucketItem.model_validate(
            {
                field: row[field]
                for field in EmissionsBucketItem.model_fields
                if field != "bucket_label"
            }
            | {"bucket_label": row["start_date"].isoformat()}
        )
        for row in rows
    ]
    grams = sum(bucket.total_co2_saved_grams for bucket in buckets)
    result = EmissionsStatisticsResponse(
        period=period,
        period_total_co2_saved_grams=grams,
        period_total_steps=sum(bucket.validated_steps for bucket in buckets),
        period_total_distance_m=sum(bucket.total_step_distance_m for bucket in buckets),
        buckets=buckets,
        equivalents=_equivalents(grams),
    )
    return Response(result.model_dump_json(), media_type="application/json")


@router.get("/equivalents", operation_id="getEcoEquivalentsSummary", responses=ERRORS)
async def equivalents(session: SignedAccess, connection: Db) -> EcoEquivalentsResponse:
    user = await _stats_user(connection, session)
    today = _local_date(user)
    week_grams: int = await connection.fetchval(
        """
        SELECT COALESCE(sum(total_co2_saved_grams), 0) FROM daily_step_summaries
        WHERE user_id = $1 AND activity_date BETWEEN $2 AND $3
        """,
        user["id"],
        today - timedelta(days=today.weekday()),
        today,
    )
    return EcoEquivalentsResponse(
        lifetime=_equivalents(user["lifetime_co2_saved_grams"]),
        current_week=_equivalents(week_grams),
    )
