# 04 — PostGIS Spatial Queries & RSO/Waste Data Pipeline Specification

> **Target Audience**: Developer 1 (Backend, PostGIS & ETL) & Developer 2 (Map Client Integration)
> **Governing Contracts**: `contracts/schema.sql`, `contracts/openapi.yaml`, `contracts/error_catalog.json`
> **Runtime Constraint**: Zero C-GIS libraries (`GDAL`, `Shapely`, `GeoPandas`, `Fiona`, `PyProj`) in the Python 3.14 runtime image (`<= 100 MB`). Every geometric construction, validity check, distance calculation, and spatial index scan executes inside PostgreSQL 17 + PostGIS 3.5 (`postgis/postgis:17-3.5-alpine`).

---

## 1. Legal Data Sources & ODbL 1.0 / CC BY 4.0 Isolation Architecture

### 1.1 Approved Legal Open Data Sources (MVP)

| Source Identifier (`rso_source_type`) | Upstream Provider | License (`license_name`) | Ingestion Mechanism & Scope |
| :--- | :--- | :--- | :--- |
| `'osm_pbf'` | OpenStreetMap via Geofabrik regional extract (`central-fed-district-latest.osm.pbf` or Moscow/MO slice) | `ODbL-1.0` | Filtered offline via `osmium tags-filter` + `osmium export` to GeoJSONSeq before PostGIS ingestion |
| `'data_mos_ru'` | Moscow Government Open Data Portal (`apidata.mos.ru/v1/datasets/...`) | `CC-BY-4.0-MosRu` | Paginated REST API v1 (`$top=500&$skip=N`) with official API key |
| `'municipal_registry'` | Regional & municipal open data portals (published CSV/GeoJSON registries of RSO containers) | `Open-Municipal-RU` | Normalized UTF-8 CSV/GeoJSON batch loader |
| `'community_verified'` | EcoTrack authenticated users via `POST /api/v1/map/waste-points/suggestions` | `EcoTrack-Community-1.0` | Direct API submission with `15 m` proximity deduplication |

> **Future Partner Extension Boundary**: External commercial/NGO aggregators such as `kudasdat.ru` or `Собиратор` may be ingested **only** after signing a written data-partnership agreement and adding a dedicated partner adapter.

### 1.2 Explicitly Forbidden & Deprecated Sources
1. **Forbidden State & Commercial Scraping**: Writing scrapers or reverse-engineering private map APIs for `utko.mnr.gov.ru`, `gisopvk.ru`, `uberu.reo.ru`, Yandex Maps, or 2GIS is **STRICTLY FORBIDDEN** (violates Russian copyright law and Computer Information access rules).
2. **Deprecated / Closed Projects**: `recyclemap.ru` (former Greenpeace Russia project, closed/archived) and `+1Город` (`plus-one.ru`, shut down) are **defunct** and must never be referenced or queried in code or documentation.

### 1.3 ODbL 1.0 Collective Database Isolation (`rso_source_records` $\to$ `point_source_links` $\to$ `waste_points`)
To comply with OpenStreetMap **ODbL 1.0 Section 4.5 (Collective Databases vs. Derivative Databases)** and ensure ETL re-runs never overwrite user crowdsourced trust data:
1. **`rso_source_records` (Raw Source Layer)**: Stores verbatim upstream coordinates (`geom`), `source_type`, `external_record_id`, `license_name`, and `raw_tags` (`JSONB`). Each upstream source is isolated by `UNIQUE (source_type, external_record_id)`.
2. **`waste_points` (Canonical Presentation Layer)**: Stores deduplicated display points, aggregated `accepted_fractions`, `status`, and crowdsourced `trust_score`, `confirmations_count`, and `issues_count`.
3. **`point_source_links` (Provenance Join Table)**: Maps each `waste_point_id` to one or more `source_record_id` rows along with `match_distance_m`.
4. **Non-Destructive ETL Invariant**: When the ETL pipeline re-runs on a newer OSM PBF or `data.mos.ru` dump, it updates `rso_source_records` and merges newly discovered `accepted_fractions` into `waste_points`, but **NEVER** resets `waste_points.trust_score`, `confirmations_count`, `issues_count`, or `last_verified_at`.

