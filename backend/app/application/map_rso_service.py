from decimal import Decimal
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.map_rso_models import (
    SubmitWastePointReportRequest,
    SuggestWastePointRequest,
    WasteFraction,
    WastePointDetailResponse,
    WastePointReportCreatedResponse,
    WastePointReportItem,
)
from app.application.activity_service import assert_activity_access
from app.application.social_service import require_active_account
from app.domain.rso_trust import BASE_TRUST_DELTA
from app.infrastructure.db.repositories import badge_repo, map_rso_repo, user_repo
from app.infrastructure.db.transactions import retry_deadlock

POINT_REWARD_DESCRIPTION = "Проверка актуальности пункта РСО"  # noqa: RUF001


async def query_bbox(
    connection: asyncpg.Connection,
    account: asyncpg.Record,
    bounds: tuple[float, float, float, float],
    zoom: int,
    include_unverified: bool,
    trust: Decimal,
    fractions: list[WasteFraction] | None,
) -> bytes:
    min_lon, min_lat, max_lon, max_lat = bounds
    if min_lat >= max_lat or min_lon >= max_lon:
        raise CatalogException("INVALID_BBOX_COORDINATES")
    if zoom >= 13 and max(max_lat - min_lat, max_lon - min_lon) > 5:
        raise CatalogException("BBOX_AREA_TOO_LARGE_FOR_ZOOM")
    assert_activity_access(account)
    return await map_rso_repo.bbox_points(
        connection, bounds, zoom, include_unverified, trust, fractions, account["view_version"]
    )


async def read_point(
    connection: asyncpg.Connection, user_id: UUID, point_id: UUID
) -> WastePointDetailResponse:
    await require_active_account(connection, user_id)
    return await map_rso_repo.point_detail(connection, point_id)


@retry_deadlock
async def report_point(
    connection: asyncpg.Connection,
    user_id: UUID,
    key: UUID,
    point_id: UUID,
    body: SubmitWastePointReportRequest,
) -> WastePointReportCreatedResponse:
    async with connection.transaction():
        await user_repo.lock_user(connection, user_id)
        await require_active_account(connection, user_id)
        await connection.execute("SELECT pg_advisory_xact_lock(hashtextextended($1, 1))", str(key))
        previous = await connection.fetchrow(
            "SELECT * FROM point_reports WHERE idempotency_key = $1", key
        )
        if previous is not None:
            if (
                previous["user_id"],
                previous["waste_point_id"],
                previous["report_type"],
                previous["comment"],
                previous["user_lat"],
                previous["user_lon"],
            ) != (
                user_id,
                point_id,
                body.report_type,
                body.comment,
                body.user_lat,
                body.user_lon,
            ):
                raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
            return await _report_response(connection, point_id, previous)
        if await connection.fetchval("SELECT 1 FROM point_ledger WHERE idempotency_key = $1", key):
            raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
        row = await _insert_report(connection, user_id, key, point_id, body)
        await connection.execute(
            """
            INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta,
                                      reference_entity_type, reference_entity_id, description)
            VALUES ($1, $2, 'challenge_reward', 15, 'point_report', $3, $4)
            """,
            user_id,
            key,
            row["id"],
            POINT_REWARD_DESCRIPTION,
        )
        await badge_repo.award_badges(connection, user_id)
        return await _report_response(connection, point_id, row)


async def _insert_report(
    connection: asyncpg.Connection,
    user_id: UUID,
    key: UUID,
    point_id: UUID,
    body: SubmitWastePointReportRequest,
) -> asyncpg.Record:
    distance = await connection.fetchval(
        """
        SELECT ST_Distance(geog, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
        FROM waste_points WHERE id = $1 FOR UPDATE
        """,
        point_id,
        body.user_lon,
        body.user_lat,
    )
    if distance is None:
        raise CatalogException("WASTE_POINT_NOT_FOUND")
    if distance > 2000:
        raise CatalogException("REPORT_USER_TOO_FAR_FROM_POINT")
    if await connection.fetchval(
        """
        SELECT 1 FROM point_reports WHERE waste_point_id = $1 AND user_id = $2
          AND created_at > now() - interval '12 hours' LIMIT 1
        """,
        point_id,
        user_id,
    ):
        raise CatalogException("DUPLICATE_POINT_REPORT_COOLDOWN")
    row = await connection.fetchrow(
        """
        INSERT INTO point_reports (
            waste_point_id, user_id, idempotency_key, report_type, comment, user_lat, user_lon,
            distance_to_point_m, trust_delta
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *
        """,
        point_id,
        user_id,
        key,
        body.report_type,
        body.comment,
        body.user_lat,
        body.user_lon,
        Decimal(str(distance)),
        BASE_TRUST_DELTA[body.report_type],
    )
    if row is None:
        raise CatalogException("INTERNAL_SERVER_ERROR")
    return row


