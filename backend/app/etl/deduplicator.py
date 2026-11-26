from dataclasses import dataclass
from typing import Literal
from uuid import UUID

import asyncpg

ImportSource = Literal["osm_pbf", "data_mos_ru", "municipal_registry"]
PointClass = Literal["general", "recycling", "hazardous", "fandomat"]
LICENSES: dict[ImportSource, str] = {
    "osm_pbf": "ODbL-1.0",
    "data_mos_ru": "CC-BY-4.0-MosRu",
    "municipal_registry": "Open-Municipal-RU",
}
ATTRIBUTIONS: dict[ImportSource, str] = {
    "osm_pbf": "© Участники OpenStreetMap (ODbL 1.0)",
    "data_mos_ru": "Портал открытых данных data.mos.ru",
    "municipal_registry": "Муниципальный реестр",
}


@dataclass(frozen=True, slots=True)
class SourceRecord:
    source: ImportSource
    external_id: str
    raw_tags: dict[str, object]
    geometry: dict[str, object]
    title: str
    fractions: list[str]
    point_class: PointClass
    address: str | None = None
    operator: str | None = None
    hours: str | None = None


async def import_record(
    connection: asyncpg.Connection,
    record: SourceRecord,
    bounds: tuple[float, float, float, float],
) -> bool:
    source_id = await connection.fetchval(
        """
        WITH shape AS (
            SELECT ST_SetSRID(ST_GeomFromGeoJSON($5::jsonb), 4326) AS geom
        ), location AS (
            SELECT ST_PointOnSurface(geom) AS geom
            FROM shape WHERE ST_IsValid(geom) AND NOT ST_IsEmpty(geom)
        )
        INSERT INTO rso_source_records (source_type, external_record_id, license_name,
                                        raw_tags, geom)
        SELECT $1, $2, $3, $4::jsonb, geom FROM location
        WHERE geom && ST_MakeEnvelope($6, $7, $8, $9, 4326)
        ON CONFLICT (source_type, external_record_id) DO UPDATE SET
            raw_tags = EXCLUDED.raw_tags, geom = EXCLUDED.geom, imported_at = now()
        RETURNING id
        """,
        record.source,
        record.external_id,
        LICENSES[record.source],
        record.raw_tags,
        record.geometry,
        *bounds,
    )
    if not isinstance(source_id, UUID):
        return False
    point = await connection.fetchrow(
        """
        SELECT w.id, ST_Distance(w.geog, s.geom::geography) AS distance
        FROM rso_source_records s JOIN waste_points w
            ON ST_DWithin(w.geog, s.geom::geography, 20.0)
        LEFT JOIN point_source_links own
          ON own.source_record_id = s.id AND own.waste_point_id = w.id
        WHERE s.id = $1 AND w.status <> 'removed' AND (
            own.source_record_id IS NOT NULL OR
            CASE $2::text
                WHEN 'general' THEN
                    w.accepted_fractions = ARRAY['general_bin']::waste_fraction_code[]
                WHEN 'fandomat' THEN w.title ILIKE '%Фандомат%' OR EXISTS (
                    SELECT 1 FROM point_source_links l JOIN rso_source_records src
                      ON src.id = l.source_record_id WHERE l.waste_point_id = w.id
                      AND src.raw_tags->>'vending' = 'bottle_return'
                )
                WHEN 'hazardous' THEN w.accepted_fractions && $3::waste_fraction_code[]
                ELSE w.accepted_fractions <> ARRAY['general_bin']::waste_fraction_code[]
                     AND w.title NOT ILIKE '%Фандомат%'
            END
        )
        ORDER BY (own.source_record_id IS NOT NULL) DESC, w.geog <-> s.geom::geography, w.id
        LIMIT 1
        """,
        source_id,
        record.point_class,
        record.fractions,
    )
    if point is None:
        point_id = await connection.fetchval(
            """
            INSERT INTO waste_points (title, address_text, operator_name, opening_hours,
                                      accepted_fractions, geom, attribution_text)
            SELECT $2, $3, $4, $5, $6, geom, $7 FROM rso_source_records WHERE id = $1
            RETURNING id
            """,
            source_id,
            record.title,
            record.address,
            record.operator,
            record.hours,
            record.fractions,
            ATTRIBUTIONS[record.source],
        )
        distance = 0
    else:
        point_id = point["id"]
        distance = point["distance"]
        await connection.execute(
            """
            UPDATE waste_points SET accepted_fractions = ARRAY(
                SELECT DISTINCT unnest(accepted_fractions || $2::waste_fraction_code[]) ORDER BY 1
            ), updated_at = now()
            WHERE id = $1 AND NOT accepted_fractions @> $2::waste_fraction_code[]
            """,
            point_id,
            record.fractions,
        )
    await connection.execute(
        "DELETE FROM point_source_links WHERE source_record_id = $1 AND waste_point_id <> $2",
        source_id,
        point_id,
    )
    await connection.execute(
        """
        INSERT INTO point_source_links (waste_point_id, source_record_id, match_distance_m)
        VALUES ($1, $2, $3::double precision)
        ON CONFLICT (waste_point_id, source_record_id) DO UPDATE SET
            match_distance_m = EXCLUDED.match_distance_m
        """,
        point_id,
        source_id,
        distance,
    )
    return True
