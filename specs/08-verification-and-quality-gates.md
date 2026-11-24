# 08 — Verification, Mathematical Proofs & Stress-Testing Quality Gates Specification

> **Target Audience**: Developer 1 (Backend/Infra), Developer 2 (Flutter Client), and All AI Coding Agents
> **Governing Contracts**: `contracts/schema.sql`, `contracts/client_sqlite_schema.sql`, `contracts/openapi.yaml`, `contracts/error_catalog.json`
> **Enforcement Rule**: No pull request or feature task is complete until `make verify` executes all 4 verification layers in sequence and exits with code `0`.

---

## 1. Zero Classic Mock-TDD Mandate

### 1.1 Rationale & Hard Prohibition
In a Contract-First architecture where financial ledger integrity (`point_ledger`), spatial queries (`PostGIS 3.5`), and offline outbox durability (`SQLite 3 WAL`) are enforced by database triggers, `CHECK` constraints, and spatial indexes, **classic mock-heavy unit tests are worse than useless**:
- Mocking `asyncpg.Connection.fetchrow` or `sqflite.Database.insert` tests only the developer's assumptions about what SQL returns, completely bypassing `trg_point_ledger_immutable`, `trg_point_ledger_sync_balance`, `CHECK (points_balance >= 0)`, `ST_IsValid`, and `idx_waste_points_geom_gist`.
- Hand-written example-based unit tests miss multi-step state machine edge cases (e.g., device reboot step counter resets, yesterday segment re-annotation CO₂ deltas, or concurrent double-spend races).

### 1.2 Permitted vs. Forbidden Test Doubles Matrix

| Architectural Layer | Forbidden (CI Fatal Error) | Mandatory Verification Mechanism |
| :--- | :--- | :--- |
| **PostgreSQL / PostGIS Repositories (`backend/app/infrastructure/db/`)** | `unittest.mock.MagicMock`, `AsyncMock`, `mocker.patch` on `asyncpg.Pool` or `asyncpg.Connection` | Live `postgis/postgis:17-3.5-alpine` container initialized with `contracts/schema.sql` |
| **SQLite Offline Engine & DAOs (`mobile/lib/core/database/`, `data/`)** | `mockito`, `mocktail`, fake in-memory Dart lists replacing SQLite tables | Real `sqflite_common_ffi` / `sqlite3` engine initialized with `contracts/client_sqlite_schema.sql` |
| **Pure Domain Math (`backend/app/domain/`, `mobile/lib/features/*/domain/`)** | Hand-picked 3-example unit tests with mocked collaborators | Symbolic SMT proofs (`icontract` + `CrossHair`/Z3) + Property-Based Testing (`Hypothesis`, `glados`) |
| **FastAPI HTTP Endpoints (`backend/app/api/v1/`)** | Mocking service or repository classes inside route tests | `Schemathesis` OpenAPI 3.1.0 fuzzing + `Hypothesis` stateful workflows against live PostGIS |
| **External Third-Party Outbound Gateways (`OAuthIdentityProvider`, `PushNotificationProvider`)** | Calling live production Yandex/VK/Google/FCM servers during automated CI | Deterministic local protocol adapters (`FakeOAuthUpstreamServer`, `NoopPushProvider`) injected via `app/api/dependencies.py` |

---

## 2. Layer 1 — Static, Contract & Architecture Gate (`make verify-static`)

### 2.1 Cross-Contract Parity Verifier (`scripts/verify_contracts.py`)
`scripts/verify_contracts.py` is the first gate executed by `make verify-contracts` and `make verify-static`. It performs 4 deterministic checks and exits non-zero on any mismatch:

