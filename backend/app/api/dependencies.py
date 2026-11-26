from collections.abc import AsyncIterator
from functools import lru_cache
from time import time
from typing import Annotated, cast
from uuid import UUID

import asyncpg
import jwt
from fastapi import Depends, Header, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.api.errors import CatalogException
from app.application.auth_service import AccessSession, Principal, signing_key
from app.config import Settings
from app.infrastructure.db.pool import create_pool

bearer = HTTPBearer(auto_error=False, scheme_name="BearerAuth")


async def get_settings(request: Request) -> Settings:
    return request.app.state.settings


async def get_database_pool(request: Request) -> asyncpg.Pool:
    # Lazily start the pool so the liveness probe survives a database outage.
    state = request.app.state
    existing: asyncpg.Pool | None = state.db_pool
    if existing is not None:
        return existing
    async with state.pool_lock:
        pool: asyncpg.Pool | None = state.db_pool
        if pool is None:
            pool = await create_pool(state.settings)
            state.db_pool = pool
        return pool


async def get_connection(request: Request) -> AsyncIterator[asyncpg.Connection]:
    try:
        pool = await get_database_pool(request)
        async with pool.acquire(timeout=5) as connection:
            yield cast(asyncpg.Connection, connection)
    except (OSError, TimeoutError, asyncpg.PostgresConnectionError, asyncpg.InterfaceError) as exc:
        raise CatalogException("DATABASE_UNAVAILABLE") from exc


Db = Annotated[asyncpg.Connection, Depends(get_connection)]
AppSettings = Annotated[Settings, Depends(get_settings)]


MutationKey = Annotated[UUID, Header(alias="Idempotency-Key")]


@lru_cache(maxsize=512)
def _verify_access_token(token: str, secret: str) -> tuple[AccessSession, int, int]:
    claims = jwt.decode(
        token,
        secret,
        algorithms=["HS256"],
        options={"require": ["sub", "jti", "fp", "iat", "exp"]},
    )
    fingerprint = claims["fp"]
    if not isinstance(fingerprint, str):
        raise ValueError("Invalid fingerprint")
    valid_from = max(int(claims["iat"]), int(claims.get("nbf", claims["iat"])))
    principal = Principal(UUID(claims["sub"]), UUID(claims["jti"]))
    return AccessSession(principal, fingerprint), valid_from, int(claims["exp"])


async def verify_access_token(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> AccessSession:
    if credentials is None:
        raise CatalogException("AUTH_TOKEN_MISSING")
    settings: Settings = request.app.state.settings
    try:
        session, valid_from, expiration = _verify_access_token(
            credentials.credentials, signing_key(settings)
        )
        # The cache holds signature validation only. Time and revocation are checked per request.
        now = time()
        if now >= expiration:
            raise CatalogException("AUTH_TOKEN_EXPIRED")
        if now < valid_from:
            raise CatalogException("AUTH_TOKEN_INVALID")
    except jwt.ExpiredSignatureError as exc:
        raise CatalogException("AUTH_TOKEN_EXPIRED") from exc
    except (jwt.InvalidTokenError, ValueError, TypeError, AttributeError, OverflowError) as exc:
        raise CatalogException("AUTH_TOKEN_INVALID") from exc
    return session


# The database must still confirm the session is active on every request.
SignedAccess = Annotated[AccessSession, Depends(verify_access_token)]


async def require_principal(session: SignedAccess, connection: Db) -> Principal:
    principal = session.principal
    active = await connection.fetchval(
        """
        SELECT EXISTS(SELECT 1 FROM auth_refresh_sessions
        WHERE id = $1 AND user_id = $2 AND device_fingerprint = $3
          AND revoked_at IS NULL AND expires_at > now())
        """,
        principal.session_id,
        principal.user_id,
        session.fingerprint,
    )
    if not active:
        raise CatalogException("AUTH_TOKEN_INVALID")
    return principal


AuthUser = Annotated[Principal, Depends(require_principal)]
