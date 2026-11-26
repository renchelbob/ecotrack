from uuid import UUID

import asyncpg

from app.api.errors import CatalogException


async def claim_in_flight_key(connection: asyncpg.Connection, key: UUID) -> None:
    # The established ledger/order lock namespace is global because keys are unique
    # in those tables. The surrounding transaction releases the lock on exit.
    if not await connection.fetchval(
        "SELECT pg_try_advisory_xact_lock(hashtextextended($1, 1))", str(key)
    ):
        raise CatalogException("IDEMPOTENCY_IN_FLIGHT")


async def wait_for_in_flight_key(connection: asyncpg.Connection, key: UUID) -> None:
    # Some operations support natural retries but have no declared in-flight 409 response.
    await connection.execute("SELECT pg_advisory_xact_lock(hashtextextended($1, 1))", str(key))
