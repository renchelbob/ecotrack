import os
from uuid import uuid4

import asyncpg
import pytest

from app.etl.deduplicator import import_record
from app.etl.osm_pbf_ingestor import normalize_osm
from app.infrastructure.db.pool import configure_connection

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")


@pytest.mark.asyncio
async def test_osm_import_deduplicates_and_preserves_trust_on_repeat() -> None:
    records = [
        normalize_osm(
            {
                "id": uuid4().hex,
                "geometry": {"type": "Point", "coordinates": [37.6 + offset, 55.7]},
                "properties": {"amenity": "recycling", "recycling:glass": "yes"},
            }
        )
        for offset in (0, 0.0001)
    ]
    connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
    await configure_connection(connection)
    transaction = connection.transaction()
    await transaction.start()
    try:
        for record in records:
            assert record is not None
            assert await import_record(connection, record, (37, 55, 38, 56))
        external_ids = [record.external_id for record in records if record is not None]
        links = await connection.fetch(
            """
            SELECT l.waste_point_id, l.match_distance_m
            FROM point_source_links l JOIN rso_source_records s ON s.id = l.source_record_id
            WHERE s.external_record_id = ANY($1::varchar[]) ORDER BY l.match_distance_m
            """,
            external_ids,
        )
        assert len(links) == 2
        assert links[0]["waste_point_id"] == links[1]["waste_point_id"]
        assert 0 < links[1]["match_distance_m"] < 20
        point_id = links[0]["waste_point_id"]
        await connection.execute(
            "UPDATE waste_points SET trust_score = 72, confirmations_count = 3 WHERE id = $1",
            point_id,
        )
        first = records[0]
        assert first is not None
        assert await import_record(connection, first, (37, 55, 38, 56))
        stats = await connection.fetchrow(
            "SELECT trust_score, confirmations_count FROM waste_points WHERE id = $1", point_id
        )
        assert stats is not None
        assert (stats["trust_score"], stats["confirmations_count"]) == (72, 3)
    finally:
        await transaction.rollback()
        await connection.close()
