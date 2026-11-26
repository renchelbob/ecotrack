import asyncio
import logging
import sys
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from typing import Literal

import asyncpg
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict

from app.api.dependencies import get_database_pool

from app.api.errors import (
    CatalogException,
    ErrorDetailItem,
    ErrorResponse,
    catalog_exception_handler,
    load_catalog,
)
from app.config import PROJECT_ROOT, load_settings
from app.api.v1.router import register_v1_routes

VERSION = "1.0.0"
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None]:
    app.state.error_catalog = load_catalog(PROJECT_ROOT / "contracts" / "error_catalog.json")
    app.state.settings = load_settings()
    app.state.pool_lock = asyncio.Lock()
    app.state.db_pool = None
    try:
        yield
    finally:
        pool: asyncpg.Pool | None = app.state.db_pool
        if pool is not None:
            try:
                await asyncio.wait_for(pool.close(), timeout=5)
            except TimeoutError:
                pool.terminate()


class HealthStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    status: Literal["ok"]
    version: str
    python_runtime: str


class ReadinessStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    status: Literal["ready"]
    postgres_connected: bool
    postgis_version: str


app = FastAPI(title="EcoTrack Backend API", version=VERSION, lifespan=lifespan)
app.add_exception_handler(CatalogException, catalog_exception_handler)
register_v1_routes(app)


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    if any(item["loc"] == ("header", "Idempotency-Key") for item in exc.errors()):
        return await catalog_exception_handler(request, CatalogException("INVALID_IDEMPOTENCY_KEY"))
    for field, code in (
        ("formal_phone_e164", "INVALID_FORMAL_PHONE_E164"),
        ("confirmation_phrase", "FZ152_INVALID_CONFIRMATION_PHRASE"),
    ):
        if any(item["loc"] == ("body", field) for item in exc.errors()):
            return await catalog_exception_handler(request, CatalogException(code))
    details = [
        ErrorDetailItem(field=".".join(map(str, item["loc"])), issue=item["msg"])
        for item in exc.errors()
    ]
    return await catalog_exception_handler(request, CatalogException("VALIDATION_ERROR", details))


@app.exception_handler(Exception)
async def unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    logger.error("Unhandled request error: %s", type(exc).__name__)
    return await catalog_exception_handler(request, CatalogException("INTERNAL_SERVER_ERROR"))


@app.get("/healthz", tags=["Health"], operation_id="getLivenessProbe")
async def healthz() -> HealthStatusResponse:
    return HealthStatusResponse(
        status="ok",
        version=VERSION,
        python_runtime=f"{sys.version_info.major}.{sys.version_info.minor}",
    )


@app.get(
    "/readyz",
    tags=["Health"],
    operation_id="getReadinessProbe",
    responses={503: {"model": ErrorResponse, "description": "Database or PostGIS check failed"}},
)
async def readyz(request: Request) -> ReadinessStatusResponse:
    try:
        async with asyncio.timeout(3):
            pool = await get_database_pool(request)
            async with pool.acquire() as connection:
                version: str | None = await connection.fetchval(
                    "SELECT extversion FROM pg_extension WHERE extname = 'postgis'"
                )
    except (OSError, TimeoutError, asyncpg.PostgresError, asyncpg.InterfaceError) as exc:
        raise CatalogException("DATABASE_UNAVAILABLE") from exc
    if version is None:
        raise CatalogException("POSTGIS_EXTENSION_UNAVAILABLE")
    return ReadinessStatusResponse(status="ready", postgres_connected=True, postgis_version=version)