---

## 2. Offline / Standalone ETL Pipeline (`scripts/osm_ingest/` & `backend/app/etl/`)

### 2.1 Pre-Ingestion OSM PBF Filtering (`scripts/osm_ingest/filter_osm_pbf.sh`)
Never import an unfiltered multi-gigabyte Geofabrik PBF into a developer laptop's PostGIS container. The shell pipeline below filters a regional PBF strictly to recycling/waste tags and exports point centroids (`GeoJSONSeq`, RFC 8142), shrinking a `3.5 GB` regional PBF to `~18 MB` in under 15 seconds:

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT_PBF="${1:?Usage: filter_osm_pbf.sh <region.osm.pbf> <output.geojsonseq>}"
OUTPUT_GEOJSONSEQ="${2:?Usage: filter_osm_pbf.sh <region.osm.pbf> <output.geojsonseq>}"
TEMP_FILTERED_PBF="$(mktemp -u /tmp/ecotrack_rso_filtered.XXXXXX.osm.pbf)"
trap 'rm -f "${TEMP_FILTERED_PBF}"' EXIT

# Step 1: Retain only nodes, ways, and relations tagged for recycling or waste collection
osmium tags-filter "${INPUT_PBF}" \
  nwr/amenity=recycling \
  nwr/amenity=waste_basket \
  nwr/amenity=waste_disposal \
  --overwrite \
  -o "${TEMP_FILTERED_PBF}"

# Step 2: Export to line-delimited GeoJSONSeq, converting polygon ways to point centroids
osmium export "${TEMP_FILTERED_PBF}" \
  --geometry-types=point \
  --add-unique-id=type_id \
  --output-format=geojsonseq \
  --overwrite \
  -o "${OUTPUT_GEOJSONSEQ}"
```

### 2.2 Canonical Tag-to-Fraction Mapping Table
Both `backend/app/etl/osm_pbf_ingestor.py` and `backend/app/etl/mos_ru_ingestor.py` normalize upstream tags into the exact `waste_fraction_code[]` ENUM array defined in `contracts/schema.sql`:

| Upstream Tag / Field (`OSM` or `data.mos.ru`) | Mapped `waste_fraction_code` | Point Compatibility Class (for Deduplication) |
| :--- | :--- | :--- |
| `recycling:plastic=yes`, `recycling:pet=yes`, `recycling:plastic_bottles=yes`, `"Пластик"` | `'plastic'` | `RECYCLING_POINT` |
| `recycling:glass=yes`, `recycling:glass_bottles=yes`, `"Стекло"` | `'glass'` | `RECYCLING_POINT` |
| `recycling:paper=yes`, `recycling:cardboard=yes`, `recycling:books=yes`, `"Бумага / Картон"` | `'paper'` | `RECYCLING_POINT` |
| `recycling:cans=yes`, `recycling:scrap_metal=yes`, `recycling:aluminium=yes`, `"Металл"` | `'metal'` | `RECYCLING_POINT` |
| `recycling:tetrapak=yes`, `recycling:beverage_cartons=yes`, `"Тетрапак"` | `'tetra_pak'` | `RECYCLING_POINT` |
| `recycling:batteries=yes`, `"Батарейки и аккумуляторы"` | `'batteries'` | `HAZARDOUS_BOX` |
| `recycling:electrical_appliances=yes`, `recycling:small_appliances=yes`, `"Электроника"` | `'electronics'` | `RECYCLING_POINT` |
| `recycling:clothes=yes`, `recycling:shoes=yes`, `recycling:textiles=yes`, `"Одежда"` | `'clothes'` | `RECYCLING_POINT` |
| `recycling:low_energy_bulbs=yes`, `recycling:fluorescent_tubes=yes`, `recycling:mercury=yes`, `"Опасные отходы"` | `'hazardous'` | `HAZARDOUS_BOX` |
| `recycling:bottle_caps=yes`, `"Добрые крышечки"` | `'caps'` | `RECYCLING_POINT` |
| `vending=bottle_return`, `recycling_type=machine`, `amenity=recycling` with no specific fraction tags, `"Фандомат / Вторсырьё"` | `'mixed_recyclables'` | `FANDOMAT` (if `vending=bottle_return`) or `RECYCLING_POINT` |
| `amenity=waste_basket`, `amenity=waste_disposal` (without `recycling:*=yes` tags) | `'general_bin'` | `GENERAL_BIN` |

### 2.3 Idempotent Source Upsert & PostGIS 20m Spatial Deduplication SQL
The ETL pipeline executes in two phases inside a database transaction:

**Phase 1 — Upsert into `rso_source_records`**:
```sql
INSERT INTO rso_source_records (
    source_type,
    external_record_id,
    license_name,
    raw_tags,
    geom,
    imported_at,
    source_updated_at
)
VALUES (
    $1::rso_source_type,
    $2,
    $3,
    $4::jsonb,
    ST_SetSRID(ST_MakePoint($5, $6), 4326),
    NOW(),
    $7
)
ON CONFLICT (source_type, external_record_id)
DO UPDATE SET
    raw_tags = EXCLUDED.raw_tags,
    geom = EXCLUDED.geom,
    imported_at = NOW(),
    source_updated_at = EXCLUDED.source_updated_at