```python
#!/usr/bin/env python3
"""Verify 100% parity across schema.sql, client_sqlite_schema.sql, openapi.yaml, and error_catalog.json."""

import asyncio
import json
import sqlite3
import sys
from pathlib import Path

import asyncpg
import yaml
from openapi_spec_validator import validate

from app.main import create_app

ROOT_DIR = Path(__file__).resolve().parent.parent
CONTRACTS_DIR = ROOT_DIR / "contracts"

REQUIRED_PG_TRIGGERS = {
    "trg_point_ledger_immutable",
    "trg_point_ledger_sync_balance",
    "trg_point_reports_apply_trust",
}

REQUIRED_PG_INDEXES = {
    "idx_waste_points_geom_gist",
    "idx_waste_points_geog_gist",
    "idx_waste_points_fractions_gin",
    "idx_rso_source_records_geom_gist",
    "idx_gps_daily_tracks_geom_gist",
    "idx_gps_track_points_geom_gist",
    "idx_route_segment_allocations_geom_gist",
    "idx_friendships_unordered_pair",
}

REQUIRED_SQLITE_TABLES = {
    "local_user_profile",
    "local_user_vehicle",
    "local_transport_catalog",
    "local_daily_step_summaries",
    "local_gps_track_points",
    "local_route_segment_allocations",
    "offline_mutation_outbox",
    "cached_waste_points",
    "pending_waste_point_reports",
    "cached_weekly_stats_snapshot",
    "cached_friends_leaderboard",
    "cached_badges_and_inventory",
}


def verify_sqlite_contract() -> None:
    ddl = (CONTRACTS_DIR / "client_sqlite_schema.sql").read_text(encoding="utf-8")
    conn = sqlite3.connect(":memory:")
    conn.executescript(ddl)
    cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
    actual_tables = {row[0] for row in cursor.fetchall()}
    missing = REQUIRED_SQLITE_TABLES - actual_tables
    if missing:
        raise RuntimeError(f"Missing SQLite tables in client_sqlite_schema.sql: {sorted(missing)}")
    conn.close()


def verify_openapi_and_error_catalog() -> None:
    openapi_doc = yaml.safe_load((CONTRACTS_DIR / "openapi.yaml").read_text(encoding="utf-8"))
    validate(openapi_doc)

    error_catalog = json.loads((CONTRACTS_DIR / "error_catalog.json").read_text(encoding="utf-8"))
    catalog_codes = set(error_catalog["errors"].keys())
    allowed_actions = set(error_catalog["allowed_client_actions"])

    for code, entry in error_catalog["errors"].items():
        if entry["code"] != code:
            raise RuntimeError(f"Error key {code} mismatches inner code {entry['code']}")
        if entry["client_action"] not in allowed_actions:
            raise RuntimeError(f"Invalid client_action in {code}: {entry['client_action']}")
        if not entry.get("ui_message_ru"):
            raise RuntimeError(f"Missing Russian UI message in {code}")

    # Verify FastAPI runtime route parity against contracts/openapi.yaml
    app = create_app()
    runtime_openapi = app.openapi()
    contract_paths = set(openapi_doc["paths"].keys())
    runtime_paths = set(runtime_openapi["paths"].keys())
    if contract_paths != runtime_paths:
        diff = contract_paths.symmetric_difference(runtime_paths)
        raise RuntimeError(f"FastAPI runtime paths diverge from contracts/openapi.yaml: {sorted(diff)}")

    # Ensure every error_code example in openapi.yaml exists in error_catalog.json
    examples = (
        openapi_doc["components"]["schemas"]["ErrorResponse"]["properties"]["error_code"].get("examples", [])
    )
    missing_codes = set(examples) - catalog_codes
    if missing_codes:
        raise RuntimeError(f"OpenAPI error_code examples missing from error_catalog.json: {missing_codes}")


async def verify_postgres_contract(dsn: str) -> None:
    conn: asyncpg.Connection = await asyncpg.connect(dsn)
    try:
        triggers = {
            row["tgname"]
            for row in await conn.fetch(
                "SELECT tgname FROM pg_trigger WHERE NOT tgisinternal"
            )
        }
        missing_trg = REQUIRED_PG_TRIGGERS - triggers
        if missing_trg:
            raise RuntimeError(f"Missing PostgreSQL triggers: {sorted(missing_trg)}")

        indexes = {
            row["indexname"]
            for row in await conn.fetch(
                "SELECT indexname FROM pg_indexes WHERE schemaname = 'public'"
            )
        }
        missing_idx = REQUIRED_PG_INDEXES - indexes
        if missing_idx:
            raise RuntimeError(f"Missing PostGIS/PostgreSQL indexes: {sorted(missing_idx)}")
    finally:
        await conn.close()


if __name__ == "__main__":
    verify_sqlite_contract()
    verify_openapi_and_error_catalog()
    import os

    db_dsn = os.environ.get("DATABASE_URL")
    if db_dsn:
        asyncio.run(verify_postgres_contract(db_dsn))
    print("ALL CONTRACT CHECKS PASSED.")
    sys.exit(0)
```

### 2.2 Backend Linter, Typechecker & Semgrep AST Configuration

#### `backend/pyproject.toml` (`ruff` & `basedpyright` sections)
```toml
[tool.ruff]
target-version = "py314"
line-length = 100
src = ["app", "tests"]

[tool.ruff.lint]
select = ["E", "F", "B", "ASYNC", "S", "SIM", "UP", "RUF", "FA", "TID", "C90"]
ignore = []

[tool.ruff.lint.mccabe]
max-complexity = 10

[tool.ruff.lint.flake8-tidy-imports.banned-api]
"pydantic.v1".msg = "pydantic.v1 is strictly forbidden; use native Pydantic v2.14 APIs."
"unittest.mock".msg = "Classic mock-heavy TDD is forbidden; use real PostGIS fixtures and Hypothesis."
"shapely".msg = "C-GIS libraries are forbidden in backend; execute spatial ops in PostGIS SQL."
"geopandas".msg = "C-GIS libraries are forbidden in backend; execute spatial ops in PostGIS SQL."
"osgeo".msg = "GDAL/osgeo is forbidden in backend; execute spatial ops in PostGIS SQL."

[tool.basedpyright]
pythonVersion = "3.14"
typeCheckingMode = "strict"
reportMissingTypeStubs = false
reportUnknownMemberType = "error"
reportUnknownArgumentType = "error"
reportUnknownVariableType = "error"
reportUnusedCoroutine = "error"
```

