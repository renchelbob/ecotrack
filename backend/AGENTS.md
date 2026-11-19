# backend/AGENTS.md — Backend, PostGIS & ETL Playbook (Developer 1)

> **Workspace Scope**: `/backend/**`, `/scripts/**`, and **3 Delegated High-Complexity Mobile Modules**:
> - `mobile/lib/features/mascot/presentation/widgets/mascot_vector_painter.dart`
> - `mobile/lib/core/database/outbox_dispatcher.dart`
> - `mobile/lib/features/map/presentation/screens/map_activity_screen.dart`
> **Read-Only Contracts**: `/contracts/schema.sql`, `/contracts/openapi.yaml`, `/contracts/error_catalog.json`
> **Relevant Specs**: `specs/02-domain-math-and-algorithms.md`, `specs/03-backend-architecture-and-152fz.md`, `specs/04-postgis-and-rso-data-pipeline.md`, `specs/05-mobile-flutter-architecture.md`, `specs/06-offline-sync-and-sensors.md`, `specs/07-devops-docker-and-vps-deployment.md`, `specs/08-verification-and-quality-gates.md`

---

## 1. Exact Directory Layout (`backend/`)

All backend code MUST reside in the exact modular structure below. Creating ad-hoc top-level modules or bypassing layer boundaries is prohibited:

```text
backend/
├── Dockerfile                                # Multi-stage python:3.14-slim-bookworm (<= 100 MB runtime)
├── pyproject.toml                            # uv dependencies, ruff, basedpyright, pytest, crosshair
├── uv.lock                                   # Locked deterministic dependency graph
├── alembic.ini                               # Alembic configuration
├── app/
│   ├── main.py                               # FastAPI >= 0.150 entrypoint, lifespan, exception handlers
│   ├── config.py                             # Pydantic Settings (env vars, JWT keys, OAuth, DB DSN)
│   ├── domain/                               # PURE PYTHON 3.14 + icontract (ZERO I/O, ZERO FastAPI/DB imports)
│   │   ├── models.py                         # Immutable domain value objects & enums
│   │   ├── hybrid_co2.py                     # Meter-based hybrid CO2 & unallocated step math (@require/@ensure)
│   │   ├── vehicle_emissions.py              # Personal car fuel L/100km -> g CO2/m calculator
│   │   ├── motion_classifier.py              # Interval GPS + cumulative_steps classifier & antifraud
│   │   ├── equivalents.py                    # CO2 grams -> trees, car km, charges, bottles, LED hours
│   │   └── rso_trust.py                      # Crowdsourced waste_point trust_score delta calculator
│   ├── application/                          # Use-case orchestrators & transaction boundaries
│   │   ├── auth_service.py                   # OAuth 2.1 PKCE exchange, Google lab banner & phone gate, 152-FZ
│   │   ├── activity_service.py               # Daily steps sync, GPS batch ingest, 48h segment allocations
│   │   ├── ledger_shop_service.py            # Idempotent ledger inserts, cart checkout, coupon/QR generator
│   │   ├── social_service.py                 # Friendships, wake-up mascot nudges, leaderboard, Shared Forest
│   │   └── map_rso_service.py                # BBox query orchestration, report distance check, suggestions
│   ├── infrastructure/
│   │   ├── db/
│   │   │   ├── pool.py                       # asyncpg >= 0.31.0 pool lifecycle & jsonb codec registration
│   │   │   ├── idempotency.py                # UUIDv7 validation & idempotent response locking
│   │   │   └── repositories/                 # Parameterized SQL ($1, $2) repositories per aggregate
│   │   │       ├── user_repo.py
│   │   │       ├── activity_repo.py
│   │   │       ├── ledger_shop_repo.py
│   │   │       ├── social_repo.py
│   │   │       └── map_rso_repo.py
│   │   ├── oauth/
│   │   │   ├── base.py                       # OAuthIdentityProvider Protocol
│   │   │   ├── yandex_provider.py            # Yandex ID OAuth 2.1 + PKCE adapter
│   │   │   ├── vk_provider.py                # VK ID OAuth 2.1 + PKCE adapter
│   │   │   └── google_provider.py            # Google OAuth 2.1 + PKCE adapter (406-FZ lab mode)
│   │   └── push/
│   │       ├── base.py                       # PushNotificationProvider Protocol (2-line swap boundary)
│   │       ├── fcm_provider.py               # Default FcmPushProvider implementation
│   │       └── noop_provider.py              # Deterministic local/test push sink
│   ├── api/
│   │   ├── dependencies.py                   # Bearer JWT auth, 152-FZ consent guard, Google phone guard
│   │   ├── errors.py                         # Maps domain/DB errors -> contracts/error_catalog.json envelope
│   │   └── v1/
│   │       ├── router.py                     # Root /api/v1 APIRouter aggregator
│   │       ├── auth_routes.py
│   │       ├── profile_vehicle_routes.py
│   │       ├── activity_routes.py
│   │       ├── stats_routes.py
│   │       ├── ledger_shop_routes.py
│   │       ├── social_routes.py
│   │       ├── map_rso_routes.py
│   │       └── push_routes.py
│   ├── etl/
│   │   ├── osm_pbf_ingestor.py               # Ingests pre-filtered Geofabrik OSM GeoJSON/PBF into PostGIS
│   │   ├── mos_ru_ingestor.py                # Ingests data.mos.ru & municipal open registries
│   │   └── deduplicator.py                   # Spatial 25m clustering -> waste_points + point_source_links
│   └── migrations/
│       ├── env.py                            # Alembic 1.20.x runner with PostGIS include_object filter
│       └── versions/
│           └── 0001_initial_contract.py      # Executes contracts/schema.sql verbatim
└── tests/
    ├── conftest.py                           # Real postgis/postgis:17-3.5-alpine fixture (NO DB mocks)
    ├── contract/
    │   ├── test_openapi_parity.py            # Diffs FastAPI app.openapi() vs ../contracts/openapi.yaml
    │   └── test_pg_triggers_invariants.py    # Tests point_ledger immutability & balance CHECK triggers
    ├── dbc/
    │   └── test_crosshair_contracts.py       # Symbolic verification harness for app/domain/
    ├── pbt/
    │   ├── test_stateful_ledger_activity.py  # Hypothesis RuleBasedStateMachine against real PostGIS
    │   └── test_schemathesis_api.py          # Schemathesis fuzzing of all 38 OpenAPI operations
    └── stress/
        ├── test_double_spend_barrier.py      # 50 concurrent checkout coroutines racing on 1 balance
        └── test_postgis_explain_analyze.py   # Asserts Index Scan on idx_waste_points_geom_gist < 15ms
```