RETURNING id;
```

**Phase 2 — Spatial Deduplication (`20.0 m` Radius + Class Guard)**:
To prevent merging a sidewalk trash bin (`'general_bin'`) with a nearby fandomat or multi-fraction RSO container, candidate matching enforces:
1. `ST_DWithin(w.geog, s.geom::geography, 20.0)` (uses `idx_waste_points_geog_gist`).
2. **Compatibility Guard**:
   - A source containing only `ARRAY['general_bin']::waste_fraction_code[]` matches ONLY an existing `waste_points` row whose `accepted_fractions = ARRAY['general_bin']::waste_fraction_code[]`.
   - A source representing a fandomat (`raw_tags->>'vending' = 'bottle_return'`) matches ONLY an existing `waste_points` row whose `title ILIKE '%Фандомат%'` or shares an existing fandomat link.
   - Multi-fraction recycling points match only other recycling points (`NOT (w.accepted_fractions = ARRAY['general_bin']::waste_fraction_code[])`).

```sql
-- Find nearest compatible canonical waste_point within 20 meters
SELECT
    w.id AS waste_point_id,
    ROUND(ST_Distance(w.geog, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography)::NUMERIC, 2) AS distance_m
FROM waste_points w
WHERE ST_DWithin(w.geog, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, 20.0)
  AND (
      ($3::boolean = TRUE AND w.accepted_fractions = ARRAY['general_bin']::waste_fraction_code[])
      OR ($3::boolean = FALSE AND w.accepted_fractions <> ARRAY['general_bin']::waste_fraction_code[])
  )
