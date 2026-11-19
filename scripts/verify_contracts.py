"""
scripts/verify_contracts.py — EcoTrack Layer 1 Contract Verification Gate
Validates structural integrity and 100% cross-contract parity across:
  1. contracts/schema.sql (PostgreSQL 17 + PostGIS 3.5)
  2. contracts/client_sqlite_schema.sql (Flutter SQLite 3 WAL)
  3. contracts/openapi.yaml (OpenAPI 3.1.0)
  4. contracts/error_catalog.json (Unified Error Catalog)
Exits 0 on success, exits 1 on any contract defect or drift.
"""

import json
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any, Final

try:
    import yaml
except ImportError:
    print("[ERROR] PyYAML is required. Run via 'uv run --with pyyaml python scripts/verify_contracts.py'")
    sys.exit(1)

ROOT: Final[Path] = Path(__file__).resolve().parent.parent
CONTRACTS_DIR: Final[Path] = ROOT / "contracts"

SCHEMA_SQL: Final[Path] = CONTRACTS_DIR / "schema.sql"
CLIENT_SQLITE_SQL: Final[Path] = CONTRACTS_DIR / "client_sqlite_schema.sql"
OPENAPI_YAML: Final[Path] = CONTRACTS_DIR / "openapi.yaml"
ERROR_CATALOG_JSON: Final[Path] = CONTRACTS_DIR / "error_catalog.json"

EXPECTED_PG_TABLES: Final[frozenset[str]] = frozenset({
    "mascot_accessories",
    "users",
    "user_oauth_identities",
    "auth_refresh_sessions",
    "fz152_consent_journal",
    "fz152_account_deletion_log",
    "user_push_tokens",
    "transport_emission_catalog",
    "user_vehicles",
    "daily_step_summaries",
    "gps_daily_tracks",
    "gps_track_points",
    "route_segment_allocations",
    "point_ledger",
    "shop_partners",
    "shop_items",
    "shop_orders",
    "shop_order_items",
    "user_mascot_inventory",
    "badges_catalog",
    "user_badges",
    "friendships",
    "friend_wakeup_nudges",
    "shared_forest_challenges",
    "shared_forest_contributions",
    "rso_source_records",
    "waste_points",
    "point_source_links",
    "point_reports",
})

EXPECTED_PG_TRIGGERS: Final[frozenset[str]] = frozenset({
    "trg_point_ledger_immutable",
    "trg_point_ledger_sync_balance",
    "trg_point_reports_apply_trust",
})

EXPECTED_PG_SPATIAL_INDEXES: Final[frozenset[str]] = frozenset({
    "idx_gps_daily_tracks_geom_gist",
    "idx_gps_track_points_geom_gist",
    "idx_route_segment_allocations_geom_gist",
    "idx_rso_source_records_geom_gist",
    "idx_rso_source_records_tags_gin",
    "idx_waste_points_geom_gist",
    "idx_waste_points_geog_gist",
    "idx_waste_points_fractions_gin",
})

EXPECTED_SQLITE_TABLES: Final[frozenset[str]] = frozenset({
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
})

# 1:1 Mapping between PostgreSQL ENUM types and OpenAPI 3.1.0 component schemas
PG_ENUM_TO_OPENAPI_SCHEMA: Final[dict[str, str]] = {
    "oauth_provider_type": "OAuthProviderType",
    "consent_action_type": "ConsentActionType",
    "fuel_type": "FuelType",
    "transport_mode_code": "TransportModeCode",
    "track_point_motion_class": "TrackPointMotionClass",
    "ledger_operation_type": "LedgerOperationType",
    "shop_item_type": "ShopItemType",
    "order_status": "OrderStatus",
    "friendship_status": "FriendshipStatus",
    "waste_fraction_code": "WasteFractionCode",
    "rso_source_type": "RsoSourceType",
    "waste_point_status": "WastePointStatus",
    "report_type": "ReportType",
    "push_platform_type": "PushPlatformType",
}