async def _report_response(
    connection: asyncpg.Connection, point_id: UUID, row: asyncpg.Record
) -> WastePointReportCreatedResponse:
    view = await connection.fetchrow(
        "SELECT trust_score, status FROM waste_points WHERE id = $1", point_id
    )
    if view is None:
        raise CatalogException("WASTE_POINT_NOT_FOUND")
    report = WastePointReportItem.model_validate(
        {field: row[field] for field in WastePointReportItem.model_fields}
    )
    return WastePointReportCreatedResponse(
        report=report,
        updated_trust_score=view["trust_score"],
        updated_status=view["status"],
        points_rewarded=15,
    )


@retry_deadlock
async def suggest_point(
    connection: asyncpg.Connection, user_id: UUID, key: UUID, body: SuggestWastePointRequest
) -> WastePointDetailResponse:
    async with connection.transaction():
        await user_repo.lock_user(connection, user_id)
        await require_active_account(connection, user_id)
        # Use one lock for the nearest-point check and insert across all map writers.
        await connection.execute("SELECT pg_advisory_xact_lock(49731, 1)")
        payload = body.model_dump(exclude={"comment"})
        payload["accepted_fractions"] = sorted(set(body.accepted_fractions))
        row = await connection.fetchrow(
            """
            SELECT l.waste_point_id, r.raw_tags
            FROM rso_source_records r JOIN point_source_links l ON l.source_record_id = r.id
            WHERE r.source_type = 'community_verified' AND r.external_record_id = $1
            """,
            str(key),
        )
        if row is not None:
            if row["raw_tags"] != payload:
                raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
            return await map_rso_repo.point_detail(connection, row["waste_point_id"])
        point_id = await _find_or_create_point(connection, body)
        await connection.execute(
            """
            WITH source AS (
                INSERT INTO rso_source_records (source_type, external_record_id, license_name,
                                                raw_tags, geom)
                VALUES ('community_verified', $1, 'EcoTrack-Community-1.0', $2::jsonb,
                        ST_SetSRID(ST_MakePoint($3, $4), 4326)) RETURNING id, geom
            )
            INSERT INTO point_source_links (waste_point_id, source_record_id, match_distance_m)
            SELECT $5, source.id, ST_Distance(source.geom::geography, w.geog)
            FROM source JOIN waste_points w ON w.id = $5
            """,
            str(key),
            payload,
            body.lon,
            body.lat,
            point_id,
        )
        return await map_rso_repo.point_detail(connection, point_id)


async def _find_or_create_point(
    connection: asyncpg.Connection, body: SuggestWastePointRequest
) -> UUID:
    fractions = sorted(set(body.accepted_fractions))
    point_id = await connection.fetchval(
        """
        WITH location AS (
            SELECT ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography AS geog
        )
        SELECT w.id FROM waste_points w CROSS JOIN location l
        WHERE ST_DWithin(w.geog, l.geog, 15) AND w.accepted_fractions && $3::waste_fraction_code[]
          AND w.status <> 'removed'
        ORDER BY w.geog <-> l.geog, w.id LIMIT 1
        """,
        body.lon,
        body.lat,
        fractions,
    )
    if isinstance(point_id, UUID):
        return point_id
    point_id = await connection.fetchval(
        """
        INSERT INTO waste_points (title, address_text, operator_name, opening_hours,
                                  accepted_fractions, geom, status, trust_score, attribution_text)
        VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($6, $7), 4326), 'unverified', 45,
                'Предложено сообществом EcoTrack (требует подтверждения)') RETURNING id
        """,
        body.title,
        body.address_text,
        body.operator_name,
        body.opening_hours,
        fractions,
        body.lon,
        body.lat,
    )
    if not isinstance(point_id, UUID):
        raise CatalogException("INTERNAL_SERVER_ERROR")
    return point_id