#### `backend/.semgrep.yml` (Custom AST Enforcement Rules)
```yaml
rules:
  - id: ban-future-annotations-py314
    patterns:
      - pattern: from __future__ import annotations
    message: "Python 3.14 implements native PEP 649/749; 'from __future__ import annotations' is forbidden."
    languages: [python]
    severity: ERROR

  - id: ban-sql-fstring-interpolation
    patterns:
      - pattern-either:
          - pattern: $CONN.fetch(f"...", ...)
          - pattern: $CONN.fetchrow(f"...", ...)
          - pattern: $CONN.fetchval(f"...", ...)
          - pattern: $CONN.execute(f"...", ...)
    message: "SQL f-string interpolation is forbidden; use positional $1, $2 asyncpg parameters."
    languages: [python]
    severity: ERROR

  - id: ban-direct-user-points-balance-update
    pattern-regex: "(?i)UPDATE\\s+users\\s+SET[^;]*points_balance\\s*="
    paths:
      exclude:
        - "app/migrations/**"
    message: "Direct UPDATE on users.points_balance is forbidden; insert into point_ledger instead."
    languages: [python]
    severity: ERROR

  - id: ban-pydantic-v1-methods
    patterns:
      - pattern-either:
          - pattern: $MODEL.dict(...)
          - pattern: $CLS.parse_obj(...)
          - pattern: $CLS.from_orm(...)
    message: "Pydantic v1 methods (.dict, .parse_obj, .from_orm) are forbidden; use .model_dump() / .model_validate()."
    languages: [python]
    severity: ERROR
```

### 2.3 Mobile Static Analysis & Architecture Boundary Gate
1. Executed unconditionally from repository root on every PR and push (`Makefile` `verify-static` & `.github/workflows/ci.yml` `code-quality-gates`):
   `uv run --with pyyaml python scripts/verify_mobile_gates.py`
   Enforces 8 deterministic verification gates (exiting `0` with `[SKIP]` on Gates 5–8 when `mobile/lib/` and `mobile/test/` contain no `.dart` source yet, and exiting `1` on any defect):
   - **Gate 1 — Visual Reference Canon (`screens/`)**: verifies all 14 canonical PNG wireframes exist and are non-empty under `screens/`.
   - **Gate 2 — `mobile/pubspec.yaml` Integrity & Package Bans**: enforces `environment.sdk >= 3.13.4`, bans codegen/DI/mock/legacy-map packages (`build_runner`, `freezed`, `riverpod`, `get_it`, `hive`, `drift`, `mockito`, `mocktail`, etc.), requires `glados`, `dart_code_linter`, `import_lint`, and `sqflite_common_ffi`, enforces runtime floor versions (`go_router >= 15.0.0`, `dio >= 5.8.0`, `flutter_bloc >= 9.1.0`, `flutter_map >= 8.2.0`, `geolocator >= 14.0.0`, `health >= 12.1.0`, `flutter_foreground_task >= 9.0.0`), and checks required schema/error assets.
   - **Gate 3 — `mobile/analysis_options.yaml` Anti-Weakening Guard**: requires top-level `plugins` (`dart_code_linter` and `import_lint`), `strict-casts`/`strict-inference`/`strict-raw-types: true`, `deprecated_member_use: error` and `deprecated_member_use_from_same_package: error` (forbidding `ignore` on critical diagnostics including `todo`), `use_primary_constructors`, `use_declaring_parameters`, `avoid_dynamic_calls`, `unawaited_futures`, and a non-empty `import_lint.rules` mapping.
   - **Gate 4 — Platform Runner Bloat & Canonical 3-Module Paths**: forbids `mobile/macos`, `mobile/windows`, `mobile/linux`, `mobile/web` runners and checks canonical paths for `mascot_vector_painter.dart`, `map_activity_screen.dart`, and `outbox_dispatcher.dart`.
   - **Gate 5 — Dart Static Bans, Anti-Suppression & Import Boundaries**: bans `// ignore:` suppressions on critical lints, `\bdynamic\b`, postfix `!` null-assertions, `showSnackBar(`, empty `catch` blocks, `deleteDatabase(`, dark theme APIs (`Brightness.dark`, `ThemeData.dark(`) in theme/app setup, `double` fields for integer CO₂/points totals, and enforces `presentation`/`domain` layer isolation plus cross-feature imports restricted to `features/<other>/domain/`.
   - **Gate 6 — OpenAPI, Error Catalog, SQLite & Anti-Stub Contract Parity**: validates all `/api/v1/...` literals against the 38 paths in `contracts/openapi.yaml` (banning `/v1/...` without `/api`), requires `API_BASE_URL` env reading, `'error_code'` parsing, and HTTP `get`/`post`/`put`/`patch`/`delete` in `core/network/`, validates `AppError.fromCode(...)` and `clientAction:` against `contracts/error_catalog.json`, bans inline `CREATE TABLE` DDL and legacy outbox literals, and blocks auth/push stub markers (`sample-google-oauth-code`, `mock-device-token`, `register_screen.dart`).
   - **Gate 7 — Android Manifest & 152-FZ Permission Gate**: bans `ACCESS_BACKGROUND_LOCATION` and requires `android.permission.health.READ_STEPS`, `android.permission.ACTIVITY_RECOGNITION`, `android.permission.FOREGROUND_SERVICE_LOCATION`, and `android:scheme="ecotrack"`.
   - **Gate 8 — Anti-Tautology Test Quality Gate**: verifies every `mobile/test/pbt/*_pbt_test.dart` imports `package:glados/glados.dart`, runs `Glados`, and imports `package:ecotrack_mobile/`, requires `outbox_fsm_pbt_test.dart` and `app_router.dart` coverage, and bans `mockito`/`mocktail`.