ORDER BY w.geog <-> ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography ASC
LIMIT 1;
```
- If a match is found:
  1. Merge any new fractions into `waste_points.accepted_fractions` via `ARRAY(SELECT DISTINCT unnest(w.accepted_fractions || $2::waste_fraction_code[]) ORDER BY 1)`.
  2. Insert `(waste_point_id, source_record_id, match_distance_m)` into `point_source_links` (`ON CONFLICT DO NOTHING`).
- If no match is found:
  1. Insert a new canonical row into `waste_points` (`trust_score = 50.00`, `status = 'active'`).
  2. Link it in `point_source_links` with `match_distance_m = 0.00`.

---

## 3. Runtime PostGIS Queries (`map_rso_repo.py`)

### 3.1 Bounding Box Validation Guards (`map_rso_service.py`)
Before executing any spatial SQL on `GET /api/v1/map/waste-points`:
1. If `min_lat >= max_lat` or `min_lon >= max_lon`, raise `400 INVALID_BBOX_COORDINATES`.
2. If `zoom >= 13` and `(max_lat - min_lat > 5.0 OR max_lon - min_lon > 5.0)`, raise `400 BBOX_AREA_TOO_LARGE_FOR_ZOOM`.

### 3.2 Low-Zoom Server-Side Grid Aggregation (`zoom <= 12`)
When `zoom <= 12`, returning thousands of individual pins wastes bandwidth. The repository snaps points within the BBox to a dynamic degree grid (`grid_size_deg = 360.0 / (2 ^ (zoom + 3))`) using `idx_waste_points_geom_gist`:

```sql
WITH bbox_filtered AS (
    SELECT
        id,
        title,
        address_text,
        accepted_fractions,
        geom,
        status,
        trust_score,
        confirmations_count,
        issues_count
    FROM waste_points
    WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
      AND (
          status = 'active'
          OR ($5::boolean = TRUE AND status = 'unverified')
      )
      AND trust_score >= $6
      AND (
          $7::waste_fraction_code[] IS NULL
          OR accepted_fractions && $7::waste_fraction_code[]
      )
),
grid_cells AS (
    SELECT
        (ARRAY_AGG(id ORDER BY trust_score DESC, id ASC))[1] AS rep_id,
        COUNT(*)::INT AS cluster_size,
        ST_Y(ST_Centroid(ST_Collect(geom))) AS centroid_lat,
        ST_X(ST_Centroid(ST_Collect(geom))) AS centroid_lon,
        (ARRAY_AGG(title ORDER BY trust_score DESC))[1] AS rep_title,
        (ARRAY_AGG(address_text ORDER BY trust_score DESC))[1] AS rep_address,
        (ARRAY_AGG(accepted_fractions ORDER BY trust_score DESC))[1] AS rep_fractions,
        (ARRAY_AGG(status ORDER BY trust_score DESC))[1] AS rep_status,
        ROUND(AVG(trust_score), 2) AS avg_trust_score,
        SUM(confirmations_count)::INT AS sum_confirmations,
        SUM(issues_count)::INT AS sum_issues
    FROM bbox_filtered
    GROUP BY ST_SnapToGrid(geom, $8)
    ORDER BY cluster_size DESC
    LIMIT 350
)
SELECT
    rep_id AS id,
    CASE
        WHEN cluster_size > 1 THEN rep_title || ' (+' || (cluster_size - 1)::TEXT || ')'
        ELSE rep_title
    END AS title,
    rep_address AS address_text,
    rep_fractions AS accepted_fractions,
    centroid_lat AS lat,
    centroid_lon AS lon,
    rep_status AS status,
    avg_trust_score AS trust_score,
    sum_confirmations AS confirmations_count,
    sum_issues AS issues_count
FROM grid_cells;
```

### 3.3 High-Zoom Precision Query (`zoom >= 13`)
At `zoom >= 13`, the query uses `idx_waste_points_geom_gist` for the bounding box (`&& ST_MakeEnvelope`) and `idx_waste_points_fractions_gin` for the array overlap operator (`&&`), returning up to `500` individual points:

```sql
SELECT
    id,
    title,
    address_text,
    accepted_fractions,
    ST_Y(geom) AS lat,
    ST_X(geom) AS lon,
    status,
    trust_score::FLOAT8 AS trust_score,
    confirmations_count,
    issues_count
FROM waste_points
WHERE geom && ST_MakeEnvelope($1, $2, $3, $4, 4326)
  AND (
      status = 'active'
      OR ($5::boolean = TRUE AND status = 'unverified')
  )
  AND trust_score >= $6
  AND (
      $7::waste_fraction_code[] IS NULL
      OR accepted_fractions && $7::waste_fraction_code[]
  )