# Endpoints exempt from requiring Idempotency-Key header on POST/DELETE
IDEMPOTENCY_EXEMPT_OPERATIONS: Final[frozenset[str]] = frozenset({
    "refreshAccessToken",
    "logoutSession",
    "unregisterPushToken",
})


def _strip_sql_comments(sql: str) -> str:
    return re.sub(r"--[^\n]*", "", sql)


def parse_pg_enums(clean_sql: str) -> dict[str, list[str]]:
    pattern = re.compile(
        r"CREATE\s+TYPE\s+([a-z0-9_]+)\s+AS\s+ENUM\s*\(([^)]+)\)\s*;",
        re.IGNORECASE | re.DOTALL,
    )
    enums: dict[str, list[str]] = {}
    for match in pattern.finditer(clean_sql):
        enum_name = match.group(1).lower()
        raw_values = match.group(2)
        values = [v.strip().strip("'") for v in raw_values.split(",") if v.strip()]
        enums[enum_name] = values
    return enums


def verify_postgres_schema() -> tuple[bool, str, dict[str, list[str]]]:
    if not SCHEMA_SQL.exists():
        return False, f"Missing {SCHEMA_SQL}", {}

    clean_sql = _strip_sql_comments(SCHEMA_SQL.read_text(encoding="utf-8"))

    found_tables = set(
        re.findall(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-z0-9_]+)\s*\(", clean_sql, re.IGNORECASE)
    )
    missing_tables = EXPECTED_PG_TABLES - found_tables
    extra_tables = found_tables - EXPECTED_PG_TABLES
    if missing_tables or extra_tables:
        return (
            False,
            f"Table mismatch! Missing: {sorted(missing_tables)}, Unexpected: {sorted(extra_tables)}",
            {},
        )

    pg_enums = parse_pg_enums(clean_sql)
    missing_enums = set(PG_ENUM_TO_OPENAPI_SCHEMA.keys()) - set(pg_enums.keys())
    if missing_enums:
        return False, f"Missing PostgreSQL ENUM types: {sorted(missing_enums)}", {}

    found_triggers = set(
        re.findall(r"CREATE\s+TRIGGER\s+([a-z0-9_]+)", clean_sql, re.IGNORECASE)
    )
    missing_triggers = EXPECTED_PG_TRIGGERS - found_triggers
    if missing_triggers:
        return False, f"Missing critical triggers: {sorted(missing_triggers)}", {}

    found_indexes = set(
        re.findall(r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+([a-z0-9_]+)\s+ON", clean_sql, re.IGNORECASE)
    )
    missing_spatial_indexes = EXPECTED_PG_SPATIAL_INDEXES - found_indexes
    if missing_spatial_indexes:
        return False, f"Missing PostGIS GIST/GIN indexes: {sorted(missing_spatial_indexes)}", {}

    if "CHECK (points_balance >= 0)" not in clean_sql:
        return False, "Missing mandatory financial invariant 'CHECK (points_balance >= 0)' in users table", {}

    if "uuid_generate_v7()" not in clean_sql:
        return False, "Missing uuid_generate_v7() function definition in schema.sql", {}

    return (
        True,
        f"PostgreSQL 17 DDL valid ({len(found_tables)} tables, {len(pg_enums)} ENUMs, "
        f"{len(found_triggers)} triggers, {len(EXPECTED_PG_SPATIAL_INDEXES)} GIST/GIN indexes)",
        pg_enums,
    )


def verify_sqlite_schema() -> tuple[bool, str, str]:
    if not CLIENT_SQLITE_SQL.exists():
        return False, f"Missing {CLIENT_SQLITE_SQL}", ""

    raw_sql = CLIENT_SQLITE_SQL.read_text(encoding="utf-8")
    clean_sql = _strip_sql_comments(raw_sql)
    conn = sqlite3.connect(":memory:")
    try:
        conn.execute("PRAGMA foreign_keys = ON;")
        conn.executescript(raw_sql)
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
        found_tables = {row[0] for row in cursor.fetchall()}
        missing_tables = EXPECTED_SQLITE_TABLES - found_tables
        extra_tables = found_tables - EXPECTED_SQLITE_TABLES
        if missing_tables or extra_tables:
            return (
                False,
                f"SQLite table mismatch! Missing: {sorted(missing_tables)}, Unexpected: {sorted(extra_tables)}",
                "",
            )

        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")
        found_indexes = {row[0] for row in cursor.fetchall()}
        if len(found_indexes) < 7:
            return False, f"Expected at least 7 custom SQLite indexes, found {len(found_indexes)}", ""

        cursor.execute("PRAGMA foreign_key_check;")
        fk_errors = cursor.fetchall()
        if fk_errors:
            return False, f"SQLite PRAGMA foreign_key_check failed: {fk_errors}", ""

        # Negative probe: ensure CHECK (points_balance >= 0) rejects negative balance
        try:
            conn.execute(
                """
                INSERT INTO local_user_profile (
                    user_id, display_name, friend_code, auth_provider, points_balance, updated_at_ms
                ) VALUES ('u1', 'Test', 'ECO-1111-2222', 'yandex', -10, 1000);
                """
            )
            return False, "SQLite CHECK constraint failed to reject negative points_balance (-10)", ""
        except sqlite3.IntegrityError:
            pass

        return (
            True,
            f"SQLite 3 WAL schema valid ({len(found_tables)} tables, {len(found_indexes)} indexes, CHECK probes passed)",
            clean_sql,
        )
    except Exception as exc:
        return False, f"SQLite DDL execution failed: {exc}", ""
    finally:
        conn.close()


def _collect_refs_and_nullables(node: Any, refs: list[str], nullables: list[str], path: str = "") -> None:
    if isinstance(node, dict):
        if "$ref" in node and isinstance(node["$ref"], str):
            refs.append(node["$ref"])
        if "nullable" in node:
            nullables.append(path)
        for k, v in node.items():
            _collect_refs_and_nullables(v, refs, nullables, f"{path}.{k}")
    elif isinstance(node, list):
        for idx, item in enumerate(node):
            _collect_refs_and_nullables(item, refs, nullables, f"{path}[{idx}]")


def _resolve_json_pointer(doc: dict[str, Any], ref: str) -> bool:
    if not ref.startswith("#/"):
        return False
    parts = ref[2:].split("/")
    curr: Any = doc
    for part in parts:
        part_unescaped = part.replace("~1", "/").replace("~0", "~")
        if not isinstance(curr, dict) or part_unescaped not in curr:
            return False
        curr = curr[part_unescaped]
    return True


def verify_openapi_contract() -> tuple[bool, str, dict[str, Any]]:
    if not OPENAPI_YAML.exists():
        return False, f"Missing {OPENAPI_YAML}", {}
    try:
        data: dict[str, Any] = yaml.safe_load(OPENAPI_YAML.read_text(encoding="utf-8"))
        version = str(data.get("openapi", ""))
        paths: dict[str, Any] = data.get("paths", {})
        schemas: dict[str, Any] = data.get("components", {}).get("schemas", {})

        if version != "3.1.0":
            return False, f"Expected OpenAPI '3.1.0', found '{version}'", {}
        if len(paths) != 38:
            return False, f"Expected exactly 38 canonical OpenAPI paths, found {len(paths)}", {}
        if len(schemas) < 85:
            return False, f"Expected at least 85 component schemas, found {len(schemas)}", {}

        # Verify all $ref pointers resolve and no legacy OpenAPI 3.0 'nullable: true' exists
        refs: list[str] = []
        nullables: list[str] = []
        _collect_refs_and_nullables(data, refs, nullables)
        if nullables:
            return False, f"Forbidden OpenAPI 3.0 'nullable' keyword found at: {nullables[:5]}", {}

        broken_refs = [r for r in refs if not _resolve_json_pointer(data, r)]
        if broken_refs:
            return False, f"Broken $ref pointers in openapi.yaml: {broken_refs}", {}

        # Verify unique operationIds and Idempotency-Key on state-mutating operations
        operation_ids: set[str] = set()
        mutating_methods = {"post", "put", "patch", "delete"}
        for path_str, path_item in paths.items():
            for method, op in path_item.items():
                if method.lower() not in {"get", "post", "put", "patch", "delete"}:
                    continue
                op_id = op.get("operationId")
                if not op_id:
                    return False, f"Missing operationId on {method.upper()} {path_str}", {}
                if op_id in operation_ids:
                    return False, f"Duplicate operationId '{op_id}' in openapi.yaml", {}
                operation_ids.add(op_id)

                if method.lower() in mutating_methods and op_id not in IDEMPOTENCY_EXEMPT_OPERATIONS:
                    params = op.get("parameters", [])
                    has_idempotency = any(
                        p.get("$ref") == "#/components/parameters/IdempotencyKeyHeader"
                        or p.get("name") == "Idempotency-Key"
                        for p in params
                    )
                    if not has_idempotency:
                        return (
                            False,
                            f"Mutating endpoint {method.upper()} {path_str} ({op_id}) missing IdempotencyKeyHeader",
                            {},
                        )

        return (
            True,
            f"OpenAPI {version} valid ({len(paths)} paths, {len(operation_ids)} operations, "
            f"{len(schemas)} schemas, {len(refs)} $refs verified)",
            data,
        )
    except Exception as exc:
        return False, f"OpenAPI YAML parsing failed: {exc}", {}


def verify_error_catalog() -> tuple[bool, str, dict[str, Any]]:
    if not ERROR_CATALOG_JSON.exists():
        return False, f"Missing {ERROR_CATALOG_JSON}", {}
    try:
        data: dict[str, Any] = json.loads(ERROR_CATALOG_JSON.read_text(encoding="utf-8"))
        allowed_actions = set(data.get("allowed_client_actions", []))
        errors: dict[str, Any] = data.get("errors", {})

        if len(errors) < 60:
            return False, f"Expected at least 60 error codes, found {len(errors)}", {}

        required_fields = {
            "code",
            "http_status",
            "domain",
            "retryable",
            "client_action",
            "description_en",
            "ui_message_ru",
        }
        for code, detail in errors.items():
            missing = required_fields - set(detail.keys())
            if missing:
                return False, f"Error '{code}' missing required fields: {sorted(missing)}", {}
            if detail["code"] != code:
                return False, f"Error key '{code}' does not match inner code '{detail['code']}'", {}
            if detail["client_action"] not in allowed_actions:
                return (
                    False,
                    f"Error '{code}' has invalid client_action '{detail['client_action']}' "
                    f"(allowed: {sorted(allowed_actions)})",
                    {},
                )
            status = detail["http_status"]
            if not isinstance(status, int) or not (400 <= status <= 599):
                return False, f"Error '{code}' has invalid http_status: {status}", {}
            if not isinstance(detail["retryable"], bool):
                return False, f"Error '{code}' retryable must be boolean", {}
            if not str(detail["ui_message_ru"]).strip() or not str(detail["description_en"]).strip():
                return False, f"Error '{code}' has empty description_en or ui_message_ru", {}

        domains = {detail["domain"] for detail in errors.values()}
        return (
            True,
            f"Error catalog valid ({len(errors)} error codes across {len(domains)} domains)",
            data,
        )
    except Exception as exc:
        return False, f"Error catalog parsing failed: {exc}", {}


def verify_cross_contract_parity(
    pg_enums: dict[str, list[str]],
    sqlite_sql: str,
    openapi_doc: dict[str, Any],
    error_catalog: dict[str, Any],
) -> tuple[bool, str]:
    schemas: dict[str, Any] = openapi_doc.get("components", {}).get("schemas", {})

    # 1. Verify 100% value parity between all 14 PostgreSQL ENUMs and OpenAPI 3.1.0 schemas
    for pg_enum_name, oa_schema_name in PG_ENUM_TO_OPENAPI_SCHEMA.items():
        pg_values = pg_enums.get(pg_enum_name, [])
        oa_schema = schemas.get(oa_schema_name, {})
        oa_values = oa_schema.get("enum", [])
        if pg_values != oa_values:
            return (
                False,
                f"ENUM drift between schema.sql ({pg_enum_name}={pg_values}) "
                f"and openapi.yaml ({oa_schema_name}={oa_values})",
            )

    # 2. Verify shared ENUM values exist in client_sqlite_schema.sql CHECK constraints
    sqlite_checked_enums = [
        "oauth_provider_type",
        "fuel_type",
        "transport_mode_code",
        "track_point_motion_class",
        "friendship_status",
        "waste_point_status",
        "report_type",
    ]
    for pg_enum_name in sqlite_checked_enums:
        for val in pg_enums[pg_enum_name]:
            if f"'{val}'" not in sqlite_sql:
                return (
                    False,
                    f"PostgreSQL ENUM value '{val}' ({pg_enum_name}) is missing from client_sqlite_schema.sql",
                )

    # 3. Verify OpenAPI ErrorResponse example error codes exist in error_catalog.json
    catalog_codes = set(error_catalog.get("errors", {}).keys())
    oa_error_examples = (
        schemas.get("ErrorResponse", {})
        .get("properties", {})
        .get("error_code", {})
        .get("examples", [])
    )
    for example_code in oa_error_examples:
        if example_code not in catalog_codes:
            return (
                False,
                f"OpenAPI ErrorResponse example code '{example_code}' not found in error_catalog.json",
            )

    return (
        True,
        f"100% parity verified across {len(PG_ENUM_TO_OPENAPI_SCHEMA)} PG<->OpenAPI ENUMs, "
        f"{len(sqlite_checked_enums)} SQLite CHECK constraints & Error Catalog codes",
    )


def main() -> int:
    print("=" * 88)
    print("EcoTrack Contract Parity Verification Gate (Layer 1)")
    print("=" * 88)

    pg_ok, pg_msg, pg_enums = verify_postgres_schema()
    print(f"{'[PASS]' if pg_ok else '[FAIL]'} {'1. PostgreSQL 17 + PostGIS DDL':<34}: {pg_msg}")

    sq_ok, sq_msg, sqlite_sql = verify_sqlite_schema()
    print(f"{'[PASS]' if sq_ok else '[FAIL]'} {'2. Client SQLite 3 WAL DDL':<34}: {sq_msg}")

    oa_ok, oa_msg, openapi_doc = verify_openapi_contract()
    print(f"{'[PASS]' if oa_ok else '[FAIL]'} {'3. OpenAPI 3.1.0 Contract':<34}: {oa_msg}")

    ec_ok, ec_msg, error_catalog = verify_error_catalog()
    print(f"{'[PASS]' if ec_ok else '[FAIL]'} {'4. Error Catalog JSON':<34}: {ec_msg}")

    all_passed = pg_ok and sq_ok and oa_ok and ec_ok
    if all_passed:
        parity_ok, parity_msg = verify_cross_contract_parity(
            pg_enums, sqlite_sql, openapi_doc, error_catalog
        )
        print(f"{'[PASS]' if parity_ok else '[FAIL]'} {'5. Cross-Contract Parity Gate':<34}: {parity_msg}")
        all_passed = all_passed and parity_ok

    print("=" * 88)
    if all_passed:
        print("[SUCCESS] All 4 canonical contracts and cross-contract invariants verified.")
        return 0
    print("[FAILED] Contract verification failed! Fix contract drift before continuing.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