2. Executed from `/mobile/` when `.dart` sources exist:
   - `dart format --output=none --set-exit-if-changed lib test`
   - `flutter analyze --fatal-infos --fatal-warnings`
   - `dart analyze --fatal-infos --fatal-warnings` (executes Dart 3.13 `analysis_server_plugin` diagnostics for `dart_code_linter ^4.4.1` — `avoid-dynamic`, `avoid-non-null-assertion`, `always-remove-listener`, `no-empty-block` — and `import_lint ^2.0.0`)
   - `dart run import_lint` (enforcing `import_lint ^2.0.0` `target` / `from` / `except` rules for `features/*/presentation/**` and `features/*/domain/**` with `severity: error`).

---

## 3. Layer 2 — Formal Design-by-Contract & Symbolic Proof Gate (`make verify-dbc`)

### 3.1 `icontract` + `CrossHair` (Z3 SMT Solver) Verification Contract
Every pure mathematical and classification function in `backend/app/domain/` is decorated with `@icontract.require` and `@icontract.ensure` and verified symbolically via `CrossHair` backed by the Z3 SMT solver:

```bash
uv run --directory backend crosshair check \
  --per_condition_timeout=10 \
  --per_path_timeout=4 \
  --analysis_kind=icontract \
  app/domain/
```

> **CrossHair / Z3 Optimization Note**: Python's `decimal.Decimal` is implemented in C (`_decimal`), which can cause Z3 solver timeouts during symbolic evaluation of `.quantize()`. Domain functions under `backend/app/domain/` verified by CrossHair must either perform intermediate math in scaled integers (e.g. micrometers, milligrams) or utilize pure-Python rounding helpers (`_pydecimal` or integer-based round-half-up) to guarantee deterministic SMT proofs in `< 0.5s`.

| Domain Module & Function | Symbolic Input Space Explored by Z3 | Proven Postcondition Invariant (`0` Counterexamples Allowed) |
| :--- | :--- | :--- |
| `vehicle_emissions.compute_vehicle_co2_factors` | All 8 `FuelType` enum members $\times$ `Decimal("0.01")..Decimal("50.00")` | `co2_g_per_km > 0`, `co2_g_per_m > 0`, and `co2_g_per_km == (co2_g_per_m * 1000).quantize(Decimal("0.01"))` |
| `motion_classifier.compute_reboot_safe_step_delta` | `prev_cumulative: int >= 0`, `curr_cumulative: int >= 0` | Result is non-negative (`>= 0`); equals `curr - prev` when monotonic, and `curr` when `curr < prev` (reboot reset) |
| `motion_classifier.classify_interval` | `delta_t_sec >= 1.0`, `delta_dist_m >= 0.0`, `delta_steps >= 0`, `accuracy_m >= 0.0` | `accuracy_m > 65.0` $\implies$ `UNKNOWN`; `WALKING` $\implies$ (`delta_steps >= 4` $\land$ `delta_dist_m >= 6.00` $\land$ `0.30 <= stride <= 2.20` $\land$ `v <= 6.50`) |
| `hybrid_co2.compute_segment_co2_grams` | `segment_distance_m > 0.0`, `co2_g_per_meter >= 0.0` | Result is an exact non-negative `int` rounded via `ROUND_HALF_UP` |
| `hybrid_co2.compute_hybrid_daily_co2` | `steps in 0..100000`, `stride in 40..120`, `alloc_m >= 0`, `alloc_co2 >= 0`, `alloc_cnt >= 0` | `unallocated_m >= 0`, `auto_co2 >= 0`, `total_co2 == alloc_co2 + auto_co2`, `is_auto_calculated == (alloc_cnt == 0)` |
| `hybrid_co2.compute_daily_step_points_delta` | `validated_steps in 0..100000`, `already_awarded in 0..1000` | `target == validated_steps // 100`, `delta == max(0, target - already_awarded)`, `0 <= delta <= 1000` |
| `equivalents.compute_eco_equivalents` | `total_co2_saved_grams: int >= 0` | All 9 physical equivalent metrics are non-negative and monotonically non-decreasing with `total_co2_saved_grams` |
| `rso_trust.compute_new_trust_score` | `current_trust in 0.00..100.00` $\times$ all 6 `ReportType` values | `new_trust` is clamped to `[0.00, 100.00]`; `< 25.00` $\implies$ `UNVERIFIED`; `>= 50.00` $\implies$ `ACTIVE` |

