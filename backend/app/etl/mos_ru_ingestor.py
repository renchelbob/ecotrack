from collections.abc import Iterator
from typing import cast

import httpx

from app.etl.deduplicator import PointClass, SourceRecord
from app.etl.osm_pbf_ingestor import text_field

PAGE_SIZE = 500


def read_mos_dataset(
    dataset_id: int, api_key: str, fractions: list[str], *, title_column: str = "Name"
) -> Iterator[SourceRecord]:
    with httpx.Client(timeout=20, follow_redirects=False) as client:
        offset = 0
        while True:
            try:
                response = client.get(
                    f"https://apidata.mos.ru/v1/datasets/{dataset_id}/rows",
                    params={"api_key": api_key, "$top": PAGE_SIZE, "$skip": offset},
                )
            except httpx.RequestError:
                raise RuntimeError("Could not connect to the Moscow open-data portal") from None
            if not response.is_success:
                raise RuntimeError(f"Moscow open-data portal returned HTTP {response.status_code}")
            rows = response.json()
            if not isinstance(rows, list):
                raise ValueError("Expected a list of Moscow open-data rows")
            batch = cast(list[object], rows)
            for value in batch:
                record = _normalize_row(value, dataset_id, fractions, title_column)
                if record is not None:
                    yield record
            if len(batch) < PAGE_SIZE:
                return
            offset += PAGE_SIZE


def _normalize_row(
    value: object, dataset_id: int, fractions: list[str], title_column: str
) -> SourceRecord | None:
    if not isinstance(value, dict):
        return None
    row = cast(dict[str, object], value)
    metadata = row.get("Cells")
    external_id = row.get("global_id") or row.get("Number")
    if not isinstance(metadata, dict) or not isinstance(external_id, (str, int)):
        return None
    cells = cast(dict[str, object], metadata)
    geometry = cells.get("geoData") or row.get("geoData")
    if not isinstance(geometry, dict):
        return None
    title = text_field(cells.get(title_column), 160) or "Пункт приёма вторсырья"
    point_class: PointClass = "recycling"
    if fractions == ["general_bin"]:
        point_class = "general"
    elif set(fractions) <= {"batteries", "hazardous"}:
        point_class = "hazardous"
    return SourceRecord(
        source="data_mos_ru",
        external_id=f"{dataset_id}:{external_id}"[:128],
        raw_tags=row,
        geometry=cast(dict[str, object], geometry),
        title=title,
        fractions=fractions,
        point_class=point_class,
        address=text_field(cells.get("Address"), 255),
        operator=text_field(cells.get("Operator"), 120),
        hours=text_field(cells.get("WorkingHours"), 160),
    )
