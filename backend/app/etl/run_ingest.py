import argparse
import asyncio
import csv
import json
from collections.abc import Iterator
from itertools import batched
from pathlib import Path
from typing import cast, get_args

import asyncpg

from app.api.v1.map_rso_models import WasteFraction
from app.config import load_settings
from app.etl.deduplicator import LICENSES, ImportSource, PointClass, SourceRecord, import_record
from app.etl.mos_ru_ingestor import read_mos_dataset
from app.etl.osm_pbf_ingestor import normalize_osm, text_field
from app.infrastructure.db.pool import create_pool

DEFAULT_BOUNDS = (36.80, 55.10, 38.20, 56.10)


def _parse_bbox(value: str) -> tuple[float, float, float, float]:
    try:
        west, south, east, north = map(float, value.split(","))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("Expected west,south,east,north") from exc
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise argparse.ArgumentTypeError("Invalid bounding box")
    return west, south, east, north


def _read_osm(path: Path) -> Iterator[SourceRecord]:
    with path.open(encoding="utf-8") as source:
        for line in source:
            item = line.removeprefix("\x1e").strip()
            if item and (record := normalize_osm(json.loads(item))):
                yield record


def _read_registry(path: Path, kind: ImportSource) -> Iterator[SourceRecord]:
    with path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        columns = {"id", "title", "lon", "lat", "fractions"}
        if reader.fieldnames is None or not columns.issubset(reader.fieldnames):
            raise ValueError("Expected columns: id,title,lon,lat,fractions")
        for row in reader:
            external_id = text_field(row["id"], 128)
            title = text_field(row["title"], 160)
            fractions = sorted(
                {part.strip() for part in row["fractions"].split(";") if part.strip()}
            )
            if (
                not external_id
                or not title
                or not fractions
                or set(fractions) - set(get_args(WasteFraction))
            ):
                raise ValueError(f"Invalid record at line {reader.line_num}")
            lon, lat = float(row["lon"]), float(row["lat"])
            if not (-180 <= lon <= 180 and -90 <= lat <= 90):
                raise ValueError(f"Invalid coordinates at line {reader.line_num}")
            point_class: PointClass = "recycling"
            if fractions == ["general_bin"]:
                point_class = "general"
            elif set(fractions) <= {"batteries", "hazardous"}:
                point_class = "hazardous"
            elif title.casefold().startswith("фандомат"):
                point_class = "fandomat"
            yield SourceRecord(
                kind,
                external_id,
                dict(row),
                {"type": "Point", "coordinates": [lon, lat]},
                title,
                fractions,
                point_class,
                text_field(row.get("address"), 255),
                text_field(row.get("operator"), 120),
                text_field(row.get("opening_hours"), 160),
            )


async def ingest(records: Iterator[SourceRecord], bounds: tuple[float, float, float, float]) -> int:
    pool = await create_pool(load_settings())
    count = 0
    try:
        async with pool.acquire() as connection:
            for batch in batched(records, 200, strict=False):
                async with connection.transaction():
                    await connection.execute("SELECT pg_advisory_xact_lock(49731, 1)")
                    for record in batch:
                        count += await import_record(
                            cast(asyncpg.Connection, connection), record, bounds
                        )
    finally:
        await pool.close()
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, choices=LICENSES)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--input", type=Path)
    inputs.add_argument("--dataset-id", type=int)
    parser.add_argument("--fractions", nargs="+", choices=get_args(WasteFraction))
    parser.add_argument("--title-column", default="Name")
    parser.add_argument("--bbox", type=_parse_bbox, default=DEFAULT_BOUNDS)
    args = parser.parse_args()
    if args.dataset_id is not None:
        if args.source != "data_mos_ru" or args.dataset_id < 1 or not args.fractions:
            parser.error("--dataset-id requires --source data_mos_ru and --fractions")
        key = load_settings().data_mos_ru_api_key
        if key is None:
            parser.error("Set DATA_MOS_RU_API_KEY to use the API")
        records = read_mos_dataset(
            args.dataset_id,
            key.get_secret_value(),
            sorted(set(args.fractions)),
            title_column=args.title_column,
        )
    elif args.source == "osm_pbf":
        records = _read_osm(args.input)
    else:
        records = _read_registry(args.input, args.source)
    print(f"Imported source records: {asyncio.run(ingest(records, args.bbox))}")


if __name__ == "__main__":
    main()