### 3.2 PostgreSQL 17 + PostGIS Constraint-Violation Matrix (`tests/contract/test_pg_triggers_invariants.py`)
This test suite runs against live `postgis/postgis:17-3.5-alpine` and executes explicit negative SQL test vectors asserting that PostgreSQL triggers and constraints reject invalid states at the database engine level:

| Invariant ID | Target Table / Trigger | Negative Test Vector Executed | Expected PostgreSQL Exception / Post-State |
| :--- | :--- | :--- | :--- |
| **`PG-INV-01`** | `point_ledger` / `trg_point_ledger_immutable` | `UPDATE point_ledger SET points_delta = 9999 WHERE id = $1` | Raises `asyncpg.IntegrityConstraintViolationError` (`SQLSTATE 23000`) |
| **`PG-INV-02`** | `point_ledger` / `trg_point_ledger_immutable` | `DELETE FROM point_ledger WHERE id = $1` (direct DELETE without `ecotrack.in_152fz_account_erasure = 'true'`) | Raises `asyncpg.IntegrityConstraintViolationError` (`SQLSTATE 23000`) |
| **`PG-INV-03`** | `users` -> `point_ledger` 152-FZ Cascade | Transaction with `SET LOCAL ecotrack.in_152fz_account_erasure = 'true'; DELETE FROM users WHERE id = $1` | Succeeds cleanly; `COUNT(*) FROM point_ledger WHERE user_id = $1` is `0` |
| **`PG-INV-04`** | `point_ledger` / `trg_point_ledger_sync_balance` + `CHECK (points_balance >= 0)` | User has `points_balance = 100`; `INSERT INTO point_ledger (..., points_delta = -150)` | Raises `asyncpg.CheckViolationError` (`SQLSTATE 23514`); transaction rolls back and `points_balance` remains `100` |
| **`PG-INV-05`** | `friendships` / `CHECK (requester_id <> addressee_id)` | `INSERT INTO friendships (requester_id, addressee_id) VALUES ($1, $1)` | Raises `asyncpg.CheckViolationError` (`SQLSTATE 23514`) |
| **`PG-INV-06`** | `friendships` / `idx_friendships_unordered_pair` | User A requests User B `(A, B)`, then User B inserts `(B, A)` | Raises `asyncpg.UniqueViolationError` (`SQLSTATE 23505`) on `(LEAST, GREATEST)` index |
| **`PG-INV-07`** | `gps_daily_tracks` & `route_segment_allocations` / `CHECK (ST_IsValid(...))` | Insert self-intersecting bowtie LineString geometry | Raises `asyncpg.CheckViolationError` (`SQLSTATE 23514`) |
| **`PG-INV-08`** | `gps_track_points` / `UNIQUE (track_id, recorded_at)` & `UNIQUE (track_id, seq_no)` | Insert duplicate `seq_no` or duplicate `recorded_at` for same `track_id` | Raises `asyncpg.UniqueViolationError` (`SQLSTATE 23505`) |
| **`PG-INV-09`** | `point_reports` / `trg_point_reports_apply_trust` | Insert two `missing_bin` (`-25.00`) reports on a point with `trust_score = 50.00`, followed by one more `missing_bin` (`-25.00`) | After 2nd report: `trust_score == 0.00`, `status == 'unverified'`; after 3rd report: `trust_score` stays clamped at `0.00` |

---

## 4. Layer 3 — Dynamic Property-Based Testing & API Contract Fuzzing (`make verify-pbt`)

### 4.1 Backend `Hypothesis` Stateful Machine (`tests/pbt/test_stateful_ledger_activity.py`)
Uses `hypothesis.stateful.RuleBasedStateMachine` (`max_examples=75, stateful_step_count=35`) executing against a live PostGIS transaction to verify that arbitrary sequences of user operations never violate ledger or CO₂ invariants:

