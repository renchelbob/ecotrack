from collections import OrderedDict
from decimal import Decimal
from uuid import UUID

import asyncpg
from app.api.errors import CatalogException
from app.api.v1.map_rso_models import (
    WasteFraction,
    WastePointDetailResponse,
    WastePointMapItem,
    WastePointsBboxResponse,
)

ATTRIBUTION = (
    "© Участники OpenStreetMap (ODbL 1.0) · Портал открытых данных data.mos.ru "
    "· Муниципальные реестры"
)

type Bounds = tuple[float, float, float, float]
type BboxKey = tuple[Bounds, int, bool, Decimal, tuple[WasteFraction, ...] | None]
BBOX_CACHE_LIMIT = 32
_bbox_cache: OrderedDict[BboxKey, tuple[str, bytes]] = OrderedDict()


async def bbox_account(
    connection: asyncpg.Connection, user_id: UUID, session_id: UUID, fingerprint: str
) -> asyncpg.Record:
    user = await connection.fetchrow(
        """
        SELECT is_152fz_consent_active, requires_formal_phone,
               ROW(current_database(), pg_postmaster_start_time(), pg_current_snapshot())::text
                   AS view_version
        FROM auth_refresh_sessions s JOIN users u ON u.id = s.user_id
        WHERE s.user_id = $1 AND s.id = $2 AND s.device_fingerprint = $3
              AND s.revoked_at IS NULL AND s.expires_at > now()
        """,
        user_id,
        session_id,
        fingerprint,
    )
    if user is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    return user


async def bbox_points(
    connection: asyncpg.Connection,
    bounds: Bounds,
    zoom: int,
    include_unverified: bool,
    trust: Decimal,
    fractions: list[WasteFraction] | None,
    view_version: str,
) -> bytes:
    # Reuse only public map data from the same PostgreSQL visibility snapshot.
    key = (bounds, zoom, include_unverified, trust, tuple(fractions) if fractions else None)
    cached = _bbox_cache.get(key)
    if cached is not None and cached[0] == view_version:
        _bbox_cache.move_to_end(key)
        return cached[1]

    params = (*bounds, include_unverified, trust, fractions)
    if zoom >= 13:
        rows = await connection.fetch(
            """
            SELECT id, title, address_text, accepted_fractions, ST_Y(geom) AS lat,
                   ST_X(geom) AS lon, status, trust_score, confirmations_count, issues_count,
                   ROW(current_database(), pg_postmaster_start_time(), pg_current_snapshot())::text
                       AS view_version
            FROM waste_points WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
                AND (status = 'active' OR ($5::boolean AND status = 'unverified'))
                AND trust_score >= $6
                AND ($7::waste_fraction_code[] IS NULL OR accepted_fractions && $7)
            ORDER BY trust_score DESC, confirmations_count DESC, id LIMIT 500
            """,
            *params,
        )
    else:
        rows = await connection.fetch(
            """
            WITH grouped AS (
                SELECT (array_agg(id ORDER BY trust_score DESC, id))[1] AS representative,
                       count(*) AS cluster_size, ST_Centroid(ST_Collect(geom)) AS center,
                       round(avg(trust_score), 2) AS trust_score,
                       sum(confirmations_count) AS confirmations_count,
                       sum(issues_count) AS issues_count
                FROM waste_points WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
                    AND (status = 'active' OR ($5::boolean AND status = 'unverified'))
                    AND trust_score >= $6
                    AND ($7::waste_fraction_code[] IS NULL OR accepted_fractions && $7)
                GROUP BY ST_SnapToGrid(geom, $8::double precision)
                ORDER BY cluster_size DESC, representative LIMIT 350
            )
            SELECT p.id, CASE WHEN g.cluster_size > 1
                       THEN p.title || ' (+' || (g.cluster_size - 1) || ')'
                       ELSE p.title END AS title,
                   p.address_text, p.accepted_fractions, p.status,
                   ST_Y(g.center) AS lat, ST_X(g.center) AS lon, g.trust_score,
                   g.confirmations_count, g.issues_count,
                   ROW(current_database(), pg_postmaster_start_time(), pg_current_snapshot())::text
                       AS view_version
            FROM grouped g JOIN waste_points p ON p.id = g.representative
            ORDER BY g.cluster_size DESC, p.id
            """,
            *params,
            360.0 / 2 ** (zoom + 3),
        )
    points = [
        WastePointMapItem.model_validate(
            {field: row[field] for field in WastePointMapItem.model_fields}
        )
        for row in rows
    ]
    payload = (
        WastePointsBboxResponse(
            attribution_banner_ru=ATTRIBUTION, total_returned=len(points), points=points
        )
        .model_dump_json()
        .encode()
    )
    if rows:
        # A commit may have occurred between the account check and the spatial query.
        _bbox_cache[key] = (rows[0]["view_version"], payload)
        _bbox_cache.move_to_end(key)
        if len(_bbox_cache) > BBOX_CACHE_LIMIT:
            _bbox_cache.popitem(last=False)
    return payload


async def point_detail(connection: asyncpg.Connection, point_id: UUID) -> WastePointDetailResponse:
    row = await connection.fetchrow(
        """
        SELECT id, title, address_text, accepted_fractions, ST_Y(geom) AS lat,
               ST_X(geom) AS lon, status, trust_score, confirmations_count, issues_count,
               operator_name, opening_hours, attribution_text, last_verified_at,
               updated_at,
               COALESCE((
                   SELECT jsonb_agg(to_jsonb(s) ORDER BY s.source_record_id)
                   FROM (
                       SELECT r.id AS source_record_id, r.source_type, r.external_record_id,
                              r.license_name, l.match_distance_m
                       FROM point_source_links l
                       JOIN rso_source_records r ON r.id = l.source_record_id
                       WHERE l.waste_point_id = $1
                   ) s
               ), '[]'::jsonb) AS sources,
               COALESCE((
                   SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC, r.id DESC)
                   FROM (
                       SELECT id, report_type, comment, distance_to_point_m, trust_delta, created_at
                       FROM point_reports WHERE waste_point_id = $1
                       ORDER BY created_at DESC, id DESC LIMIT 20
                   ) r
               ), '[]'::jsonb) AS recent_reports
        FROM waste_points WHERE id = $1
        """,
        point_id,
    )
    if row is None:
        raise CatalogException("WASTE_POINT_NOT_FOUND")
    return WastePointDetailResponse.model_validate(dict(row))
