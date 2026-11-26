from collections.abc import Sequence
from datetime import date
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.route_models import GpsTrackPointClassified, GpsTrackPointInput
from app.domain.motion_classifier import MotionRejected, classify_interval

POINT_FIELDS = (
    "seq_no",
    "recorded_at",
    "lat",
    "lon",
    "accuracy_m",
    "speed_mps",
    "cumulative_steps",
)


async def route_context(
    connection: asyncpg.Connection, user_id: UUID, activity_date: date
) -> asyncpg.Record:
    user = await connection.fetchrow(
        """
        SELECT u.id, u.stride_length_cm, u.points_balance, u.requires_formal_phone,
               u.is_152fz_consent_active,
               COALESCE((SELECT timezone_offset_minutes FROM daily_step_summaries
                         WHERE user_id = u.id AND activity_date = $2),
                        (SELECT timezone_offset_minutes FROM daily_step_summaries
                         WHERE user_id = u.id ORDER BY activity_date DESC LIMIT 1), 180) AS offset,
               COALESCE((SELECT action <> 'revoked'
                              AND (consent_scope->>'background_geolocation')::boolean
                         FROM fz152_consent_journal WHERE user_id = u.id
                         ORDER BY recorded_at DESC, id DESC LIMIT 1), false) AS gps_scope
        FROM users u WHERE u.id = $1
        """,
        user_id,
        activity_date,
    )
    if user is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    return user


async def ensure_track(
    connection: asyncpg.Connection, user: asyncpg.Record, activity_date: date
) -> UUID:
    await connection.execute(
        """
        INSERT INTO daily_step_summaries
            (user_id, activity_date, timezone_offset_minutes, stride_length_cm)
        VALUES ($1, $2, $3, $4) ON CONFLICT (user_id, activity_date) DO NOTHING
        """,
        user["id"],
        activity_date,
        user["offset"],
        user["stride_length_cm"],
    )
    track_id: UUID = await connection.fetchval(
        """
        INSERT INTO gps_daily_tracks (user_id, daily_summary_id, activity_date)
        SELECT user_id, id, activity_date FROM daily_step_summaries
        WHERE user_id = $1 AND activity_date = $2
        ON CONFLICT (user_id, activity_date) DO UPDATE SET activity_date = EXCLUDED.activity_date
        RETURNING id
        """,
        user["id"],
        activity_date,
    )
    return track_id


def _point_arrays(
    points: Sequence[GpsTrackPointInput | GpsTrackPointClassified],
) -> list[list[object]]:
    return [[getattr(point, field) for point in points] for field in POINT_FIELDS]


async def find_new_points(
    connection: asyncpg.Connection, track_id: UUID, points: list[GpsTrackPointInput]
) -> list[GpsTrackPointInput]:
    # Compare float4 inputs after a cast so precision in stored sensor readings
    # does not make an identical network retry appear to have different data.
    rows = await connection.fetch(
        """
        SELECT i.seq_no, p.seq_no AS existing,
               ROW(p.recorded_at, p.lat, p.lon, p.accuracy_m, p.speed_mps, p.cumulative_steps)
               IS NOT DISTINCT FROM
               ROW(i.recorded_at, i.lat, i.lon, i.accuracy_m, i.speed_mps, i.cumulative_steps)
               AS same
        FROM unnest($2::int[], $3::timestamptz[], $4::float8[], $5::float8[],
                    $6::real[], $7::real[], $8::int[])
            AS i(seq_no, recorded_at, lat, lon, accuracy_m, speed_mps, cumulative_steps)
        LEFT JOIN gps_track_points p ON p.track_id = $1 AND p.seq_no = i.seq_no
        ORDER BY i.seq_no
        """,
        track_id,
        *_point_arrays(points),
    )
    if any(row["existing"] is not None and not row["same"] for row in rows):
        raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
    return [point for point, row in zip(points, rows, strict=True) if row["existing"] is None]