```python
from datetime import date, timedelta
from uuid import uuid4

from hypothesis import settings, strategies as st
from hypothesis.stateful import Bundle, RuleBasedStateMachine, invariant, rule


class EcoTrackStatefulMachine(RuleBasedStateMachine):
    users = Bundle("users")
    synced_days = Bundle("synced_days")

    def __init__(self) -> None:
        super().__init__()
        self.db = get_sync_test_db_wrapper()
        self.used_idempotency_keys: list[tuple[str, str, dict[str, object]]] = []

    @rule(target=users, stride_cm=st.integers(min_value=40, max_value=120))
    def create_user(self, stride_cm: int) -> str:
        return self.db.create_test_user(stride_length_cm=stride_cm)

    @rule(
        target=synced_days,
        user_id=users,
        day_offset=st.sampled_from([0, 1]),
        raw_steps=st.integers(min_value=0, max_value=95000),
    )
    def sync_daily_steps(self, user_id: str, day_offset: int, raw_steps: int) -> tuple[str, date]:
        activity_date = date.today() - timedelta(days=day_offset)
        idem_key = str(uuid4())
        payload = {
            "activity_date": activity_date.isoformat(),
            "timezone_offset_minutes": 180,
            "raw_sensor_steps": raw_steps,
        }
        self.db.sync_steps(user_id=user_id, idempotency_key=idem_key, payload=payload)
        self.used_idempotency_keys.append((user_id, idem_key, payload))
        return (user_id, activity_date)

    @rule(
        user_day=synced_days,
        mode=st.sampled_from(["bus", "metro", "tram", "personal_car", "car_sedan", "car_suv"]),
        segment_dist_m=st.integers(min_value=50, max_value=3000),
    )
    def upload_track_and_allocate_segment(
        self, user_day: tuple[str, date], mode: str, segment_dist_m: int
    ) -> None:
        user_id, activity_date = user_day
        self.db.seed_walking_track(user_id, activity_date, distance_m=segment_dist_m)
        self.db.replace_allocations(
            user_id=user_id,
            activity_date=activity_date,
            idempotency_key=str(uuid4()),
            allocations=[
                {
                    "idempotency_key": str(uuid4()),
                    "start_seq_no": 0,
                    "end_seq_no": 1,
                    "replaced_transport_mode": mode,
                }
            ],
        )

    @rule()
    def replay_previous_idempotency_key(self) -> None:
        if not self.used_idempotency_keys:
            return
        user_id, idem_key, payload = self.used_idempotency_keys[-1]
        balance_before = self.db.get_user_balance(user_id)
        self.db.sync_steps(user_id=user_id, idempotency_key=idem_key, payload=payload)
        balance_after = self.db.get_user_balance(user_id)
        assert balance_before == balance_after

    @rule(user_id=users, qty=st.integers(min_value=1, max_value=2))
    def attempt_shop_checkout(self, user_id: str, qty: int) -> None:
        self.db.attempt_checkout_streak_freeze(user_id=user_id, quantity=qty, idempotency_key=str(uuid4()))

    @invariant()
    def ledger_and_hybrid_co2_invariants_hold(self) -> None:
        self.db.assert_all_global_invariants()


TestEcoTrackStateful = EcoTrackStatefulMachine.TestCase
TestEcoTrackStateful.settings = settings(max_examples=75, stateful_step_count=35, deadline=None)
```

**Global Invariants Checked After Every Single Rule Transition (`assert_all_global_invariants()`)**:
1. **Non-Negative Balance**: `SELECT COUNT(*) FROM users WHERE points_balance < 0` $== 0$.
2. **Exact Ledger Sum Parity**:
   ```sql
   SELECT COUNT(*)
   FROM users u
   LEFT JOIN (
       SELECT user_id,
              COALESCE(SUM(points_delta), 0) AS net_points,
              COALESCE(SUM(points_delta) FILTER (WHERE points_delta > 0), 0) AS earned_points
       FROM point_ledger
       GROUP BY user_id
   ) l ON l.user_id = u.id
   WHERE u.points_balance <> COALESCE(l.net_points, 0)
      OR u.lifetime_points_earned <> COALESCE(l.earned_points, 0);
   ```
   Must equal `0`.
3. **Hybrid CO₂ Conservation**: For every row in `daily_step_summaries`, `total_co2_saved_grams == allocated_co2_saved_grams + auto_default_co2_saved_grams` and `unallocated_step_distance_m == GREATEST(0.00, total_step_distance_m - allocated_gps_distance_m)`.

### 4.2 `Schemathesis` OpenAPI 3.1.0 Fuzzing Suite (`tests/pbt/test_schemathesis_api.py`)
Fuzzes all 38 operations in `contracts/openapi.yaml` using ASGI in-process transport connected to the test PostGIS database:

```python
import uuid
import schemathesis
from hypothesis import settings

schema = schemathesis.from_path("../contracts/openapi.yaml")


@schemathesis.hook
def before_call(context, case):
    case.headers = case.headers or {}
    if case.method.upper() in {"POST", "PUT", "PATCH", "DELETE"}:
        case.headers.setdefault("Idempotency-Key", str(uuid.uuid4()))


@schema.parametrize()
@settings(max_examples=30, deadline=None)
def test_openapi_contract_fuzzing(case, auth_bearer_header):
    case.headers = {**(case.headers or {}), **auth_bearer_header}
    response = case.call_asgi()
    case.validate_response(response)
    assert response.status_code < 500, f"Unexpected 5xx on {case.method} {case.path}: {response.text}"
```

### 4.3 Mobile `glados` Property-Based Testing Suite (`mobile/test/pbt/`)
Executed via `flutter test test/pbt/`:
1. **DTO Serialization Round-Trip Property (`dto_roundtrip_pbt_test.dart`)**:
   - Generates arbitrary valid `DailyActivitySummary`, `UserVehicle`, `RouteSegmentAllocationItem`, `WastePointMapItem`, and `ShopOrderDetail` instances via `any.combine...` and asserts `Model.fromJson(model.toJson()) == Ok(model)`.
2. **Client-Server Hybrid CO₂ Parity Property (`hybrid_co2_parity_pbt_test.dart`)**:
   - For all `validatedSteps` $\in [0, 100000]$, `strideCm` $\in [40, 120]$, and non-overlapping segment allocations, asserts that the Dart preview calculator produces the **exact same integer grams** (`allocatedCo2`, `autoDefaultCo2`, `totalCo2`) as the Python `compute_hybrid_daily_co2` specification in `specs/02-domain-math-and-algorithms.md`.
