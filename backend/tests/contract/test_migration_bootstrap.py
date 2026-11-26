import asyncio
import os
import shutil
import sys
from pathlib import Path
from uuid import UUID, uuid4

import asyncpg
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import URL, make_url

from app.application.account_service import erase_account
from app.application.reconcile_erasure import reconcile
from app.config import Settings
from app.main import app

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")
BACKEND = Path(__file__).resolve().parents[2]
CONTRACT = BACKEND.parent / "contracts" / "schema.sql"
HEAD = "0003_backfill_forest_progress"


@pytest.mark.parametrize("setup", ["empty", "legacy12", "legacy13", "drift", "seed_drift"])
async def test_initial_upgrade_and_restart(
    setup: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    source_dsn = os.environ["TEST_DATABASE_URL"]
    name = f"ecotrack_migration_{uuid4().hex}"
    target_dsn = make_url(source_dsn).set(database=name).render_as_string(hide_password=False)
    admin = await asyncpg.connect(source_dsn)
    try:
        await admin.execute(f"CREATE DATABASE {name} TEMPLATE template0")  # generated identifier
        await _exercise_upgrade(setup, target_dsn, monkeypatch)
    finally:
        try:
            await admin.execute(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")  # generated name
        finally:
            await admin.close()


async def _upgrade(env: dict[str, str]) -> tuple[int, str]:
    process = await asyncio.create_subprocess_exec(
        sys.executable, "-m", "alembic", "upgrade", "head",
        cwd=BACKEND, env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    try:
        output, _ = await asyncio.wait_for(process.communicate(), timeout=45)
    except TimeoutError:
        process.kill()
        await process.wait()
        raise
    assert process.returncode is not None
    return process.returncode, output.decode(errors="replace")


async def _exercise_upgrade(setup: str, dsn: str, monkeypatch: pytest.MonkeyPatch) -> None:
    connection = await asyncpg.connect(dsn)
    try:
        if setup != "empty":
            ddl = CONTRACT.read_text(encoding="utf-8")
            if setup == "legacy12":
                ddl = ddl.replace("friend_code VARCHAR(13)", "friend_code VARCHAR(12)")
            await connection.execute(ddl)
            # The old 12-character column could not store any valid code.
            if setup != "legacy12":
                user_id = await connection.fetchval(
                    "INSERT INTO users (display_name, friend_code) "
                    "VALUES ('Migrated', 'ECO-TEST-0001') RETURNING id"
                )
                await connection.execute(
                    """
                    INSERT INTO point_ledger (
                        user_id, idempotency_key, operation_type, points_delta, description
                    ) VALUES ($1, $2, 'daily_steps_reward', 42, 'Migration preservation test')
                    """,
                    user_id,
                    uuid4(),
                )
            await connection.execute(
                "UPDATE shop_items SET stock_quantity = 17 WHERE sku = 'DEMO-ECODOM-200'"
            )
        if setup == "drift":
            await connection.execute("ALTER TABLE users DROP COLUMN avatar_url")
        if setup == "seed_drift":
            await connection.execute(
                "UPDATE transport_emission_catalog SET co2_grams_per_km = 83 "
                "WHERE mode_code = 'bus'"
            )

        env = dict(os.environ, DATABASE_URL=dsn)
        status, output = await _upgrade(env)
        await _assert_no_reference_schema(connection)
        failures = {
            "drift": "Legacy EcoTrack schema differs",
            "seed_drift": "Legacy EcoTrack database is missing canonical seed data",
        }
        if setup in failures:
            assert status != 0 and failures[setup] in output
            assert await connection.fetchval("SELECT to_regclass('alembic_version')") is None
            assert await connection.fetchval(
                "SELECT points_balance FROM users WHERE friend_code = 'ECO-TEST-0001'"
            ) == 42
            return
        assert status == 0, output
        assert await connection.fetchval("SELECT version_num FROM alembic_version") == HEAD
        status, output = await _upgrade(env)
        assert status == 0, output
        await _assert_no_reference_schema(connection)
        assert await connection.fetchval("SELECT version_num FROM alembic_version") == HEAD
        assert await connection.fetchval(
            "SELECT character_maximum_length FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'friend_code'"
        ) == 13
        if setup != "empty":
            assert await connection.fetchval(
                "SELECT stock_quantity FROM shop_items WHERE sku = 'DEMO-ECODOM-200'"
            ) == 17
        if setup == "legacy13":
            user = await connection.fetchrow(
                "SELECT id, display_name, points_balance FROM users "
                "WHERE friend_code = 'ECO-TEST-0001'"
            )
            assert user is not None
            assert (user["display_name"], user["points_balance"]) == ("Migrated", 42)
            assert await connection.fetchval(
                "SELECT sum(points_delta) FROM point_ledger WHERE user_id = $1", user["id"]
            ) == 42
    finally:
        await connection.close()
    monkeypatch.setenv("DATABASE_URL", dsn)
    with TestClient(app) as client:
        assert client.get("/readyz").status_code == 200


async def _assert_no_reference_schema(connection: asyncpg.Connection) -> None:
    prefix = "ecotrack_reference_"
    assert not await connection.fetchval(
        "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE starts_with(nspname::text, $1))",
        prefix,
    )


async def test_snapshot_before_erasure_does_not_resurrect_account(tmp_path: Path) -> None:
    pg_dump = shutil.which("pg_dump")
    pg_restore = shutil.which("pg_restore")
    if pg_dump is None or pg_restore is None:
        pytest.skip("PostgreSQL 17 client tools pg_dump and pg_restore are required")
    dsn = os.environ["TEST_DATABASE_URL"]
    source_name = f"ecotrack_erasure_source_{uuid4().hex}"
    restored_name = f"ecotrack_erasure_target_{uuid4().hex}"
    secret = uuid4().hex + uuid4().hex
    archive = tmp_path / "before-erasure.dump"
    admin = await asyncpg.connect(dsn)
    try:
        await admin.execute(f"CREATE DATABASE {source_name} TEMPLATE template0")
        await admin.execute(f"CREATE DATABASE {restored_name} TEMPLATE template0")
        source_dsn = make_url(dsn).set(database=source_name).render_as_string(hide_password=False)
        status, output = await _upgrade(dict(os.environ, DATABASE_URL=source_dsn))
        assert status == 0, output

        source = await asyncpg.connect(source_dsn)
        try:
            user_id = await _seed_erasure_fixture(source)
            await _run_pg_tool(
                pg_dump, dsn, source_name, "--format=custom", "--no-owner", "--no-acl",
                "--file", str(archive),
            )
            settings = Settings.model_validate(
                {"database_url": source_dsn, "fz152_deletion_hmac_secret": secret}
            )
            receipt = await erase_account(source, settings, user_id, "archive reconciliation test")

            await _run_pg_tool(
                pg_restore, dsn, restored_name, "--single-transaction", "--exit-on-error",
                "--no-owner", "--no-acl", str(archive),
            )
            target = await asyncpg.connect(dsn, database=restored_name)
            try:
                assert await target.fetchval(
                    "SELECT points_balance FROM users WHERE id = $1", user_id
                ) == 42
                assert await target.fetchval(
                    "SELECT sum(points_delta) FROM point_ledger WHERE user_id = $1", user_id
                ) == 42
                assert await target.fetchval(
                    "SELECT count(*) FROM daily_step_summaries WHERE user_id = $1", user_id
                ) == 1
                assert await reconcile(source, target, secret.encode()) == 1
                assert await reconcile(source, target, secret.encode()) == 0
                assert await target.fetchval(
                    "SELECT count(*) FROM users WHERE id = $1", user_id
                ) == 0
                assert await target.fetchval(
                    "SELECT count(*) FROM daily_step_summaries WHERE user_id = $1", user_id
                ) == 0
                assert await target.fetchval(
                    "SELECT count(*) FROM point_ledger WHERE user_id = $1", user_id
                ) == 0
                assert await target.fetchval(
                    "SELECT verification_signature FROM fz152_account_deletion_log WHERE id = $1",
                    receipt.receipt_id,
                ) == receipt.verification_signature
                assert await target.fetchval(
                    "SELECT count(*) FROM users WHERE friend_code = 'ECO-TEST-0003'"
                ) == 1
            finally:
                await target.close()
        finally:
            await source.close()
    finally:
        try:
            await admin.execute(f"DROP DATABASE IF EXISTS {restored_name} WITH (FORCE)")
            await admin.execute(f"DROP DATABASE IF EXISTS {source_name} WITH (FORCE)")
        finally:
            await admin.close()


async def _seed_erasure_fixture(connection: asyncpg.Connection) -> UUID:
    user_id = await connection.fetchval(
        "INSERT INTO users (display_name, friend_code) VALUES "
        "('Erasure snapshot', 'ECO-TEST-0002') RETURNING id"
    )
    await connection.execute(
        "INSERT INTO users (display_name, friend_code) VALUES ('Unaffected', 'ECO-TEST-0003')"
    )
    await connection.execute(
        "INSERT INTO daily_step_summaries (user_id, activity_date) VALUES ($1, CURRENT_DATE)",
        user_id,
    )
    await connection.execute(
        """
        INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta, description)
        VALUES ($1, uuid_generate_v7(), 'daily_steps_reward', 42, 'Erasure snapshot test')
        """,
        user_id,
    )
    assert isinstance(user_id, UUID)
    return user_id


async def _run_pg_tool(executable: str, dsn: str, database: str, *options: str) -> None:
    url = make_url(dsn)
    target = URL.create(
        "postgresql",
        username=url.username,
        host=url.host,
        port=url.port,
        database=database,
        query=url.query,
    ).render_as_string()
    env = dict(os.environ, PGCONNECT_TIMEOUT="5")
    if url.password is not None:
        env["PGPASSWORD"] = str(url.password)
    process = await asyncio.create_subprocess_exec(
        executable,
        "--no-password",
        "--dbname",
        target,
        *options,
        env=env,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        output, _ = await asyncio.wait_for(process.communicate(), timeout=45)
    except TimeoutError:
        process.kill()
        await process.wait()
        raise
    assert process.returncode == 0, output.decode(errors="replace")
