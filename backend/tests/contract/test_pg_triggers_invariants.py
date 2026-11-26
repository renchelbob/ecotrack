import os
from uuid import uuid4, uuid7

import asyncpg
import pytest

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")


@pytest.mark.asyncio
async def test_ledger_rejects_mutation_and_rolls_back_overdraft() -> None:
    connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
    tx = connection.transaction()
    await tx.start()
    try:
        suffix = uuid4().hex.upper()
        user = await connection.fetchval(
            "INSERT INTO users (display_name, friend_code) VALUES ('Test', $1) RETURNING id",
            f"ECO-{suffix[:4]}-{suffix[4:8]}",
        )
        ledger = await connection.fetchval(
            """
            INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta,
                                      description)
            VALUES ($1, $2, 'admin_adjustment', 25, 'Test') RETURNING id
            """,
            user,
            uuid7(),
        )
        with pytest.raises(asyncpg.IntegrityConstraintViolationError):
            async with connection.transaction():
                await connection.execute(
                    "UPDATE point_ledger SET points_delta = 26 WHERE id = $1", ledger
                )
        with pytest.raises(asyncpg.IntegrityConstraintViolationError):
            async with connection.transaction():
                await connection.execute("DELETE FROM point_ledger WHERE id = $1", ledger)
        with pytest.raises(asyncpg.CheckViolationError):
            async with connection.transaction():
                await connection.execute(
                    """
                    INSERT INTO point_ledger (user_id, idempotency_key, operation_type,
                                              points_delta, description)
                    VALUES ($1, $2, 'shop_purchase', -26, 'Test overdraft')
                    """,
                    user,
                    uuid7(),
                )
        assert (
            await connection.fetchval("SELECT points_balance FROM users WHERE id = $1", user) == 25
        )
        assert (
            await connection.fetchval("SELECT count(*) FROM point_ledger WHERE user_id = $1", user)
            == 1
        )
    finally:
        await tx.rollback()
        await connection.close()