3. **SQLite Outbox Causal & Zero-Loss Property (`outbox_fsm_pbt_test.dart`)**:
   - Runs against a real `sqflite_common_ffi` database loaded with `contracts/client_sqlite_schema.sql`. Generates random sequences of `[enqueueSteps, enqueueGpsBatch, enqueueSegmentAllocation, networkDrop, networkRestore, http429, http200]` and asserts:
     - `upsert_segment_allocation` never enters `in_flight` while an earlier `sync_daily_steps` or `upload_gps_track_batch` for the same `activity_date` is still in `offline_mutation_outbox`.
     - `idempotency_key` remains invariant across all retry transitions for a given `outbox_id`.

---

## 5. Layer 4 — Concurrency, Spatial Performance, Load & UI Frame Stress Gates (`make verify-stress`)

### 5.1 Gate 4.1 — Double-Spend & Idempotency Race Barrier (`tests/stress/test_double_spend_barrier.py`)
1. **Scenario 1 (50 Concurrent Checkouts Racing for Last Balance)**:
   - Seed a test user with `points_balance = 300 ★` (via `INSERT INTO point_ledger`) and a shop item (`DEMO-COFFEE-30`, price `250 ★`).
   - Launch `50` concurrent `asyncio.gather` coroutines against `POST /api/v1/shop/orders`, each with a **distinct** UUIDv7 `Idempotency-Key` attempting to purchase `1` unit (`250 ★`).
   - **Pass Criteria**:
     - Exactly `1` coroutine returns `201 Created`.
     - Exactly `49` coroutines return `409 Conflict` (`error_code == "INSUFFICIENT_POINTS_BALANCE"`).
     - Post-test database state: `users.points_balance == 50`, `COUNT(*) FROM shop_orders WHERE user_id = $1` $== 1$, `COUNT(*) FROM point_ledger WHERE user_id = $1 AND operation_type = 'shop_purchase'` $== 1$.
2. **Scenario 2 (50 Concurrent Identical `Idempotency-Key` Replays)**:
   - Launch `50` concurrent `asyncio.gather` coroutines sending the **exact same** `Idempotency-Key` to `POST /api/v1/activity/tracks/points:batch` (50 points) and `PUT /api/v1/activity/steps/daily` (`5,000` steps).
   - **Pass Criteria**:
     - Zero `500` responses; all responses are either `200 OK` or `409 IDEMPOTENCY_IN_FLIGHT`.
     - Exactly `50` track points exist in `gps_track_points` (zero duplicates) and exactly `+50 ★` was credited once to `point_ledger`.

### 5.2 Gate 4.2 — PostGIS `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` Spatial Gate (`tests/stress/test_postgis_explain_analyze.py`)
1. **Synthetic Dataset Seeding**:
   - Bulk-inserts `100,000` valid `waste_points` distributed across Moscow, St. Petersburg, and Russian regional centers plus `1,000,000` `gps_track_points` across `2,000` daily tracks, then runs `VACUUM ANALYZE waste_points, gps_track_points;`.
2. **Automated Plan Inspection**:
   - Executes `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` on the canonical BBox + fraction query from `specs/04-postgis-and-rso-data-pipeline.md`:
     ```sql
     EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
     SELECT id, title, accepted_fractions, ST_Y(geom) AS lat, ST_X(geom) AS lon, status, trust_score
     FROM waste_points
     WHERE geom && ST_MakeEnvelope(37.50, 55.70, 37.70, 55.80, 4326)
       AND status = 'active'
       AND trust_score >= 25.00
       AND accepted_fractions && ARRAY['plastic', 'glass']::waste_fraction_code[]
     LIMIT 300;
     ```
3. **Pass Criteria**:
   - Recursive traversal of the JSON plan tree confirms `"Node Type" != "Seq Scan"` on `waste_points` and `gps_track_points`.
   - Asserts `"Index Name": "idx_waste_points_geom_gist"` (or BitmapAnd combining `idx_waste_points_geom_gist` and `idx_waste_points_fractions_gin`) is present in the plan.
   - Asserts `"Execution Time"` is `< 15.0 ms` at `25,000` rows and `< 25.0 ms` at `100,000` rows.

### 5.3 Gate 4.3 — `k6` Constrained VPS Load Test (`backend/tests/stress/k6_load_gate.js`)
Executed against the Docker Compose stack with resource limits active (`cpus: "1.0"`, `memory: 512M` on both `api` and `db`):