---

## 2. Mandatory Stack & Runtime Rules (Nov 2026)

1. **Python 3.14 (Standard GIL Build)**:
   - Target runtime is CPython `3.14.x` standard GIL build (`python:3.14-slim-bookworm`).
   - Python 3.14 implements native deferred evaluation of annotations (PEP 649 / PEP 749). **NEVER** write `from __future__ import annotations`.
2. **FastAPI `>= 0.150.0` & Pydantic `v2.14.x`**:
   - All request/response schemas must inherit from `pydantic.BaseModel` with `model_config = ConfigDict(extra="forbid", frozen=True)`.
   - Use `Annotated[T, Depends(...)]` and `Annotated[UUID, Header(alias="Idempotency-Key")]` for dependency and header injection.
3. **`asyncpg >= 0.31.0` & PostGIS 3.5 Rules**:
   - Every connection in `asyncpg.create_pool(..., init=init_connection)` MUST register JSON/JSONB codecs:
     ```python
     async def init_connection(conn: asyncpg.Connection) -> None:
         await conn.set_type_codec(
             "jsonb", encoder=json.dumps, decoder=json.loads, schema="pg_catalog", format="text"
         )
         await conn.set_type_codec(
             "json", encoder=json.dumps, decoder=json.loads, schema="pg_catalog", format="text"
         )
     ```
   - **Zero C-GIS in Python**: All spatial operations (`ST_MakePoint`, `ST_SetSRID`, `ST_MakeLine`, `ST_MakeEnvelope`, `ST_DWithin`, `ST_Length(geom::geography)`, `ST_IsValid`, `ST_AsGeoJSON`) MUST execute inside PostgreSQL/PostGIS SQL statements.
4. **Alembic `1.20.x` Rules**:
   - Declared inside `[dependency-groups] dev = ["alembic>=1.20.0,<2.0.0", ...]` in `pyproject.toml` so it is excluded from the production runtime image.
   - `app/migrations/env.py` MUST define `include_object` to ignore PostGIS internal tables:
     ```python
     POSTGIS_SYSTEM_TABLES: Final[frozenset[str]] = frozenset({
         "spatial_ref_sys", "geometry_columns", "geography_columns", "raster_columns", "raster_overviews"
     })
     ```
5. **`PushNotificationProvider` Abstraction**:
   - `app/infrastructure/push/base.py` defines `class PushNotificationProvider(Protocol): async def send_wakeup_nudge(...) -> bool`.
   - `FcmPushProvider` is wired via FastAPI dependency injection so switching to RuStore Push or APNs requires changing only 2 lines in `app/api/dependencies.py`.

---

## 3. Canonical Python 3.14 + Pydantic v2.14 + `icontract` + `asyncpg` Syntax

All backend code MUST follow this exact style:

```python
from datetime import date
from decimal import Decimal
from typing import Annotated, Final
from uuid import UUID

import asyncpg
import icontract
from fastapi import APIRouter, Depends, Header, status
from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.api.dependencies import AuthenticatedUser, get_db_conn, require_active_152fz_consent
from app.api.errors import raise_catalog_error

DEFAULT_BUS_CO2_G_PER_M: Final[Decimal] = Decimal("0.08200")
UNALLOCATED_BUS_SHARE: Final[Decimal] = Decimal("0.80")
UNALLOCATED_CONFIDENCE: Final[Decimal] = Decimal("0.70")


class RouteSegmentAllocationInputDTO(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    idempotency_key: UUID
    start_seq_no: Annotated[int, Field(ge=0)]
    end_seq_no: Annotated[int, Field(ge=1)]
    replaced_transport_mode: str

    @model_validator(mode="after")
    def validate_seq_order(self) -> "RouteSegmentAllocationInputDTO":
        if self.end_seq_no <= self.start_seq_no:
            raise ValueError("end_seq_no must be strictly greater than start_seq_no")
        return self


@icontract.require(lambda total_step_distance_m: total_step_distance_m >= Decimal("0"))
@icontract.require(lambda allocated_gps_distance_m: allocated_gps_distance_m >= Decimal("0"))
@icontract.require(lambda allocated_co2_grams: allocated_co2_grams >= 0)
@icontract.ensure(lambda result: result[0] >= Decimal("0") and result[1] >= 0 and result[2] >= 0)
def compute_hybrid_daily_co2(
    total_step_distance_m: Decimal,
    allocated_gps_distance_m: Decimal,
    allocated_co2_grams: int,
) -> tuple[Decimal, int, int]:
    """Return (unallocated_distance_m, auto_default_co2_grams, total_co2_grams)."""
    unallocated_m = max(Decimal("0.00"), total_step_distance_m - allocated_gps_distance_m)
    auto_co2_raw = unallocated_m * UNALLOCATED_BUS_SHARE * DEFAULT_BUS_CO2_G_PER_M * UNALLOCATED_CONFIDENCE
    auto_co2_grams = int(round(auto_co2_raw))
    return unallocated_m, auto_co2_grams, allocated_co2_grams + auto_co2_grams


router = APIRouter(prefix="/api/v1/activity", tags=["Activity & Hybrid CO2"])


@router.delete(
    "/daily/{activity_date}/allocations/{allocation_id}",
    status_code=status.HTTP_200_OK,
)
async def delete_route_segment_allocation(
    activity_date: date,
    allocation_id: UUID,
    idempotency_key: Annotated[UUID, Header(alias="Idempotency-Key")],
    user: Annotated[AuthenticatedUser, Depends(require_active_152fz_consent)],
    conn: Annotated[asyncpg.Connection, Depends(get_db_conn)],
) -> dict[str, object]:
    if (user.local_today - activity_date).days not in (0, 1):
        raise_catalog_error("EDIT_WINDOW_EXPIRED")

    deleted_id: UUID | None = await conn.fetchval(
        """
        DELETE FROM route_segment_allocations
        WHERE id = $1 AND user_id = $2 AND activity_date = $3
        RETURNING id
        """,
        allocation_id,
        user.id,
        activity_date,
    )
    if deleted_id is None:
        raise_catalog_error("ALLOCATION_NOT_FOUND")
    return {"deleted_allocation_id": str(deleted_id), "idempotency_key": str(idempotency_key)}
```

---

## 4. Strict Negative Constraints (Backend Bans)

1. **FORBIDDEN**: `from __future__ import annotations` (flagged as fatal by `ruff` rule `FA102`).
2. **FORBIDDEN**: `import pydantic.v1`, `.dict()`, `.json()`, `.parse_obj()`, `@validator`, `@root_validator`, or `class Config:`.
3. **FORBIDDEN**: Installing `GDAL`, `Shapely`, `GeoPandas`, `Fiona`, `PyProj`, `scipy`, `pandas`, or `numpy` in `pyproject.toml` (breaks the `<= 100 MB` Docker runtime limit).
4. **FORBIDDEN**: Using `float` for `points_balance`, `points_delta`, `price_points`, or `co2_saved_grams`. Always use `int` for points/grams and `Decimal` for intermediate meter/rate math.
5. **FORBIDDEN**: String interpolation (`f"SELECT ... {var}"` or `%`) in SQL queries. Every SQL query must use positional `$1, $2, ...` `asyncpg` parameters.
6. **FORBIDDEN**: Direct `UPDATE users SET points_balance = ...` or `UPDATE`/`DELETE` on `point_ledger`. Balances change strictly via `INSERT INTO point_ledger`.
7. **FORBIDDEN**: Mocking `asyncpg.Connection`, `asyncpg.Pool`, or repository classes in `tests/`. All database tests must execute against a real `postgis/postgis:17-3.5-alpine` container.

---

## 5. Local Verification Commands (Developer 1)

Run all checks from `/backend/` via `uv`:

```bash
# 1. Static Analysis, Formatting, Type Checking & Security
uv run ruff check app tests
uv run ruff format --check app tests
uv run basedpyright --level error
uv run semgrep --config auto --error app

# 2. Contract Parity Gate (SQL + OpenAPI 3.1.0 + Error Catalog)
uv run python ../scripts/verify_contracts.py
uv run pytest tests/contract/ -v

# 3. Formal Design-by-Contract Symbolic Verification (Z3 / CrossHair)
uv run crosshair check --per_condition_timeout=10 app/domain/

# 4. Property-Based Testing (Hypothesis Stateful + Schemathesis)
uv run pytest tests/pbt/ -v

# 5. Concurrency & PostGIS Spatial Index Stress Gates
uv run pytest tests/stress/ -v
```
