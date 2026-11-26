# AGENTS.md — EcoTrack Contract-First Monorepo Governance Guide

> **Mandatory Reading for All AI Coding Agents & Human Developers**
> This repository uses a strict **Contract-First Monorepo** architecture for **EcoTrack** (Russian Federation, 152-FZ / 406-FZ). Every database table, SQLite table, HTTP endpoint, payload schema, and error code is locked inside `/contracts/`. Neither Developer 1 (Backend/Infra) nor Developer 2 (Flutter Client) nor any AI agent may deviate from `/contracts/` by a single field name, type, constraint, or status code.

---

## 1. Repository Topology & File Ownership Matrix

```text
ecotrack/
├── AGENTS.md                           # Root AI & Developer governance (READ-ONLY)
├── Makefile                            # Unified verification, build & dev entrypoint
├── docker-compose.yml                  # Self-hosted MVP stack (FastAPI + PostGIS 17-3.5-alpine)
├── contracts/                          # LOCKED SINGLE SOURCE OF TRUTH (READ-ONLY DURING FEATURE WORK)
│   ├── schema.sql                      # PostgreSQL 17 + PostGIS 3.5 canonical DDL + triggers + seeds
│   ├── client_sqlite_schema.sql        # Flutter SQLite 3 WAL offline engine canonical DDL
│   ├── openapi.yaml                    # OpenAPI 3.1.0 REST contract (38 paths, 88 schemas)
│   └── error_catalog.json              # Machine-readable error codes, HTTP statuses & RU messages
├── specs/                              # Progressive Disclosure Technical Specifications
│   ├── 01-product-and-ux-spec.md
│   ├── 02-domain-math-and-algorithms.md
│   ├── 03-backend-architecture-and-152fz.md
│   ├── 04-postgis-and-rso-data-pipeline.md
│   ├── 05-mobile-flutter-architecture.md
│   ├── 06-offline-sync-and-sensors.md
│   ├── 07-devops-docker-and-vps-deployment.md
│   └── 08-verification-and-quality-gates.md
├── backend/                            # OWNED BY DEVELOPER 1 (Python 3.14 + FastAPI >=0.150 + asyncpg)
│   ├── Dockerfile                      # Multi-stage python:3.14-slim-bookworm (<= 100 MB runtime)
│   ├── pyproject.toml                  # uv lockfile & tool configs (ruff, basedpyright, pytest)
│   ├── alembic/                        # Explicit SQL DDL migrations matching contracts/schema.sql
│   ├── src/ecotrack_api/               # Application source code
│   └── tests/                          # Contract, CrossHair/icontract, Hypothesis, Schemathesis, k6
├── mobile/                             # OWNED BY DEVELOPER 2 (Flutter / Dart ^3.13.4, Zero build_runner)
│   ├── pubspec.yaml                    # Locked Flutter dependencies
│   ├── analysis_options.yaml           # Strict dart analyze + dart_code_linter + import_lint
│   ├── assets/                         # Bundled SQLite DDL, vector mascot layers, partner logos
│   ├── lib/                            # Feature-first BLoC architecture
│   └── test/                           # Glados PBT, SQLite outbox tests, Impeller frame benchmarks
├── screens/                            # LOCKED VISUAL REFERENCE CANON (READ-ONLY DURING FEATURE WORK)
│   ├── wireframes.png                  # Overall navigation & Architectural Wireframe Grayscale panorama
│   ├── 07_Onboarding_... — 09_...      # 07..09: Onboarding & 152-FZ screens (in-place OAuth on 09)
│   └── 14_Main_... — 23_Shop_...       # 14..23: Final screens (Home, Calc/Map, Stats, Profile, Shop/Orders)
└── scripts/                            # OWNED BY DEVELOPER 1
    ├── verify_contracts.py             # Validates SQL <-> OpenAPI <-> Error Catalog parity
    ├── verify_mobile_gates.py          # Validates /screens/ canon, mobile configs, static bans & tests
    └── osm_ingest/                     # Geofabrik OSM PBF + data.mos.ru + municipal ETL into PostGIS
```

