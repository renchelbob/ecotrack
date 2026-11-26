import asyncio

from alembic import context
from sqlalchemy import Connection, pool, text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import create_async_engine

from app.config import load_settings

POSTGIS_SYSTEM_TABLES = frozenset(
    {
        "spatial_ref_sys",
        "geometry_columns",
        "geography_columns",
        "raster_columns",
        "raster_overviews",
    }
)


def include_object(
    _object: object, name: str | None, type_: str, _reflected: bool, _compare_to: object
) -> bool:
    return type_ != "table" or name not in POSTGIS_SYSTEM_TABLES


def run_migrations(connection: Connection) -> None:
    with connection.begin():
        # Lock before Alembic reads the version table, including on an empty database.
        connection.execute(text("SELECT pg_advisory_xact_lock(454374062001)"))
        context.configure(connection=connection, include_object=include_object)
        with context.begin_transaction():
            context.run_migrations()


async def migrate() -> None:
    dsn = make_url(load_settings().database_url).set(drivername="postgresql+asyncpg")
    engine = create_async_engine(dsn, poolclass=pool.NullPool)
    try:
        async with engine.connect() as connection:
            await connection.run_sync(run_migrations)
    finally:
        await engine.dispose()


if context.is_offline_mode():
    raise RuntimeError("EcoTrack migrations require a live PostgreSQL database")

asyncio.run(migrate())