ORDER BY trust_score DESC, confirmations_count DESC, id ASC
LIMIT 500;
```
*(Parameter order: `$1 = min_lon`, `$2 = min_lat`, `$3 = max_lon`, `$4 = max_lat`, `$5 = include_unverified`, `$6 = min_trust_score`, `$7 = fractions`)*

### 3.4 Point Details Query (`GET /api/v1/map/waste-points/{point_id}`)
Retrieves the canonical point, its linked provenance records in `rso_source_records`, and the 20 most recent crowdsourced reports in a single round-trip:

```sql
SELECT
    w.id,
    w.title,
    w.address_text,
    w.operator_name,
    w.opening_hours,
    w.accepted_fractions,
    ST_Y(w.geom) AS lat,
    ST_X(w.geom) AS lon,
    w.status,
    w.trust_score::FLOAT8 AS trust_score,
    w.confirmations_count,
    w.issues_count,
    w.attribution_text,
    w.last_verified_at,
    w.updated_at,
    COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'source_record_id', s.id,
                    'source_type', s.source_type,
                    'external_record_id', s.external_record_id,
                    'license_name', s.license_name,
                    'match_distance_m', l.match_distance_m::FLOAT8
                )
                ORDER BY l.linked_at ASC
            )
            FROM point_source_links l
            JOIN rso_source_records s ON s.id = l.source_record_id
            WHERE l.waste_point_id = w.id
        ),
        '[]'::jsonb
    ) AS sources,
    COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', r.id,
                    'report_type', r.report_type,
                    'comment', r.comment,
                    'distance_to_point_m', r.distance_to_point_m::FLOAT8,
                    'trust_delta', r.trust_delta::FLOAT8,
                    'created_at', r.created_at
                )
                ORDER BY r.created_at DESC
            )
            FROM (
                SELECT id, report_type, comment, distance_to_point_m, trust_delta, created_at
                FROM point_reports
                WHERE waste_point_id = w.id
                ORDER BY created_at DESC
                LIMIT 20
            ) r
        ),
        '[]'::jsonb
    ) AS recent_reports
FROM waste_points w
WHERE w.id = $1;
```

### 3.5 Mandatory `EXPLAIN (ANALYZE, BUFFERS)` Performance Gate
In `backend/tests/stress/test_postgis_explain_analyze.py`, the test suite seeds `25,000` synthetic waste points across Moscow Oblast, runs `ANALYZE waste_points;`, and executes `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` on the Section 3.3 query:
1. The query plan JSON **MUST** contain `"Index Scan"` or `"Bitmap Index Scan"` referencing `"idx_waste_points_geom_gist"` (or `"idx_waste_points_fractions_gin"` when filtered by rare fraction).
2. The query plan **MUST NOT** contain `"Seq Scan"` on `"waste_points"`.
3. Total `"Execution Time"` **MUST** be `< 15.0 ms`.

---

## 4. GPS Track Spatial SQL in PostGIS (Zero `Shapely`/`GDAL` in Python)

All geometry creation and geodesic distance calculations for interval GPS tracking (`POST /api/v1/activity/tracks/points:batch` and `PUT /api/v1/activity/daily/{activity_date}/allocations`) execute inside PostGIS:

### 4.1 Geodesic Interval Distances via Window Function
When a batch of raw track points is uploaded, the backend computes consecutive WGS-84 spheroid distances in meters directly inside PostgreSQL before running the pure Python motion classifier:

```sql
WITH raw_points AS (
    SELECT
        p.seq_no,
        p.recorded_at,
        p.lat,
        p.lon,
        p.accuracy_m,
        p.speed_mps,
        p.cumulative_steps,
        ST_SetSRID(ST_MakePoint(p.lon, p.lat), 4326) AS pt_geom
    FROM jsonb_to_recordset($1::jsonb) AS p(
        seq_no INT,
        recorded_at TIMESTAMPTZ,
        lat FLOAT8,
        lon FLOAT8,
        accuracy_m REAL,
        speed_mps REAL,
        cumulative_steps INT
    )
)
SELECT
    seq_no,
    recorded_at,
    lat,
    lon,
    accuracy_m,
    speed_mps,
    cumulative_steps,
    ST_IsValid(pt_geom) AS is_valid_geom,
    COALESCE(
        ROUND(
            ST_Distance(
                LAG(pt_geom) OVER (ORDER BY seq_no ASC)::geography,
                pt_geom::geography
            )::NUMERIC,
            2
        ),
        0.00
    ) AS delta_distance_m
