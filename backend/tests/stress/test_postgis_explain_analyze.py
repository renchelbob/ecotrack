import json
import os
from collections.abc import Iterator
from decimal import Decimal
from uuid import uuid4

import asyncpg
import pytest

from app.infrastructure.db.repositories.map_rso_repo import BBOX_CLUSTERS_SQL, BBOX_POINTS_SQL
from app.infrastructure.db.repositories.track_repo import LAST_TRACK_POINT_SQL

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")


def _plan_nodes(node: dict) -> Iterator[dict]:
    yield node
    for child in node.get("Plans", []):
        yield from _plan_nodes(child)


@pytest.mark.parametrize("clustered", [False, True])
async def test_bbox_uses_index_on_25000_points(clustered: bool) -> None:
    connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
    transaction = connection.transaction()
    await transaction.start()
    try:
        await connection.execute(
            """
            INSERT INTO waste_points (title, accepted_fractions, geom)
            SELECT 'Index gate sample',
                   CASE WHEN n % 100 = 0 THEN ARRAY['plastic']::waste_fraction_code[]
                        ELSE ARRAY['glass']::waste_fraction_code[] END,
                   ST_SetSRID(ST_MakePoint(-40 + (n % 250) * 0.1, 10 + ((n / 250) * 0.1)), 4326)
            FROM generate_series(0, 24999) n
            """
        )
        await connection.execute("ANALYZE waste_points")
        sql = BBOX_CLUSTERS_SQL if clustered else BBOX_POINTS_SQL
        params = [-40.02, 9.98, -39.97, 10.03, False, Decimal(25), ["plastic"]]
        if clustered:
            params.append(360.0 / 2**15)
        raw = await connection.fetchval(f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {sql}", *params)
        (query,) = json.loads(raw)
        nodes = list(_plan_nodes(query["Plan"]))
        assert any(
            node.get("Index Name") in {"idx_waste_points_geom_gist", "idx_waste_points_fractions_gin"}
            and node["Node Type"] in {"Index Scan", "Bitmap Index Scan"}
            for node in nodes
        ), query
        assert not any(
            node.get("Relation Name") == "waste_points" and node["Node Type"] == "Seq Scan"
            for node in nodes
        ), query
        assert query["Execution Time"] < 15, query
    finally:
        await transaction.rollback()
        await connection.close()


async def test_gps_predecessor_uses_sequence_index() -> None:
    connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
    transaction = connection.transaction()
    await transaction.start()
    try:
        suffix = uuid4().hex.upper()
        user_id = await connection.fetchval(
            "INSERT INTO users (display_name, friend_code) VALUES ('Index test', $1) RETURNING id",
            f"ECO-{suffix[:4]}-{suffix[4:8]}",
        )
        tracks = await connection.fetch(
            """
            WITH days AS (
                INSERT INTO daily_step_summaries (user_id, activity_date)
                SELECT $1, CURRENT_DATE - n FROM generate_series(0, 49) n
                RETURNING id, activity_date
            )
            INSERT INTO gps_daily_tracks (user_id, daily_summary_id, activity_date)
            SELECT $1, id, activity_date FROM days RETURNING id
            """,
            user_id,
        )
        await connection.execute(
            """
            INSERT INTO gps_track_points (
                track_id, user_id, seq_no, recorded_at, lat, lon, accuracy_m, cumulative_steps
            )
            SELECT t.id, $1, n, now() + n * interval '1 second', 55.75, 37.6, 10, n
            FROM gps_daily_tracks t CROSS JOIN generate_series(0, 499) n WHERE t.user_id = $1
            """,
            user_id,
        )
        await connection.execute("ANALYZE gps_track_points")
        raw = await connection.fetchval(
            f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {LAST_TRACK_POINT_SQL}", tracks[0]["id"]
        )
        (query,) = json.loads(raw)
        nodes = list(_plan_nodes(query["Plan"]))
        assert any(
            node["Node Type"] in {"Index Scan", "Index Only Scan"}
            and node.get("Relation Name") == "gps_track_points"
            and "track_id" in node.get("Index Cond", "")
            for node in nodes
        ), query
        assert query["Execution Time"] < 15, query
    finally:
        await transaction.rollback()
        await connection.close()
