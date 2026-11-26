from typing import cast

from app.etl.deduplicator import PointClass, SourceRecord

TAG_FRACTIONS = {
    "plastic": ("plastic", "pet", "plastic_bottles"),
    "glass": ("glass", "glass_bottles"),
    "paper": ("paper", "cardboard", "books"),
    "metal": ("cans", "scrap_metal", "aluminium", "metal"),
    "tetra_pak": ("tetrapak", "beverage_cartons"),
    "batteries": ("batteries",),
    "electronics": ("electrical_appliances", "small_appliances"),
    "clothes": ("clothes", "shoes", "textiles"),
    "hazardous": ("low_energy_bulbs", "fluorescent_tubes", "mercury"),
    "caps": ("bottle_caps",),
}


def text_field(value: object, max_length: int) -> str | None:
    return value.strip()[:max_length] or None if isinstance(value, str) else None


def normalize_osm(feature: dict[str, object]) -> SourceRecord | None:
    properties = feature.get("properties")
    geometry = feature.get("geometry")
    external_id = feature.get("id")
    if not isinstance(properties, dict) or not isinstance(geometry, dict):
        return None
    tags = dict(cast(dict[str, object], properties))
    if external_id is None:
        external_id = tags.get("@id")
    if not isinstance(external_id, (str, int)) or len(str(external_id)) > 128:
        return None
    amenity = tags.get("amenity")
    is_machine = tags.get("vending") == "bottle_return" or tags.get("recycling_type") == "machine"
    if not is_machine and amenity not in ("recycling", "waste_basket", "waste_disposal"):
        return None
    fractions = [
        fraction
        for fraction, names in TAG_FRACTIONS.items()
        if any(tags.get(f"recycling:{name}") == "yes" for name in names)
    ]
    point_class: PointClass = "recycling"
    if is_machine:
        point_class = "fandomat"
        tags["vending"] = "bottle_return"
        fractions = fractions or ["mixed_recyclables"]
    elif fractions and set(fractions) <= {"batteries", "hazardous"}:
        point_class = "hazardous"
    elif not fractions and amenity != "recycling":
        point_class = "general"
        fractions = ["general_bin"]
    titles = {
        "recycling": "Пункт приёма вторсырья",
        "fandomat": "Фандомат",
        "general": "Контейнер для отходов",
        "hazardous": "Приём опасных отходов",
    }
    name = text_field(tags.get("name"), 160) or titles[point_class]
    if is_machine and not name.casefold().startswith("фандомат"):
        name = f"Фандомат · {name}"[:160]
    address = (
        " ".join(
            part
            for key in ("addr:street", "addr:housenumber")
            if (part := text_field(tags.get(key), 120))
        )
        or None
    )
    return SourceRecord(
        "osm_pbf",
        str(external_id),
        tags,
        cast(dict[str, object], geometry),
        name,
        fractions or ["mixed_recyclables"],
        point_class,
        address,
        text_field(tags.get("operator"), 120),
        text_field(tags.get("opening_hours"), 160),
    )
