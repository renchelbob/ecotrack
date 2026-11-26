import json

import asyncpg

from app.config import Settings


async def configure_connection(connection: asyncpg.Connection) -> None:
    for name in ("json", "jsonb"):
        await connection.set_type_codec(
            name, schema="pg_catalog", encoder=json.dumps, decoder=json.loads, format="text"
        )


async def create_pool(settings: Settings) -> asyncpg.Pool:
    return await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=settings.db_pool_min_size,
        max_size=settings.db_pool_max_size,
        init=configure_connection,
        server_settings={"timezone": "UTC"},
        command_timeout=15,
        timeout=5,
        max_queries=50_000,
    )
