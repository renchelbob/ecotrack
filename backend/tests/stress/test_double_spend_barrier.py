import asyncio
import os
from uuid import UUID, uuid4, uuid7

import asyncpg
import pytest

from app.api.errors import CatalogException
from app.api.v1.ledger_shop_models import CartLineInput
from app.application.ledger_shop_service import checkout

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")


@pytest.mark.asyncio
async def test_50_checkouts_cannot_spend_same_balance() -> None:
    pool = await asyncpg.create_pool(
        os.environ["TEST_DATABASE_URL"], min_size=2, max_size=16, command_timeout=10
    )
    user = uuid7()
    suffix = uuid4().hex.upper()
    user_refs = (user, f"ECO-{suffix[:4]}-{suffix[4:8]}")
    try:
        async with pool.acquire() as connection:
            await connection.execute(
                "INSERT INTO users (id, display_name, friend_code) VALUES ($1, 'Stress user', $2)",
                *user_refs,
            )
            await connection.execute(
                """
                INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta,
                                          description)
                VALUES ($1, $2, 'admin_adjustment', 300, 'Stress test credit')
                """,
                user,
                uuid7(),
            )
        item = CartLineInput(shop_item_id=UUID("01950000-0000-7000-8000-000000000101"), quantity=1)

        async def attempt() -> str:
            async with pool.acquire() as connection:
                try:
                    await checkout(connection, user, uuid7(), [item])
                except CatalogException as exc:
                    return exc.code
                return "completed"

        results = await asyncio.gather(*(attempt() for _ in range(50)))
        assert results.count("completed") == 1
        assert results.count("INSUFFICIENT_POINTS_BALANCE") == 49
        async with pool.acquire() as connection:
            assert (
                await connection.fetchval("SELECT points_balance FROM users WHERE id = $1", user)
                == 0
            )
            assert (
                await connection.fetchval(
                    "SELECT count(*) FROM shop_orders WHERE user_id = $1", user
                )
                == 1
            )
    finally:
        try:
            async with pool.acquire() as connection, connection.transaction():
                await connection.execute("SET LOCAL ecotrack.in_152fz_account_erasure = 'true'")
                await connection.execute("DELETE FROM users WHERE id = $1", user)
        finally:
            await pool.close()