async def classify_points(
    connection: asyncpg.Connection, track_id: UUID, points: list[GpsTrackPointInput]
) -> list[GpsTrackPointClassified]:
    previous = await connection.fetchrow(
        """
        SELECT seq_no, recorded_at, cumulative_steps FROM gps_track_points
        WHERE track_id = $1 ORDER BY seq_no DESC LIMIT 1
        """,
        track_id,
    )
    expected = previous["seq_no"] + 1 if previous else 0
    previous_at = previous["recorded_at"] if previous else None
    if any(point.seq_no != expected + i for i, point in enumerate(points)) or (
        previous_at is not None and points[0].recorded_at <= previous_at
    ):
        raise CatalogException("VALIDATION_ERROR")
    distances = await connection.fetch(
        """
        WITH incoming AS (
            SELECT seq_no, ST_SetSRID(ST_MakePoint(lon, lat), 4326) AS geom
            FROM unnest($2::int[], $3::float8[], $4::float8[]) AS p(seq_no, lon, lat)
        ), intervals AS (
            SELECT seq_no, geom, lag(geom, 1, (
                SELECT geom FROM gps_track_points WHERE track_id = $1
                ORDER BY seq_no DESC LIMIT 1
            )) OVER (ORDER BY seq_no) AS prev_geom FROM incoming
        )
        SELECT COALESCE(
            round(ST_Distance(geom::geography, prev_geom::geography)::numeric, 2), 0
        ) AS distance_m FROM intervals ORDER BY seq_no
        """,
        track_id,
        [point.seq_no for point in points],
        [point.lon for point in points],
        [point.lat for point in points],
    )
    previous_steps = previous["cumulative_steps"] if previous else 0
    classified: list[GpsTrackPointClassified] = []
    for point, row in zip(points, distances, strict=True):
        distance = row["distance_m"]
        if distance > 999_999.99:
            raise CatalogException("TRACK_POINT_INVALID_GEOMETRY")
        steps, motion = 0, "stationary"
        if previous_at is not None:
            try:
                interval = classify_interval(
                    float(distance),
                    (point.recorded_at - previous_at).total_seconds(),
                    point.accuracy_m,
                    previous_steps,
                    point.cumulative_steps,
                )
            except MotionRejected as exc:
                raise CatalogException(str(exc)) from exc
            steps, motion = interval.delta_steps, interval.motion_class
        classified.append(
            GpsTrackPointClassified.model_validate(
                point.model_dump()
                | {"delta_steps": steps, "delta_distance_m": distance, "motion_class": motion}
            )
        )
        previous_at, previous_steps = point.recorded_at, point.cumulative_steps
    return classified


async def append_track_points(
    connection: asyncpg.Connection,
    user_id: UUID,
    track_id: UUID,
    points: list[GpsTrackPointClassified],
) -> None:
    await connection.execute(
        """
        INSERT INTO gps_track_points (
            track_id, user_id, seq_no, recorded_at, lat, lon, accuracy_m, speed_mps,
            cumulative_steps, delta_steps, delta_distance_m, motion_class
        )
        SELECT $1, $2, i.seq_no, i.recorded_at, i.lat, i.lon, i.accuracy_m, i.speed_mps,
               i.steps, i.delta_steps, i.distance::numeric, i.motion::track_point_motion_class
        FROM unnest($3::int[], $4::timestamptz[], $5::float8[], $6::float8[],
                    $7::real[], $8::real[], $9::int[], $10::int[], $11::float8[], $12::text[])
            AS i(seq_no, recorded_at, lat, lon, accuracy_m, speed_mps, steps,
                 delta_steps, distance, motion)
        """,
        track_id,
        user_id,
        *_point_arrays(points),
        [point.delta_steps for point in points],
        [point.delta_distance_m for point in points],
        [point.motion_class for point in points],
    )
    await connection.execute(
        """
        UPDATE gps_daily_tracks SET point_count = totals.points,
            total_gps_walking_distance_m = totals.walking_distance,
            route_geom = CASE WHEN ST_IsValid(totals.route) THEN totals.route ELSE NULL END,
            updated_at = now()
        FROM (
            SELECT count(*)::int AS points,
                   COALESCE(sum(delta_distance_m) FILTER (WHERE motion_class = 'walking'), 0)
                       AS walking_distance,
                   CASE WHEN count(*) FILTER (WHERE motion_class <> 'unknown') >= 2 THEN
                       ST_MakeLine(geom ORDER BY seq_no) FILTER (WHERE motion_class <> 'unknown')
                   END AS route
            FROM gps_track_points WHERE track_id = $1
        ) totals WHERE id = $1
        """,
        track_id,
    )
