import json
import os

import asyncpg
import pytest

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")


@pytest.mark.asyncio
async def test_bbox_uses_gist_on_25000_points() -> None:
    connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
    transaction = connection.transaction()
    await transaction.start()
    try:
        await connection.execute(
            """
            INSERT INTO waste_points (title, accepted_fractions, geom)
            SELECT 'Index gate sample', ARRAY['glass']::waste_fraction_code[],
                   ST_SetSRID(ST_MakePoint(-40 + (n % 250) * 0.1, 10 + ((n / 250) * 0.1)), 4326)
            FROM generate_series(0, 24999) n
            """
        )
        await connection.execute("ANALYZE waste_points")
        raw = await connection.fetchval(
            """
            EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
            SELECT id, accepted_fractions FROM waste_points
            WHERE geom && ST_MakeEnvelope(-28.73, 12.07, -28.67, 12.13, 4326)
              AND status = 'active' AND trust_score >= 25
            ORDER BY trust_score DESC, confirmations_count DESC, id LIMIT 500
            """
        )
        (query,) = json.loads(raw)
        assert "idx_waste_points_geom_gist" in raw
        assert query["Execution Time"] < 15, query
    finally:
        await transaction.rollback()
        await connection.close()
