from itertools import pairwise
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.route_models import RouteSegmentAllocationInput, RouteSegmentAllocationItem
from app.domain.hybrid_co2 import round_grams


async def list_allocations(
    connection: asyncpg.Connection, summary_id: UUID
) -> list[RouteSegmentAllocationItem]:
    rows = await connection.fetch(
        """
        SELECT a.id, a.idempotency_key, a.start_seq_no, a.end_seq_no, a.segment_distance_m,
               a.segment_steps, a.replaced_transport_mode, a.applied_co2_g_per_meter,
               a.confidence_factor, a.is_auto_calculated, a.co2_saved_grams,
               (SELECT jsonb_agg(jsonb_build_object('lat', p.lat, 'lon', p.lon) ORDER BY p.seq_no)
                FROM gps_track_points p WHERE p.track_id = a.track_id
                  AND p.seq_no BETWEEN a.start_seq_no AND a.end_seq_no) AS coordinates
        FROM route_segment_allocations a
        WHERE a.daily_summary_id = $1 ORDER BY a.start_seq_no
        """,
        summary_id,
    )
    return [RouteSegmentAllocationItem.model_validate(dict(row)) for row in rows]


def validate_allocations(items: list[RouteSegmentAllocationInput]) -> None:
    if len({item.idempotency_key for item in items}) != len(items):
        raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
    if any(item.start_seq_no >= item.end_seq_no for item in items):
        raise CatalogException("SEGMENT_SEQ_OUT_OF_BOUNDS")
    ordered = sorted(items, key=lambda item: item.start_seq_no)
    if any(left.end_seq_no > right.start_seq_no for left, right in pairwise(ordered)):
        raise CatalogException("SEGMENT_OVERLAP_CONFLICT")


async def replace_allocations(
    connection: asyncpg.Connection,
    summary: asyncpg.Record,
    track_id: UUID | None,
    items: list[RouteSegmentAllocationInput],
) -> None:
    validate_allocations(items)
    if items and track_id is None:
        raise CatalogException("SEGMENT_SEQ_OUT_OF_BOUNDS")
    keys = [item.idempotency_key for item in items]
    for key in sorted(keys):
        await connection.execute("SELECT pg_advisory_xact_lock(hashtextextended($1, 2))", str(key))
    existing = await connection.fetch(
        """
        SELECT daily_summary_id, idempotency_key, start_seq_no, end_seq_no, replaced_transport_mode
        FROM route_segment_allocations WHERE idempotency_key = ANY($1::uuid[])
        """,
        keys,
    )
    by_key = {row["idempotency_key"]: row for row in existing}
    for item in items:
        row = by_key.get(item.idempotency_key)
        if row is not None and (
            row["daily_summary_id"] != summary["id"]
            or row["start_seq_no"] != item.start_seq_no
            or row["end_seq_no"] != item.end_seq_no
            or row["replaced_transport_mode"] != item.replaced_transport_mode
        ):
            raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
        if row is None and track_id is not None:
            await _insert_allocation(connection, summary, track_id, item)
    await connection.execute(
        """
        DELETE FROM route_segment_allocations
        WHERE daily_summary_id = $1 AND NOT (idempotency_key = ANY($2::uuid[]))
        """,
        summary["id"],
        keys,
    )


async def _insert_allocation(
    connection: asyncpg.Connection,
    summary: asyncpg.Record,
    track_id: UUID,
    item: RouteSegmentAllocationInput,
) -> None:
    segment = await connection.fetchrow(
        """
        SELECT min(seq_no) AS first, max(seq_no) AS last,
               bool_or(motion_class = 'vehicle_suspected' AND seq_no > $2) AS vehicle_motion,
               sum(delta_distance_m) FILTER (WHERE seq_no > $2) AS distance_m,
               sum(delta_steps) FILTER (WHERE seq_no > $2) AS steps,
               CASE WHEN count(*) >= 2 THEN ST_IsValid(ST_MakeLine(geom ORDER BY seq_no)) END
                  AS valid_line
        FROM gps_track_points WHERE track_id = $1 AND seq_no BETWEEN $2 AND $3
        """,
        track_id,
        item.start_seq_no,
        item.end_seq_no,
    )
    if (
        segment is None
        or segment["first"] != item.start_seq_no
        or segment["last"] != item.end_seq_no
    ):
        raise CatalogException("SEGMENT_SEQ_OUT_OF_BOUNDS")
    if segment["vehicle_motion"]:
        raise CatalogException("SEGMENT_CONTAINS_VEHICLE_MOTION")
    if not segment["valid_line"] or not segment["distance_m"] or segment["steps"] > 2_147_483_647:
        raise CatalogException("TRACK_POINT_INVALID_GEOMETRY")
    factor = await connection.fetchval(
        """
        SELECT COALESCE(CASE WHEN m.is_personal_vehicle_slot THEN v.computed_co2_g_per_meter END,
                        m.co2_grams_per_meter)
        FROM transport_emission_catalog m LEFT JOIN user_vehicles v ON v.user_id = $1
        WHERE m.mode_code = $2::transport_mode_code
        """,
        summary["user_id"],
        item.replaced_transport_mode,
    )
    if factor is None:
        raise CatalogException("INTERNAL_SERVER_ERROR")
    grams = round_grams(segment["distance_m"] * factor)
    await connection.execute(
        """
        INSERT INTO route_segment_allocations (
            daily_summary_id, track_id, user_id, activity_date, start_seq_no, end_seq_no,
            segment_geom, segment_distance_m, segment_steps, replaced_transport_mode,
            applied_co2_g_per_meter, co2_saved_grams, idempotency_key
        )
        SELECT $1, $2, $3, $4, $5, $6, ST_MakeLine(geom ORDER BY seq_no), $7, $8, $9, $10, $11, $12
        FROM gps_track_points WHERE track_id = $2 AND seq_no BETWEEN $5 AND $6
        """,
        summary["id"],
        track_id,
        summary["user_id"],
        summary["activity_date"],
        item.start_seq_no,
        item.end_seq_no,
        segment["distance_m"],
        segment["steps"],
        item.replaced_transport_mode,
        factor,
        grams,
        item.idempotency_key,
    )