```javascript
import http from 'k6/http';
import { check } from 'k6';
import { uuidv4 } from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';

export const options = {
  scenarios: {
    mixed_mvp_workload: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '15s', target: 30 },
        { duration: '45s', target: 30 },
        { duration: '10s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate==0.00'],
    http_req_duration: ['p(95)<120', 'p(50)<50'],
  },
};

const BASE_URL = __ENV.API_BASE_URL || 'http://127.0.0.1:8000';
const TOKEN = __ENV.LOAD_TEST_BEARER_TOKEN;

export default function () {
  const headers = {
    Authorization: `Bearer ${TOKEN}`,
    'Content-Type': 'application/json',
    'Idempotency-Key': uuidv4(),
  };

  // 1. BBox Recycling Map Query
  const mapRes = http.get(
    `${BASE_URL}/api/v1/map/waste-points?min_lat=55.70&min_lon=37.50&max_lat=55.80&max_lon=37.70&zoom=14&fractions=plastic`,
    { headers }
  );
  check(mapRes, { 'map 200': (r) => r.status === 200 });

  // 2. Daily Steps Sync
  const stepRes = http.put(
    `${BASE_URL}/api/v1/activity/steps/daily`,
    JSON.stringify({
      activity_date: new Date().toISOString().slice(0, 10),
      timezone_offset_minutes: 180,
      raw_sensor_steps: 6400,
    }),
    { headers: { ...headers, 'Idempotency-Key': uuidv4() } }
  );
  check(stepRes, { 'steps 200': (r) => r.status === 200 });

  // 3. Stats Overview Query
  const statsRes = http.get(`${BASE_URL}/api/v1/stats/emissions?period=days`, { headers });
  check(statsRes, { 'stats 200': (r) => r.status === 200 });
}
```
- **Pass Criteria**: `p95 < 120 ms` (target `< 80 ms`), `p50 < 50 ms`, `0.00%` unexpected `5xx` errors, and `docker inspect ecotrack-api --format '{{.State.OOMKilled}}'` equals `false`.

### 5.4 Gate 4.4 — Flutter Impeller Map & Mascot Frame Benchmark (`mobile/integration_test/impeller_map_mascot_benchmark_test.dart`)
Runs on an Impeller-enabled simulator/device to verify smooth 60fps rendering under worst-case visual load:
1. Seeds `10,000` classified GPS track points (`walking`, `indoor_pacing`, `vehicle_suspected`) with `15` transport allocations and `5,000` RSO waste points into local SQLite.
2. Pumps `HomeScreen` (with `FoxMascotWidget` breathing + long-press squinting + `firefly_aura` accessory) for `180` frames, then switches to `MapActivityScreen` and performs programmatic pan/zoom gestures across both `[ Мои маршруты ]` and `[ Пункты РСО ]` modes for `300` frames while recording `FrameTiming` via `WidgetsBinding.instance.addTimingsCallback`.
3. **Pass Criteria**:
   - `p99` `FrameTiming.buildDuration.inMicroseconds <= 16600` (`16.6 ms`)
   - `p99` `FrameTiming.rasterDuration.inMicroseconds <= 16600` (`16.6 ms`)

---

## 6. Master CI Pipeline Blueprint (`.github/workflows/verify.yml`)

Every Pull Request targeting `main` MUST pass this 4-Layer Verification workflow before merge is unlocked:

```yaml
name: EcoTrack 4-Layer Verification Gate

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  verify-monorepo:
    runs-on: ubuntu-24.04
    timeout-minutes: 25

    services:
      postgis:
        image: postgis/postgis:17-3.5-alpine
        env:
          POSTGRES_USER: ecotrack
          POSTGRES_PASSWORD: ci_test_password
          POSTGRES_DB: ecotrack
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready -U ecotrack -d ecotrack"
          --health-interval=5s
          --health-timeout=3s
          --health-retries=10

    env:
      DATABASE_URL: postgresql://ecotrack:ci_test_password@127.0.0.1:5432/ecotrack
      JWT_SECRET_KEY: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
      FZ152_DELETION_HMAC_SECRET: fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210

    steps:
      - name: Checkout Monorepo
        uses: actions/checkout@v4

      - name: Load Canonical PostgreSQL 17 + PostGIS 3.5 Contract
        run: |
          PGPASSWORD=ci_test_password psql -h 127.0.0.1 -U ecotrack -d ecotrack -v ON_ERROR_STOP=1 -f contracts/schema.sql

      - name: Install uv & Python 3.14
        uses: astral-sh/setup-uv@v5
        with:
          python-version: "3.14"

      - name: Sync Backend Dependencies
        working-directory: backend
        run: uv sync --locked

      - name: Setup Flutter & Dart ^3.13.4
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Install Mobile Dependencies
        working-directory: mobile
        run: flutter pub get --enforce-lockfile

      - name: "Layer 1: Static, Contract Parity, Semgrep & Import Boundaries"
        run: make verify-static

      - name: "Layer 1b: Runtime Docker Image Footprint Gate (<= 100 MB)"
        run: make check-image-size

      - name: "Layer 2: Formal Design-by-Contract (CrossHair/Z3) & PG Trigger Invariants"
        run: make verify-dbc

      - name: "Layer 3: Property-Based Testing (Hypothesis + Schemathesis + Glados)"
        run: make verify-pbt

      - name: "Layer 4: Double-Spend Concurrency & PostGIS EXPLAIN ANALYZE Stress Gates"
        run: |
          uv run --directory backend pytest tests/stress/ -v
```