### Ownership Boundaries & Core Mobile Module Paths
| Role | Write Access | Read-Only Access |
| :--- | :--- | :--- |
| **UI/UX Designer / PM / Team Lead** | `/screens/**` (`wireframes.png`, `07..09`, `14..23` — **LOCKED VISUAL REFERENCE CANON**), `/specs/01-product-and-ux-spec.md` | `/contracts/**`, `/mobile/**`, `/backend/**` |
| **Developer 1 (Backend, Data & DevOps)** | `/backend/**`, `/scripts/**`, `/docker-compose.yml`, `/Makefile` (backend targets) | `/contracts/**`, `/specs/**`, `/screens/**`, `/mobile/**` |
| **Developer 2 (Flutter Mobile Client)** | `/mobile/**` (all Flutter client modules including `mascot_vector_painter.dart`, `outbox_dispatcher.dart`, and `map_activity_screen.dart`), `/Makefile` (mobile targets) | `/contracts/**`, `/specs/**`, `/screens/**`, `/backend/**` |
| **Feature AI Coding Agents** | Strictly scoped to the assigned workspace (`/backend/**` OR `/mobile/**`) | `/contracts/**`, `/specs/**`, `/screens/**`, `/AGENTS.md` |

> **Core Mobile Module Canonical Paths (Owned by Developer 2)**:
> All Flutter modules under `/mobile/**` — including the three core modules with elevated domain/UI requirements — are owned and delivered end-to-end by **Developer 2**. **Developer 1** must not author or modify files under `/mobile/**`. The canonical paths below remain mandatory for Gate 4:
> 1. `mobile/lib/features/home_mascot/presentation/widgets/mascot_vector_painter.dart` (fox mascot Canvas geometry, mood transitions, 5 vector accessories).
> 2. `mobile/lib/core/database/outbox_dispatcher.dart` (offline mutation outbox FSM with causal barriers, exponential backoff, coalescing).
> 3. `mobile/lib/features/map_activity/presentation/screens/map_activity_screen.dart` (dual-mode `flutter_map` instance with `LayerHitNotifier` clickable polylines).

---

## 2. Strict Change Protocol for `/contracts/`

Files inside `/contracts/` (`schema.sql`, `client_sqlite_schema.sql`, `openapi.yaml`, `error_catalog.json`) are **IMMUTABLE** during feature implementation.

1. **Hard Prohibition**: An AI agent executing a backend or mobile implementation task **MUST NEVER** edit, rename, or patch any file in `/contracts/` to make a test pass or to work around an implementation bug.
2. **Contract Defect Escalation**: If a genuine contradiction is discovered in `/contracts/`:
   - **Step 1**: Immediately halt feature code generation and output a structured `CONTRACT_RFC` block citing the exact file, line number, and conflict.
   - **Step 2**: Both Developer 1 and Developer 2 must explicitly approve the RFC in writing.
   - **Step 3**: Update `/contracts/` in a dedicated, standalone commit containing **zero** application code changes.
   - **Step 4**: Run `make verify-contracts` to validate PostgreSQL 17 DDL execution, SQLite 3 DDL execution, OpenAPI 3.1.0 schema validity, and `error_catalog.json` coverage.
   - **Step 5**: Resume backend and mobile implementation against the updated contract.

---

## 3. Progressive Disclosure Index (Context Routing Table)

To prevent context-window bloat and hallucination, AI agents **MUST NOT** load all files in `/specs/` at once. Load **only** the specification file(s) mapped to your active task; for any Flutter UI implementation, **ALWAYS** inspect the matching reference PNG(s) in `screens/*.png` first:

| Active Task / Domain | Required Contract File(s) | Required Spec & Visual Canon (`specs/...`, `screens/...`) |
| :--- | :--- | :--- |
| **UI screens, 5-tab navigation, Russian copy, Mascot UX, 152-FZ modals** | `contracts/openapi.yaml`, `contracts/error_catalog.json` | `specs/01-product-and-ux-spec.md`, **`screens/*.png` (mandatory before any UI implementation)** |
| **Hybrid CO₂ formula, vehicle L/100km math, GPS+steps motion classifier, antifraud, RSO trust math** | `contracts/schema.sql`, `contracts/openapi.yaml` | `specs/02-domain-math-and-algorithms.md` |
| **FastAPI endpoints, OAuth 2.1 + PKCE, `asyncpg` queries, `point_ledger`, 152-FZ erasure, Push** | `contracts/schema.sql`, `contracts/openapi.yaml`, `contracts/error_catalog.json` | `specs/03-backend-architecture-and-152fz.md` |
| **PostGIS BBox queries, OSM PBF `osmium` filter, `data.mos.ru` ingestion, RSO deduplication** | `contracts/schema.sql`, `contracts/openapi.yaml` | `specs/04-postgis-and-rso-data-pipeline.md` |
| **Flutter BLoC, `go_router`, `dio` interceptors, `flutter_map` dual mode, custom vector mascot painter** | `contracts/openapi.yaml`, `contracts/error_catalog.json` | `specs/05-mobile-flutter-architecture.md`, **`screens/*.png` (for UI/screen widgets)**, `.agents/skills/` |
| **SQLite WAL storage, `offline_mutation_outbox`, `health` + `pedometer` sync, `geolocator` foreground task** | `contracts/client_sqlite_schema.sql`, `contracts/openapi.yaml` | `specs/06-offline-sync-and-sensors.md` |
| **Dockerfile (`<= 100 MB` Python 3.14), `docker-compose.yml`, local laptop & Russian VPS deployment** | `contracts/schema.sql` | `specs/07-devops-docker-and-vps-deployment.md` |
| **Linters, `icontract`+`CrossHair`, `Hypothesis`+`Schemathesis`+`glados`, Stress & Concurrency gates** | All 4 files in `/contracts/` | `specs/08-verification-and-quality-gates.md` |