FROM raw_points
ORDER BY seq_no ASC;
```

### 4.2 Rebuilding Daily Track `LineString` & Total Walking Distance
After inserting classified points into `gps_track_points`, `gps_daily_tracks` is updated atomically in PostGIS:

```sql
UPDATE gps_daily_tracks t
SET
    route_geom = CASE
        WHEN sub.pt_count >= 2 THEN sub.line_geom
        ELSE NULL
    END,
    total_gps_walking_distance_m = sub.walk_dist_m,
    point_count = sub.pt_count,
    updated_at = NOW()
FROM (
    SELECT
        COUNT(*)::INT AS pt_count,
        ST_MakeLine(geom ORDER BY seq_no ASC) AS line_geom,
        COALESCE(
            SUM(delta_distance_m) FILTER (WHERE motion_class = 'walking'),
            0.00
        )::NUMERIC(10, 2) AS walk_dist_m
    FROM gps_track_points
    WHERE track_id = $1
) sub
WHERE t.id = $1
RETURNING t.id, t.point_count, t.total_gps_walking_distance_m::FLOAT8;
```

### 4.3 Constructing & Validating `route_segment_allocations.segment_geom`
For each segment `[start_seq_no, end_seq_no]` in `PUT /api/v1/activity/daily/{activity_date}/allocations`, PostGIS constructs the `LineString`, verifies `ST_IsValid`, checks for prohibited `'vehicle_suspected'` points, and aggregates distance and steps in a single query:

```sql
SELECT
    COUNT(*)::INT AS point_count,
    BOOL_OR(motion_class = 'vehicle_suspected' AND seq_no > $2) AS has_vehicle_motion,
    ST_MakeLine(geom ORDER BY seq_no ASC) AS segment_geom,
    COALESCE(SUM(delta_distance_m) FILTER (WHERE seq_no > $2), 0.00)::NUMERIC(10, 2) AS segment_distance_m,
    COALESCE(SUM(delta_steps) FILTER (WHERE seq_no > $2), 0)::INT AS segment_steps
FROM gps_track_points
WHERE track_id = $1
  AND seq_no BETWEEN $2 AND $3;
