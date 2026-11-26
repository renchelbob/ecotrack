from uuid import uuid4

import asyncpg

# Compare PostgreSQL's parsed definitions, including triggers and constraints, rather
# than trusting the presence of a single table or comparing raw SQL text.
_DEFINITIONS = """
WITH tables AS (
    SELECT c.oid, c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relkind IN ('r', 'p')
      AND c.relname <> 'alembic_version'
      AND NOT EXISTS (
          SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass
            AND d.objid = c.oid AND d.deptype = 'e'
      )
), definitions AS (
    SELECT 'table' AS kind, relname AS name,
           jsonb_build_array(relkind, relrowsecurity, relforcerowsecurity) AS definition
    FROM tables
    UNION ALL
    SELECT 'column', t.relname || '.' || a.attname,
           jsonb_build_array(
               CASE WHEN t.relname = 'users' AND a.attname = 'friend_code'
                         AND a.atttypmod = 16 AND a.atttypid = 'varchar'::regtype
                    THEN 'character varying(13)' ELSE format_type(a.atttypid, a.atttypmod) END,
               a.attnotnull, a.attgenerated, a.attidentity,
               pg_get_expr(d.adbin, d.adrelid, false), a.attcollation::regcollation::text
           )
    FROM tables t JOIN pg_attribute a ON a.attrelid = t.oid
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attnum > 0 AND NOT a.attisdropped
    UNION ALL
    SELECT 'constraint', t.relname || '.' || c.conname,
           jsonb_build_array(pg_get_constraintdef(c.oid, false), c.convalidated)
    FROM tables t JOIN pg_constraint c ON c.conrelid = t.oid
    UNION ALL
    SELECT 'index', c.relname,
           jsonb_build_array(pg_get_indexdef(c.oid, 0, false), i.indisvalid, i.indisready)
    FROM tables t JOIN pg_index i ON i.indrelid = t.oid
    JOIN pg_class c ON c.oid = i.indexrelid
    UNION ALL
    SELECT 'trigger', t.relname || '.' || r.tgname,
           jsonb_build_array(pg_get_triggerdef(r.oid, false), r.tgenabled)
    FROM tables t JOIN pg_trigger r ON r.tgrelid = t.oid
    WHERE NOT r.tgisinternal
    UNION ALL
    SELECT 'enum', t.typname, jsonb_agg(e.enumlabel ORDER BY e.enumsortorder)
    FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE n.nspname = $1 GROUP BY t.typname
    UNION ALL
    SELECT 'function', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
           to_jsonb(pg_get_functiondef(p.oid))
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = $1 AND p.prokind = 'f'
      AND NOT EXISTS (
          SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass
            AND d.objid = p.oid AND d.deptype = 'e'
      )
)
SELECT kind, name, replace(definition::text, $1 || '.', 'public.') AS definition
FROM definitions
"""


async def _definitions(connection: asyncpg.Connection, schema: str) -> dict[tuple[str, str], str]:
    rows = await connection.fetch(_DEFINITIONS, schema)
    return {(row["kind"], row["name"]): row["definition"] for row in rows}


async def initialize_schema(connection: asyncpg.Connection, ddl: str) -> None:
    await connection.execute("SET LOCAL search_path TO pg_catalog")
    existing = await _definitions(connection, "public")
    if not existing:
        await connection.execute("SET LOCAL search_path TO public")
        await connection.execute(ddl)
        return

    # Generate the reference in the same server without touching existing rows.
    # The random identifier contains only ASCII letters, digits and underscores.
    # Roll the savepoint back so reference objects never persist.
    shadow = f"ecotrack_reference_{uuid4().hex}"
    reference = connection.transaction()
    await reference.start()
    try:
        extensions = await connection.fetchval(
            """
            SELECT count(*) FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
            WHERE e.extname IN ('postgis', 'pgcrypto') AND n.nspname = 'public'
            """
        )
        if extensions != 2:
            raise RuntimeError("Legacy EcoTrack database lacks PostGIS or pgcrypto in public")
        await connection.execute(f"CREATE SCHEMA {shadow}")  # noqa: S608 - internally generated
        await connection.execute(f"SET LOCAL search_path TO {shadow}, public")
        await connection.execute(ddl)
        await connection.execute("SET LOCAL search_path TO pg_catalog")
        expected = await _definitions(connection, shadow)
        changed = sorted(
            f"{kind} {name}" for kind, name in existing.keys() | expected.keys()
            if existing.get((kind, name)) != expected.get((kind, name))
        )
        if changed:
            raise RuntimeError("Legacy EcoTrack schema differs: " + ", ".join(changed))
        await _check_seed_data(connection, shadow)
    finally:
        await reference.rollback()
    await connection.execute("SET LOCAL search_path TO public")


async def _check_seed_data(connection: asyncpg.Connection, shadow: str) -> None:
    # Enum labels match, but the reference and live enum types have different OIDs.
    # Compare identities and domain coefficients while preserving mutable shop inventory.
    missing = await connection.fetchval(
        f"""
        SELECT EXISTS (
            SELECT mode_code::text, co2_grams_per_km FROM {shadow}.transport_emission_catalog
            EXCEPT SELECT mode_code::text, co2_grams_per_km FROM public.transport_emission_catalog
        ) OR EXISTS (
            SELECT code FROM {shadow}.mascot_accessories
            EXCEPT SELECT code FROM public.mascot_accessories
        ) OR EXISTS (
            SELECT code FROM {shadow}.badges_catalog
            EXCEPT SELECT code FROM public.badges_catalog
        ) OR EXISTS (
            SELECT id, slug FROM {shadow}.shop_partners
            EXCEPT SELECT id, slug FROM public.shop_partners
        ) OR EXISTS (
            SELECT id, sku FROM {shadow}.shop_items
            EXCEPT SELECT id, sku FROM public.shop_items
        )
        """  # noqa: S608 - schema name is internally generated
    )
    if missing:
        raise RuntimeError("Legacy EcoTrack database is missing canonical seed data")