---

## 4. Global Negative Constraints (Strictly Forbidden)

Every developer and AI agent must enforce these hard bans. Any PR violating a single item below is automatically rejected by CI:

### 4.1 Testing & Verification Bans
- **NO Classic Mock-Heavy Unit TDD**: Writing tautological unit tests that mock `asyncpg.Connection`, mock SQLite, or mock repositories (`unittest.mock.MagicMock`, `mockito`, `mocktail` for database/domain logic) is **STRICTLY FORBIDDEN**. All persistence and domain tests must run against a real PostGIS 17-3.5 container or real in-memory/temp-file SQLite 3 instance using Property-Based Testing (`Hypothesis`, `Schemathesis`, `glados`) and Design-by-Contract (`icontract` + `CrossHair`).

### 4.2 Database & Financial Integrity Bans
- **NO Direct Balance Mutation**: Executing `UPDATE users SET points_balance = ...` anywhere in application code is **STRICTLY FORBIDDEN**. User balances may only change via `INSERT INTO point_ledger`, which fires `trg_point_ledger_sync_balance`.
- **NO Ledger Mutation**: Executing `UPDATE` or direct `DELETE` on `point_ledger` is **STRICTLY FORBIDDEN** and blocked by `trg_point_ledger_immutable`.
- **NO Floating-Point Currency or CO₂ Totals**: `points_balance`, `points_delta`, `total_co2_saved_grams`, and `price_points` must always be exact integers (`INTEGER` / `BIGINT` in SQL, `int` in Python and Dart). Never store point balances as `float` or `double`.
- **NO Unbounded Spatial Queries**: Every query against `waste_points` or `gps_track_points` must use indexed spatial predicates (`&& ST_MakeEnvelope(...)` or `ST_DWithin(...)`) backed by `GIST` indexes.

### 4.3 Backend (Python 3.14) Bans
- **NO `from __future__ import annotations`**: Python 3.14 implements PEP 649 / PEP 749 deferred evaluation of annotations natively. Using `from __future__ import annotations` breaks runtime `Pydantic v2.14.x` and `FastAPI >= 0.150` type introspection and is banned via `ruff`.
- **NO `pydantic.v1` or Legacy Validators**: Never import `pydantic.v1`, `@validator`, or `class Config:`. Use Pydantic v2 (`ConfigDict`, `@field_validator`, `@model_validator`, `TypeAdapter`).
- **NO Heavy C-GIS Libraries in Backend Image**: Installing `GDAL`, `Fiona`, `Shapely`, `GeoPandas`, or `PyProj` into the FastAPI runtime image is **STRICTLY FORBIDDEN** (violates the `<= 100 MB` Python runtime image budget). All geometry validation (`ST_IsValid`), distance math (`ST_Length`, `ST_Distance`), and BBox filtering must execute inside PostGIS SQL via `asyncpg`.
- **NO ORM Magic in Runtime Queries**: Do not use SQLAlchemy ORM lazy-loading or session state in runtime request handlers. Use explicit parameterized SQL via `asyncpg` pools (`Alembic` is used strictly in the `migrations` CLI group for schema versioning).