```
- If `point_count < 2` (or `start_seq_no` / `end_seq_no` missing), raise `422 SEGMENT_SEQ_OUT_OF_BOUNDS`.
- If `has_vehicle_motion = TRUE`, raise `422 SEGMENT_CONTAINS_VEHICLE_MOTION`.

---

## 5. Crowd-Verification & New Point Suggestion Workflow

### 5.1 Submitting a Waste Point Report (`POST /api/v1/map/waste-points/{point_id}/reports`)
Executed inside an `asyncpg` transaction:
1. **Verify Point Existence & Compute Geodesic Proximity**:
   ```sql
   SELECT
       id,
       status,
       trust_score,
       ROUND(
           ST_Distance(
               geog,
               ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography
           )::NUMERIC,
           2
       ) AS distance_to_point_m
   FROM waste_points
   WHERE id = $1
   FOR UPDATE;
   ```
   - If no row found, raise `404 WASTE_POINT_NOT_FOUND`.
   - If `distance_to_point_m > 2000.00`, raise `422 REPORT_USER_TOO_FAR_FROM_POINT`.
2. **Enforce 12-Hour Per-User Cooldown**:
   ```sql
   SELECT EXISTS (
       SELECT 1
       FROM point_reports
       WHERE waste_point_id = $1
         AND user_id = $2
         AND created_at > NOW() - INTERVAL '12 hours'
   );
   ```
   - If `TRUE`, raise `429 DUPLICATE_POINT_REPORT_COOLDOWN`.
3. **Insert Report & Trigger Trust Update (`trg_point_reports_apply_trust`)**:
   - Insert into `point_reports` with `trust_delta` from `rso_trust.compute_new_trust_score()`.
   - The PostgreSQL trigger `trg_point_reports_apply_trust` automatically clamps `waste_points.trust_score` to `[0.00, 100.00]`, increments `confirmations_count` or `issues_count`, and transitions `status` between `'active'` and `'unverified'`.
4. **Award `+15 ★` Eco-Points & Evaluate `'rso_scout_5'` Badge**:
   - Insert `+15 ★` into `point_ledger` (`operation_type = 'daily_steps_reward'` or `'challenge_reward'` / `'badge_reward'` as applicable; specifically `operation_type = 'challenge_reward'` with `description = 'Проверка актуальности пункта РСО'` and `reference_entity_type = 'point_report'`).
   - If user's total report count reaches `5`, unlock badge `'rso_scout_5'` (`+150 ★`).

### 5.2 Suggesting a New Community Waste Point (`POST /api/v1/map/waste-points/suggestions`)
1. **15-Meter Duplicate Proximity Check**:
   ```sql
   SELECT id
   FROM waste_points
   WHERE ST_DWithin(geog, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, 15.0)
     AND accepted_fractions && $3::waste_fraction_code[]
   ORDER BY geog <-> ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography ASC
   LIMIT 1;
   ```
   - If an overlapping point already exists within `15.0 m`, return the existing point details instead of creating a duplicate pin.
2. **Isolated Community Source Creation**:
   - Insert into `rso_source_records` (`source_type = 'community_verified'`, `external_record_id = idempotency_key::TEXT`, `license_name = 'EcoTrack-Community-1.0'`).
   - Insert into `waste_points` with `status = 'unverified'`, `trust_score = 45.00`, and `attribution_text = 'Предложено сообществом EcoTrack (требует подтверждения)'`.
   - Link both in `point_source_links` (`match_distance_m = 0.00`).

---

## 6. Map Tiles & External Navigation Deep Links

### 6.1 Tile Server Policy (`flutter_map ^8.2+`)
- **Hard Prohibition**: Direct production tile requests to `https://tile.openstreetmap.org/{z}/{x}/{y}.png` are **STRICTLY FORBIDDEN** by the OpenStreetMap Foundation Tile Usage Policy.
- **Approved Tile Configuration**:
  - Primary Tile URL: OpenFreeMap / CARTO Positron high-contrast grayscale raster/vector tiles (`https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png` or self-hosted Russian VPS tile proxy `https://tiles.ecotrack.ru/light/{z}/{x}/{y}.png`) with custom `User-Agent: EcoTrackMobile/1.0 (https://ecotrack.ru)`.
  - Offline Tile Caching: Configured via `flutter_map_cache` backed by a local SQLite cache store (`maxAge: const Duration(days: 30)`) so previously viewed neighborhoods render offline with zero network calls.

### 6.2 External Pedestrian Navigation Deep Links (`"Построить маршрут"`)
When the user taps `"Построить маршрут во внешнем навигаторе"` in `WastePointDetailSheet` for target coordinates `(lat, lon)`, the Flutter client probes installed navigation apps in priority order:

| Priority | Target App | Deep Link URI Template (Pedestrian Mode) |
| :--- | :--- | :--- |
| **1** | **Яндекс Карты** | `yandexmaps://maps.yandex.ru/?rtext=~{lat},{lon}&rtt=pd` |
| **2** | **2ГИС (2GIS)** | `dgis://2gis.ru/routeSearch/rsType/pedestrian/to/{lon},{lat}` *(note `lon,lat` order in 2GIS)* |
| **3** | **System Geo Intent (Fallback)** | `geo:{lat},{lon}?q={lat},{lon}({encoded_title})` |