### 4.4 Mobile (Flutter / Dart `^3.13.4`) Bans
- **NO Visual Drift from `/screens/`**: Every Flutter screen, layout hierarchy, card geometry, Architectural Wireframe Grayscale palette (`#FFFFFF` / `#1E1E1E` / `#D9D9D9`), line-art fox mascot style, and 5-tab bottom bar MUST match the corresponding PNG in `/screens/`. Every mobile AI agent MUST inspect the matching PNGs in `/screens/` before writing UI code; dark themes, green gradients, or generic Material templates are strictly forbidden. Sole intentional product delta: on `screens/09_Onboarding_Compact_08_Подарки_и_152ФЗ.png`, the 3 OAuth 2.1 + PKCE buttons (`"Войти через Яндекс ID"`, `"Войти через VK ID"`, `"Войти через Google (Лаб. режим)"`) replace `"Начать >"` directly in-place (with no separate email/password or `/auth/login` screen).
- **NO `build_runner` or Code Generation**: `freezed`, `json_serializable`, `injectable`, `auto_route`, and `retrofit` are **STRICTLY FORBIDDEN**. Write explicit, zero-reflection Dart 3.13 classes, sealed states, and `fromJson`/`toJson` mappers.
- **NO 6th Bottom Navigation Tab**: The bottom navigation bar is strictly locked to 5 tabs (`Stats`, `Map & Activity`, `Home`, `Shop`, `Profile & Settings`). The Recycling Map is accessed via the top mode toggle `[ My Routes ] | [ Recycling Map ]` on Tab 2 and via the shortcut card inside Tab 5 (`Profile & Settings`).
- **NO Arbitrary Manual Activity Entry**: Users cannot manually type "I walked 5 km" or "I rode a bus" without sensor steps. Step counts come exclusively from hardware sensors (`health` + `pedometer`), and transport replacement is annotated on recorded GPS segments (or calculated via the default 80% * 0.7 fallback formula).
- **NO Unhandled Raw SnackBars**: Never display raw exception strings or spam stacked `SnackBar` widgets. Every API error must be mapped through `contracts/error_catalog.json` to its deterministic `client_action` and `ui_message_ru`.

---

## 5. Global Definition of Done & 4-Layer Verification Gate

No task is complete until `make verify` exits with code `0`. The verification pipeline executes four mandatory layers in order:

1. **Layer 1 — Static, Contract & Architecture Gate (`make verify-static`)**:
   - `uv run --with pyyaml python scripts/verify_contracts.py` (verifies 100% alignment across `schema.sql`, `client_sqlite_schema.sql`, `openapi.yaml`, and `error_catalog.json`).
   - `uv run --with pyyaml python scripts/verify_mobile_gates.py` (verifies the 14 locked `/screens/*.png` files, `pubspec.yaml` bans/SDK floors, `analysis_options.yaml` anti-weakening guards, canonical 3-module paths, Dart static bans, layer import boundaries, OpenAPI/error catalog parity, Android permissions, and anti-tautology test rules).
   - Backend: `ruff check`, `ruff format --check`, `basedpyright --level error`, `semgrep --config auto --error`.
   - Mobile: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze --fatal-infos --fatal-warnings`, `dart analyze --fatal-infos --fatal-warnings` (runs `dart_code_linter` and `import_lint ^2.0.0` analyzer plugins), `dart run import_lint`.
2. **Layer 2 — Formal Design-by-Contract & Symbolic Gate (`make verify-dbc`)**:
   - Backend domain math (Hybrid CO₂, vehicle emissions, motion classification, antifraud, RSO trust score) decorated with `@icontract.require` and `@icontract.ensure`, verified symbolically via `crosshair check` (Z3 solver) with zero counterexamples.
   - PostgreSQL 17 DDL constraints and immutability triggers (`trg_point_ledger_immutable`, `trg_point_ledger_sync_balance`, `trg_point_reports_apply_trust`) verified against constraint-violation test vectors.
3. **Layer 3 — Property-Based & Stateful Fuzzing Gate (`make verify-pbt`)**:
   - `Hypothesis` `RuleBasedStateMachine` testing multi-day step syncs, GPS segment annotations, ledger balance invariants, and shop orders against live PostGIS.
   - `Schemathesis` fuzzing all 38 OpenAPI endpoints in `contracts/openapi.yaml`.
   - `glados` property-based tests on Dart domain models, hybrid CO₂ preview math, and SQLite outbox state transitions.
4. **Layer 4 — Concurrency, Spatial Performance & UI Frame Gate (`make verify-stress`)**:
   - **Double-Spend Barrier**: 50 concurrent shop checkout coroutines racing for the last coupon / balance (`points_balance >= 0` holds, exactly 1 succeeds or N up to balance).
   - **PostGIS Index Gate**: `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` on BBox waste-point query over 25,000 synthetic points asserting `Index Scan using idx_waste_points_geom_gist` and execution time `< 15 ms`.
   - **Load Gate**: `k6` steady-state run (`p95 < 120 ms`, `0%` unexpected 5xx).
   - **Impeller Frame Gate**: Flutter integration benchmark verifying vector mascot animation + map pan/zoom maintains `< 16.6 ms` frame build/raster time.
